'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { randomUUID } = require('node:crypto');
const { createShop, quote } = require('../workload/shop.cjs');

async function fixture(context, options = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'srelab-shop-'));
  const server = http.createServer(createShop({ getConfig: () => ({ role: 'backend', release: 'v1', vault: 'test', storage: 'test' }), dataPath: directory, azureRead: async () => ({ value: 'test-key-not-a-real-secret-1234567890' }), ...options }));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  context.after(async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); fs.rmSync(directory, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${server.address().port}`;
  return { directory, get: route => fetch(`${base}${route}`), post: body => fetch(`${base}/shop/checkout`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) };
}
test('prices are computed on the server and invalid baskets rejected', () => {
  assert.equal(quote([{ id: 'watch', quantity: 2, price: 1 }]).total, 17800);
  for (const items of [[], [{ id: 'watch', quantity: -1 }], [{ id: '../x', quantity: 1 }], [{ id: 'watch', quantity: 1 }, { id: 'watch', quantity: 1 }]]) assert.throws(() => quote(items));
});
test('checkout persists, retries are idempotent, conflicting reuse fails', async context => {
  const app = await fixture(context);
  const body = { requestId: randomUUID(), items: [{ id: 'watch', quantity: 1 }] };
  const responses = await Promise.all([app.post(body), app.post(body)]);
  const orders = await Promise.all(responses.map(response => response.json()));
  assert.deepEqual(orders[0], orders[1]);
  assert.equal(orders[0].payment, 'simulated');
  assert.equal(fs.readdirSync(path.join(app.directory, 'orders')).length, 1);
  assert.deepEqual(await (await app.get(`/shop/orders/${body.requestId}`)).json(), orders[0]);
  assert.equal((await app.post({ ...body, items: [{ id: 'camera', quantity: 1 }] })).status, 409);
});
test('Vault outage prevents a new order without leaking dependency errors', async context => {
  const app = await fixture(context, { azureRead: async () => { throw new Error('sensitive upstream details'); } });
  const response = await app.post({ requestId: randomUUID(), items: [{ id: 'watch', quantity: 1 }] });
  assert.equal(response.status, 503);
  assert.match((await response.json()).error, /payment authorization/);
  assert.equal(fs.existsSync(path.join(app.directory, 'orders')), false);
});
test('unwritable order filesystem cannot report checkout success', async context => {
  const app = await fixture(context);
  fs.writeFileSync(path.join(app.directory, 'orders'), 'not a directory');
  const response = await app.post({ requestId: randomUUID(), items: [{ id: 'watch', quantity: 1 }] });
  assert.equal(response.status, 503);
  assert.match((await response.json()).error, /could not be saved/);
});
test('Blob failure removes media response while catalog stays available', async context => {
  const app = await fixture(context, { azureRead: async () => { throw new Error('Blob denied'); } });
  assert.equal((await app.get('/shop/media')).status, 503);
  assert.equal((await app.get('/shop/catalog')).status, 200);
});
test('client backend DNS or connection failure becomes unavailable', async context => {
  const app = await fixture(context, { getConfig: () => ({ role: 'client', release: 'v1', backend: 'http://backend.invalid' }), fetcher: async () => { throw new Error('ENOTFOUND'); } });
  assert.equal((await app.get('/shop/catalog')).status, 503);
});