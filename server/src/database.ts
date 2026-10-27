import { PGlite } from '@electric-sql/pglite';
import { connectPostgres } from './postgres.js';
import { readFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

export interface Database {
  query<T extends Record<string, any> = Record<string, any>>(sql: string, params?: unknown[]): Promise<T[]>;
  transaction<T>(work: (db: Database) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

export async function connectDatabase(connection: string): Promise<Database> {
  if (connection.startsWith('pglite://')) {
    const path = connection.slice('pglite://'.length);
    if (path) await mkdir(resolve(path), { recursive: true });
    const client = new PGlite(path || undefined);
    const wrap = (executor: Pick<PGlite, 'query'>): Database => ({
      query: async <T extends Record<string, any>>(sql: string, params?: unknown[]) => (await executor.query<T>(sql, params)).rows,
      transaction: async work => client.transaction(tx => work(wrap(tx))),
      close: () => client.close(),
    });
    return wrap(client);
  }
  return connectPostgres(connection);
}

export async function migrate(db: Database) {
  // A transaction and advisory lock prevent concurrent API processes racing migrations.
  await db.transaction(async tx => {
    await tx.query('SELECT pg_advisory_xact_lock(721608)');
    await tx.query('CREATE TABLE IF NOT EXISTS schema_migrations (version integer PRIMARY KEY)');
    if ((await tx.query('SELECT version FROM schema_migrations WHERE version = 1')).length) return;
    const sql = await readFile(new URL('../migrations/001_initial.sql', import.meta.url), 'utf8');
    // This migration contains no function bodies, so semicolon splitting is deliberate.
    for (const statement of sql.split(';').map(s => s.trim()).filter(Boolean)) await tx.query(statement);
    const countries = JSON.parse(await readFile(new URL('../../Resources/countries.json', import.meta.url), 'utf8')) as { code: string; name: string }[];
    await tx.query('INSERT INTO countries(code, name) SELECT code, name FROM jsonb_to_recordset($1::jsonb) AS x(code text, name text)', [JSON.stringify(countries)]);
    await tx.query('INSERT INTO schema_migrations(version) VALUES(1)');
  });
}
