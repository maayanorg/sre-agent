'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { createDashboard } = require('../workload/frontend/server.cjs');

test('all frontend inline scripts parse', () => {
  const html = fs.readFileSync(require('node:path').join(__dirname, '../workload/frontend/index.html'), 'utf8');
  for (const match of html.matchAll(/<script>([\s\S]*?)<\/script>/g)) new vm.Script(match[1]);
  assert.ok(html.includes('Service health'));
});

test('healthy checks expose only safe status fields', async () => {
  const app = createDashboard({ fetcher: async () => new Response('private service data') });
  const result = await app.collect();
  assert.equal(result.overall, 'healthy');
  assert.equal(result.checks.length, 6);
  assert.ok(result.checks.every(check => check.healthy));
  assert.ok(!JSON.stringify(result).includes('private service data'));
});

test('HTTP and connection failures degrade the dashboard without claiming a pod crash', async () => {
  const app = createDashboard({ fetcher: async url => {
    if (url.endsWith('/vault')) throw new Error('sensitive internal detail');
    return new Response('', { status: url.endsWith('/storage') ? 503 : 200 });
  } });
  const result = await app.collect();
  assert.equal(result.overall, 'degraded');
  assert.equal(result.checks.find(check => check.id === 'storage').code, 503);
  assert.equal(result.checks.find(check => check.id === 'vault').code, null);
  assert.equal(result.checks[0].healthy, true);
  assert.ok(!JSON.stringify(result).includes('sensitive'));
});

test('concurrent collection requests share one set of dependency checks', async () => {
  let calls = 0;
  const app = createDashboard({ fetcher: async () => { calls += 1; return new Response(''); } });
  await Promise.all([app.collect(), app.collect()]);
  assert.equal(calls, 5);
});

test('API returns unknown before first collection and rejects writes', async () => {
  const app = createDashboard();
  await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${app.server.address().port}`;
  try {
    assert.equal((await fetch(`${base}/api/status`)).status, 503);
    assert.equal((await fetch(`${base}/healthz`)).status, 200);
    assert.equal((await fetch(`${base}/api/status`, { method: 'POST' })).status, 405);
  } finally { await new Promise(resolve => app.server.close(resolve)); }
});