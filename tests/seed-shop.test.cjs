'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { seed } = require('../scripts/seed-shop.cjs');
const config = { storage: 'fixture', vault: 'fixture', clientId: 'fixture' };
const assets = [{ id: 'watch', source: 'https://images.unsplash.com/fixture' }];
test('Azure seed uses identity, conditional Blob writes and an in-memory secret', async () => {
  const writes = [];
  const bytes = Buffer.alloc(200); bytes[0] = 255; bytes[1] = 216;
  await seed({ config, assets, fetcher: async (url, options = {}) => {
    if (String(url).includes('169.254.169.254')) return Response.json({ access_token: 'fixture-token' });
    if (String(url).includes('images.unsplash.com')) return new Response(bytes);
    assert.equal(options.headers.Authorization, 'Bearer fixture-token');
    if (options.method === 'PUT') { writes.push({ url, options }); return new Response('{}', { status: 201 }); }
    return new Response(null, { status: 404 });
  } });
  assert.equal(writes.length, 2);
  assert.equal(writes[0].options.headers['If-None-Match'], '*');
  assert.ok(JSON.parse(writes[1].options.body).value.length >= 32);
});
test('Azure seed refuses denied Blob access rather than overwriting or creating secret', async () => {
  const bytes = Buffer.alloc(200); bytes[0] = 255; bytes[1] = 216;
  await assert.rejects(seed({ config, assets, retryDelays: [], fetcher: async url => {
    if (String(url).includes('169.254.169.254')) return Response.json({ access_token: 'fixture' });
    if (String(url).includes('images.unsplash.com')) return new Response(bytes);
    return new Response(null, { status: 403 });
  } }), /Blob preflight failed: HTTP 403/);
});
test('Azure seed retries role propagation with a bounded schedule', async () => {
  const waits = [];
  let deniedRequests = 0;
  const bytes = Buffer.alloc(200); bytes[0] = 255; bytes[1] = 216;
  await assert.rejects(seed({ config, assets, retryDelays: [5, 10], wait: async milliseconds => waits.push(milliseconds), fetcher: async url => {
    if (String(url).includes('169.254.169.254')) return Response.json({ access_token: 'fixture' });
    if (String(url).includes('images.unsplash.com')) return new Response(bytes);
    deniedRequests++;
    return new Response(null, { status: 403 });
  } }), /Blob preflight failed: HTTP 403/);
  assert.deepEqual(waits, [5, 10]);
  assert.equal(deniedRequests, 3);
});