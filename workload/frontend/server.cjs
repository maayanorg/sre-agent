'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { createShopProxy, clientTransport } = require('./shop-proxy.cjs');

const targets = [
  { id: 'backend', label: 'Backend API', url: 'http://backend.srelab.internal:8081/health', path: 'AKS > private DNS > backend VM' },
  { id: 'client', label: 'Client API', url: 'http://10.70.1.4:8080/health', path: 'AKS > client VM > backend VM' },
  { id: 'storage', label: 'Blob Storage', url: 'http://10.70.1.4:8080/storage', path: 'Client VM > private endpoint > Blob Storage' },
  { id: 'vault', label: 'Key Vault', url: 'http://10.70.1.4:8080/vault', path: 'Client VM > private endpoint > Key Vault' },
  { id: 'arm', label: 'Azure Resource Manager', url: 'http://10.70.1.4:8080/arm', path: 'Client VM > managed identity > ARM' }
];

function createDashboard({ fetcher = fetch, timeoutMs = 12000, intervalMs = 10000, checks = targets, shopTransport = clientTransport() } = {}) {
  const shopProxy = createShopProxy(shopTransport);
  let snapshot = null;
  let running = null;
  let timer = null;
  let stopped = false;

  async function collect() {
    if (running) return running;
    running = (async () => {
      const results = await Promise.all(checks.map(async target => {
        const started = performance.now();
        try {
          const response = await fetcher(target.url, { signal: AbortSignal.timeout(timeoutMs), redirect: 'error' });
          await response.body?.cancel();
          return { id: target.id, label: target.label, path: target.path, healthy: response.status === 200,
            code: response.status, latencyMs: Math.round(performance.now() - started), detail: response.status === 200 ? 'Request succeeded' : 'Dependency returned an error' };
        } catch {
          return { id: target.id, label: target.label, path: target.path, healthy: false, code: null,
            latencyMs: Math.round(performance.now() - started), detail: 'No response: timeout, DNS or connection failure' };
        }
      }));
      const web = { id: 'web', label: 'AKS Web', path: 'Browser > web Service > Node.js pod', healthy: true, code: 200, latencyMs: null, detail: 'Status API responded' };
      snapshot = { version: 1, observedAt: new Date().toISOString(), overall: results.every(result => result.healthy) ? 'healthy' : 'degraded',
        checks: [web, ...results], instance: process.env.HOSTNAME || 'local', transport: 'direct' };
      console.log(JSON.stringify({ event: 'dependency-check', observedAt: snapshot.observedAt, overall: snapshot.overall,
        checks: snapshot.checks.map(({ id, healthy, code }) => ({ id, healthy, code })) }));
      return snapshot;
    })();
    try { return await running; } finally { running = null; }
  }

  const server = http.createServer(async (request, response) => {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Referrer-Policy', 'no-referrer');
    if (request.url.startsWith('/api/shop/')) return shopProxy(request, response);
    if (request.method !== 'GET') { response.writeHead(405); response.end(); return; }
    const route = request.url.split('?')[0];
    if (route === '/healthz') { response.writeHead(200); response.end('ok'); return; }
    if (route === '/api/status') {
      response.setHeader('Content-Type', 'application/json');
      if (!snapshot) { response.writeHead(503); response.end(JSON.stringify({ error: 'Initial checks in progress' })); return; }
      const stale = Date.now() - Date.parse(snapshot.observedAt) > 45000;
      response.writeHead(stale ? 503 : 200);
      response.end(JSON.stringify({ ...snapshot, stale }));
      return;
    }
    if (route === '/' || route === '/index.html' || route === '/health') {
      response.setHeader('Content-Type', 'text/html; charset=utf-8');
      response.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'");
      response.end(fs.readFileSync(path.join(__dirname, route === '/health' ? 'index.html' : 'shop.html')));
      return;
    }
    response.writeHead(404); response.end('Not found');
  });

  async function cycle() {
    try { await collect(); } finally { if (!stopped) timer = setTimeout(cycle, intervalMs); }
  }
  return { server, collect, start: () => { stopped = false; void cycle(); }, stop: () => { stopped = true; clearTimeout(timer); } };
}

if (require.main === module) {
  const app = createDashboard();
  app.server.listen(Number(process.env.PORT || 8080), '0.0.0.0', () => app.start());
  process.on('SIGTERM', () => { app.stop(); app.server.close(); });
}
module.exports = { createDashboard };