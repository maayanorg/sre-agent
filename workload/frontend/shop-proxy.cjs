'use strict';
const allowed = route => /^\/api\/shop\/(catalog|media|checkout|orders\/[0-9a-f-]{36})$/.test(route);
async function readBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 8192) throw new Error('Body too large');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
function createShopProxy(transport, { maxRequests = 120, maxCheckouts = 10, maxConcurrent = 8, now = Date.now } = {}) {
  let windowStart = now(), requests = 0, checkouts = 0, active = 0;
  return async (request, response) => {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('Content-Type', 'application/json');
    const route = request.url.split('?')[0];
    if (!allowed(route)) { response.writeHead(404); response.end('{}'); return; }
    const method = route === '/api/shop/checkout' ? 'POST' : 'GET';
    if (request.method !== method) { response.writeHead(405); response.end('{}'); return; }
    if (method === 'POST') {
      let sameOrigin = false;
      try { sameOrigin = new URL(request.headers.origin).host === request.headers.host; } catch {}
      if (!sameOrigin || request.headers['sec-fetch-site'] === 'cross-site' || !request.headers['content-type']?.startsWith('application/json')) {
        response.writeHead(403); response.end(JSON.stringify({ error: 'Checkout requires a same-origin JSON request.' })); return;
      }
    }
    if (now() - windowStart >= 60000) { windowStart = now(); requests = 0; checkouts = 0; }
    if (active >= maxConcurrent || requests >= maxRequests || (method === 'POST' && checkouts >= maxCheckouts)) {
      response.setHeader('Retry-After', '60');
      response.writeHead(429); response.end(JSON.stringify({ error: 'Demo request limit reached. Please retry shortly with the same checkout reference.' })); return;
    }
    requests++; if (method === 'POST') checkouts++;
    active++;
    try {
      let body;
      if (method === 'POST') {
        try { body = await readBody(request); }
        catch { response.writeHead(400); response.end(JSON.stringify({ error: 'Invalid checkout request.' })); return; }
      }
      const result = await transport({ route, method, body });
      response.writeHead(result.status); response.end(JSON.stringify(result.body));
    } catch {
      response.writeHead(503); response.end(JSON.stringify({ error: 'Shop connection unavailable. Retry checkout with the same reference.' }));
    } finally { active--; }
  };
}
function clientTransport(fetcher = fetch, clientUrl = 'http://10.70.1.4:8080') {
  return async ({ route, method, body }) => {
    const response = await fetcher(`${clientUrl}${route.replace('/api/shop/', '/shop/')}`, {
      method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined,
      redirect: 'error', signal: AbortSignal.timeout(30000)
    });
    const chunks = [];
    let size = 0;
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > 600000) throw new Error('Shop response too large');
      chunks.push(chunk);
    }
    return { status: response.status, body: JSON.parse(Buffer.concat(chunks).toString('utf8')) };
  };
}
module.exports = { allowed, createShopProxy, clientTransport };