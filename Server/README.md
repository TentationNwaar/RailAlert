# Serveur push Rail Alert

Le serveur surveille les trajets de chaque utilisateur **chaque minute** et envoie les alertes par notification push (APNs, le service d'Apple qui achemine les notifications), même quand l'app est fermée :

- retard au-dessus du seuil, suppression, **changement de voie** (horaire officiel OJP 2.0) ;
- perturbations et travaux sur le parcours (GTFS-RT Service Alerts), une seule fois par alerte ;
- mise à jour de la **Live Activity** (suivi en direct sur l'écran verrouillé) ;
- textes dans la langue choisie dans l'app (FR, DE, IT, EN).

Aucune dépendance npm : Node.js 22 suffit.

## Tester sur ton Mac (sans compte Apple)

1. Installe Node.js 22 (https://nodejs.org).
2. Dans le Terminal, va dans ce dossier : `cd "…/RedAlert/Server"`.
3. Lance les tests : `npm test` (6 tests doivent passer).
4. Lance le serveur en mode essai (rien n'est envoyé à Apple, les notifications s'affichent dans le Terminal) :
   ```
   DRY_RUN=1 APP_KEY=test OTD_GTFS_SA_KEY=<clé GTFS-SA> OTD_OJP_KEY=<clé OJP> node src/index.js
   ```
5. Ouvre http://localhost:8080/health : tu dois voir `"ok": true` et le nombre d'alertes chargées.

## Mise en service (avec le compte Apple Developer)

### 1. Créer la clé APNs chez Apple
1. https://developer.apple.com/account → **Certificates, Identifiers & Profiles** → **Keys** → **+**.
2. Nom : « Rail Alert Push », coche **Apple Push Notifications service (APNs)** → **Continue** → **Register**.
3. Télécharge le fichier `AuthKey_XXXXXXXXXX.p8` (téléchargeable **une seule fois**) et note le **Key ID** (10 caractères).
4. Note ton **Team ID** (dans **Membership**).

### 2. Activer les notifications push dans l'app (Xcode)
1. Cible **RedAlert** → **Signing & Capabilities** → **+ Capability** → **Push Notifications**.
2. Dans `Shared/Secrets.swift`, remplis `serverURL` (adresse https du serveur) et `serverAppKey` (même valeur que `APP_KEY`).

### 3. Héberger le serveur
N'importe quel hébergement Node.js ou Docker convient (Fly.io, Railway, Render, un petit VPS…). Le serveur doit tourner en continu et garder le dossier `DATA_DIR` (volume persistant). L'adresse doit être en **https** (exigence d'iOS).

Variables à définir (voir `.env.example`) : `APP_KEY`, `OTD_GTFS_SA_KEY`, `OTD_OJP_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`, `APNS_KEY_FILE` (ou `APNS_KEY` avec le contenu du .p8).

Exemple avec Docker :
```
docker build -t redalert-server .
docker run -d --env-file .env -v "$(pwd)/data:/data" -v "$(pwd)/AuthKey.p8:/secrets/AuthKey.p8" -p 8080:8080 redalert-server
```

## Fonctionnement

| Fichier | Rôle |
|---|---|
| `src/index.js` | API : `POST /v1/devices` (inscription, clé `X-App-Key`), `DELETE /v1/devices/:token`, `GET /health` |
| `src/monitor.js` | Boucle chaque minute : horaires, alertes, notifications, Live Activities |
| `src/ojp.js` | Horaires officiels OJP 2.0 (même lecture que `OJPService.swift`) |
| `src/alerts.js` | Perturbations et travaux GTFS-SA + arrêts officiels data.sbb.ch |
| `src/matcher.js` | Correspondance alerte ↔ trajet (mêmes règles que `TripAlertMatcher.swift`) |
| `src/apns.js` | Envoi à Apple (HTTP/2, jeton JWT ES256 signé avec la clé .p8) |
| `src/store.js` | Appareils et trajets (fichier `devices.json`) |

Un trajet est interrogé chaque minute de 2 h avant à 30 min après son heure habituelle, et au moins une fois par heure sinon. Les appareils dont l'app a été désinstallée (réponse 410 d'Apple) sont supprimés automatiquement.

Testé le 30.09.2026 en mode DRY_RUN sur les vraies données : 78 alertes ferroviaires chargées, trajet Montreux → Berne interrogé via OJP, notification de retard générée en allemand et mise à jour de Live Activity produite.

## Données personnelles

Le serveur conserve uniquement : le jeton push de l'iPhone, la langue, les trajets (gares, heure, jours, seuil) et ce qui a déjà été notifié. Aucun nom, e-mail ni position GPS. Voir `Legal/` à la racine du projet.
