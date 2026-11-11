# Rail Alert

App iOS qui affiche les perturbations du réseau CFF sur une carte et surveille les trajets habituels de l'utilisateur (retard, suppression), jusque sur l'écran verrouillé.

## Ouvrir et lancer le projet

Version minimale : iOS 18 (nécessaire pour la traduction automatique). Langues : français, allemand, italien, anglais.

1. Double-cliquer sur `RedAlert.xcodeproj`.
2. Dans la colonne de gauche, cliquer sur l'icône bleue **RedAlert** (tout en haut).
3. Dans la liste **TARGETS**, sélectionner **RedAlert**, puis l'onglet **Signing & Capabilities**.
   - **Team** : choisir ton compte Apple (ou « Add an Account… » pour te connecter).
4. Refaire la même chose pour la cible **RedAlertWidget** (même Team).
5. En haut de la fenêtre, choisir le schéma **RedAlert** et ton iPhone (ou un simulateur), puis appuyer sur ▶ (Cmd+R).

Si Xcode signale que l'identifiant `ch.maxweyermann.RedAlert` est déjà pris, remplacer `maxweyermann` par autre chose dans les deux cibles (le widget doit garder le suffixe `.Widget`).

Si Xcode signale un problème d'**App Group** : dans **Signing & Capabilities**, vérifier que la case `group.ch.maxweyermann.redalert` est cochée pour les deux cibles. Si tu changes ce nom, change-le aussi dans `Shared/AppConfig.swift`.

## Premier lancement

1. **Splash screen** (`RedAlert/Onboarding/SplashView.swift`) : le logo apparaît en fondu, un petit train rouge traverse l'écran de gauche à droite en traçant une ligne, puis l'écran s'ouvre en deux le long de cette ligne. Il s'affiche à chaque lancement (environ 2,5 s).
2. **Choix de la langue** (premier lancement seulement) : français, allemand, italien ou anglais. Modifiable ensuite dans Réglages → Langue.
3. **Tutoriel à bulles** (premier lancement seulement) : 7 bulles, avec mise en évidence des boutons Filtres, Liste et Réglages, une légende des triangles, un bouton pour activer les notifications et un bouton « Ajouter mon premier trajet ». Relançable depuis Réglages → Revoir le tutoriel.

Pour revoir le premier lancement pendant le développement : supprimer l'app de l'iPhone puis la relancer depuis Xcode.

## Langues

- Tous les textes passent par `t("texte en français")` (`Shared/Localization.swift`). Les traductions sont dans `Shared/Translations.swift`, une ligne par texte : français, allemand, italien, anglais.
- La langue est enregistrée dans l'App Group : le widget et les notifications l'utilisent aussi.
- Les messages officiels (opentransportdata.swiss) sont affichés dans la langue choisie ; le classement (travaux, interruption) se fait toujours sur la version française.
- Le romanche n'est pas proposé : les messages officiels n'existent pas dans cette langue et le traducteur d'Apple ne le prend pas en charge.

## Fonctions de suivi

- **Horaires officiels OJP 2.0** (`Shared/OJPService.swift`) : retard exact, voie prévue et réelle, affluence, gares traversées, suppressions.
- **Changement de voie** : notification « Le train de 07:23 part de la voie 4 (au lieu de 1) ».
- **Alternative** : quand le train est supprimé, en retard ou le tronçon interrompu, l'app propose le train qui arrive le plus tôt (carte du trajet, notification, Live Activity, Siri).
- **Affluence** : 1 à 3 silhouettes (vert, jaune, rouge) sur la carte du trajet et dans les départs.
- **Suivi en direct (Live Activity)** : bouton dans le détail d'un trajet ; écran verrouillé + Dynamic Island.
- **Raccourcis Siri** : « Mon train est à l'heure avec Rail Alert » (phrases dans les 4 langues, `RedAlert/AppShortcuts.xcstrings`).
- **Départs d'une gare** : toucher une gare d'un tronçon sur la carte, ou les boutons « Départs de … » dans le détail d'un trajet.
- **Ponctualité sur 30 jours** : dans le détail d'un trajet (basée sur les vérifications faites par l'app peu avant le départ).
- **Accessibilité** : descriptions VoiceOver sur les triangles, boutons ronds, voies, affluence, jours ; heures qui suivent la taille de texte choisie.

## Serveur push

Dossier `Server/` : serveur Node.js qui surveille les trajets chaque minute et envoie les alertes par push (voir `Server/README.md`). Nécessite le compte Apple Developer payant. Tant que `serverURL` est vide dans `Shared/Secrets.swift`, l'app fonctionne seule (notifications locales).

## Confidentialité et publication

- `RedAlert/PrivacyInfo.xcprivacy` et `RedAlertWidget/PrivacyInfo.xcprivacy` : déclarations exigées par Apple (pas de tracking ; jeton push et trajets envoyés au serveur pour le fonctionnement).
- `Legal/politique-de-confidentialite.md` et `Legal/privacy-policy.md` : politique à compléter (nom, contact, hébergeur) puis à publier en ligne ; son adresse est demandée dans App Store Connect.
- Conditions des sources (vérifiées le 30.09.2026) :
  - **opentransportdata.swiss** : usage dans une app publiée autorisé, **citer opentransportdata.swiss comme source** (fait dans les réglages et le tableau des départs), aucune responsabilité des CFF.
  - **search.ch** : ses conditions générales interdisent l'accès automatisé et l'usage commercial ; il a été retiré de l'app.
  - **Marque CFF** : ne pas utiliser « CFF », « SBB » ni leur logo dans le nom de l'app, l'icône ou les captures de l'App Store. La mention « n'est pas une application officielle des CFF » est présente dans les réglages.

## Clé API (développeur uniquement)

Les perturbations et les travaux viennent d'opentransportdata.swiss (produit LA-GTFS-SA). La clé est intégrée dans `Shared/Secrets.swift`, fichier ignoré par git : ne pas le publier. Les utilisateurs n'ont rien à configurer.

Si la clé est vide ou refusée, l'app utilise automatiquement data.sbb.ch (perturbations seulement, textes traduits sur l'iPhone).

Limite du plan : 5 requêtes par minute ; l'app en fait une toutes les 5 minutes (environ 1 Mo compressé).

## Filtres

Bouton « filtres » en haut de la carte : types d'alertes (perturbations, travaux en cours / du jour / 7 jours, informations), seulement les interruptions, et une ou plusieurs des 7 grandes régions de Suisse. Les choix sont enregistrés sur l'iPhone. Par défaut : perturbations et travaux en cours, toute la Suisse.

## Alertes sur les trajets

Pour chaque trajet, l'app surveille :
- le train lui-même (OJP 2.0) : retard au-dessus du seuil choisi, suppression ;
- les perturbations et travaux du réseau qui touchent son parcours (`RedAlert/Services/TripAlertMatcher.swift`) :
  1. **lieu** : le train roule directement entre deux gares citées par l'alerte (deux arrêts consécutifs du trajet), ou l'alerte vise une seule gare du trajet nommée dans son titre ;
  2. **moment** : une des plages horaires de l'alerte recouvre l'horaire du train (± 10 min). Des travaux de nuit ne concernent donc pas le train de 7 h.

Le résultat apparaît sur la carte du trajet (bordure jaune ou rouge), dans le détail, dans le widget, et en notification locale (une seule fois par alerte et par trajet).

## Ajouter le widget sur l'écran verrouillé

1. Lancer l'app une fois et ajouter un trajet (onglet **Mes trajets**, bouton +).
2. Verrouiller l'iPhone, appuyer longuement sur l'écran verrouillé, puis **Personnaliser** → **Écran verrouillé**.
3. Toucher la zone sous l'heure, chercher **Rail Alert**, choisir le widget rectangulaire **Mon trajet**.

## Organisation du code

| Dossier | Contenu |
|---|---|
| `Shared/` | Code commun à l'app et au widget : modèles, appels aux API, stockage (App Group) |
| `RedAlert/Map/` | Carte de la Suisse, triangles d'alerte, filtres par type et par région |
| `RedAlert/Trips/` | Liste, création et détail des trajets |
| `RedAlert/Services/` | Perturbations et travaux (deux sources), vérification en arrière-plan, notifications |
| `RedAlert/Onboarding/` | Splash screen, choix de la langue, tutoriel à bulles |
| `RedAlert/Settings/` | Écran de réglages (langue, notifications, aide, sources) |
| `RedAlert/LiveActivity/` | Démarrage et mise à jour du suivi en direct |
| `RedAlert/Stations/` | Tableau des départs d'une gare |
| `RedAlert/Intents/` | Raccourcis Siri |
| `Server/` | Serveur push (Node.js) |
| `Legal/` | Politique de confidentialité (FR, EN) |
| `RedAlertWidget/` | Widget écran verrouillé et écran d'accueil |
| `Config/` | Info.plist et fichiers d'autorisations (entitlements) |

Les dossiers sont « synchronisés » : tout fichier `.swift` ajouté dans un de ces dossiers est compilé automatiquement.

## Sources de données

| Source | Utilisation | Limite |
|---|---|---|
| data.sbb.ch — `rail-traffic-information` | Perturbations officielles CFF (carte, sans clé) | Mise à jour toutes les 5 min, textes en anglais |
| opentransportdata.swiss — `gtfs-sa` | Perturbations + travaux, en français (avec clé) | 2 requêtes par minute |
| data.sbb.ch — `dienststellen` | Coordonnées et type des arrêts (train / bus) | Usage raisonnable |
| opentransportdata.swiss — OJP 2.0 | Horaires en temps réel, voies, affluence, départs d'une gare | Selon le plan de la clé |
| transport.opendata.ch — `locations` | Recherche de gares, coordonnées GPS | Usage raisonnable |

## Limites connues de cette version

- Les vérifications en arrière-plan sont lancées quand iOS le décide (souvent toutes les 15 à 60 min). Pour des alertes à la minute près, il faudra un serveur qui envoie des notifications push (nécessite le compte Apple Developer payant).
- L'horaire ne donne que les gares où le train s'arrête : une perturbation limitée à une portion traversée sans arrêt peut ne pas être détectée.
- Le widget se rafraîchit toutes les 10 min quand le trajet approche, sinon toutes les 30 min (quota imposé par iOS).
- Seules les perturbations dont les gares sont reconnues apparaissent sur la carte. Les autres restent visibles dans la liste.

## Rail Alert+ (modèle freemium)

| Gratuit | Rail Alert+ |
|---|---|
| Carte, filtres, liste, départs en gare, Siri, widget | Tout le gratuit |
| 2 trajets surveillé (notifications locales) | Trajets illimités, serveur push |
| | Suivi en direct (Live Activity), alternatives, ponctualité |

- Produits (identifiants à reprendre tels quels dans App Store Connect) :
  - `ch.maxweyermann.RedAlert.plus.subscription.monthly` : abonnement mensuel, CHF 3.–, essai gratuit de 7 jours, groupe « Rail Alert+ » ;
  - `ch.maxweyermann.RedAlert.plus.lifetime` : achat non consommable, CHF 25.–.
- Code : `Shared/Premium.swift` (règles gratuit / payant), `RedAlert/Store/StoreManager.swift` (StoreKit 2), `RedAlert/Store/PaywallView.swift` (écran d'achat).
- Test dans Xcode sans compte payant : `RedAlert/RedAlert.storekit` (Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration).
- Si l'abonnement se termine : les trajets restent enregistrés, seul le premier est surveillé, et le serveur arrête de surveiller l'appareil.
