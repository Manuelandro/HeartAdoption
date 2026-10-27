import { connectPostgres } from './postgres.js';
import { createApp } from './app.js';
import { createFetchHandler } from './fetch-handler.js';

let handler: Promise<ReturnType<typeof createFetchHandler>> | undefined;

function initialize() {
  handler ??= (async () => {
    const connection = process.env.DATABASE_URL;
    const publicURL = process.env.PUBLIC_URL;
    if (!connection || !publicURL?.startsWith('https://')) throw new Error('DATABASE_URL and HTTPS PUBLIC_URL must be configured.');
    const db = connectPostgres(connection);
    // Migrations are run by the deployment command, before publishing the function.
    const app = await createApp(db, { publicURL, appStoreURL: process.env.APP_STORE_URL, logger: true, accountRateLimits: true });
    return createFetchHandler(app);
  })().catch(error => { handler = undefined; throw error; });
  return handler;
}

export default {
  async fetch(request: Request): Promise<Response> {
    try { return await (await initialize())(request); }
    catch (error) {
      console.error('Function request failed:', error instanceof Error ? error.message : 'Unknown error');
      return Response.json({ message: 'The adoption service is temporarily unavailable. Please try again.' }, { status: 503 });
    }
  },
};
