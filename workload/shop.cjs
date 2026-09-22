'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID, createHmac, createHash } = require('node:crypto');

const products = Object.freeze([
  { id: 'headphones', name: 'Studio Headphones', category: 'Audio', price: 12900, description: 'Over-ear listening, wherever the day takes you.' },
  { id: 'camera', name: 'Everyday Camera', category: 'Photography', price: 34900, description: 'A compact companion for the moments worth keeping.' },
  { id: 'watch', name: 'Field Watch', category: 'Accessories', price: 8900, description: 'An understated essential for your daily routine.' },
  { id: 'speaker', name: 'Portable Speaker', category: 'Audio', price: 7900, description: 'Room-filling sound in a take-anywhere size.' }
]);
const orderPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function failure(status, message) { return Object.assign(new Error(message), { status }); }
async function jsonBody(request) {
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 8192) throw failure(413, 'Request is too large.');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw failure(400, 'Invalid JSON request.'); }
}
function quote(items) {
  if (!Array.isArray(items) || items.length < 1 || items.length > products.length) throw failure(400, 'Choose at least one product.');
  const seen = new Set();
  const lines = items.map(item => {
    const product = products.find(candidate => candidate.id === item?.id);
    if (!product || seen.has(item.id) || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 10) throw failure(400, 'Invalid product or quantity.');
    seen.add(item.id);
    return { id: product.id, name: product.name, quantity: item.quantity, price: product.price };
  }).sort((left, right) => left.id.localeCompare(right.id));
  return { items: lines, total: lines.reduce((total, item) => total + item.price * item.quantity, 0), currency: 'USD' };
}
function createShop({ getConfig, dataPath, fetcher = fetch, azureRead, now = () => new Date().toISOString() }) {
  async function remote(config, route, method, body) {
    let response;
    try {
      response = await fetcher(`${config.backend}${route}`, {
        method, headers: { 'Content-Type': 'application/json' }, redirect: 'error',
        body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(12000)
      });
    } catch { throw failure(503, 'The order service is unavailable. Please try again.'); }
    const result = await response.json();
    if (!response.ok) throw failure(response.status, result.error || 'The order service is unavailable.');
    return result;
  }
  async function dispatch(route, method, body) {
    const config = getConfig();
    if (config.release !== 'v1') throw failure(503, 'Shop configuration is unavailable.');
    if (route === '/shop/media' && method === 'GET') {
      const images = await Promise.all(products.map(async product => {
        try {
          const bytes = await azureRead('https://storage.azure.com/', `https://${config.storage}.blob.core.windows.net/lab/shop/${product.id}.jpg`, 'bytes');
          if (!bytes.length || bytes.length > 100000) throw new Error('Invalid image size');
          return [product.id, `data:image/jpeg;base64,${bytes.toString('base64')}`];
        } catch { throw failure(503, 'Product images are unavailable.'); }
      }));
      return { images: Object.fromEntries(images), observedAt: now() };
    }
    if (config.role === 'client') return remote(config, route, method, body);
    if (route === '/shop/catalog' && method === 'GET') return { products, currency: 'USD', observedAt: now() };
    const orderDirectory = path.join(dataPath, 'orders');
    if (route.startsWith('/shop/orders/') && method === 'GET') {
      const id = route.slice('/shop/orders/'.length);
      if (!orderPattern.test(id)) throw failure(400, 'Invalid order reference.');
      try { return JSON.parse(fs.readFileSync(path.join(orderDirectory, `${id}.json`), 'utf8')).order; }
      catch (error) { if (error.code === 'ENOENT') throw failure(404, 'Order not found.'); throw error; }
    }
    if (route !== '/shop/checkout' || method !== 'POST') throw failure(404, 'Not found.');
    if (!orderPattern.test(body?.requestId)) throw failure(400, 'A valid checkout reference is required.');
    const priced = quote(body.items);
    const fingerprint = createHash('sha256').update(JSON.stringify(priced)).digest('hex');
    const destination = path.join(orderDirectory, `${body.requestId}.json`);
    function existing() {
      try {
        const saved = JSON.parse(fs.readFileSync(destination, 'utf8'));
        if (saved.fingerprint !== fingerprint) throw failure(409, 'This checkout reference was used for a different basket.');
        return saved.order;
      } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    }
    const previous = existing();
    if (previous) return previous;
    let paymentKey;
    try {
      const secret = await azureRead('https://vault.azure.net', `https://${config.vault}.vault.azure.net/secrets/shop-demo-payment-key?api-version=7.4`, 'json');
      paymentKey = secret.value;
      if (typeof paymentKey !== 'string' || paymentKey.length < 32) throw new Error('Missing key');
    } catch { throw failure(503, 'Demo payment authorization is unavailable. No order was placed.'); }
    const authorization = createHmac('sha256', paymentKey).update(`${body.requestId}:${fingerprint}`).digest('hex');
    const order = { id: body.requestId, ...priced, placedAt: now(), status: 'confirmed', payment: 'simulated' };
    const temporary = path.join(orderDirectory, `.${randomUUID()}.tmp`);
    let descriptor;
    try {
      fs.mkdirSync(orderDirectory, { recursive: true });
      descriptor = fs.openSync(temporary, 'wx', 0o600);
      fs.writeFileSync(descriptor, JSON.stringify({ fingerprint, authorization, order }));
      fs.fsyncSync(descriptor);
      fs.closeSync(descriptor); descriptor = undefined;
      try { fs.linkSync(temporary, destination); }
      catch (error) { if (error.code !== 'EEXIST') throw error; return existing(); }
      return order;
    } catch (error) {
      if (error.status) throw error;
      throw failure(503, 'The order could not be saved. Retry with the same checkout reference.');
    } finally {
      if (descriptor !== undefined) fs.closeSync(descriptor);
      try { fs.unlinkSync(temporary); } catch (error) { if (error.code !== 'ENOENT') console.error('Order temporary-file cleanup failed'); }
    }
  }
  return async function handle(request, response) {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('Content-Type', 'application/json');
    try {
      const route = request.url.split('?')[0];
      const body = request.method === 'POST' ? await jsonBody(request) : undefined;
      const result = await dispatch(route, request.method, body);
      response.writeHead(200); response.end(JSON.stringify(result));
    } catch (error) {
      response.writeHead(error.status || 503);
      response.end(JSON.stringify({ error: error.status ? error.message : 'Shop service is unavailable.' }));
    }
  };
}
function createAzureRead(getConfig, fetcher = fetch) {
  return async function azureRead(resource, url, format = 'json') {
    const config = getConfig();
    const identity = new URL('http://169.254.169.254/metadata/identity/oauth2/token');
    identity.search = new URLSearchParams({ 'api-version': '2018-02-01', resource, client_id: config.clientId });
    const tokenResponse = await fetcher(identity, { headers: { Metadata: 'true' }, signal: AbortSignal.timeout(8000), redirect: 'error' });
    if (!tokenResponse.ok) throw new Error('Identity unavailable');
    const token = (await tokenResponse.json()).access_token;
    if (!token) throw new Error('Identity unavailable');
    const response = await fetcher(url, { headers: { Authorization: `Bearer ${token}`, 'x-ms-version': '2023-11-03' }, signal: AbortSignal.timeout(8000), redirect: 'error' });
    if (!response.ok) throw new Error('Azure dependency request failed');
    const chunks = [];
    let size = 0;
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > 262144) throw new Error('Dependency response too large');
      chunks.push(chunk);
    }
    const bytes = Buffer.concat(chunks);
    return format === 'bytes' ? bytes : JSON.parse(bytes.toString('utf8'));
  };
}
module.exports = { createShop, createAzureRead, products, quote, jsonBody };