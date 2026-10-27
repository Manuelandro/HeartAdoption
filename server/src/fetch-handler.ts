import type { FastifyInstance } from 'fastify';

const maxBody = 13 * 1024 * 1024;

/** Adapt the existing API to Neon's Fetch contract, preserving binary photos. */
export function createFetchHandler(app: FastifyInstance) {
  return async (request: Request): Promise<Response> => {
    const url = new URL(request.url);
    type Method = 'GET' | 'HEAD' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'OPTIONS';
    if (!['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'].includes(request.method)) return new Response(null, { status: 405 });
    let payload: Buffer | undefined;
    if (request.body) {
      const reader = request.body.getReader();
      const chunks: Uint8Array[] = []; let size = 0;
      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > maxBody) {
            await reader.cancel();
            return Response.json({ message: 'The upload is too large. Use up to six photos under 1.5 MB each.' }, { status: 413 });
          }
          chunks.push(value);
        }
      } catch { return Response.json({ message: 'The upload was interrupted. Please try again.' }, { status: 400 }); }
      payload = Buffer.concat(chunks);
    }
    const result = await app.inject({
      method: request.method as Method,
      url: url.pathname + url.search,
      headers: Object.fromEntries(request.headers),
      payload,
    });
    const headers = new Headers();
    for (const [name, value] of Object.entries(result.headers)) {
      if (value == null || ['connection', 'transfer-encoding', 'keep-alive'].includes(name.toLowerCase())) continue;
      if (Array.isArray(value)) for (const item of value) headers.append(name, String(item));
      else headers.set(name, String(value));
    }
    const noBody = request.method === 'HEAD' || [204, 205, 304].includes(result.statusCode);
    return new Response(noBody ? null : new Uint8Array(result.rawPayload), { status: result.statusCode, headers });
  };
}
