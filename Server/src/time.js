// Dates en heure suisse (Europe/Zurich), sans dépendance externe.

const TZ = 'Europe/Zurich';

/** Éléments de date/heure d'un instant, vus depuis Zurich. */
export function zurichParts(date) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', weekday: 'short', hour12: false,
  }).formatToParts(date);
  const get = (type) => parts.find((p) => p.type === type)?.value;
  const weekdays = { Sun: 1, Mon: 2, Tue: 3, Wed: 4, Thu: 5, Fri: 6, Sat: 7 };
  return {
    year: Number(get('year')), month: Number(get('month')), day: Number(get('day')),
    hour: Number(get('hour')) % 24, minute: Number(get('minute')),
    weekday: weekdays[get('weekday')], // 1 = dimanche ... 7 = samedi (comme Calendar dans l'app)
  };
}

/** Décalage de Zurich par rapport à UTC (en minutes) à un instant donné. */
function offsetMinutes(date) {
  const p = zurichParts(date);
  const asUTC = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute);
  return Math.round((asUTC - Math.floor(date.getTime() / 60000) * 60000) / 60000);
}

/** Instant correspondant à une heure locale de Zurich. */
export function zurichDate(year, month, day, hour, minute) {
  const guess = new Date(Date.UTC(year, month - 1, day, hour, minute));
  const offset = offsetMinutes(guess);
  const result = new Date(guess.getTime() - offset * 60000);
  // Correction autour des changements d'heure.
  const offset2 = offsetMinutes(result);
  return offset2 === offset ? result : new Date(guess.getTime() - offset2 * 60000);
}

/** "07:23" en heure suisse. */
export function hhmm(date) {
  const p = zurichParts(date);
  return `${String(p.hour).padStart(2, '0')}:${String(p.minute).padStart(2, '0')}`;
}

/** "mer. 30 sept., 20:30" dans la langue donnée. */
export function dayTime(date, language) {
  const locales = { fr: 'fr-CH', de: 'de-CH', it: 'it-CH', en: 'en-GB' };
  return new Intl.DateTimeFormat(locales[language] ?? 'fr-CH', {
    timeZone: TZ, weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
  }).format(date);
}

/**
 * Prochaine occurrence de l'heure habituelle d'un trajet, strictement après `after`,
 * sur un jour actif (même logique que Trip.nextOccurrence dans l'app).
 */
export function nextOccurrence(trip, after) {
  if (trip.usualHour == null || trip.usualMinute == null) return null;
  const start = zurichParts(after);
  for (let offset = 0; offset < 8; offset++) {
    const dayUTC = new Date(Date.UTC(start.year, start.month - 1, start.day + offset, 12));
    const d = { year: dayUTC.getUTCFullYear(), month: dayUTC.getUTCMonth() + 1, day: dayUTC.getUTCDate() };
    const candidate = zurichDate(d.year, d.month, d.day, trip.usualHour, trip.usualMinute);
    const weekday = zurichParts(candidate).weekday;
    const active = !trip.weekdays?.length || trip.weekdays.includes(weekday);
    if (active && candidate > after) return candidate;
  }
  return null;
}

/** Le trajet est-il d'actualité ? (de 2 h avant à 30 min après l'heure habituelle ; toujours sans heure). */
export function isInMonitoringWindow(trip, now) {
  if (trip.usualHour == null) return true;
  const next = nextOccurrence(trip, new Date(now.getTime() - 30 * 60000));
  return next != null && next.getTime() - now.getTime() <= 2 * 3600 * 1000;
}
