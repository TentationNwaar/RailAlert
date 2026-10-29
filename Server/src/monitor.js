// Boucle de surveillance : chaque minute, vérifie les trajets de tous les appareils et envoie les alertes.
import { config } from './config.js';
import { allDevices, removeDevice, markChanged } from './store.js';
import { tripReport, bestAlternative, transferRisks } from './ojp.js';
import { fetchRailAlerts } from './alerts.js';
import { matchTrip } from './matcher.js';
import { isInMonitoringWindow, nextOccurrence, hhmm, dayTime } from './time.js';
import { t, alertLabel } from './i18n.js';
import { send, swiftDate } from './apns.js';

let alerts = [];
let alertsFetchedAt = 0;
const reports = new Map(); // "deviceToken|tripId" -> { report, fetchedAt }
export const status = { lastTick: null, alerts: 0, lastError: null };

const alternativeText = (language, c) =>
  `${hhmm(c.expectedDeparture)}${c.line ? ` ${c.line}` : ''} · ${t(language, 'arrival', hhmm(c.expectedArrival))}${c.track ? ` · ${t(language, 'track', c.track)}` : ''}`;

async function push(device, title, body, collapseId, urgent = true) {
  const result = await send({
    deviceToken: device.deviceToken,
    environment: device.environment,
    collapseId,
    payload: {
      aps: {
        alert: { title, body },
        sound: 'default',
        'interruption-level': urgent ? 'time-sensitive' : 'active',
        'thread-id': collapseId.split('|')[0],
      },
      // Lu par l'app quand on touche la notification : ouvre ce trajet.
      tripID: collapseId.split('|')[0],
    },
  });
  // 410 = l'app a été désinstallée ou le jeton n'est plus valable.
  if (result.status === 410 || result.reason === 'BadDeviceToken' || result.reason === 'Unregistered') {
    removeDevice(device.deviceToken);
  } else if (result.status !== 200) {
    console.warn('APNs', result.status, result.reason);
  }
}

/** Retard / suppression : une notification quand l'état change (même règle que l'app). */
async function checkDelay(device, trip, report, notified) {
  const focus = report.focus;
  if (!focus) return;
  const base = String(Math.floor(focus.plannedDeparture.getTime() / 1000));
  let signature = `${base}-ok`;
  if (focus.isCancelled) signature = `${base}-X`;
  else if ((focus.departureDelay ?? 0) <= -1) signature = `${base}-E${-focus.departureDelay}`;
  else if ((focus.departureDelay ?? 0) >= trip.delayThreshold) signature = `${base}-D${Math.min(Math.floor(focus.departureDelay / 5), 12)}`;
  if (notified.delay === signature) return;
  notified.delay = signature;
  if (signature.endsWith('-ok')) return;

  const lang = device.language;
  const title = `${trip.fromName} → ${trip.toName}`;
  const time = hhmm(focus.plannedDeparture);
  const line = focus.line ? ` (${focus.line})` : '';
  let heading, body;
  if (focus.isCancelled) {
    heading = t(lang, 'trainCancelled', title);
    body = t(lang, 'trainCancelledBody', time, line);
  } else if (focus.departureDelay <= -1) {
    heading = t(lang, 'early', title);
    body = t(lang, 'earlyBody', time, line, -focus.departureDelay, hhmm(focus.expectedDeparture));
  } else {
    heading = t(lang, 'delay', focus.departureDelay, title);
    body = t(lang, 'delayBody', time, line, hhmm(focus.expectedDeparture));
  }
  const alternative = bestAlternative(report);
  if (alternative) body += `\n${t(lang, 'alternative', alternativeText(lang, alternative))}`;
  await push(device, heading, body, `${trip.id}|delay`);
}

/** Changement de voie. */
async function checkTrack(device, trip, report, notified) {
  const focus = report.focus;
  if (!focus?.track || focus.isCancelled) return;
  const key = `${focus.id}|${focus.track}`;
  const seen = notified.lastTrack?.startsWith(`${focus.id}|`) ? notified.lastTrack.split('|').pop() : null;
  const previous = seen && seen !== focus.track ? seen : (focus.trackChanged ? focus.plannedTrack : null);
  notified.lastTrack = key;
  const changed = focus.trackChanged || (previous != null && previous !== focus.track);
  if (!changed || notified.trackNotified === key) return;
  notified.trackNotified = key;
  const lang = device.language;
  const time = hhmm(focus.plannedDeparture);
  const body = previous ? t(lang, 'trackChangeBodyFrom', time, focus.track, previous) : t(lang, 'trackChangeBody', time, focus.track);
  await push(device, t(lang, 'trackChange', `${trip.fromName} → ${trip.toName}`), body, `${trip.id}|track`);
}

/** Correspondance serrée ou compromise à cause d'un retard : une notification par état. */
async function checkTransfer(device, trip, report, notified) {
  const focus = report.focus;
  if (!focus || focus.isCancelled) return;
  const risk = transferRisks(focus)[0];
  if (!risk) return;
  const key = `${focus.id}|${risk.index}|${risk.missed ? 'missed' : 'tight'}`;
  if (notified.transfer === key) return;
  notified.transfer = key;
  const lang = device.language;
  const title = `${trip.fromName} → ${trip.toName}`;
  let body = risk.missed ? t(lang, 'transferMissedBody', risk.station) : t(lang, 'transferTightBody', Math.max(risk.margin, 0), risk.station);
  const alternative = bestAlternative(report);
  if (alternative) body += `\n${t(lang, 'alternative', alternativeText(lang, alternative))}`;
  await push(device, t(lang, risk.missed ? 'transferMissed' : 'transferTight', title), body, `${trip.id}|transfer`);
}

/** Messages officiels sur le train surveillé : une seule notification par message (même règle que l'app). */
async function checkMessages(device, trip, report, notified, matches) {
  const focus = report.focus;
  if (!focus || focus.isCancelled) return;
  const candidates = (focus.messages ?? []).filter((m) => m.affectsService && (!m.isPlanned || matches.length === 0));
  notified.messages ??= [];
  const lang = device.language;
  for (const m of candidates) {
    if (notified.messages.includes(m.id)) continue;
    notified.messages.push(m.id);
    let body = t(lang, 'trainMessage', hhmm(focus.plannedDeparture), m.summary);
    if (m.details) body += `\n${m.details}`;
    await push(device, t(lang, 'trafficInfo', `${trip.fromName} → ${trip.toName}`), body.slice(0, 1500),
      `${trip.id}|msg-${m.id}`.slice(0, 200), !m.isPlanned);
  }
  notified.messages = notified.messages.slice(-40);
}

/** Perturbations et travaux sur le parcours : une seule notification par alerte. */
async function checkNetwork(device, trip, report, notified, now) {
  const lang = device.language;
  const matches = matchTrip(trip, report, alerts, lang);
  const already = new Set(notified.alerts ?? []);
  const current = new Set(matches.map((m) => m.id));
  notified.alerts = [...already].filter((id) => current.has(id));
  for (const match of matches) {
    if (already.has(match.id)) continue;
    notified.alerts.push(match.id);
    const active = !match.start || (match.start <= now && (!match.end || match.end >= now));
    let body = match.title + (active ? t(lang, 'ongoing') : ` (${dayTime(match.start, lang)})`);
    const alternative = match.isInterruption ? (bestAlternative(report) ?? report.upcoming.find((c) => !c.isCancelled && c.id !== report.focus?.id)) : null;
    if (alternative) body += `\n${t(lang, 'alternative', alternativeText(lang, alternative))}`;
    if (match.details) body += `\n${match.details}`;
    await push(device, t(lang, 'onTrip', alertLabel(lang, match), `${trip.fromName} → ${trip.toName}`), body.slice(0, 1500),
      `${trip.id}|${match.id}`, match.isInterruption);
  }
  return matches;
}

/** Mise à jour de la Live Activity du trajet (même contenu que TripActivityAttributes.ContentState). */
async function updateLiveActivity(device, trip, report, matches, notified) {
  const live = device.liveActivities.find((l) => l.tripId === trip.id);
  const focus = report.focus;
  if (!live || !focus) return;
  const lang = device.language;
  let severity = focus.isCancelled ? 3 : (focus.departureDelay ?? 0) >= trip.delayThreshold ? 2 : focus.departureDelay == null ? 0 : 1;
  if (matches.some((m) => m.isInterruption)) severity = 3;
  else if (matches.length && severity < 2) severity = 2;
  const alternative = bestAlternative(report);
  const state = {
    plannedDeparture: swiftDate(focus.plannedDeparture),
    expectedDeparture: swiftDate(focus.expectedDeparture),
    expectedArrival: swiftDate(focus.expectedArrival),
    delayMinutes: focus.departureDelay,
    isCancelled: focus.isCancelled,
    track: focus.track,
    trackChanged: focus.trackChanged,
    line: focus.line,
    severity,
    alertText: matches[0]?.title ?? null,
    alternativeText: alternative ? alternativeText(lang, alternative) : null,
  };
  const signature = JSON.stringify(state);
  if (notified[`live-${trip.id}`] === signature) return;
  notified[`live-${trip.id}`] = signature;
  const ended = focus.expectedArrival.getTime() < Date.now() - 10 * 60000;
  await send({
    deviceToken: live.token,
    environment: device.environment,
    pushType: 'liveactivity',
    payload: {
      aps: {
        timestamp: Math.floor(Date.now() / 1000),
        event: ended ? 'end' : 'update',
        'content-state': state,
        ...(ended ? { 'dismissal-date': Math.floor(Date.now() / 1000) + 60 } : {}),
      },
    },
  });
}

export async function tick(now = new Date()) {
  // 1. Perturbations et travaux (toutes les 3 minutes).
  if (now - alertsFetchedAt > 3 * 60000) {
    try {
      alerts = await fetchRailAlerts(now);
      alertsFetchedAt = now.getTime();
      status.alerts = alerts.length;
    } catch (error) {
      status.lastError = `alertes : ${error.message}`;
      console.warn(status.lastError);
    }
  }

  // 2. Trajets de chaque appareil.
  for (const device of allDevices()) {
    for (const trip of device.trips) {
      const key = `${device.deviceToken}|${trip.id}`;
      const cached = reports.get(key);
      const inWindow = isInMonitoringWindow(trip, now);
      const stale = !cached
        || (cached.report.focus && cached.report.focus.plannedArrival < now)
        || now - cached.fetchedAt > 60 * 60000;
      if (inWindow || stale) {
        try {
          reports.set(key, { report: await tripReport(trip, now, nextOccurrence, device.language), fetchedAt: now });
        } catch (error) {
          status.lastError = `OJP : ${error.message}`;
          console.warn(status.lastError);
        }
      }
      const report = reports.get(key)?.report;
      if (!report) continue;
      device.notified[trip.id] ??= {};
      const notified = device.notified[trip.id];
      let matches = [];
      if (trip.notificationsEnabled) {
        if (inWindow) {
          await checkDelay(device, trip, report, notified);
          await checkTrack(device, trip, report, notified);
        }
        matches = await checkNetwork(device, trip, report, notified, now);
        if (inWindow) {
          await checkMessages(device, trip, report, notified, matches);
          await checkTransfer(device, trip, report, notified);
        }
      } else {
        matches = matchTrip(trip, report, alerts, device.language);
      }
      await updateLiveActivity(device, trip, report, matches, notified);
    }
  }
  markChanged();
  status.lastTick = now.toISOString();
}

export function start() {
  const run = async () => {
    try { await tick(); } catch (error) { status.lastError = error.message; console.error(error); }
  };
  run();
  setInterval(run, config.tickSeconds * 1000);
}
