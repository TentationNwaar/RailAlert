// Correspondance alerte ↔ trajet (même règles que TripAlertMatcher.swift, testées sur le flux réel).
//  1. Lieu : le train roule directement entre deux gares citées par l'alerte (deux arrêts consécutifs),
//     ou l'alerte vise une seule gare du trajet nommée dans son titre.
//  2. Moment : une plage de l'alerte recouvre l'horaire du train (± 10 min).

export function shortNumber(id) {
  const parts = String(id).split(':');
  if (parts.length >= 4 && parts[2] === 'sloid') return String(Number(parts[3]));
  const n = Number(id);
  if (!Number.isFinite(n)) return null;
  return n >= 8500000 && n < 8600000 ? String(n - 8500000) : String(n);
}

export function matchTrip(trip, report, alerts, language) {
  const connection = report?.focus ?? report?.upcoming?.[0];
  if (!connection) return [];
  let route = connection.stopIds.map(shortNumber).filter(Boolean);
  if (!route.length) route = [trip.fromId, trip.toId].map(shortNumber).filter(Boolean);
  const routeSet = new Set(route);
  const start = connection.expectedDeparture.getTime() - 10 * 60000;
  const end = connection.expectedArrival.getTime() + 10 * 60000;

  const result = [];
  for (const alert of alerts) {
    const numbers = new Set(alert.places.map((p) => shortNumber(p.sloid)));
    const title = alert.title(language);
    let touches;
    if (alert.places.length === 1) {
      touches = [...numbers].every((n) => routeSet.has(n)) && title.toLowerCase().includes(alert.places[0].name.toLowerCase());
    } else {
      touches = route.some((n, i) => i + 1 < route.length && numbers.has(n) && numbers.has(route[i + 1]));
    }
    if (!touches) continue;
    const ranges = alert.periods.length ? alert.periods : [];
    const range = ranges.find((p) => p.start.getTime() <= end && p.end.getTime() >= start);
    if (ranges.length && !range) continue;
    result.push({
      id: alert.id,
      title,
      details: alert.details(language),
      isConstruction: alert.isConstruction,
      isInterruption: alert.interrupted,
      start: range?.start ?? null,
      end: range?.end ?? null,
    });
  }
  return result.sort((a, b) => (a.isInterruption === b.isInterruption ? 0 : a.isInterruption ? -1 : 1));
}
