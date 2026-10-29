# Red Alert : fiche App Store et liste de contrôle

Tout ce qu'il faut pour publier Red Alert sur l'App Store. Les textes sont prêts à copier dans App Store Connect, le site d'Apple où l'on gère les apps publiées. Les longueurs respectent les limites d'Apple : 30 caractères pour le nom et le sous-titre, 100 pour les mots-clés.

## 1. Avant la soumission (dans l'ordre)

1. **Compte Apple Developer** : s'inscrire au programme (99 $ par an) sur developer.apple.com.
2. **Sécurité des clés** : régénérer les deux clés opentransportdata.swiss (GTFS-SA et OJP), puis mettre les nouvelles dans `Shared/Secrets.swift`. L'ancienne clé GTFS-SA figure dans l'historique Git (commit « ajout du projet »).
3. **Xcode, cible RedAlert → Signing & Capabilities** :
   - choisir l'équipe payante (pas « Personal Team ») ;
   - vérifier **App Groups** (`group.ch.maxweyermann.redalert`) sur les deux cibles ;
   - ajouter **Push Notifications** et **Background Modes → Background fetch**.
4. **App Store Connect → Business** : accepter le contrat **Paid Applications**, ajouter le compte bancaire et remplir les formulaires fiscaux. Sans cela, les achats ne fonctionnent pas.
5. **App Store Connect → Mon app → Achats intégrés** : créer les deux produits (voir section 6).
6. **Politique de confidentialité** :
   - remplir `RedAlert/Settings/LegalInfo.swift` ;
   - publier la page web (par exemple avec GitHub Pages) ;
   - copier son adresse dans `privacyPolicyURL` et dans App Store Connect.
7. **Page d'assistance** : une adresse web avec un moyen de contact (exigée par Apple). Une simple page avec ton e-mail suffit.
8. **TestFlight** : envoyer une version de test et l'installer sur ton iPhone. Pour l'envoyer : **Product → Archive** dans Xcode, puis **Distribute App → App Store Connect**.
9. **Tester l'accessibilité** sur l'iPhone (voir section 8).
10. **Soumettre** la version à Apple.

## 2. Informations générales

| Champ | Valeur |
|---|---|
| Catégorie principale | Voyages (Travel) |
| Catégorie secondaire | Navigation |
| Âge | 4+ (aucun contenu sensible) |
| Prix | Gratuit, avec achats intégrés |
| Appareils | iPhone uniquement, iOS 18 ou plus récent |
| Chiffrement | Aucun chiffrement propre (déjà déclaré dans Info.plist : `ITSAppUsesNonExemptEncryption = NO`) |
| Copyright | 2026 Max Weyermann |

À ne pas utiliser : le nom ou le logo **CFF / SBB / FFS** dans le nom, le sous-titre, les mots-clés ou les captures. Sinon, Apple peut refuser l'app pour usage d'une marque (règle 5.2).

## 3. Nom, sous-titre et mots-clés

| Langue | Nom (30 max) | Sous-titre (30 max) |
|---|---|---|
| Français | Red Alert – Trains en Suisse | Retards, travaux et voies |
| Deutsch | Red Alert – Bahn Schweiz | Verspätungen, Bau und Gleise |
| Italiano | Red Alert – Treni in Svizzera | Ritardi, lavori e binari |
| English | Red Alert – Swiss Trains | Delays, works and platforms |

**Mots-clés** (séparés par des virgules, sans espace) :

- FR : `train,retard,suppression,travaux,voie,gare,horaire,suisse,perturbation,trajet,alerte,quai,widget`
- DE : `zug,verspätung,ausfall,bauarbeiten,gleis,bahnhof,fahrplan,schweiz,störung,pendler,warnung,widget`
- IT : `treno,ritardo,soppressione,lavori,binario,stazione,orario,svizzera,perturbazione,pendolare,avviso`
- EN : `train,delay,cancellation,works,platform,station,timetable,switzerland,disruption,commute,alert`

## 4. Description

### Français

**Texte promotionnel** : Ton train a du retard ? Red Alert te prévient avant même que tu partes.

Red Alert surveille les trajets que tu fais tous les jours et te prévient dès que quelque chose change : retard, suppression, changement de voie, perturbation ou travaux sur le parcours.

CARTE DU RÉSEAU
• Toutes les perturbations et tous les travaux en Suisse, sur une carte
• Triangle rouge : plus aucun train ; triangle jaune : service restreint
• Filtres par type d'alerte et par région

TES TRAJETS
• Retard, suppression et voie du train, en temps réel
• Un autre train proposé quand le tien a un problème
• Affluence en 1re et 2e classe
• Historique de ponctualité

TOUJOURS À PORTÉE
• Notifications et widget sur l'écran verrouillé
• Suivi en direct dans la Dynamic Island
• « Dis Siri, mon train est à l'heure avec Red Alert »
• Départs en gare avec voies et retards

ACCESSIBLE
VoiceOver, grande taille de texte, contraste renforcé et animations réduites sont pris en charge.

RED ALERT+
La version gratuite surveille 1 trajet. Red Alert+ débloque les trajets illimités, le suivi en direct, les alternatives et la ponctualité : CHF 3.– par mois (7 jours d'essai gratuit) ou un achat unique à vie.

Données : opentransportdata.swiss (plateforme officielle des données ouvertes des transports publics suisses). Red Alert n'est pas une application officielle des CFF ni d'une entreprise de transport.

### Deutsch

**Werbetext**: Dein Zug hat Verspätung? Red Alert sagt es dir, bevor du losgehst.

Red Alert überwacht deine täglichen Strecken und warnt dich, sobald sich etwas ändert: Verspätung, Ausfall, Gleisänderung, Störung oder Bauarbeiten auf der Strecke.

NETZKARTE
• Alle Störungen und Bauarbeiten der Schweiz auf einer Karte
• Rotes Dreieck: kein Zugverkehr; gelbes Dreieck: eingeschränkter Betrieb
• Filter nach Meldungsart und Region

DEINE STRECKEN
• Verspätung, Ausfall und Gleis in Echtzeit
• Ein anderer Zug, wenn deiner ein Problem hat
• Auslastung in der 1. und 2. Klasse
• Pünktlichkeitsverlauf

IMMER GRIFFBEREIT
• Mitteilungen und Widget auf dem Sperrbildschirm
• Live-Verfolgung in der Dynamic Island
• «Hey Siri, ist mein Zug pünktlich laut Red Alert»
• Abfahrten am Bahnhof mit Gleisen und Verspätungen

BARRIEREFREI
VoiceOver, grosse Schrift, erhöhter Kontrast und reduzierte Bewegung werden unterstützt.

RED ALERT+
Die Gratisversion überwacht 1 Strecke. Red Alert+ schaltet unbegrenzte Strecken, Live-Verfolgung, Alternativen und Pünktlichkeit frei: CHF 3.– pro Monat (7 Tage gratis) oder einmaliger Kauf auf Lebenszeit.

Daten: opentransportdata.swiss (offizielle Open-Data-Plattform des Schweizer ÖV). Red Alert ist keine offizielle App der SBB oder eines Transportunternehmens.

### Italiano

**Testo promozionale**: Il tuo treno è in ritardo? Red Alert te lo dice prima ancora che tu esca.

Red Alert controlla i tragitti che fai ogni giorno e ti avvisa appena qualcosa cambia: ritardo, soppressione, cambio di binario, perturbazione o lavori sul percorso.

MAPPA DELLA RETE
• Tutte le perturbazioni e i lavori in Svizzera su una mappa
• Triangolo rosso: nessun treno; triangolo giallo: servizio limitato
• Filtri per tipo di avviso e per regione

I TUOI TRAGITTI
• Ritardo, soppressione e binario in tempo reale
• Un altro treno quando il tuo ha un problema
• Affluenza in 1a e 2a classe
• Storico della puntualità

SEMPRE A PORTATA DI MANO
• Notifiche e widget sulla schermata di blocco
• Diretta nella Dynamic Island
• «Ehi Siri, il mio treno è in orario secondo Red Alert»
• Partenze in stazione con binari e ritardi

ACCESSIBILE
VoiceOver, testo grande, contrasto elevato e movimento ridotto sono supportati.

RED ALERT+
La versione gratuita controlla 1 tragitto. Red Alert+ sblocca tragitti illimitati, diretta, alternative e puntualità: CHF 3.– al mese (7 giorni gratis) o acquisto unico a vita.

Dati: opentransportdata.swiss (piattaforma ufficiale dei dati aperti dei trasporti pubblici svizzeri). Red Alert non è un'app ufficiale delle FFS né di un'impresa di trasporto.

### English

**Promotional text**: Train running late? Red Alert tells you before you even leave.

Red Alert watches the trips you make every day and warns you as soon as something changes: delay, cancellation, platform change, disruption or construction work on the route.

NETWORK MAP
• Every disruption and construction site in Switzerland on one map
• Red triangle: no trains; yellow triangle: limited service
• Filters by alert type and region

YOUR TRIPS
• Real-time delay, cancellation and platform
• Another train suggested when yours has a problem
• 1st and 2nd class occupancy
• Punctuality history

ALWAYS AT HAND
• Notifications and lock screen widget
• Live tracking in the Dynamic Island
• "Hey Siri, is my train on time with Red Alert"
• Station departures with platforms and delays

ACCESSIBLE
VoiceOver, larger text, increased contrast and reduced motion are supported.

RED ALERT+
The free version watches 1 trip. Red Alert+ unlocks unlimited trips, live tracking, alternatives and punctuality: CHF 3 per month (7-day free trial) or a one-time lifetime purchase.

Data: opentransportdata.swiss (official open data platform of Swiss public transport). Red Alert is not an official app of SBB or any transport company.

## 5. Captures d'écran

Le format obligatoire est l'iPhone 6,9 pouces (1320 × 2868 pixels). Apple réduit lui-même ces captures pour les autres tailles. Avec le simulateur **iPhone 17 Pro Max**, faire **Cmd + S** pour enregistrer une capture.

Ordre conseillé (de 3 à 10 captures) :

1. Carte avec plusieurs triangles et une fiche d'alerte ouverte.
2. « Mes trajets » avec un retard et une alternative.
3. Écran verrouillé avec le widget et une notification.
4. Suivi en direct dans la Dynamic Island.
5. Tableau des départs d'une gare.
6. Écran Red Alert+.

Les captures peuvent être faites en français seulement. Apple les réutilise pour les autres langues si on n'en fournit pas d'autres.

## 6. Achats intégrés

| Produit | Type | Identifiant | Prix | Détail |
|---|---|---|---|---|
| Red Alert+ mensuel | Abonnement auto-renouvelable, groupe « Red Alert+ » | `ch.maxweyermann.RedAlert.plus.monthly` | CHF 3.– | Offre d'introduction : essai gratuit d'une semaine |
| Red Alert+ à vie | Non consommable | `ch.maxweyermann.RedAlert.plus.lifetime` | à choisir (25.– ou environ 60.–) | — |

Pour chaque produit, Apple demande un nom et une description dans chaque langue, ainsi qu'une **capture de l'écran d'achat** pour la vérification.

## 7. Confidentialité (« App Privacy » dans App Store Connect)

**Tant que le serveur push n'est pas en ligne** : répondre « Aucune donnée collectée » (Data Not Collected). Tout reste sur l'iPhone.

**Une fois le serveur en ligne** : déclarer la catégorie **Autres données → Autres types de données** (les trajets : gares, heure, jours) avec les réponses suivantes :

- utilisation : fonctionnalité de l'app ;
- liée à l'identité de l'utilisateur : **non** ;
- utilisée pour le suivi (tracking) : **non**.

Le jeton de notification n'a pas besoin d'être déclaré.

**Étiquettes d'accessibilité** : App Store Connect permet de déclarer les fonctions d'accessibilité prises en charge. Ne cocher que ce qui a été testé (section 8) :

- VoiceOver ;
- Texte plus grand ;
- Interface sombre ;
- Contraste suffisant ;
- Différencier sans couleur ;
- Réduire les animations.

## 8. Tester l'accessibilité sur l'iPhone

Astuce : dans **Réglages → Accessibilité → Raccourci accessibilité**, coche VoiceOver. Trois appuis sur le bouton latéral l'activent ou le désactivent.

| Fonction | Où l'activer | Ce qu'il faut vérifier |
|---|---|---|
| VoiceOver (lecteur d'écran) | Réglages → Accessibilité → VoiceOver | Chaque bouton est lu avec un nom clair. Le bouton « Liste des alertes » permet de tout parcourir sans la carte. On peut ouvrir un trajet. Le tutoriel garde le focus dans la bulle. |
| Texte plus grand | Réglages → Accessibilité → Affichage et taille du texte → Police plus grande (taille maximale) | Aucun texte coupé de façon gênante. La bulle du tutoriel défile. L'en-tête de la carte retire le logo pour laisser la place au texte. |
| Augmenter le contraste | même menu → Augmenter le contraste | Les rouges deviennent plus lisibles. Les cartes ont un contour plus visible. |
| Différencier sans couleur | même menu → Différencier sans couleur | Les triangles d'interruption ont un contour blanc. |
| Réduire les animations | Accessibilité → Mouvement → Réduire les animations | Le splash devient un simple fondu. Plus de pulsation sur la carte ni dans le tutoriel. |

Dans Xcode, **Xcode → Open Developer Tool → Accessibility Inspector** audite un écran du simulateur : bouton **Audit**, puis **Run Audit**.

## 9. Note pour l'équipe de vérification d'Apple (App Review)

> Red Alert displays Swiss rail disruptions and construction work from opentransportdata.swiss (official open data platform of Swiss public transport, used under its terms of use). It is not affiliated with SBB.
> To test: open the "My trips" tab, add a trip (e.g. Lausanne → Genève), and open it to see real-time status, departures and punctuality. A second trip opens the Red Alert+ purchase screen (monthly subscription with a 7-day free trial, or lifetime purchase). Notifications are sent when a monitored train is delayed, cancelled or changes platform.
