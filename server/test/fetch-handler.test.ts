import { test } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { createApp } from '../src/app.js';
import { connectDatabase, migrate } from '../src/database.js';
import { createFetchHandler } from '../src/fetch-handler.js';

test('Neon Fetch adapter preserves account, post, photo, sharing, and empty responses', async () => {
  const db = await connectDatabase('pglite://'); await migrate(db);
  const app = await createApp(db, { publicURL: 'https://function.example', rateLimits: false });
  const handler = createFetchHandler(app);
  const request = (path, method = 'GET', body?, token?) => new Request('https://function.example' + path, { method, headers: { ...(body ? { 'content-type': 'application/json' } : {}), ...(token ? { authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
  try {
    const registered = await handler(request('/v1/auth/register', 'POST', { email: 'fetch@example.org', password: 'A-long-test-password!', name: 'Fetch tester', homeCountry: 'IT' }));
    assert.equal(registered.status, 201); const { token } = await registered.json();
    const photo = await sharp({ create: { width: 30, height: 30, channels: 3, background: '#224dc7' } }).jpeg().toBuffer();
    const created = await handler(request('/v1/posts', 'POST', { name: 'Fetch puppy', species: 'dog', sex: 'male', ageMonths: 12, size: 'medium', source: 'shelter', countryCode: 'IT', city: 'Rome', story: 'A gentle puppy looking for a patient and loving family.', contactEmail: 'fetch@example.org', vaccinated: true, neutered: true, photos: [photo.toString('base64')] }, token));
    assert.equal(created.status, 201); const post = await created.json();
    const feed = await handler(request('/v1/posts?scope=all&q=Fetch')); assert.equal((await feed.json()).posts[0].id, post.id);
    const image = await handler(request(new URL(post.photos[0].url).pathname));
    assert.equal(image.headers.get('content-type'), 'image/jpeg');
    assert.equal((await sharp(Buffer.from(await image.arrayBuffer())).metadata()).width, 30);
    const page = await handler(request('/p/' + post.id)); assert.match(await page.text(), /og:image/);
    const liked = await handler(request(`/v1/posts/${post.id}/like`, 'PUT', undefined, token)); assert.equal(liked.status, 204); assert.equal(await liked.text(), '');
    const head = await handler(request('/health', 'HEAD')); assert.equal(await head.text(), '');
    const removed = await handler(request('/v1/me', 'DELETE', { password: 'A-long-test-password!' }, token)); assert.equal(removed.status, 204);
  } finally { await app.close(); await db.close(); }
});

test('Neon Fetch adapter rejects oversized bodies before dispatch', async () => {
  const db = await connectDatabase('pglite://'); const app = await createApp(db, { publicURL: 'https://function.example', rateLimits: false });
  try {
    const response = await createFetchHandler(app)(new Request('https://function.example/v1/posts', { method: 'POST', body: 'x'.repeat(13 * 1024 * 1024 + 1) }));
    assert.equal(response.status, 413);
  } finally { await app.close(); await db.close(); }
});
