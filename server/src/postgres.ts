import pg from 'pg';
import type { Database } from './database.js';

/** Kept separate so a Neon Function does not bundle the development WASM database. */
export function connectPostgres(connection: string): Database {
  const address = new URL(connection);
  if (address.hostname.endsWith('.neon.tech')) {
    address.searchParams.set('sslmode', 'verify-full');
    address.searchParams.delete('uselibpqcompat');
  }
  const pool = new pg.Pool({ connectionString: address.toString(), max: 5, connectionTimeoutMillis: 10_000 });
  pool.on('error', error => console.error('Idle database connection failed:', error.message));
  const wrap = (executor: Pick<pg.Pool, 'query'>): Database => ({
    query: async <T extends Record<string, any>>(sql: string, params?: unknown[]) => (await executor.query(sql, params)).rows as T[],
    transaction: async work => {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const result = await work(wrap(client));
        await client.query('COMMIT');
        return result;
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally { client.release(); }
    },
    close: () => pool.end(),
  });
  return wrap(pool);
}
