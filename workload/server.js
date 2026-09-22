'use strict';
const http = require('node:http');
const fs = require('node:fs');
const { randomUUID } = require('node:crypto');
const { createShop, createAzureRead } = require('./shop.cjs');
const configPath = process.env.LAB_CONFIG || '/opt/srelab/config.json';
const dataPath = process.env.LAB_DATA || '/mnt/srelab-data';
const getConfig = () => JSON.parse(fs.readFileSync(configPath, 'utf8'));
const azureRead = createAzureRead(getConfig);
const shop = createShop({ getConfig, dataPath, azureRead });

function log(message) {
  console.log(JSON.stringify({ time: new Date().toISOString(), ...message }));
}

const server = http.createServer(async (request, response) => {
  if (request.url.startsWith('/shop/')) {
    response.on('finish', () => log({ path: request.url.split('?')[0], status: response.statusCode }));
    return shop(request, response);
  }
  const started = Date.now();
  let status = 200;
  let result = { status: 'healthy' };
  try {
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    if (request.url === '/health') {
      if (config.release !== 'v1') throw new Error('Unsupported application configuration');
      const probePath = `${dataPath}/health-${randomUUID()}`;
      try { fs.writeFileSync(probePath, Buffer.alloc(4096, 'a'), { flag: 'wx' }); }
      finally { if (fs.existsSync(probePath)) fs.unlinkSync(probePath); }
      if (config.role === 'client') {
        const reply = await fetch(`${config.backend}/health`, { signal: AbortSignal.timeout(4000) });
        if (!reply.ok) throw new Error(`Dependency HTTP ${reply.status}`);
      }
    } else if (request.url === '/storage') {
      await azureRead('https://storage.azure.com/', `https://${config.storage}.blob.core.windows.net/lab?restype=container&comp=list`, 'bytes');
    } else if (request.url === '/vault') {
      await azureRead('https://vault.azure.net', `https://${config.vault}.vault.azure.net/secrets?api-version=7.4`);
    } else if (request.url === '/arm') {
      await azureRead('https://management.azure.com/', `https://management.azure.com${config.resourceGroupId}?api-version=2022-09-01`);
    } else {
      status = 404;
      result = { error: 'Not found' };
    }
  } catch (error) {
    status = 503;
    result = { error: 'Application dependency or local health check failed' };
  }
  log({ path: request.url, status, durationMs: Date.now() - started, ...result });
  response.writeHead(status, { 'Content-Type': 'application/json' });
  response.end(JSON.stringify(result));
});

const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
server.listen(config.role === 'backend' ? 8081 : 8080, '0.0.0.0');