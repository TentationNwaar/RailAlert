// Réglages du serveur, lus dans les variables d'environnement (voir README.md).
import { readFileSync } from 'node:fs';

function env(name, fallback = '') {
  return process.env[name] ?? fallback;
}

export const config = {
  port: Number(env('PORT', '8080')),
  /** Clé partagée avec l'app (Secrets.serverAppKey), envoyée dans l'en-tête X-App-Key. */
  appKey: env('APP_KEY'),
  /** Clé opentransportdata.swiss abonnée à LA-GTFS-SA (perturbations et travaux). */
  gtfsSaKey: env('OTD_GTFS_SA_KEY'),
  /** Clé opentransportdata.swiss abonnée à OJP 2.0 (horaires en temps réel). */
  ojpKey: env('OTD_OJP_KEY'),
  /** APNs : identifiant de la clé (.p8), identifiant d'équipe Apple, identifiant de l'app. */
  apnsKeyId: env('APNS_KEY_ID'),
  apnsTeamId: env('APNS_TEAM_ID'),
  apnsTopic: env('APNS_TOPIC', 'ch.maxweyermann.RedAlert'),
  apnsKey: env('APNS_KEY_FILE') ? readFileSync(env('APNS_KEY_FILE'), 'utf8') : env('APNS_KEY'),
  /** Dossier où sont enregistrés les appareils et leurs trajets. */
  dataDir: env('DATA_DIR', './data'),
  /** DRY_RUN=1 : n'envoie rien à Apple, affiche seulement les notifications dans le journal. */
  dryRun: env('DRY_RUN') === '1' || !env('APNS_KEY_ID'),
  /** Intervalle de surveillance (secondes). */
  tickSeconds: Number(env('TICK_SECONDS', '60')),
};
