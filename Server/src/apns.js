// Envoi des notifications push via APNs (service d'Apple), sans dépendance :
// authentification par jeton JWT signé avec la clé .p8 (ES256), connexion HTTP/2.
import http2 from 'node:http2';
import crypto from 'node:crypto';
import { config } from './config.js';

const HOSTS = { production: 'https://api.push.apple.com', sandbox: 'https://api.sandbox.push.apple.com' };
const sessions = {};
let cachedToken = null;

const base64url = (input) => Buffer.from(input).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');

/** Jeton d'authentification APNs, renouvelé toutes les 50 minutes (Apple le refuse après 60). */
export function providerToken(now = Date.now()) {
  if (cachedToken && now - cachedToken.createdAt < 50 * 60 * 1000) return cachedToken.value;
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: config.apnsKeyId }));
  const claims = base64url(JSON.stringify({ iss: config.apnsTeamId, iat: Math.floor(now / 1000) }));
  const signature = crypto.sign('sha256', Buffer.from(`${header}.${claims}`), { key: config.apnsKey, dsaEncoding: 'ieee-p1363' });
  cachedToken = { value: `${header}.${claims}.${base64url(signature)}`, createdAt: now };
  return cachedToken.value;
}

function session(environment) {
  const host = HOSTS[environment] ?? HOSTS.production;
  if (!sessions[host] || sessions[host].closed || sessions[host].destroyed) {
    sessions[host] = http2.connect(host);
    sessions[host].on('error', () => { delete sessions[host]; });
  }
  return sessions[host];
}

/**
 * Envoie une notification.
 * @param {object} p { deviceToken, environment, pushType: 'alert' | 'liveactivity', payload, collapseId }
 * @returns {Promise<{status:number, reason?:string}>}
 */
export async function send({ deviceToken, environment, pushType = 'alert', payload, collapseId }) {
  if (config.dryRun) {
    console.log(`[DRY_RUN] push ${pushType} → ${deviceToken.slice(0, 8)}…`, JSON.stringify(payload));
    return { status: 200 };
  }
  const topic = pushType === 'liveactivity' ? `${config.apnsTopic}.push-type.liveactivity` : config.apnsTopic;
  const headers = {
    ':method': 'POST',
    ':path': `/3/device/${deviceToken}`,
    authorization: `bearer ${providerToken()}`,
    'apns-topic': topic,
    'apns-push-type': pushType,
    'apns-priority': '10',
    'apns-expiration': '0',
    'content-type': 'application/json',
  };
  if (collapseId) headers['apns-collapse-id'] = collapseId.slice(0, 64);

  return new Promise((resolve) => {
    const request = session(environment).request(headers);
    let status = 0;
    let body = '';
    request.on('response', (h) => { status = h[':status']; });
    request.on('data', (chunk) => { body += chunk; });
    request.on('end', () => {
      let reason;
      try { reason = JSON.parse(body || '{}').reason; } catch { reason = body; }
      resolve({ status, reason });
    });
    request.on('error', (error) => resolve({ status: 0, reason: error.message }));
    request.setTimeout(15000, () => { request.close(); resolve({ status: 0, reason: 'timeout' }); });
    request.end(JSON.stringify(payload));
  });
}

/** Dates pour ActivityKit : secondes depuis le 1er janvier 2001 (format par défaut de Swift). */
export const swiftDate = (date) => date.getTime() / 1000 - 978307200;
