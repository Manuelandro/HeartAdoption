import Fastify, { type FastifyRequest, type FastifyContextConfig } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { z } from 'zod';
import sharp from 'sharp';
import { randomUUID } from 'node:crypto';
import type { Database } from './database.js';
import { checkPassword, createSession, hashPassword, tokenHash } from './auth.js';

class APIError extends Error {
  constructor(public statusCode: number, message: string) { super(message); }
}

const countryCode = z.string().regex(/^[A-Z]{2}$/, 'Choose a country.');
const uuid = z.uuid();
const postFields = z.object({
  name: z.string().trim().min(1).max(80),
  species: z.enum(['dog', 'cat']),
  sex: z.enum(['female', 'male', 'unknown']),
  ageMonths: z.number().int().min(0).max(360),
  size: z.enum(['small', 'medium', 'large']),
  source: z.enum(['shelter', 'street', 'family']),
  countryCode,
  city: z.string().trim().min(1).max(100),
  story: z.string().trim().min(20, 'Tell adopters a little more (at least 20 characters).').max(6000),
  contactEmail: z.email().max(254),
  vaccinated: z.boolean(),
  neutered: z.boolean(),
}).strict();
const credentials = z.object({ email: z.email().max(254).transform(s => s.toLowerCase()), password: z.string().min(10).max(128) });
const idOf = (request: FastifyRequest) => uuid.parse((request.params as { id: string }).id);
const escaped = (text: string) => text.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

export interface AppOptions { publicURL: string; appStoreURL?: string; logger?: boolean; rateLimits?: boolean; accountRateLimits?: boolean }

export async function createApp(db: Database, options: AppOptions) {
  const app = Fastify({
    logger: options.logger ? { redact: ['req.headers.authorization', 'req.body.password', 'req.body.photos'] } : false,
    bodyLimit: 13 * 1024 * 1024,
    requestTimeout: 30_000,
  });
  const base = options.publicURL.replace(/\/$/, '');
  if (options.rateLimits !== false) await app.register(rateLimit, {
    max: 300, timeWindow: '1 minute', hook: 'preHandler',
    keyGenerator: request => {
      if (!options.accountRateLimits) return request.ip;
      // Fetch runtimes have no trusted socket IP. Never trust client forwarding headers.
      if (request.headers.authorization) return tokenHash(request.headers.authorization);
      const body = request.body as { email?: unknown } | undefined;
      if (typeof body?.email === 'string') return tokenHash(body.email.trim().toLowerCase());
      return 'public-read-budget';
    },
  });
  const dummyPassword = await hashPassword(randomUUID());

  app.addHook('onSend', async (_request, reply) => {
    reply.header('X-Content-Type-Options', 'nosniff');
    reply.header('Referrer-Policy', 'no-referrer');
    reply.header('X-Frame-Options', 'DENY');
    reply.header('Cache-Control', 'no-store');
  });
  app.setErrorHandler((error, request, reply) => {
    if (error instanceof z.ZodError) return reply.code(400).send({ message: error.issues.map(i => `${i.path.join('.')}: ${i.message}`).join('\n') });
    if (error instanceof APIError) return reply.code(error.statusCode).send({ message: error.message });
    const detail = error as { statusCode?: number; code?: string };
    if (detail.code === '23503') return reply.code(400).send({ message: 'Choose an existing country or post.' });
    if (detail.statusCode && detail.statusCode < 500) return reply.code(detail.statusCode).send({ message: error instanceof Error ? error.message : 'The request could not be completed.' });
    request.log.error(error);
    return reply.code(500).send({ message: 'The server could not finish this request. Please try again.' });
  });

  async function viewer(request: FastifyRequest, required = true): Promise<string | null> {
    const header = request.headers.authorization;
    if (!header) {
      if (required) throw new APIError(401, 'Sign in to continue.');
      return null;
    }
    const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(header);
    if (!match) throw new APIError(401, 'Your session has expired. Sign in again.');
    const [session] = await db.query('SELECT user_id FROM sessions WHERE token_hash = $1 AND expires_at > now()', [tokenHash(match[1]!)]);
    if (!session) throw new APIError(401, 'Your session has expired. Sign in again.');
    return session.user_id;
  }

  async function user(id: string, executor = db) {
    const [row] = await executor.query(`SELECT id, name, email, home_country AS "homeCountry",
      ARRAY(SELECT country_code FROM country_admins WHERE user_id = users.id ORDER BY country_code) AS "adminCountries",
      ARRAY(SELECT country_code FROM country_follows WHERE user_id = users.id ORDER BY country_code) AS "followedCountries"
      FROM users WHERE id = $1`, [id]);
    if (!row) throw new APIError(401, 'Sign in again.');
    return row;
  }

  async function canAdmin(userID: string, country: string, executor = db) {
    return (await executor.query('SELECT 1 FROM country_admins WHERE user_id = $1 AND country_code = $2', [userID, country])).length > 0;
  }

  const selectPost = `SELECT p.id, p.author_id AS "authorID", u.name AS "authorName", p.name, p.species, p.sex,
    p.age_months AS "ageMonths", p.size, p.source, p.country_code AS "countryCode", p.city, p.story,
    p.contact_email AS "contactEmail", p.vaccinated, p.neutered, p.status, p.created_at AS "createdAt",
    (SELECT count(*)::int FROM likes l WHERE l.post_id = p.id) AS "likesCount",
    EXISTS(SELECT 1 FROM likes l WHERE l.post_id = p.id AND l.user_id = $1) AS liked,
    COALESCE((SELECT json_agg(json_build_object('id', ph.id, 'url', $2::text || '/v1/photos/' || ph.id) ORDER BY ph.position) FROM photos ph WHERE ph.post_id = p.id), '[]') AS photos
    FROM posts p JOIN users u ON u.id = p.author_id`;

  async function getPost(id: string, userID: string | null, executor = db) {
    const [post] = await executor.query(`${selectPost} WHERE p.id = $3 AND (p.status <> 'hidden' OR p.author_id = $1 OR EXISTS(SELECT 1 FROM country_admins a WHERE a.user_id = $1 AND a.country_code = p.country_code))`, [userID, base, id]);
    if (!post) throw new APIError(404, 'This adoption post is no longer available.');
    return post;
  }

  app.get('/health', async () => { await db.query('SELECT 1'); return { status: 'ok' }; });

  const authConfig: FastifyContextConfig = options.rateLimits === false ? {} : { rateLimit: { max: 12, timeWindow: '15 minutes' } };
  app.post('/v1/auth/register', { config: authConfig }, async (request, reply) => {
    const data = credentials.extend({ name: z.string().trim().min(1).max(80), homeCountry: countryCode }).strict().parse(request.body);
    const password = await hashPassword(data.password);
    try {
      const response = await db.transaction(async tx => {
        const [row] = await tx.query('INSERT INTO users(email, name, password_hash, home_country) VALUES($1, $2, $3, $4) RETURNING id', [data.email, data.name, password, data.homeCountry]);
        const token = await createSession(tx, row!.id);
        await tx.query('INSERT INTO country_follows(user_id, country_code) VALUES($1, $2)', [row!.id, data.homeCountry]);
        return { token, user: await user(row!.id, tx) };
      });
      return reply.code(201).send(response);
    } catch (error) {
      if ((error as { code?: string }).code === '23505') throw new APIError(409, 'An account with this email already exists. Sign in instead.');
      throw error;
    }
  });

  app.post('/v1/auth/login', { config: authConfig }, async request => {
    const data = credentials.parse(request.body);
    const [row] = await db.query('SELECT id, password_hash FROM users WHERE email = $1', [data.email]);
    const correct = await checkPassword(data.password, row?.password_hash ?? dummyPassword);
    if (!row || !correct) throw new APIError(401, 'The email or password is incorrect.');
    return { token: await createSession(db, row.id), user: await user(row.id) };
  });

  app.delete('/v1/auth/session', async (request, reply) => {
    await viewer(request);
    await db.query('DELETE FROM sessions WHERE token_hash = $1', [tokenHash(request.headers.authorization!.slice(7))]);
    return reply.code(204).send();
  });

  app.get('/v1/me', async request => user((await viewer(request))!));
  app.patch('/v1/me', async request => {
    const id = (await viewer(request))!;
    const data = z.object({ name: z.string().trim().min(1).max(80), homeCountry: countryCode }).strict().parse(request.body);
    await db.query('UPDATE users SET name = $1, home_country = $2 WHERE id = $3', [data.name, data.homeCountry, id]);
    return user(id);
  });
  app.delete('/v1/me', async (request, reply) => {
    const id = (await viewer(request))!;
    const { password } = z.object({ password: z.string().max(128) }).parse(request.body);
    const [row] = await db.query('SELECT password_hash FROM users WHERE id = $1', [id]);
    if (!row || !(await checkPassword(password, row.password_hash))) throw new APIError(403, 'Enter your current password to delete your account.');
    await db.query('DELETE FROM users WHERE id = $1', [id]);
    return reply.code(204).send();
  });

  app.get('/v1/countries', async request => {
    const id = await viewer(request, false);
    return db.query(`SELECT c.code, c.name,
      (SELECT count(*)::int FROM posts p WHERE p.country_code = c.code AND p.status = 'available') AS "postCount",
      (SELECT count(*)::int FROM country_follows f WHERE f.country_code = c.code) AS "followerCount",
      EXISTS(SELECT 1 FROM country_follows f WHERE f.country_code = c.code AND f.user_id = $1) AS "isFollowing"
      FROM countries c ORDER BY c.name`, [id]);
  });

  app.put('/v1/countries/:code/follow', async (request, reply) => {
    const id = await viewer(request);
    const code = countryCode.parse((request.params as { code: string }).code);
    await db.query('INSERT INTO country_follows(user_id, country_code) VALUES($1, $2) ON CONFLICT DO NOTHING', [id, code]);
    return reply.code(204).send();
  });
  app.delete('/v1/countries/:code/follow', async (request, reply) => {
    const id = await viewer(request);
    const code = countryCode.parse((request.params as { code: string }).code);
    await db.query('DELETE FROM country_follows WHERE user_id = $1 AND country_code = $2', [id, code]);
    return reply.code(204).send();
  });

  app.get('/v1/posts', async request => {
    const id = await viewer(request, false);
    const query = z.object({
      scope: z.enum(['home', 'following', 'all', 'country', 'liked', 'mine']).default('home'),
      country: countryCode.optional(), species: z.enum(['dog', 'cat']).optional(),
      q: z.string().trim().max(100).optional(), cursor: z.string().max(500).optional(),
      limit: z.coerce.number().int().min(1).max(50).default(20),
    }).parse(request.query);
    const values: unknown[] = [id, base];
    const where = ["p.status = 'available'"];
    const bind = (value: unknown) => { values.push(value); return `$${values.length}`; };
    if (query.scope === 'mine') { if (!id) throw new APIError(401, 'Sign in to view your posts.'); where[0] = `p.author_id = ${bind(id)}`; }
    if (query.scope === 'home') where.push(`p.country_code = ${bind(id ? (await user(id)).homeCountry : query.country ?? 'IT')}`);
    if (query.scope === 'following') { if (!id) throw new APIError(401, 'Sign in to follow countries.'); where.push('p.country_code IN (SELECT country_code FROM country_follows WHERE user_id = $1)'); }
    if (query.scope === 'country') { if (!query.country) throw new APIError(400, 'Choose a country.'); where.push(`p.country_code = ${bind(query.country)}`); }
    if (query.scope === 'liked') { if (!id) throw new APIError(401, 'Sign in to view your likes.'); where.push('EXISTS(SELECT 1 FROM likes l WHERE l.post_id = p.id AND l.user_id = $1)'); }
    if (query.species) where.push(`p.species = ${bind(query.species)}`);
    if (query.q) {
      const term = query.q.replace(/[\\%_]/g, c => `\\${c}`);
      where.push(`(p.name ILIKE ${bind(`%${term}%`)} OR p.city ILIKE $${values.length} OR p.story ILIKE $${values.length})`);
    }
    if (query.cursor) {
      let cursor: { date: string; id: string };
      try { cursor = z.object({ date: z.iso.datetime({ offset: true }), id: uuid }).parse(JSON.parse(Buffer.from(query.cursor, 'base64url').toString())); }
      catch { throw new APIError(400, 'This page link has expired. Refresh the feed.'); }
      where.push(`(p.created_at, p.id) < (${bind(cursor.date)}::timestamptz, ${bind(cursor.id)}::uuid)`);
    }
    const posts = await db.query(`${selectPost} WHERE ${where.join(' AND ')} ORDER BY p.created_at DESC, p.id DESC LIMIT ${bind(query.limit + 1)}`, values);
    const hasMore = posts.length > query.limit;
    if (hasMore) posts.pop();
    const last = posts.at(-1);
    return { posts, nextCursor: hasMore && last ? Buffer.from(JSON.stringify({ date: new Date(last.createdAt).toISOString(), id: last.id })).toString('base64url') : null };
  });

  app.get('/v1/posts/:id', async request => getPost(idOf(request), await viewer(request, false)));

  app.post('/v1/posts', async (request, reply) => {
    const id = (await viewer(request))!;
    const data = postFields.extend({ photos: z.array(z.string().min(1).max(2_097_152)).min(1).max(6) }).parse(request.body);
    const photos: Buffer[] = [];
    for (const encoded of data.photos) {
      if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) throw new APIError(400, 'Choose a valid JPEG or PNG photo.');
      const input = Buffer.from(encoded, 'base64');
      if (input.length > 1_572_864) throw new APIError(400, 'Each photo must be smaller than 1.5 MB.');
      try {
        const metadata = await sharp(input, { limitInputPixels: 40_000_000 }).metadata();
        if (!['jpeg', 'png', 'webp', 'heif'].includes(metadata.format ?? '')) throw new Error('Unsupported photo');
        photos.push(await sharp(input, { limitInputPixels: 40_000_000 }).rotate().resize(1600, 1600, { fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 82 }).toBuffer());
      } catch { throw new APIError(400, 'One of the photos could not be read. Choose another image.'); }
    }
    const post = await db.transaction(async tx => {
      const [row] = await tx.query(`INSERT INTO posts(author_id, name, species, sex, age_months, size, source, country_code, city, story, contact_email, vaccinated, neutered)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING id`,
      [id, data.name, data.species, data.sex, data.ageMonths, data.size, data.source, data.countryCode, data.city, data.story, data.contactEmail, data.vaccinated, data.neutered]);
      for (const [position, photo] of photos.entries()) await tx.query('INSERT INTO photos(post_id, position, data) VALUES($1,$2,$3)', [row!.id, position, photo]);
      return getPost(row!.id, id, tx);
    });
    return reply.code(201).send(post);
  });

  app.patch('/v1/posts/:id', async request => {
    const userID = (await viewer(request))!;
    const id = idOf(request);
    const data = postFields.extend({ status: z.enum(['available', 'adopted']) }).parse(request.body);
    return db.transaction(async tx => {
      const [existing] = await tx.query('SELECT author_id, status FROM posts WHERE id = $1 FOR UPDATE', [id]);
      if (!existing) throw new APIError(404, 'Post not found.');
      if (existing.author_id !== userID) throw new APIError(403, 'Only the person who posted this animal can edit it.');
      if (existing.status === 'hidden') throw new APIError(403, 'This post was hidden by a country administrator. Contact them before making changes.');
      await tx.query(`UPDATE posts SET name=$1, species=$2, sex=$3, age_months=$4, size=$5, source=$6, country_code=$7,
        city=$8, story=$9, contact_email=$10, vaccinated=$11, neutered=$12, status=$13, updated_at=now() WHERE id=$14`,
      [data.name, data.species, data.sex, data.ageMonths, data.size, data.source, data.countryCode, data.city, data.story, data.contactEmail, data.vaccinated, data.neutered, data.status, id]);
      return getPost(id, userID, tx);
    });
  });
  app.delete('/v1/posts/:id', async (request, reply) => {
    const userID = await viewer(request);
    const rows = await db.query('DELETE FROM posts WHERE id=$1 AND author_id=$2 RETURNING id', [idOf(request), userID]);
    if (!rows.length) throw new APIError(403, 'Only the person who created this post can delete it.');
    return reply.code(204).send();
  });

  app.put('/v1/posts/:id/like', async (request, reply) => {
    const userID = await viewer(request);
    const id = idOf(request);
    await db.transaction(async tx => {
      const [row] = await tx.query("SELECT id FROM posts WHERE id=$1 AND status='available' FOR SHARE", [id]);
      if (!row) throw new APIError(404, 'This animal is no longer available.');
      await tx.query('INSERT INTO likes(user_id, post_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [userID, id]);
    });
    return reply.code(204).send();
  });
  app.delete('/v1/posts/:id/like', async (request, reply) => {
    const userID = await viewer(request);
    await db.query('DELETE FROM likes WHERE user_id=$1 AND post_id=$2', [userID, idOf(request)]);
    return reply.code(204).send();
  });
  app.post('/v1/posts/:id/report', async (request, reply) => {
    const userID = await viewer(request);
    const id = idOf(request);
    const { reason } = z.object({ reason: z.string().trim().min(5).max(1000) }).parse(request.body);
    await getPost(id, userID);
    await db.query(`INSERT INTO reports(user_id, post_id, reason) VALUES($1,$2,$3)
      ON CONFLICT(user_id, post_id) DO UPDATE SET reason=excluded.reason, resolved=false`, [userID, id, reason]);
    return reply.code(204).send();
  });

  app.get('/v1/photos/:id', async (request, reply) => {
    const userID = await viewer(request, false);
    const [row] = await db.query(`SELECT ph.data FROM photos ph JOIN posts p ON p.id=ph.post_id WHERE ph.id=$1
      AND (p.status <> 'hidden' OR p.author_id=$2 OR EXISTS(SELECT 1 FROM country_admins a WHERE a.user_id=$2 AND a.country_code=p.country_code))`, [idOf(request), userID]);
    if (!row) throw new APIError(404, 'Photo not found.');
    return reply.type('image/jpeg').send(Buffer.from(row.data));
  });

  app.get('/v1/moderation', async request => {
    const id = (await viewer(request))!;
    const profile = await user(id);
    if (!profile.adminCountries.length) throw new APIError(403, 'Country administrator access is required.');
    const query = z.object({ cursor: z.string().max(500).optional(), limit: z.coerce.number().int().min(1).max(100).default(50) }).parse(request.query);
    const params: unknown[] = [id, base];
    let after = '';
    if (query.cursor) {
      try {
        const cursor = z.object({ date: z.iso.datetime({ offset: true }), id: uuid }).parse(JSON.parse(Buffer.from(query.cursor, 'base64url').toString()));
        params.push(cursor.date, cursor.id);
        after = 'AND (p.created_at,p.id) < ($3::timestamptz,$4::uuid)';
      } catch { throw new APIError(400, 'Refresh the administration feed to continue.'); }
    }
    params.push(query.limit + 1);
    const posts = await db.query(`${selectPost} WHERE p.country_code IN (SELECT country_code FROM country_admins WHERE user_id=$1) ${after}
      ORDER BY p.created_at DESC, p.id DESC LIMIT $${params.length}`, params);
    const hasMore = posts.length > query.limit;
    if (hasMore) posts.pop();
    const last = posts.at(-1);
    const nextCursor = hasMore && last ? Buffer.from(JSON.stringify({ date: new Date(last.createdAt).toISOString(), id: last.id })).toString('base64url') : null;
    const reports = await db.query(`SELECT r.id, r.post_id AS "postID", p.name AS "postName", p.country_code AS "countryCode", r.reason, r.created_at AS "createdAt" FROM reports r JOIN posts p ON p.id=r.post_id
      WHERE NOT r.resolved AND p.country_code IN (SELECT country_code FROM country_admins WHERE user_id=$1) ORDER BY r.created_at`, [id]);
    return { posts, reports, nextCursor };
  });
  app.patch('/v1/moderation/posts/:id', async request => {
    const userID = (await viewer(request))!;
    const id = idOf(request);
    const { status } = z.object({ status: z.enum(['available', 'adopted', 'hidden']) }).strict().parse(request.body);
    return db.transaction(async tx => {
      const [post] = await tx.query('SELECT country_code, status FROM posts WHERE id=$1 FOR UPDATE', [id]);
      if (!post) throw new APIError(404, 'Post not found.');
      if (!(await canAdmin(userID, post.country_code, tx))) throw new APIError(403, 'You can only moderate posts in your assigned countries.');
      await tx.query('UPDATE posts SET status=$1, updated_at=now() WHERE id=$2', [status, id]);
      await tx.query('UPDATE reports SET resolved=true WHERE post_id=$1', [id]);
      await tx.query('INSERT INTO moderation_events(admin_id, post_id, previous_status, new_status) VALUES($1,$2,$3,$4)', [userID, id, post.status, status]);
      return getPost(id, userID, tx);
    });
  });
  app.post('/v1/moderation/reports/:id/resolve', async (request, reply) => {
    const userID = (await viewer(request))!;
    const rows = await db.query(`UPDATE reports r SET resolved=true FROM posts p WHERE r.id=$1 AND p.id=r.post_id
      AND EXISTS(SELECT 1 FROM country_admins a WHERE a.user_id=$2 AND a.country_code=p.country_code) RETURNING r.id`, [idOf(request), userID]);
    if (!rows.length) throw new APIError(403, 'You can only resolve reports in your assigned countries.');
    return reply.code(204).send();
  });

  function html(title: string, content: string, image?: string, description = 'Help shelter and street dogs and cats find a home.') {
    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escaped(title)}</title><meta property="og:title" content="${escaped(title)}"><meta property="og:description" content="${escaped(description)}">${image ? `<meta property="og:image" content="${escaped(image)}">` : ''}<style>body{font:18px system-ui;color:#142d4f;background:#f5f8fc;margin:0}main{max-width:620px;margin:48px auto;padding:24px}img{width:100%;max-height:500px;object-fit:cover;border-radius:24px}h1{font-size:42px;letter-spacing:-1.5px}a.button{display:inline-block;background:#224dc7;color:white;text-decoration:none;padding:16px 24px;border-radius:16px;margin:8px 0}p{line-height:1.65;white-space:pre-wrap}small{color:#526681}</style></head><body><main><small>♥ Heart Adoption</small>${content}</main></body></html>`;
  }
  app.get('/p/:id', async (request, reply) => {
    const post = await getPost(idOf(request), null);
    const title = `${post.name} is looking for a home`;
    const photo = post.photos[0]?.url as string | undefined;
    return reply.type('text/html').send(html(title, `${photo ? `<img src="${escaped(photo)}" alt="${escaped(post.name)}">` : ''}<h1>${escaped(post.name)}</h1><p>${escaped(post.city)}, ${escaped(post.countryCode)}${post.status === 'adopted' ? ' · Adopted' : ''}</p><p>${escaped(post.story)}</p><a class="button" href="heartadoption://post/${post.id}">Open in Heart Adoption</a><p><a href="mailto:${escaped(post.contactEmail)}">Contact the person caring for ${escaped(post.name)}</a></p>`, photo, post.story.slice(0, 180)));
  });
  app.get('/invite', async (_request, reply) => reply.type('text/html').send(html('A home changes everything.', `<h1>A home changes everything.</h1><p>Find dogs and cats looking for a family. Follow country groups, share an animal's story, and help them find their people.</p><a class="button" href="heartadoption://invite">Open Heart Adoption</a>${options.appStoreURL ? `<p><a href="${escaped(options.appStoreURL)}">Get the iOS app</a></p>` : '<p>The iOS app is currently in development. Ask the person who invited you for the TestFlight link.</p>'}`)));
  app.get('/', async (_request, reply) => reply.redirect('/invite'));
  return app;
}
