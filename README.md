# Red Alert

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

## Clé API (développeur uniquement)

Les perturbations et les travaux viennent d'opentransportdata.swiss (produit LA-GTFS-SA). La clé est intégrée dans `RedAlert/Settings/Secrets.swift`, fichier ignoré par git : ne pas le publier. Les utilisateurs n'ont rien à configurer.

Si la clé est vide ou refusée, l'app utilise automatiquement data.sbb.ch (perturbations seulement, textes traduits sur l'iPhone).

Limite du plan : 5 requêtes par minute ; l'app en fait une toutes les 5 minutes (environ 1 Mo compressé).

## Filtres

Bouton « filtres » en haut de la carte : types d'alertes (perturbations, travaux en cours / du jour / 7 jours, informations), seulement les interruptions, et une ou plusieurs des 7 grandes régions de Suisse. Les choix sont enregistrés sur l'iPhone. Par défaut : perturbations et travaux en cours, toute la Suisse.

## Alertes sur les trajets

Pour chaque trajet, l'app surveille :
- le train lui-même (search.ch) : retard au-dessus du seuil choisi, suppression ;
- les perturbations et travaux du réseau qui touchent son parcours (`RedAlert/Services/TripAlertMatcher.swift`) :
  1. **lieu** : le train roule directement entre deux gares citées par l'alerte (deux arrêts consécutifs du trajet), ou l'alerte vise une seule gare du trajet nommée dans son titre ;
  2. **moment** : une des plages horaires de l'alerte recouvre l'horaire du train (± 10 min). Des travaux de nuit ne concernent donc pas le train de 7 h.

Le résultat apparaît sur la carte du trajet (bordure jaune ou rouge), dans le détail, dans le widget, et en notification locale (une seule fois par alerte et par trajet).

## Ajouter le widget sur l'écran verrouillé

1. Lancer l'app une fois et ajouter un trajet (onglet **Mes trajets**, bouton +).
2. Verrouiller l'iPhone, appuyer longuement sur l'écran verrouillé, puis **Personnaliser** → **Écran verrouillé**.
3. Toucher la zone sous l'heure, chercher **Red Alert**, choisir le widget rectangulaire **Mon trajet**.

## Organisation du code

| Dossier | Contenu |
|---|---|
| `Shared/` | Code commun à l'app et au widget : modèles, appels aux API, stockage (App Group) |
| `RedAlert/Map/` | Carte de la Suisse, triangles d'alerte, filtres par type et par région |
| `RedAlert/Trips/` | Liste, création et détail des trajets |
| `RedAlert/Services/` | Perturbations et travaux (deux sources), vérification en arrière-plan, notifications |
| `RedAlert/Onboarding/` | Splash screen, choix de la langue, tutoriel à bulles |
| `RedAlert/Settings/` | Écran de réglages (notifications, sources) et clé API privée |
| `RedAlertWidget/` | Widget écran verrouillé et écran d'accueil |
| `Config/` | Info.plist et fichiers d'autorisations (entitlements) |

Les dossiers sont « synchronisés » : tout fichier `.swift` ajouté dans un de ces dossiers est compilé automatiquement.

## Sources de données (sans clé API)

| Source | Utilisation | Limite |
|---|---|---|
| data.sbb.ch — `rail-traffic-information` | Perturbations officielles CFF (carte, sans clé) | Mise à jour toutes les 5 min, textes en anglais |
| opentransportdata.swiss — `gtfs-sa` | Perturbations + travaux, en français (avec clé) | 2 requêtes par minute |
| data.sbb.ch — `dienststellen` | Coordonnées et type des arrêts (train / bus) | Usage raisonnable |
| search.ch — `route.json` | Retard et suppression des trains d'un trajet | 1000 recherches par jour |
| transport.opendata.ch — `locations` | Recherche de gares, coordonnées GPS | Usage raisonnable |

## Limites connues de cette version

- Les vérifications en arrière-plan sont lancées quand iOS le décide (souvent toutes les 15 à 60 min). Pour des alertes à la minute près, il faudra un serveur qui envoie des notifications push (nécessite le compte Apple Developer payant).
- search.ch ne donne que les gares où le train s'arrête : une perturbation limitée à une portion traversée sans arrêt peut ne pas être détectée.
- Le widget se rafraîchit toutes les 10 min quand le trajet approche, sinon toutes les 30 min (quota imposé par iOS).
- Seules les perturbations dont les gares sont reconnues apparaissent sur la carte. Les autres restent visibles dans la liste.
