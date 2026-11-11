// Serveur push de Rail Alert.
//   POST   /v1/devices          inscription / mise à jour d'un appareil (jeton push, langue, trajets)
//   DELETE /v1/devices/:token   désinscription
//   GET    /health              état du serveur
import http from 'node:http';
import { config } from './config.js';
import { upsertDevice, removeDevice, allDevices } from './store.js';
import { start, status } from './monitor.js';

function json(res, code, body) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

function authorized(req) {
  return config.appKey !== '' && req.headers['x-app-key'] === config.appKey;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  try {
    if (req.method === 'GET' && url.pathname === '/health') {
      return json(res, 200, { ok: true, devices: allDevices().length, dryRun: config.dryRun, ...status });
    }
    if (!authorized(req)) return json(res, 401, { error: 'unauthorized' });

    if (req.method === 'POST' && url.pathname === '/v1/devices') {
      let raw = '';
      for await (const chunk of req) {
        raw += chunk;
        if (raw.length > 200_000) return json(res, 413, { error: 'too large' });
      }
      upsertDevice(JSON.parse(raw));
      return json(res, 200, { ok: true });
    }
    const match = url.pathname.match(/^\/v1\/devices\/([0-9a-fA-F]+)$/);
    if (req.method === 'DELETE' && match) {
      removeDevice(match[1]);
      return json(res, 200, { ok: true });
    }
    return json(res, 404, { error: 'not found' });
  } catch (error) {
    return json(res, 400, { error: error.message });
  }
});

if (!config.appKey) console.warn('Attention : APP_KEY est vide, toutes les inscriptions seront refusées.');
if (config.dryRun) console.warn('Mode DRY_RUN : aucune notification ne sera envoyée à Apple (affichage dans le journal).');

server.listen(config.port, () => {
  console.log(`Rail Alert server sur le port ${config.port}`);
  start();
});
