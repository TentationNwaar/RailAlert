// Appareils inscrits (jeton push, langue, trajets), enregistrés dans un fichier JSON.
import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { config } from './config.js';

mkdirSync(config.dataDir, { recursive: true });
const FILE = join(config.dataDir, 'devices.json');

const devices = new Map(existsSync(FILE) ? Object.entries(JSON.parse(readFileSync(FILE, 'utf8'))) : []);
let saveTimer = null;

function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const tmp = `${FILE}.tmp`;
    writeFileSync(tmp, JSON.stringify(Object.fromEntries(devices), null, 1));
    renameSync(tmp, FILE);
  }, 500);
}

const isToken = (s) => typeof s === 'string' && /^[0-9a-f]{32,200}$/i.test(s);

/** Crée ou remplace un appareil à partir de ce qu'envoie l'app (ServerSync.swift). */
export function upsertDevice(body) {
  if (!isToken(body?.deviceToken)) throw new Error('deviceToken invalide');
  const previous = devices.get(body.deviceToken);
  const trips = (Array.isArray(body.trips) ? body.trips : []).slice(0, 20).map((t) => ({
    id: String(t.id),
    fromId: String(t.fromId), fromName: String(t.fromName ?? ''),
    toId: String(t.toId), toName: String(t.toName ?? ''),
    usualHour: Number.isInteger(t.usualHour) ? t.usualHour : null,
    usualMinute: Number.isInteger(t.usualMinute) ? t.usualMinute : null,
    weekdays: Array.isArray(t.weekdays) ? t.weekdays.filter(Number.isInteger) : [],
    notificationsEnabled: t.notificationsEnabled !== false,
    delayThreshold: Number.isInteger(t.delayThreshold) ? t.delayThreshold : 3,
  }));
  devices.set(body.deviceToken, {
    deviceToken: body.deviceToken,
    environment: body.environment === 'sandbox' ? 'sandbox' : 'production',
    language: ['fr', 'de', 'it', 'en'].includes(body.language) ? body.language : 'fr',
    trips,
    liveActivities: (Array.isArray(body.liveActivities) ? body.liveActivities : [])
      .filter((l) => isToken(l?.token)).map((l) => ({ tripId: String(l.tripId), token: l.token })),
    // Ce qui a déjà été notifié (pour ne pas envoyer deux fois la même alerte).
    notified: previous?.notified ?? {},
    updatedAt: new Date().toISOString(),
  });
  save();
}

export function removeDevice(token) {
  devices.delete(token);
  save();
}

export function allDevices() {
  return [...devices.values()];
}

export function markChanged() {
  save();
}
