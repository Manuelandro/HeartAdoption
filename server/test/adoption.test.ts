import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import sharp from 'sharp';
import { connectDatabase, migrate } from '../src/database.js';
import { createApp } from '../src/app.js';

test('shared adoption workflow and country authorization', async t => {
  const db = await connectDatabase('pglite://');
  await migrate(db);
  const app = await createApp(db, { publicURL: 'https://adoption.example', rateLimits: false });
  const photo = (await sharp({ create: { width: 20, height: 20, channels: 3, background: '#224dc7' } }).jpeg().toBuffer()).toString('base64');
  const auth = (token: string) => ({ authorization: `Bearer ${token}` });
  const register = async (email: string, country = 'IT') => {
    const response = await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: 'A-long-test-password!', name: email.split('@')[0], homeCountry: country } });
    assert.equal(response.statusCode, 201, response.body); return response.json();
  };
  const body = (name: string, countryCode = 'IT', species = 'dog') => ({ name, countryCode, species, sex: 'female', ageMonths: 18, size: 'medium', source: 'street', city: countryCode === 'IT' ? 'Florence' : 'Athens', story: `${name} is a gentle rescue who loves company and long walks.`, contactEmail: 'rescue@example.org', vaccinated: true, neutered: true, photos: [photo] });
  let alice: any, bob: any, moderator: any, italy: any, greece: any, portugal: any;
  try {
    await t.test('accounts are independent and passwords and sessions are hashed', async () => {
      alice = await register('ALICE@example.org'); bob = await register('bob@example.org', 'GR'); moderator = await register('moderator@example.org');
      assert.equal(alice.user.email, 'alice@example.org'); assert.deepEqual(alice.user.adminCountries, []);
      assert.deepEqual(alice.user.followedCountries, ['IT']);
      const [secret] = await db.query('SELECT password_hash FROM users WHERE id=$1', [alice.user.id]);
      assert.notEqual(secret!.password_hash, 'A-long-test-password!');
      assert.equal((await db.query('SELECT 1 FROM sessions WHERE token_hash=$1', [alice.token])).length, 0);
      const login = await app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: 'alice@example.org', password: 'A-long-test-password!' } });
      assert.equal(login.statusCode, 200, login.body);
      const wrong = await app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: 'alice@example.org', password: 'A-wrong-password!' } });
      assert.equal(wrong.statusCode, 401);
    });
    await t.test('regular users cannot assign administrator roles', async () => {
      const injectRole = await app.inject({ method: 'PATCH', url: '/v1/me', headers: auth(alice.token), payload: { name: 'Alice', homeCountry: 'IT', adminCountries: ['IT', 'GR'] } });
      assert.equal(injectRole.statusCode, 400);
      const roleOnSignup = await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email: 'intruder@example.org', password: 'A-long-test-password!', name: 'Intruder', homeCountry: 'IT', adminCountries: ['IT'] } });
      assert.equal(roleOnSignup.statusCode, 400);
      assert.equal((await app.inject({ url: '/v1/moderation', headers: auth(alice.token) })).statusCode, 403);
    });
    await t.test('posting validates photos, species, country, and authentication', async () => {
      assert.equal((await app.inject({ method: 'POST', url: '/v1/posts', payload: body('Milo') })).statusCode, 401);
      for (const invalid of [{ ...body('Milo'), photos: [] }, { ...body('Milo'), photos: ['bm90LWFuLWltYWdl'] }, { ...body('Milo'), species: 'rabbit' }, { ...body('Milo'), countryCode: 'XX' }, { ...body('Milo'), story: 'short' }]) {
        const response = await app.inject({ method: 'POST', url: '/v1/posts', headers: auth(alice.token), payload: invalid });
        assert.equal(response.statusCode, 400, response.body);
      }
      for (const [name, country, species] of [['Milo', 'IT', 'dog'], ['Luna', 'GR', 'cat'], ['Olive', 'PT', 'dog']]) {
        const response = await app.inject({ method: 'POST', url: '/v1/posts', headers: auth(alice.token), payload: body(name!, country, species) });
        assert.equal(response.statusCode, 201, response.body);
        if (country === 'IT') italy = response.json(); else if (country === 'GR') greece = response.json(); else portugal = response.json();
      }
      assert.equal((await db.query('SELECT count(*)::int AS n FROM posts'))[0]!.n, 3, 'invalid posts do not leave partial records');
      const image = await app.inject({ url: `/v1/photos/${italy.photos[0].id}` });
      assert.equal(image.statusCode, 200); assert.equal(image.headers['content-type'], 'image/jpeg');
      assert.equal((await sharp(image.rawPayload).metadata()).exif, undefined, 'uploads strip metadata');
    });
    await t.test('home feed defaults to the signed-in user’s country', async () => {
      const home = await app.inject({ url: '/v1/posts', headers: auth(bob.token) });
      assert.deepEqual(home.json().posts.map((p: any) => p.id), [greece.id]);
      const group = await app.inject({ url: '/v1/posts?scope=country&country=IT' });
      assert.deepEqual(group.json().posts.map((p: any) => p.id), [italy.id]);
    });
    await t.test('following another country includes its posts and unfollowing removes them', async () => {
      for (let i = 0; i < 2; i++) assert.equal((await app.inject({ method: 'PUT', url: '/v1/countries/GR/follow', headers: auth(alice.token) })).statusCode, 204);
      let following = (await app.inject({ url: '/v1/posts?scope=following', headers: auth(alice.token) })).json();
      assert.deepEqual(new Set(following.posts.map((p: any) => p.id)), new Set([italy.id, greece.id]));
      assert.equal((await app.inject({ method: 'DELETE', url: '/v1/countries/GR/follow', headers: auth(alice.token) })).statusCode, 204);
      following = (await app.inject({ url: '/v1/posts?scope=following', headers: auth(alice.token) })).json();
      assert.deepEqual(following.posts.map((p: any) => p.id), [italy.id]);
    });
    await t.test('search crosses borders and species filters work', async () => {
      const found = (await app.inject({ url: '/v1/posts?scope=all&q=Luna&species=cat', headers: auth(alice.token) })).json();
      assert.deepEqual(found.posts.map((p: any) => p.id), [greece.id]);
      const dogs = (await app.inject({ url: '/v1/posts?scope=all&species=dog' })).json();
      assert.equal(dogs.posts.length, 2);
      assert.equal((await app.inject({ url: '/v1/posts?scope=all&q=%25' })).json().posts.length, 0, 'SQL wildcard characters are searched literally');
    });
    await t.test('keyset pagination does not duplicate or omit posts with identical timestamps', async () => {
      await db.query("UPDATE posts SET created_at='2026-10-20T10:00:00.123Z'");
      const collected: string[] = []; let cursor: string | null = null;
      do {
        const page = (await app.inject({ url: '/v1/posts?scope=all&limit=1' + (cursor ? `&cursor=${cursor}` : '') })).json();
        collected.push(...page.posts.map((p: any) => p.id)); cursor = page.nextCursor;
      } while (cursor);
      assert.equal(collected.length, 3); assert.equal(new Set(collected).size, 3);
      assert.equal((await app.inject({ url: '/v1/posts?scope=all&cursor=invalid' })).statusCode, 400);
    });
    await t.test('likes are idempotent and scoped to the person liking the post', async () => {
      for (let i = 0; i < 2; i++) assert.equal((await app.inject({ method: 'PUT', url: `/v1/posts/${italy.id}/like`, headers: auth(bob.token) })).statusCode, 204);
      const post = (await app.inject({ url: `/v1/posts/${italy.id}`, headers: auth(bob.token) })).json();
      assert.equal(post.likesCount, 1); assert.equal(post.liked, true);
      assert.equal((await app.inject({ url: `/v1/posts/${italy.id}`, headers: auth(alice.token) })).json().liked, false);
      assert.equal((await app.inject({ url: '/v1/posts?scope=liked', headers: auth(bob.token) })).json().posts[0].id, italy.id);
      assert.equal((await app.inject({ method: 'DELETE', url: `/v1/posts/${italy.id}/like`, headers: auth(bob.token) })).statusCode, 204);
      assert.equal((await app.inject({ url: '/v1/posts?scope=liked', headers: auth(bob.token) })).json().posts.length, 0);
    });
    await t.test('sharing has a public animal page and an invitation landing page', async () => {
      const page = await app.inject({ url: `/p/${italy.id}` }); assert.equal(page.statusCode, 200); assert.match(page.body, /og:image/); assert.match(page.body, /heartadoption:\/\/post\//);
      assert.match((await app.inject({ url: '/invite' })).body, /heartadoption:\/\/invite/);
    });
    await t.test('one administrator can moderate multiple countries but cannot touch another country', async () => {
      for (const code of ['IT', 'GR']) await db.query('INSERT INTO country_admins(user_id,country_code) VALUES($1,$2)', [moderator.user.id, code]);
      const me = (await app.inject({ url: '/v1/me', headers: auth(moderator.token) })).json(); assert.deepEqual(me.adminCountries, ['GR', 'IT']);
      const report = await app.inject({ method: 'POST', url: `/v1/posts/${italy.id}/report`, headers: auth(bob.token), payload: { reason: 'The contact details need a moderator review.' } }); assert.equal(report.statusCode, 204);
      const moderation = (await app.inject({ url: '/v1/moderation', headers: auth(moderator.token) })).json();
      assert.deepEqual(new Set(moderation.posts.map((p: any) => p.countryCode)), new Set(['IT', 'GR'])); assert.equal(moderation.reports.length, 1);
      const firstPage = (await app.inject({ url: '/v1/moderation?limit=1', headers: auth(moderator.token) })).json();
      assert.equal(firstPage.posts.length, 1); assert.ok(firstPage.nextCursor);
      const secondPage = (await app.inject({ url: `/v1/moderation?limit=1&cursor=${firstPage.nextCursor}`, headers: auth(moderator.token) })).json();
      assert.equal(secondPage.posts.length, 1); assert.notEqual(firstPage.posts[0].id, secondPage.posts[0].id);
      assert.equal(secondPage.nextCursor, null);
      const forbidden = await app.inject({ method: 'PATCH', url: `/v1/moderation/posts/${portugal.id}`, headers: auth(moderator.token), payload: { status: 'hidden' } }); assert.equal(forbidden.statusCode, 403);
      const hidden = await app.inject({ method: 'PATCH', url: `/v1/moderation/posts/${italy.id}`, headers: auth(moderator.token), payload: { status: 'hidden' } }); assert.equal(hidden.statusCode, 200, hidden.body);
      assert.equal((await app.inject({ url: `/v1/posts/${italy.id}` })).statusCode, 404);
      assert.equal((await app.inject({ url: `/v1/photos/${italy.photos[0].id}` })).statusCode, 404);
      assert.equal((await app.inject({ url: `/p/${italy.id}` })).statusCode, 404);
      assert.equal((await app.inject({ url: `/v1/posts/${italy.id}`, headers: auth(moderator.token) })).statusCode, 200);
      const { photos, ...edit } = body('Milo');
      assert.equal((await app.inject({ method: 'PATCH', url: `/v1/posts/${italy.id}`, headers: auth(alice.token), payload: { ...edit, status: 'available' } })).statusCode, 403, 'an owner cannot undo a moderation decision');
      assert.equal((await app.inject({ url: '/v1/moderation', headers: auth(moderator.token) })).json().reports.length, 0);
      assert.equal((await db.query('SELECT count(*)::int AS n FROM moderation_events'))[0]!.n, 1);
      const restore = await app.inject({ method: 'PATCH', url: `/v1/moderation/posts/${italy.id}`, headers: auth(moderator.token), payload: { status: 'available' } }); assert.equal(restore.statusCode, 200);
    });
    await t.test('only the author can edit and adopted animals leave discovery', async () => {
      const { photos, ...edit } = body('Milo');
      assert.equal((await app.inject({ method: 'PATCH', url: `/v1/posts/${italy.id}`, headers: auth(bob.token), payload: { ...edit, status: 'adopted' } })).statusCode, 403);
      const updated = await app.inject({ method: 'PATCH', url: `/v1/posts/${italy.id}`, headers: auth(alice.token), payload: { ...edit, status: 'adopted' } }); assert.equal(updated.statusCode, 200);
      assert.equal((await app.inject({ url: '/v1/posts?scope=country&country=IT' })).json().posts.length, 0);
      assert.equal((await app.inject({ url: '/v1/posts?scope=mine', headers: auth(alice.token) })).json().posts.length, 3);
    });
    await t.test('sign out revokes the token and account deletion removes posts and photos', async () => {
      assert.equal((await app.inject({ method: 'DELETE', url: '/v1/auth/session', headers: auth(bob.token) })).statusCode, 204);
      assert.equal((await app.inject({ url: '/v1/me', headers: auth(bob.token) })).statusCode, 401);
      const wrong = await app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(alice.token), payload: { password: 'wrong' } }); assert.equal(wrong.statusCode, 403);
      const deleted = await app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(alice.token), payload: { password: 'A-long-test-password!' } }); assert.equal(deleted.statusCode, 204);
      assert.equal((await db.query('SELECT count(*)::int AS n FROM posts'))[0]!.n, 0);
      assert.equal((await db.query('SELECT count(*)::int AS n FROM photos'))[0]!.n, 0);
      assert.equal((await app.inject({ url: '/v1/me', headers: auth(alice.token) })).statusCode, 401);
    });
  } finally { await app.close(); await db.close(); }
});

test('file-backed development database survives restart and migrations are repeatable', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'heart-db-'));
  try {
    const db = await connectDatabase(`pglite://${directory}`); await migrate(db); await db.close();
    const reopened = await connectDatabase(`pglite://${directory}`); await migrate(reopened);
    assert.equal((await reopened.query('SELECT count(*)::int AS n FROM countries'))[0]!.n, 249);
    await reopened.close();
  } finally { await rm(directory, { recursive: true, force: true }); }
});
