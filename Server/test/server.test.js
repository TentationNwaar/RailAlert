// Tests : node --test test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import crypto from 'node:crypto';

process.env.DATA_DIR = './test-data';
const { zurichDate, zurichParts, nextOccurrence, isInMonitoringWindow, hhmm } = await import('../src/time.js');
const { parseXML } = await import('../src/xml.js');
const { parseConnection } = await import('../src/ojp.js');
const { matchTrip, shortNumber } = await import('../src/matcher.js');

test('heure suisse, y compris changement d\'heure', () => {
  const summer = zurichDate(2026, 7, 1, 7, 23);
  assert.equal(summer.toISOString(), '2026-07-01T05:23:00.000Z');
  const winter = zurichDate(2026, 12, 1, 7, 23);
  assert.equal(winter.toISOString(), '2026-12-01T06:23:00.000Z');
  assert.equal(hhmm(summer), '07:23');
  assert.equal(zurichParts(summer).weekday, 4); // mercredi
});

test('prochaine occurrence d\'un trajet en semaine', () => {
  const trip = { usualHour: 7, usualMinute: 23, weekdays: [2, 3, 4, 5, 6] };
  // Samedi 3 octobre 2026 à 10:00 -> lundi 5 octobre 07:23
  const next = nextOccurrence(trip, zurichDate(2026, 10, 3, 10, 0));
  assert.equal(next.toISOString(), zurichDate(2026, 10, 5, 7, 23).toISOString());
  assert.equal(isInMonitoringWindow(trip, zurichDate(2026, 10, 5, 6, 0)), true);
  assert.equal(isInMonitoringWindow(trip, zurichDate(2026, 10, 5, 4, 0)), false);
});

test('lecture d\'une réponse OJP réelle', () => {
  const root = parseXML(readFileSync(new URL('./ojp-trip-sample.xml', import.meta.url), 'utf8'));
  const list = root.descendants('TripResult').map(parseConnection).filter(Boolean);
  assert.equal(list.length, 3);
  assert.equal(list[0].line, 'IR 90');
  assert.equal(list[0].track, '1');
  assert.equal(list[0].departureDelay, 1);
  assert.deepEqual(list[0].stopIds, ['ch:1:sloid:1300', 'ch:1:sloid:1200', 'ch:1:sloid:1120']);
  assert.equal(list[0].occupancySecond, 2);
});

test('numéros de gare', () => {
  assert.equal(shortNumber('ch:1:sloid:1120'), '1120');
  assert.equal(shortNumber('8501120'), '1120');
});

test('correspondance alerte / trajet (lieu + moment)', () => {
  const connection = {
    id: 'x', stopIds: ['ch:1:sloid:1300', 'ch:1:sloid:1200', 'ch:1:sloid:4013', 'ch:1:sloid:4012'],
    expectedDeparture: new Date('2026-10-01T19:00:00Z'), expectedArrival: new Date('2026-10-01T19:40:00Z'),
  };
  const alert = (periodStart, periodEnd) => ({
    id: 'a', isConstruction: true, interrupted: true,
    places: [{ sloid: 'ch:1:sloid:1200', name: 'Vevey' }, { sloid: 'ch:1:sloid:4013', name: 'Chexbres-Village' }, { sloid: 'ch:1:sloid:4012', name: 'Puidoux' }],
    periods: [{ start: new Date(periodStart), end: new Date(periodEnd) }],
    title: () => 'Interruption Vevey – Puidoux', details: () => '',
  });
  const trip = { fromId: '8501300', toId: '8504012' };
  assert.equal(matchTrip(trip, { focus: connection, upcoming: [] }, [alert('2026-10-01T18:30:00Z', '2026-10-02T02:00:00Z')], 'fr').length, 1);
  assert.equal(matchTrip(trip, { focus: connection, upcoming: [] }, [alert('2026-10-01T21:00:00Z', '2026-10-02T02:00:00Z')], 'fr').length, 0);
});

test('jeton APNs signé en ES256 et vérifiable', async () => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  process.env.APNS_KEY = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const { config } = await import('../src/config.js');
  config.apnsKey = process.env.APNS_KEY;
  config.apnsKeyId = 'ABC123DEFG';
  config.apnsTeamId = 'TEAM123456';
  const { providerToken } = await import('../src/apns.js');
  const token = providerToken();
  const [h, c, s] = token.split('.');
  const ok = crypto.verify('sha256', Buffer.from(`${h}.${c}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url'));
  assert.equal(ok, true);
  assert.equal(JSON.parse(Buffer.from(h, 'base64url')).kid, 'ABC123DEFG');
});
