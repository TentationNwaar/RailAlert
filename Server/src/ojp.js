// Horaire officiel en temps réel via OJP 2.0 (même lecture que OJPService.swift dans l'app).
import { parseXML } from './xml.js';
import { config } from './config.js';
import { t } from './i18n.js';

const ENDPOINT = 'https://api.opentransportdata.swiss/ojp20';

const escape = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const iso = (d) => d.toISOString().replace(/\.\d{3}Z$/, 'Z');

async function send(body, language = 'fr') {
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<OJP xmlns="http://www.vdv.de/ojp" xmlns:siri="http://www.siri.org.uk/siri" version="2.0">
  <OJPRequest><siri:ServiceRequest>
    <siri:ServiceRequestContext><siri:Language>${escape(language)}</siri:Language></siri:ServiceRequestContext>
    <siri:RequestTimestamp>${iso(new Date())}</siri:RequestTimestamp>
    <siri:RequestorRef>RedAlert_Server</siri:RequestorRef>
    ${body}
  </siri:ServiceRequest></OJPRequest>
</OJP>`;
  const response = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/xml', Authorization: `Bearer ${config.ojpKey}` },
    body: xml,
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) throw new Error(`OJP ${response.status}`);
  return parseXML(await response.text());
}

export async function connections(fromId, toId, at, count = 6, language = 'fr') {
  const root = await send(`<OJPTripRequest>
    <siri:RequestTimestamp>${iso(new Date())}</siri:RequestTimestamp>
    <Origin><PlaceRef><StopPlaceRef>${escape(fromId)}</StopPlaceRef><Name><Text>-</Text></Name></PlaceRef><DepArrTime>${iso(at)}</DepArrTime></Origin>
    <Destination><PlaceRef><StopPlaceRef>${escape(toId)}</StopPlaceRef><Name><Text>-</Text></Name></PlaceRef></Destination>
    <Params><NumberOfResults>${count}</NumberOfResults><IncludeIntermediateStops>true</IncludeIntermediateStops><UseRealtimeData>explanatory</UseRealtimeData></Params>
  </OJPTripRequest>`, language);
  const sits = situations(root);
  return root.descendants('TripResult').map((r) => parseConnection(r, sits, language)).filter(Boolean);
}

const date = (text) => (text ? new Date(text) : null);
const minutes = (planned, estimated) => Math.round((estimated - planned) / 60000);
export const normalizeSloid = (id) => {
  const parts = id.split(':');
  return parts.length >= 4 && parts[2] === 'sloid' ? parts.slice(0, 4).join(':') : id;
};

function lineName(service) {
  const raw = service?.path('PublishedServiceName', 'Text')?.text ?? service?.child('PublicCode')?.text;
  if (!raw) return null;
  const i = raw.search(/\d/);
  if (i <= 0) return raw;
  const prefix = raw.slice(0, i);
  return prefix === 'S' || prefix === 'SN' ? raw : `${prefix} ${raw.slice(i)}`;
}

function occupancy(call) {
  const result = {};
  for (const item of call?.all('ExpectedDepartureOccupancy') ?? []) {
    const fare = (item.child('FareClass')?.text ?? '').trim();
    const level = { empty: 1, manySeatsAvailable: 1, seatsAvailable: 1, fewSeatsAvailable: 2, standingRoomOnly: 3,
      crushedStandingRoomOnly: 3, full: 3, notAcceptingPassengers: 3 }[(item.child('OccupancyLevel')?.text ?? '').trim()];
    if (fare === 'firstClass') result.first = level ?? null;
    if (fare === 'secondClass') result.second = level ?? null;
  }
  return result;
}

export function parseConnection(tripResult, sits = new Map(), language = 'fr') {
  const trip = tripResult.child('Trip');
  if (!trip) return null;
  const timed = trip.all('Leg').map((l) => l.child('TimedLeg')).filter(Boolean);
  if (!timed.length) return null;
  const board = timed[0].child('LegBoard');
  const alight = timed[timed.length - 1].child('LegAlight');
  const plannedDeparture = date(board?.path('ServiceDeparture', 'TimetabledTime')?.text);
  if (!plannedDeparture || !alight) return null;
  const estimatedDeparture = date(board.path('ServiceDeparture', 'EstimatedTime')?.text);
  const plannedArrival = date(alight.path('ServiceArrival', 'TimetabledTime')?.text) ?? plannedDeparture;
  const estimatedArrival = date(alight.path('ServiceArrival', 'EstimatedTime')?.text);

  const cancelled = timed.some((leg) =>
    leg.path('Service', 'Cancelled')?.text === 'true'
    || leg.path('LegBoard', 'NotServicedStop')?.text === 'true'
    || leg.path('LegAlight', 'NotServicedStop')?.text === 'true'
    || leg.path('LegBoard', 'NoBoardingAtStop')?.text === 'true'
    || leg.path('LegAlight', 'NoAlightingAtStop')?.text === 'true');
  const messages = serviceMessages(timed, sits, language);

  const stopIds = [];
  for (const leg of timed) {
    for (const call of [leg.child('LegBoard'), ...leg.all('LegIntermediate'), leg.child('LegAlight')]) {
      const ref = call?.child('StopPointRef')?.text;
      if (!ref) continue;
      const sloid = normalizeSloid(ref);
      if (stopIds[stopIds.length - 1] !== sloid) stopIds.push(sloid);
    }
  }
  const service = timed[0].child('Service');
  const plannedTrack = board.path('PlannedQuay', 'Text')?.text ?? null;
  const estimatedTrack = board.path('EstimatedQuay', 'Text')?.text ?? null;
  const occ = occupancy(board);
  const delay = estimatedDeparture ? minutes(plannedDeparture, estimatedDeparture) : null;
  const arrivalDelay = estimatedArrival ? minutes(plannedArrival, estimatedArrival) : delay;

  return {
    id: `${lineName(service) ?? '-'}-${Math.floor(plannedDeparture.getTime() / 1000)}`,
    plannedDeparture,
    plannedArrival,
    departureDelay: delay,
    arrivalDelay,
    expectedDeparture: new Date(plannedDeparture.getTime() + (delay ?? 0) * 60000),
    expectedArrival: new Date(plannedArrival.getTime() + (arrivalDelay ?? 0) * 60000),
    isCancelled: cancelled,
    line: lineName(service),
    track: estimatedTrack ?? plannedTrack,
    trackChanged: estimatedTrack != null && plannedTrack != null && estimatedTrack !== plannedTrack,
    terminal: service?.path('DestinationText', 'Text')?.text ?? null,
    transfers: Number(trip.child('Transfers')?.text ?? timed.length - 1),
    stopIds,
    occupancyFirst: occ.first ?? null,
    occupancySecond: occ.second ?? null,
    plannedTrack,
    messages,
    legs: tripLegs(trip),
  };
}

/** "PT5M" -> 5, "PT1H8M30S" -> 68 */
export function durationMinutes(text) {
  const m = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?$/.exec(text ?? '');
  if (!m) return null;
  return Math.floor(Number(m[1] ?? 0) * 60 + Number(m[2] ?? 0) + Number(m[3] ?? 0) / 60);
}

/** Étapes en transport, avec le temps de marche prévu entre elles (même logique que OJPService.swift). */
export function tripLegs(trip) {
  const legs = [];
  let walk = null;
  for (const leg of trip.all('Leg')) {
    const transfer = leg.child('TransferLeg') ?? leg.child('ContinuousLeg');
    if (transfer) { walk = (walk ?? 0) + (durationMinutes(transfer.child('Duration')?.text) ?? 0); continue; }
    const timed = leg.child('TimedLeg');
    const board = timed?.child('LegBoard');
    const alight = timed?.child('LegAlight');
    const plannedDeparture = date(board?.path('ServiceDeparture', 'TimetabledTime')?.text);
    if (!plannedDeparture || !alight) continue;
    const plannedArrival = date(alight.path('ServiceArrival', 'TimetabledTime')?.text) ?? plannedDeparture;
    const estDep = date(board.path('ServiceDeparture', 'EstimatedTime')?.text);
    const estArr = date(alight.path('ServiceArrival', 'EstimatedTime')?.text);
    const service = timed.child('Service');
    legs.push({
      fromName: board.path('StopPointName', 'Text')?.text ?? '',
      plannedDeparture,
      plannedArrival,
      expectedDeparture: estDep ?? plannedDeparture,
      expectedArrival: estArr ?? (estDep ? new Date(plannedArrival.getTime() + (estDep - plannedDeparture)) : plannedArrival),
      hasRealtime: Boolean(estDep || estArr),
      isCancelled: service?.child('Cancelled')?.text === 'true',
      walkMinutesBefore: legs.length ? walk : null,
    });
    walk = null;
  }
  return legs;
}

/** Correspondances menacées par un retard (même règle que ConnectionInfo.transferRisks). */
export function transferRisks(connection) {
  const legs = connection?.legs ?? [];
  const risks = [];
  for (let i = 1; i < legs.length; i++) {
    const prev = legs[i - 1], next = legs[i];
    if (prev.isCancelled || next.isCancelled || !(prev.hasRealtime || next.hasRealtime)) continue;
    const margin = Math.floor((next.expectedDeparture - prev.expectedArrival) / 60000);
    const needed = Math.max(next.walkMinutesBefore ?? 1, 1);
    const planned = Math.floor((next.plannedDeparture - prev.plannedArrival) / 60000);
    if (margin < needed && margin < planned) risks.push({ index: i, station: next.fromName, margin, missed: margin < 0 });
  }
  return risks;
}

// Messages officiels (SIRI-SX) et changements révélés par l'horaire (même logique que OJPService.swift).
const ACCESSIBILITY_CAUSES = new Set(['liftFailure', 'escalatorFailure', 'lifts', 'escalators',
  'stairsOutOfService', 'accessibilityProblem', 'toiletsOutOfService']);

export function situations(root) {
  const map = new Map();
  for (const sit of root.descendants('PtSituation')) {
    const number = sit.child('SituationNumber')?.text;
    const content = sit.descendants('TextualContent')[0];
    const summary = content?.path('SummaryContent', 'SummaryText')?.text;
    if (!number || !summary) continue;
    const details = [
      content.path('ReasonContent', 'ReasonText')?.text,
      content.path('DescriptionContent', 'DescriptionText')?.text,
      content.path('RecommendationContent', 'RecommendationText')?.text,
      content.path('DurationContent', 'DurationText')?.text,
    ].filter(Boolean).join('\n');
    map.set(number, {
      id: number,
      summary,
      details,
      affectsService: !ACCESSIBILITY_CAUSES.has(sit.child('AlertCause')?.text ?? ''),
      isPlanned: sit.child('Planned')?.text === 'true',
    });
  }
  return map;
}

export function serviceMessages(legs, sits, language = 'fr') {
  const list = [];
  const add = (m) => { if (!list.some((x) => x.id === m.id)) list.push(m); };
  for (const leg of legs) {
    const journey = leg.path('Service', 'JourneyRef')?.text ?? String(Math.random());
    const from = leg.path('LegBoard', 'StopPointName', 'Text')?.text ?? '';
    const to = leg.path('LegAlight', 'StopPointName', 'Text')?.text ?? '';
    if (leg.path('Service', 'Mode', 'BusSubmode')?.text === 'railReplacementBus') {
      add({ id: `bus-${journey}`, summary: t(language, 'replacementBus', from, to), details: t(language, 'replacementBusBody'),
        affectsService: true, isPlanned: false });
    }
    if (leg.descendants('Deviation').some((n) => n.text === 'true')) {
      add({ id: `deviation-${journey}`, summary: t(language, 'deviation'), details: '', affectsService: true, isPlanned: false });
    }
    if (leg.descendants('Unplanned').some((n) => n.text === 'true')) {
      add({ id: `extra-${journey}`, summary: t(language, 'extraTrain'), details: '', affectsService: false, isPlanned: false });
    }
    for (const ref of leg.descendants('SituationFullRef')) {
      const m = sits.get(ref.child('SituationNumber')?.text);
      if (m) add(m);
    }
  }
  return [...list.filter((m) => m.affectsService), ...list.filter((m) => !m.affectsService)];
}

/** Rapport sur un trajet : train surveillé + trains suivants (même logique que TripChecker dans l'app). */
export async function tripReport(trip, now, nextOccurrence, language = 'fr') {
  const anchor = nextOccurrence(trip, new Date(now.getTime() - 30 * 60000));
  const queryStart = anchor ? new Date(anchor.getTime() - 10 * 60000) : now;
  const all = await connections(trip.fromId, trip.toId, queryStart, 6, language);
  const relevant = all.filter((c) => c.expectedDeparture >= new Date(now.getTime() - 60000));
  let focus = null;
  if (anchor) {
    focus = relevant
      .filter((c) => Math.abs(c.plannedDeparture - anchor) <= 15 * 60000)
      .sort((a, b) => Math.abs(a.plannedDeparture - anchor) - Math.abs(b.plannedDeparture - anchor))[0] ?? null;
  }
  focus ??= relevant[0] ?? null;
  const upcoming = relevant.filter((c) => c.plannedDeparture >= (focus?.plannedDeparture ?? now));
  return { focus, upcoming, fetchedAt: now };
}

/** Meilleure alternative : le train non supprimé qui arrive le plus tôt (si le train surveillé a un problème). */
export function bestAlternative(report, now = new Date()) {
  const { focus, upcoming } = report;
  if (!focus) return null;
  const candidates = upcoming.filter((c) => !c.isCancelled && c.id !== focus.id && c.expectedDeparture >= new Date(now.getTime() - 60000));
  if (!candidates.length) return null;
  const best = candidates.reduce((a, b) => (b.expectedArrival < a.expectedArrival ? b : a));
  if (focus.isCancelled) return best;
  return best.expectedArrival < focus.expectedArrival ? best : null;
}
