'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { execFile } = require('node:child_process');
const { createShopProxy } = require('./shop-proxy.cjs');
const root = path.resolve(__dirname, '../..');
const page = fs.readFileSync(path.join(root, '.state/frontend-page.html'));
const healthPage = fs.readFileSync(path.join(root, '.state/health-page.html'));
const shopChildren = new Set();
const shopProxy = createShopProxy(({ route, method, body }) => new Promise((resolve, reject) => {
  if (shopChildren.size >= 4 || stopped) { reject(new Error('Shop relay busy')); return; }
  const process = execFile('pwsh', ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', path.join(root, 'scripts/Invoke-ShopRequest.ps1'), '-Route', route, '-Method', method],
    { cwd: root, timeout: 240000, maxBuffer: 1024 * 1024, windowsHide: true }, (error, stdout) => {
      shopChildren.delete(process);
      try { if (error) throw error; resolve(JSON.parse(stdout.replace(/^\uFEFF/, ''))); } catch (error) { reject(error); }
    });
  shopChildren.add(process);
  process.stdin.on('error', () => {});
  process.stdin.end(body ? JSON.stringify(body) : '');
}));
const script = path.join(root, 'scripts/Get-DemoSnapshot.ps1');
const operationsScript = path.join(root, 'scripts/Get-OperationsSnapshot.ps1');
const port = Number(process.argv[2] || 8090);
let snapshot = null;
let observationError = true;
let timer;
let child;
let stopped = false;
let operations = null;
let operationsError = true;
let operationsTimer;
let operationsChild;

function refreshOperations() {
  operationsChild = execFile('pwsh', ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', operationsScript],
    { cwd: root, timeout: 180000, maxBuffer: 1024 * 1024, windowsHide: true }, (error, stdout) => {
      try {
        if (error) throw error;
        const next = JSON.parse(stdout.replace(/^\uFEFF/, ''));
        if (next.version !== 1 || !Array.isArray(next.checks)) throw new Error('Invalid operations observation');
        operations = next; operationsError = false;
        console.log(`${new Date().toISOString()} Operations: ${next.checks.filter(check => check.state === 'failed').length} failed checks`);
      } catch { operationsError = true; console.error('Operations observation unavailable.'); }
      if (!stopped) operationsTimer = setTimeout(refreshOperations, 30000);
    });
}

function refresh() {
  child = execFile('pwsh', ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', script],
    { cwd: root, timeout: 150000, maxBuffer: 1024 * 1024, windowsHide: true }, (error, stdout) => {
      try {
        if (error) throw error;
        const next = JSON.parse(stdout.replace(/^\uFEFF/, ''));
        if (next.version !== 1 || !Array.isArray(next.checks)) throw new Error('Invalid observation');
        snapshot = next; observationError = false;
        console.log(`${new Date().toISOString()} AKS observation: ${next.overall}`);
      } catch {
        observationError = true;
        console.error(`${new Date().toISOString()} Observation unavailable; verify Azure sign-in and AKS Run Command access.`);
      }
      if (!stopped) timer = setTimeout(refresh, 15000);
    });
}

const server = http.createServer((request, response) => {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Referrer-Policy', 'no-referrer');
  if (request.headers.host !== `127.0.0.1:${port}` && request.headers.host !== `localhost:${port}`) { response.writeHead(403); response.end(); return; }
  if (request.url.startsWith('/api/shop/')) { void shopProxy(request, response); return; }
  if (request.method !== 'GET') { response.writeHead(405); response.end(); return; }
  const route = request.url.split('?')[0];
  if (route === '/' || route === '/health') {
    response.setHeader('Content-Type', 'text/html; charset=utf-8');
    response.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'");
    response.end(route === '/health' ? healthPage : page); return;
  }
  if (route === '/api/status') {
    response.setHeader('Content-Type', 'application/json');
    const stale = !snapshot || Date.now() - Date.parse(snapshot.observedAt) > 120000 || snapshot.stale;
    if (observationError || stale) { response.writeHead(503); response.end(JSON.stringify({ error: 'Observation unavailable' })); return; }
    response.end(JSON.stringify(snapshot)); return;
  }
  if (route === '/api/operations') {
    response.setHeader('Content-Type', 'application/json');
    if (operationsError || !operations) { response.writeHead(503); response.end(JSON.stringify({ error: 'Operations observation unavailable' })); return; }
    response.end(JSON.stringify(operations)); return;
  }
  response.writeHead(404); response.end();
});
server.listen(port, '127.0.0.1', () => { console.log(`Private AKS viewer: http://127.0.0.1:${port}`); refresh(); refreshOperations(); });
server.on('error', error => { console.error(error.code === 'EADDRINUSE' ? 'Port is already in use. Choose another -Port.' : error.message); process.exitCode = 1; });
function stop() { stopped = true; clearTimeout(timer); clearTimeout(operationsTimer); child?.kill(); operationsChild?.kill(); for (const process of shopChildren) process.kill(); server.close(); }
process.on('SIGINT', stop);
process.on('SIGTERM', stop);