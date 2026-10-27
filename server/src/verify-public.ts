import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import type { Database } from './database.js';

/** Checks the actual HTTPS deployment, using temporary accounts removed on exit. */
export async function verifyPublic(db: Database, publicURL: string) {
  const base = publicURL.replace(/\/$/, '');
  if (!base.startsWith('https://')) throw new Error('PUBLIC_URL must be the deployed HTTPS origin.');
  const suffix = randomUUID(); const password = randomUUID();
  const accounts: { id: string; token: string }[] = [];
  async function call(path: string, method = 'GET', body?: unknown, token?: string, expected = 200): Promise<any> {
    const response = await fetch(base + path, {
      method, headers: { ...(body ? { 'content-type': 'application/json' } : {}), ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(45_000),
    });
    const text = await response.text();
    assert.equal(response.status, expected, `${method} ${path}: ${text.slice(0, 500)}`);
    return text ? JSON.parse(text) : undefined;
  }
  try {
    await call('/health');
    for (const country of ['IT', 'GR']) {
      const result = await call('/v1/auth/register', 'POST', { email: `public-${country}-${suffix}@example.invalid`, password, name: 'Deployment verification', homeCountry: country }, undefined, 201);
      accounts.push({ id: result.user.id, token: result.token });
    }
    const [author, admin] = accounts;
    const photo = (await readFile(new URL('../../HeartAdoption/Assets.xcassets/milo.imageset/milo.jpg', import.meta.url))).toString('base64');
    const posts: any[] = [];
    for (const [species, country] of [['dog', 'IT'], ['cat', 'GR']]) {
      posts.push(await call('/v1/posts', 'POST', { name: `Check ${species} ${suffix}`, species, sex: 'female', ageMonths: 18, size: 'small', source: 'shelter', countryCode: country, city: 'Verification', story: 'Temporary deployment verification record; automatically removed after the check.', contactEmail: 'verification@example.invalid', vaccinated: true, neutered: true, photos: [photo] }, author!.token, 201));
    }
    const dog = posts[0];
    assert.equal(new URL(dog.photos[0].url).origin, base);
    assert.ok((await call(`/v1/posts?scope=all&q=${suffix}`)).posts.length === 2);
    await call('/v1/countries/IT/follow', 'PUT', undefined, admin!.token, 204);
    const following = await call('/v1/posts?scope=following', 'GET', undefined, admin!.token);
    assert.ok(posts.every(post => following.posts.some((p: any) => p.id === post.id)));
    await call(`/v1/posts/${dog.id}/like`, 'PUT', undefined, admin!.token, 204);
    assert.equal((await call(`/v1/posts/${dog.id}`, 'GET', undefined, admin!.token)).likesCount, 1);
    const image = await fetch(dog.photos[0].url); assert.equal(image.status, 200); assert.equal(image.headers.get('content-type'), 'image/jpeg'); assert.ok((await image.arrayBuffer()).byteLength > 100);
    const share = await fetch(base + '/p/' + dog.id); assert.equal(share.status, 200); assert.match(await share.text(), /og:image/);
    const invite = await fetch(base + '/invite'); assert.equal(invite.status, 200); assert.match(await invite.text(), /heartadoption:\/\/invite/);
    await call(`/v1/moderation/posts/${dog.id}`, 'PATCH', { status: 'hidden' }, admin!.token, 403);
    await db.query('INSERT INTO country_admins(user_id,country_code) VALUES($1,$2),($1,$3)', [admin!.id, 'IT', 'GR']);
    assert.equal((await call('/v1/me', 'GET', undefined, admin!.token)).adminCountries.length, 2);
    await call('/v1/moderation?limit=1', 'GET', undefined, admin!.token);
    await call(`/v1/moderation/posts/${dog.id}`, 'PATCH', { status: 'hidden' }, admin!.token);
    await call(`/v1/posts/${dog.id}`, 'GET', undefined, undefined, 404);
    assert.equal((await fetch(dog.photos[0].url)).status, 404);
    assert.equal((await fetch(base + '/p/' + dog.id)).status, 404);
    for (const account of accounts) await call('/v1/me', 'DELETE', { password }, account.token, 204);
    console.log('Public HTTPS verification passed: accounts, dogs/cats with processed photos, cross-country feeds, follows, likes, social pages, invitations, and country-scoped moderation.');
  } finally {
    for (const account of accounts) await db.query('DELETE FROM users WHERE id=$1', [account.id]);
  }
}
