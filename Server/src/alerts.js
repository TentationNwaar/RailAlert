// Perturbations et travaux (GTFS-RT Service Alerts d'opentransportdata.swiss) + arrêts officiels (data.sbb.ch).
// Même logique que OpenTransportDataSource.swift dans l'app.
import { config } from './config.js';
import { normalizeSloid } from './ojp.js';

const SA_URL = 'https://api.opentransportdata.swiss/la/gtfs-sa?format=json';
const POINTS_URL = 'https://data.sbb.ch/api/explore/v2.1/catalog/datasets/dienststellen-gemass-opentransportdataswiss/records';
const LOOK_AHEAD = 7 * 24 * 3600 * 1000;

const pointCache = new Map(); // sloid -> { name, isTrain, canton } | null

async function lookupPoints(sloids) {
  const missing = sloids.filter((s) => !pointCache.has(s));
  for (let i = 0; i < missing.length; i += 80) {
    const chunk = missing.slice(i, i + 80);
    const url = new URL(POINTS_URL);
    url.searchParams.set('where', `sloid in (${chunk.map((s) => `"${s}"`).join(',')})`);
    url.searchParams.set('select', 'sloid,designationofficial,meansoftransport,cantonabbreviation');
    url.searchParams.set('limit', '100');
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(20000) });
      const data = await response.json();
      const found = new Set();
      for (const r of data.results ?? []) {
        const modes = (r.meansoftransport ?? '').toUpperCase();
        pointCache.set(r.sloid, { name: r.designationofficial, isTrain: modes.includes('TRAIN') || modes.includes('RACK_RAILWAY'), canton: r.cantonabbreviation });
        found.add(r.sloid);
      }
      for (const s of chunk) if (!found.has(s)) pointCache.set(s, null);
    } catch (error) {
      console.warn('Arrêts :', error.message);
    }
  }
}

function translations(value) {
  const out = {};
  for (const t of value?.translation ?? []) {
    if (t.text) out[(t.language ?? '').slice(0, 2).toLowerCase()] = t.text;
  }
  return out;
}

const pick = (texts, language) => texts[language] ?? texts.fr ?? texts.en ?? texts.de ?? Object.values(texts)[0] ?? '';
const stripHTML = (s) => s.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '').trim();

/** Télécharge et interprète le flux ; renvoie les alertes ferroviaires utiles (en cours, ou travaux dans 7 jours). */
export async function fetchRailAlerts(now = new Date()) {
  const response = await fetch(SA_URL, {
    headers: { Authorization: `Bearer ${config.gtfsSaKey}` },
    signal: AbortSignal.timeout(60000),
  });
  if (!response.ok) throw new Error(`GTFS-SA ${response.status}`);
  const feed = await response.json();
  const raw = [];
  for (const entity of feed.entity ?? []) {
    const a = entity.alert;
    if (!a) continue;
    const header = translations(a.headerText);
    const description = translations(a.descriptionText);
    const periods = (a.activePeriod ?? []).map((p) => ({
      start: p.start ? new Date(Number(p.start) * 1000) : new Date(0),
      end: p.end ? new Date(Number(p.end) * 1000) : new Date(8.64e15),
    })).filter((p) => p.end >= p.start);
    let window = null;
    if (periods.length) {
      window = periods.find((p) => p.start <= now && p.end >= now)
        ?? periods.filter((p) => p.start > now).sort((x, y) => x.start - y.start)[0] ?? null;
      if (!window) continue; // toutes les plages sont passées
    }
    const frText = `${header.fr ?? ''} ${description.fr ?? ''}`.toLowerCase();
    const cause = (a.cause ?? '').toUpperCase();
    const isConstruction = cause.includes('CONSTRUCTION') || cause.includes('MAINTENANCE')
      || ['travaux', 'chantier', 'bauarbeiten', 'construction work'].some((k) => frText.includes(k));
    const horizon = isConstruction ? LOOK_AHEAD : 3 * 3600 * 1000;
    if (window && window.start > new Date(now.getTime() + horizon)) continue;
    const interrupted = ['interrompu', 'interruption', 'ne circule pas', 'ne circulent pas', 'bus de remplacement',
      'remplacé par des bus', 'unterbrochen', 'interrupted'].some((k) => frText.includes(k));
    const info = !interrupted && ['mobilité réduite', 'information sur', "n'est pas accessible", 'ascenseur', 'accès limité'].some((k) => frText.includes(k));
    const stopIds = [];
    for (const e of a.informedEntity ?? []) {
      if (e.stopId) {
        const s = normalizeSloid(String(e.stopId));
        if (!stopIds.includes(s)) stopIds.push(s);
      }
    }
    raw.push({ id: String(entity.id), header, description, periods, window, isConstruction, interrupted, info, stopIds });
  }

  await lookupPoints([...new Set(raw.flatMap((r) => r.stopIds))]);
  return raw
    .filter((r) => !r.info)
    .map((r) => {
      const trainStops = r.stopIds.map((s) => ({ sloid: s, point: pointCache.get(s) })).filter((x) => x.point?.isTrain);
      return { ...r, places: trainStops.map((x) => ({ sloid: x.sloid, name: x.point.name })) };
    })
    .filter((r) => r.places.length > 0)
    .map((r) => ({
      ...r,
      title: (language) => pick(r.header, language) || r.places.map((p) => p.name).join(' – '),
      details: (language) => stripHTML(pick(r.description, language)),
    }));
}
