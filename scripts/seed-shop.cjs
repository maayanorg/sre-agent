'use strict';
const { randomBytes, createHash } = require('node:crypto');
const { setTimeout: delay } = require('node:timers/promises');
async function seed({ config, assets, fetcher = fetch, retryDelays = [5000, 10000, 20000, 30000, 60000], wait = delay }) {
  async function azure(resource, url, options = {}) {
    const identity = new URL('http://169.254.169.254/metadata/identity/oauth2/token');
    identity.search = new URLSearchParams({ 'api-version': '2018-02-01', resource, client_id: config.clientId });
    const tokenReply = await fetcher(identity, { headers: { Metadata: 'true' }, signal: AbortSignal.timeout(10000), redirect: 'error' });
    if (!tokenReply.ok) throw new Error('Managed identity unavailable');
    const token = (await tokenReply.json()).access_token;
    if (!token) throw new Error('Managed identity unavailable');
    for (let attempt = 0; ; attempt++) {
      const reply = await fetcher(url, { ...options, headers: { ...options.headers, Authorization: `Bearer ${token}`, 'x-ms-version': '2023-11-03' }, signal: AbortSignal.timeout(20000), redirect: 'error' });
      if (reply.status !== 403 || attempt >= retryDelays.length) return reply;
      await reply.arrayBuffer();
      await wait(retryDelays[attempt]);
    }
  }
  for (const asset of assets) {
    if (!/^(headphones|camera|watch|speaker)$/.test(asset.id) || new URL(asset.source).hostname !== 'images.unsplash.com' || new URL(asset.source).protocol !== 'https:') throw new Error('Invalid asset manifest');
    const reply = await fetcher(asset.source, { signal: AbortSignal.timeout(30000), redirect: 'error' });
    if (!reply.ok) throw new Error(`Image download failed: ${asset.id}`);
    const bytes = Buffer.from(await reply.arrayBuffer());
    if (bytes.length < 100 || bytes.length > 100000 || bytes[0] !== 255 || bytes[1] !== 216) throw new Error(`Invalid image: ${asset.id}`);
    const hash = createHash('sha256').update(bytes).digest('hex');
    const url = `https://${config.storage}.blob.core.windows.net/lab/shop/${asset.id}.jpg`;
    const existing = await azure('https://storage.azure.com/', url, { method: 'HEAD' });
    if (existing.ok) {
      if (existing.headers.get('x-ms-meta-srelab_sha256') !== hash) throw new Error(`Refusing to overwrite different image: ${asset.id}`);
      continue;
    }
    if (existing.status !== 404) throw new Error(`Blob preflight failed: HTTP ${existing.status}`);
    const uploaded = await azure('https://storage.azure.com/', url, { method: 'PUT', headers: { 'x-ms-blob-type': 'BlockBlob', 'Content-Type': 'image/jpeg', 'x-ms-blob-cache-control': 'no-store', 'x-ms-meta-srelab_sha256': hash, 'If-None-Match': '*' }, body: bytes });
    if (!uploaded.ok) throw new Error(`Blob upload failed: HTTP ${uploaded.status}`);
    await uploaded.arrayBuffer();
  }
  const secretUrl = `https://${config.vault}.vault.azure.net/secrets/shop-demo-payment-key?api-version=7.4`;
  const existingSecret = await azure('https://vault.azure.net', secretUrl);
  if (existingSecret.ok) {
    const secret = await existingSecret.json();
    if (typeof secret.value !== 'string' || secret.value.length < 32) throw new Error('Existing demo secret is invalid; refusing rotation');
  } else {
    if (existingSecret.status !== 404) throw new Error(`Vault preflight failed: HTTP ${existingSecret.status}`);
    const created = await azure('https://vault.azure.net', secretUrl, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ value: randomBytes(48).toString('base64'), contentType: 'SRE lab simulated payment key' }) });
    if (!created.ok) throw new Error(`Secret creation failed: HTTP ${created.status}`);
    await created.arrayBuffer();
  }
}
if (require.main === module) {
  seed({ config: require('/opt/srelab/config.json'), assets: require(process.argv[2]) })
    .then(() => console.log('Shop seed completed inside Azure: four Blob images and demo Vault secret.'))
    .catch(error => { console.error(error.message); process.exitCode = 1; });
}
module.exports = { seed };