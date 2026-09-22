'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { createShop } = require('../workload/shop.cjs');
const { createShopProxy, clientTransport } = require('../workload/frontend/shop-proxy.cjs');
const root = path.resolve(__dirname, '..');
const directory = path.join(root, '.state/shop-preview');
fs.mkdirSync(directory, { recursive: true });
const config = { role: 'backend', release: 'v1', vault: 'local-fixture', storage: 'local-fixture' };
const azureRead = async (resource, url, format) => {
  if (format === 'bytes') {
    const id = new URL(url).pathname.split('/').pop();
    if (!/^(headphones|camera|watch|speaker)\.jpg$/.test(id)) throw new Error('Unknown fixture');
    return fs.readFileSync(path.join(root, '.state/shop-assets', id));
  }
  return { value: 'local-preview-only-not-an-azure-secret-123456' };
};
const backend = http.createServer(createShop({ getConfig: () => config, dataPath: directory, azureRead }));
let frontend;
backend.listen(0, '127.0.0.1', () => {
  const proxy = createShopProxy(clientTransport(fetch, `http://127.0.0.1:${backend.address().port}`));
  frontend = http.createServer((request, response) => {
    const port = frontend.address().port;
    if (![ `127.0.0.1:${port}`, `localhost:${port}` ].includes(request.headers.host)) { response.writeHead(403); response.end(); return; }
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    if (request.url.startsWith('/api/shop/')) return void proxy(request, response);
    if (request.url.startsWith('/api/')) { response.writeHead(503, { 'Content-Type': 'application/json' }); response.end('{"error":"Local preview has no Azure observations"}'); return; }
    const file = request.url.split('?')[0] === '/health' ? 'index.html' : 'shop.html';
    const html = fs.readFileSync(path.join(root, 'workload/frontend', file), 'utf8').replace('<body>', '<body><p style="margin:0;padding:10px 20px;background:var(--cp-warning);color:var(--cp-text)">LOCAL PREVIEW: fixture images and simulated dependencies. Not connected to Azure.</p>');
    response.setHeader('Content-Type', 'text/html; charset=utf-8'); response.end(html);
  });
  frontend.listen(Number(process.argv[2] || 8092), '127.0.0.1', () => console.log(`Local fixture preview (NOT Azure): http://127.0.0.1:${frontend.address().port}`));
  frontend.on('error', error => { console.error(error.message); backend.close(); process.exitCode = 1; });
});
function stop() { frontend?.closeAllConnections(); frontend?.close(); backend.closeAllConnections(); backend.close(); }
process.on('SIGINT', stop); process.on('SIGTERM', stop);