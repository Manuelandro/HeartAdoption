import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import type { Database } from './database.js';
import { createApp } from './app.js';

/** Uses isolated temporary accounts and removes them (and their posts/photos) on exit. */
export async function verifyNeon(db: Database) {
  const app = await createApp(db, { publicURL: 'http://localhost:8787', rateLimits: false });
  const suffix = randomUUID(); const password = randomUUID();
  const accounts: { id: string; token: string }[] = [];
  const authorization = (token: string) => ({ authorization: `Bearer ${token}` });
  try {
    for (const homeCountry of ['IT', 'GR']) {
      const response = await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email: `verification-${homeCountry}-${suffix}@example.invalid`, password, name: `Verification ${homeCountry}`, homeCountry } });
      assert.equal(response.statusCode, 201, response.body);
      const account = response.json(); accounts.push({ id: account.user.id, token: account.token });
    }
    const [author, admin] = accounts;
    const photo = (await readFile(new URL('../../HeartAdoption/Assets.xcassets/milo.imageset/milo.jpg', import.meta.url))).toString('base64');
    const postBody = { name: 'Neon verification dog', species: 'dog', sex: 'male', ageMonths: 24, size: 'medium', source: 'shelter', countryCode: 'IT', city: 'Florence', story: 'Temporary verification post. This record is removed when the checks finish.', contactEmail: 'verification@example.invalid', vaccinated: true, neutered: true, photos: [photo] };
    const created = await app.inject({ method: 'POST', url: '/v1/posts', headers: authorization(author!.token), payload: postBody });
    assert.equal(created.statusCode, 201, created.body); const post = created.json();
    assert.equal((await app.inject({ url: '/v1/posts?scope=country&country=IT', headers: authorization(admin!.token) })).json().posts.some((p: { id: string }) => p.id === post.id), true);
    assert.equal((await app.inject({ method: 'PUT', url: '/v1/countries/IT/follow', headers: authorization(admin!.token) })).statusCode, 204);
    assert.equal((await app.inject({ url: '/v1/posts?scope=following', headers: authorization(admin!.token) })).json().posts.some((p: { id: string }) => p.id === post.id), true);
    assert.equal((await app.inject({ method: 'PUT', url: `/v1/posts/${post.id}/like`, headers: authorization(admin!.token) })).statusCode, 204);
    assert.equal((await app.inject({ url: `/v1/posts/${post.id}`, headers: authorization(admin!.token) })).json().likesCount, 1);
    assert.equal((await app.inject({ url: `/v1/photos/${post.photos[0].id}` })).statusCode, 200);
    assert.equal((await app.inject({ url: `/p/${post.id}` })).statusCode, 200);
    assert.equal((await app.inject({ method: 'PATCH', url: `/v1/moderation/posts/${post.id}`, headers: authorization(admin!.token), payload: { status: 'hidden' } })).statusCode, 403);
    await db.query('INSERT INTO country_admins(user_id,country_code) VALUES($1,$2),($1,$3)', [admin!.id, 'IT', 'GR']);
    assert.equal((await app.inject({ method: 'PATCH', url: `/v1/moderation/posts/${post.id}`, headers: authorization(admin!.token), payload: { status: 'hidden' } })).statusCode, 200);
    assert.equal((await app.inject({ url: `/p/${post.id}` })).statusCode, 404);
    assert.equal((await app.inject({ url: `/v1/photos/${post.photos[0].id}` })).statusCode, 404);
    const [result] = await db.query('SELECT count(*)::int AS count FROM countries'); assert.equal(result!.count, 249);
    console.log('Neon verification passed: accounts, photo post, country feed, following, likes, share page, and country-scoped moderation.');
  } finally {
    for (const account of accounts) await db.query('DELETE FROM users WHERE id=$1', [account.id]);
    await app.close();
  }
}
