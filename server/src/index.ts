import { connectDatabase, migrate } from './database.js';
import { createApp } from './app.js';

const connection = process.env.DATABASE_URL ?? 'pglite://.data/local';
if (process.env.NODE_ENV === 'production' && (!process.env.DATABASE_URL || connection.startsWith('pglite:'))) throw new Error('Production requires a Neon DATABASE_URL.');
const local = process.argv.includes('--local');
if (local && process.env.NODE_ENV === 'production') throw new Error('--local is only available in development.');
const port = Number(process.env.PORT ?? 8787);
const publicURL = local ? `http://localhost:${port}` : process.env.PUBLIC_URL ?? `http://localhost:${port}`;
if (process.env.NODE_ENV === 'production' && !publicURL.startsWith('https://')) throw new Error('Production requires an HTTPS PUBLIC_URL.');
const db = await connectDatabase(connection);
await migrate(db);
if (process.argv.includes('--verify-neon')) {
  try { await (await import('./verify-neon.js')).verifyNeon(db); }
  finally { await db.close(); }
  process.exit(0);
}
const app = await createApp(db, { publicURL, appStoreURL: process.env.APP_STORE_URL, logger: true });
await app.listen({ port, host: local ? '127.0.0.1' : process.env.HOST ?? '127.0.0.1' });
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.once(signal, async () => { await app.close(); await db.close(); process.exit(0); });
