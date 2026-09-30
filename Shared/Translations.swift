import Foundation

/// Traductions de l'interface. Chaque ligne : [français, allemand, italien, anglais].
/// Le texte français sert de clé : un texte absent de la table reste affiché en français.
///
/// Pour ajouter un texte : écrire `t("Mon texte")` dans le code, puis ajouter une ligne ici.
enum Translations {
    static func text(_ french: String, in language: AppLanguage) -> String {
        let column: Int
        switch language {
        case .fr: return french
        case .de: column = 1
        case .it: column = 2
        case .en: column = 3
        }
        guard let row = table[french], row.count > column, !row[column].isEmpty else { return french }
        return row[column]
    }

    private static let table: [String: [String]] = {
        var dict: [String: [String]] = [:]
        for row in rows where !row.isEmpty { dict[row[0]] = row }
        return dict
    }()

    private static let rows: [[String]] = [
        // MARK: Onglets et général
        ["Carte", "Karte", "Mappa", "Map"],
        ["Mes trajets", "Meine Strecken", "I miei tragitti", "My trips"],
        ["OK", "OK", "OK", "OK"],
        ["Annuler", "Abbrechen", "Annulla", "Cancel"],
        ["Enregistrer", "Sichern", "Salva", "Save"],
        ["Supprimer", "Löschen", "Elimina", "Delete"],
        ["Choisir", "Wählen", "Scegli", "Choose"],
        ["Continuer", "Weiter", "Continua", "Continue"],

        // MARK: Carte
        ["Chargement…", "Wird geladen…", "Caricamento…", "Loading…"],
        ["Rien à signaler", "Keine Meldungen", "Nessuna segnalazione", "All clear"],
        ["1 alerte", "1 Meldung", "1 avviso", "1 alert"],
        ["%ld alertes", "%ld Meldungen", "%ld avvisi", "%ld alerts"],
        ["Impossible de charger les perturbations. %@", "Störungen konnten nicht geladen werden. %@", "Impossibile caricare le perturbazioni. %@", "Could not load disruptions. %@"],
        ["Aucune perturbation ni aucun travail en cours dans cette catégorie.", "Keine Störungen oder Bauarbeiten in dieser Kategorie.", "Nessuna perturbazione o lavoro in corso in questa categoria.", "No disruptions or construction work in this category."],
        [" · non localisé", " · ohne Standort", " · non localizzato", " · no location"],
        ["Alertes", "Meldungen", "Avvisi", "Alerts"],
        ["Voir la source", "Quelle anzeigen", "Vedi la fonte", "View source"],
        ["Traduit automatiquement", "Automatisch übersetzt", "Tradotto automaticamente", "Automatically translated"],

        // MARK: Alertes du réseau
        ["Service interrompu", "Unterbruch", "Servizio interrotto", "Service interrupted"],
        ["Service restreint", "Eingeschränkter Betrieb", "Servizio limitato", "Limited service"],
        ["Information", "Information", "Informazione", "Information"],
        ["Perturbation", "Störung", "Perturbazione", "Disruption"],
        ["Travaux", "Bauarbeiten", "Lavori", "Construction work"],
        ["Travaux · %@", "Bauarbeiten · %@", "Lavori · %@", "Works · %@"],
        ["%@ · à venir", "%@ · geplant", "%@ · previsto", "%@ · upcoming"],
        ["En cours jusqu'à %@", "Andauernd bis %@", "In corso fino a %@", "Ongoing until %@"],
        ["Prochaine fois : %@ → %@", "Nächstes Mal: %@ → %@", "Prossima volta: %@ → %@", "Next: %@ → %@"],
        ["Depuis %@", "Seit %@", "Dal %@", "Since %@"],
        ["Jusqu'à %@", "Bis %@", "Fino a %@", "Until %@"],
        ["Période inconnue", "Zeitraum unbekannt", "Periodo sconosciuto", "Unknown period"],
        ["Travaux · interruption", "Bauarbeiten · Unterbruch", "Lavori · interruzione", "Works · interruption"],
        ["Interruption", "Unterbruch", "Interruzione", "Interruption"],
        ["en cours", "laufend", "in corso", "ongoing"],
        ["jusqu'à %@", "bis %@", "fino alle %@", "until %@"],
        ["Interrompu", "Unterbrochen", "Interrotto", "Interrupted"],
        ["Restreint", "Eingeschränkt", "Limitato", "Limited"],

        // MARK: Filtres
        ["Région lémanique", "Genferseeregion", "Regione del Lemano", "Lake Geneva region"],
        ["Espace Mittelland", "Espace Mittelland", "Espace Mittelland", "Espace Mittelland"],
        ["Suisse du Nord-Ouest", "Nordwestschweiz", "Svizzera nordoccidentale", "Northwestern Switzerland"],
        ["Zurich", "Zürich", "Zurigo", "Zurich"],
        ["Suisse orientale", "Ostschweiz", "Svizzera orientale", "Eastern Switzerland"],
        ["Suisse centrale", "Zentralschweiz", "Svizzera centrale", "Central Switzerland"],
        ["Tessin", "Tessin", "Ticino", "Ticino"],
        ["En cours", "Laufend", "In corso", "Ongoing"],
        ["Aujourd'hui", "Heute", "Oggi", "Today"],
        ["7 jours", "7 Tage", "7 giorni", "7 days"],
        ["Toute la Suisse", "Ganze Schweiz", "Tutta la Svizzera", "All of Switzerland"],
        ["%ld régions", "%ld Regionen", "%ld regioni", "%ld regions"],
        ["interruptions", "Unterbrüche", "interruzioni", "interruptions"],
        ["perturbations", "Störungen", "perturbazioni", "disruptions"],
        ["travaux en cours", "laufende Bauarbeiten", "lavori in corso", "ongoing works"],
        ["travaux du jour", "Bauarbeiten heute", "lavori di oggi", "today's works"],
        ["travaux (7 j)", "Bauarbeiten (7 T.)", "lavori (7 g)", "works (7 d)"],
        ["infos", "Infos", "info", "info"],
        ["aucune alerte", "keine Meldungen", "nessun avviso", "no alerts"],
        ["Filtres", "Filter", "Filtri", "Filters"],
        ["Perturbations", "Störungen", "Perturbazioni", "Disruptions"],
        ["Travaux à afficher", "Anzuzeigende Bauarbeiten", "Lavori da mostrare", "Works to show"],
        ["Types d'alertes", "Meldungsarten", "Tipi di avviso", "Alert types"],
        ["Les travaux sont momentanément indisponibles.", "Bauarbeiten sind momentan nicht verfügbar.", "I lavori non sono momentaneamente disponibili.", "Construction work is temporarily unavailable."],
        ["Seulement les interruptions", "Nur Unterbrüche", "Solo le interruzioni", "Interruptions only"],
        ["Informations diverses", "Weitere Informationen", "Informazioni varie", "Other information"],
        ["Gravité", "Schweregrad", "Gravità", "Severity"],
        ["Interruption : plus aucun train ne circule sur le tronçon (triangle rouge). Les informations diverses (accessibilité des gares, informations sur un train précis) apparaissent seulement dans la liste.",
         "Unterbruch: Auf dem Abschnitt verkehren keine Züge mehr (rotes Dreieck). Weitere Informationen (Zugänglichkeit von Bahnhöfen, Hinweise zu einzelnen Zügen) erscheinen nur in der Liste.",
         "Interruzione: sulla tratta non circola più alcun treno (triangolo rosso). Le informazioni varie (accessibilità delle stazioni, informazioni su un treno specifico) compaiono solo nell'elenco.",
         "Interruption: no trains run on the section (red triangle). Other information (station accessibility, notes about a specific train) only appears in the list."],
        ["Région", "Region", "Regione", "Region"],
        ["Tu peux choisir plusieurs régions. La carte zoome automatiquement dessus.", "Du kannst mehrere Regionen wählen. Die Karte zoomt automatisch darauf.", "Puoi scegliere più regioni. La mappa si ingrandisce automaticamente su di esse.", "You can pick several regions. The map zooms in on them automatically."],
        ["Réinitialiser les filtres", "Filter zurücksetzen", "Reimposta i filtri", "Reset filters"],
        ["Aucune alerte avec ces filtres", "Keine Meldungen mit diesen Filtern", "Nessun avviso con questi filtri", "No alerts with these filters"],
        ["1 alerte affichée", "1 Meldung angezeigt", "1 avviso mostrato", "1 alert shown"],
        ["%ld alertes affichées", "%ld Meldungen angezeigt", "%ld avvisi mostrati", "%ld alerts shown"],

        // MARK: Réglages
        ["Réglages", "Einstellungen", "Impostazioni", "Settings"],
        ["Perturbations et travaux sur le réseau ferroviaire suisse", "Störungen und Bauarbeiten im Schweizer Bahnnetz", "Perturbazioni e lavori sulla rete ferroviaria svizzera", "Disruptions and works on the Swiss rail network"],
        ["Notifications", "Mitteilungen", "Notifiche", "Notifications"],
        ["Autoriser les notifications", "Mitteilungen erlauben", "Consenti le notifiche", "Allow notifications"],
        ["Ouvrir les réglages de l'iPhone", "iPhone-Einstellungen öffnen", "Apri le impostazioni dell'iPhone", "Open iPhone Settings"],
        ["Red Alert t'avertit quand un de tes trajets (onglet « Mes trajets ») est en retard, supprimé, ou touché par une perturbation ou des travaux. Le seuil de retard se règle dans chaque trajet.",
         "Red Alert warnt dich, wenn eine deiner Strecken (Tab «Meine Strecken») verspätet, ausgefallen oder von einer Störung oder Bauarbeiten betroffen ist. Die Verspätungsschwelle stellst du pro Strecke ein.",
         "Red Alert ti avvisa quando uno dei tuoi tragitti (scheda «I miei tragitti») è in ritardo, soppresso o interessato da una perturbazione o da lavori. La soglia di ritardo si imposta per ogni tragitto.",
         "Red Alert warns you when one of your trips (“My trips” tab) is delayed, cancelled, or affected by a disruption or construction work. The delay threshold is set for each trip."],
        ["Perturbations et travaux", "Störungen und Bauarbeiten", "Perturbazioni e lavori", "Disruptions and works"],
        ["Retards et suppressions", "Verspätungen und Ausfälle", "Ritardi e soppressioni", "Delays and cancellations"],
        ["Recherche de gares", "Bahnhofsuche", "Ricerca stazioni", "Station search"],
        ["Gares et cantons", "Bahnhöfe und Kantone", "Stazioni e cantoni", "Stations and cantons"],
        ["Sources des données", "Datenquellen", "Fonti dei dati", "Data sources"],
        ["Données ouvertes des transports publics suisses. Red Alert n'est pas une application officielle des CFF : en cas de doute, vérifie sur sbb.ch ou l'app CFF.",
         "Offene Daten des Schweizer öffentlichen Verkehrs. Red Alert ist keine offizielle App der SBB: Prüfe im Zweifel auf sbb.ch oder in der SBB-App.",
         "Dati aperti dei trasporti pubblici svizzeri. Red Alert non è un'app ufficiale delle FFS: in caso di dubbio, verifica su sbb.ch o nell'app FFS.",
         "Open data from Swiss public transport. Red Alert is not an official SBB app: if in doubt, check sbb.ch or the SBB app."],
        ["Version", "Version", "Versione", "Version"],
        ["Activées", "Aktiviert", "Attivate", "On"],
        ["Désactivées", "Deaktiviert", "Disattivate", "Off"],
        ["Pas encore demandées", "Noch nicht angefragt", "Non ancora richieste", "Not requested yet"],
        ["Langue", "Sprache", "Lingua", "Language"],
        ["Aide", "Hilfe", "Aiuto", "Help"],
        ["Revoir le tutoriel", "Anleitung erneut ansehen", "Rivedi il tutorial", "Replay the tutorial"],
        ["Les messages officiels sont affichés dans cette langue.", "Offizielle Meldungen werden in dieser Sprache angezeigt.", "I messaggi ufficiali vengono mostrati in questa lingua.", "Official messages are shown in this language."],

        // MARK: Trajets
        ["Aucun trajet", "Keine Strecken", "Nessun tragitto", "No trips"],
        ["Ajoute un trajet que tu fais souvent. Red Alert te préviendra en cas de retard, de suppression, de perturbation ou de travaux sur ton parcours, même sur l’écran verrouillé.",
         "Füge eine Strecke hinzu, die du oft fährst. Red Alert warnt dich bei Verspätungen, Ausfällen, Störungen oder Bauarbeiten auf deiner Strecke – auch auf dem Sperrbildschirm.",
         "Aggiungi un tragitto che fai spesso. Red Alert ti avviserà in caso di ritardi, soppressioni, perturbazioni o lavori sul tuo percorso, anche sulla schermata di blocco.",
         "Add a trip you take often. Red Alert warns you about delays, cancellations, disruptions or construction work on your route, even on the lock screen."],
        ["Ajouter un trajet", "Strecke hinzufügen", "Aggiungi un tragitto", "Add a trip"],
        ["Aucun train", "Kein Zug", "Nessun treno", "No train"],
        ["Habituellement %@ · %@", "Normalerweise %@ · %@", "Di solito %@ · %@", "Usually %@ · %@"],
        ["Prochain départ", "Nächste Abfahrt", "Prossima partenza", "Next departure"],
        ["Voie %@", "Gleis %@", "Binario %@", "Platform %@"],
        ["+ %ld autre(s)", "+ %ld weitere", "+ %ld altri", "+ %ld more"],
        ["Trajet supprimé", "Strecke gelöscht", "Tragitto eliminato", "Trip deleted"],
        ["Perturbations et travaux sur le parcours", "Störungen und Bauarbeiten auf der Strecke", "Perturbazioni e lavori sul percorso", "Disruptions and works on the route"],
        ["Prochains départs", "Nächste Abfahrten", "Prossime partenze", "Next departures"],
        ["Mis à jour à %@", "Aktualisiert um %@", "Aggiornato alle %@", "Updated at %@"],
        ["Actualiser", "Aktualisieren", "Aggiorna", "Refresh"],
        ["Tester une notification (dans 5 s)", "Mitteilung testen (in 5 s)", "Prova una notifica (tra 5 s)", "Test a notification (in 5 s)"],
        ["Verrouille ton iPhone maintenant pour voir la notification.", "Sperre jetzt dein iPhone, um die Mitteilung zu sehen.", "Blocca ora l'iPhone per vedere la notifica.", "Lock your iPhone now to see the notification."],
        ["Modifier le trajet", "Strecke bearbeiten", "Modifica il tragitto", "Edit trip"],
        ["direction %@", "Richtung %@", "direzione %@", "towards %@"],
        ["· voie %@", "· Gleis %@", "· binario %@", "· platform %@"],
        ["· 1 changement", "· 1 Umstieg", "· 1 cambio", "· 1 change"],
        ["· %ld changements", "· %ld Umstiege", "· %ld cambi", "· %ld changes"],
        ["Trajet", "Strecke", "Tragitto", "Trip"],
        ["Gare de départ", "Abfahrtsbahnhof", "Stazione di partenza", "Departure station"],
        ["Départ", "Abfahrt", "Partenza", "From"],
        ["Gare d'arrivée", "Ankunftsbahnhof", "Stazione di arrivo", "Arrival station"],
        ["Arrivée", "Ankunft", "Arrivo", "To"],
        ["Inverser le sens", "Richtung tauschen", "Inverti il senso", "Swap direction"],
        ["Heure habituelle", "Übliche Zeit", "Orario abituale", "Usual time"],
        ["Départ vers", "Abfahrt um", "Partenza verso le", "Departure around"],
        ["Red Alert surveille le train le plus proche de cette heure, les jours choisis.", "Red Alert überwacht an den gewählten Tagen den Zug, der dieser Zeit am nächsten ist.", "Red Alert controlla il treno più vicino a quest'orario, nei giorni scelti.", "Red Alert watches the train closest to this time, on the chosen days."],
        ["Red Alert surveille simplement le prochain départ.", "Red Alert überwacht einfach die nächste Abfahrt.", "Red Alert controlla semplicemente la prossima partenza.", "Red Alert simply watches the next departure."],
        ["Alerte dès %ld min de retard", "Warnung ab %ld Min. Verspätung", "Avviso da %ld min di ritardo", "Alert from %ld min delay"],
        ["Une suppression déclenche toujours une alerte.", "Ein Ausfall löst immer eine Warnung aus.", "Una soppressione genera sempre un avviso.", "A cancellation always triggers an alert."],
        ["Nouveau trajet", "Neue Strecke", "Nuovo tragitto", "New trip"],
        ["Nom de la gare", "Name des Bahnhofs", "Nome della stazione", "Station name"],
        ["Recherche impossible : %@", "Suche nicht möglich: %@", "Ricerca impossibile: %@", "Search failed: %@"],
        ["Horaire indisponible (%@)", "Fahrplan nicht verfügbar (%@)", "Orario non disponibile (%@)", "Timetable unavailable (%@)"],
        ["Tous les jours", "Täglich", "Tutti i giorni", "Every day"],
        ["En semaine", "Werktags", "Nei giorni feriali", "Weekdays"],
        ["Le week-end", "Am Wochenende", "Nel fine settimana", "Weekends"],

        // MARK: État d'un train
        ["À l'heure", "Pünktlich", "In orario", "On time"],
        ["+%ld min", "+%ld Min.", "+%ld min", "+%ld min"],
        ["Supprimé", "Ausfall", "Soppresso", "Cancelled"],
        ["Pas d'info temps réel", "Keine Echtzeitdaten", "Nessun dato in tempo reale", "No real-time data"],

        // MARK: Erreurs
        ["Accès aux données refusé (code %ld).", "Zugriff auf die Daten verweigert (Code %ld).", "Accesso ai dati negato (codice %ld).", "Data access denied (code %ld)."],
        ["Trop de requêtes. Réessaie dans une minute.", "Zu viele Anfragen. Versuche es in einer Minute erneut.", "Troppe richieste. Riprova tra un minuto.", "Too many requests. Try again in a minute."],
        ["Le serveur a répondu avec le code %ld.", "Der Server antwortete mit Code %ld.", "Il server ha risposto con il codice %ld.", "The server responded with code %ld."],
        ["Adresse de requête invalide.", "Ungültige Anfrageadresse.", "Indirizzo di richiesta non valido.", "Invalid request address."],
        ["Réponse du serveur dans un format inattendu.", "Serverantwort in unerwartetem Format.", "Risposta del server in un formato inatteso.", "Unexpected server response format."],

        // MARK: Notifications
        ["%@ sur ton trajet %@", "%@ auf deiner Strecke %@", "%@ sul tuo tragitto %@", "%@ on your trip %@"],
        [" (en cours)", " (laufend)", " (in corso)", " (ongoing)"],
        ["Train supprimé : %@", "Zug fällt aus: %@", "Treno soppresso: %@", "Train cancelled: %@"],
        ["Le train de %@%@ est supprimé.", "Der Zug um %@%@ fällt aus.", "Il treno delle %@%@ è soppresso.", "The %@%@ train is cancelled."],
        [" Prochain départ : %@", " Nächste Abfahrt: %@", " Prossima partenza: %@", " Next departure: %@"],
        ["Retard de %ld min : %@", "%ld Min. Verspätung: %@", "Ritardo di %ld min: %@", "%ld min delay: %@"],
        ["Le train de %@%@ partira vers %@.", "Der Zug um %@%@ fährt ca. um %@ ab.", "Il treno delle %@%@ partirà verso le %@.", "The %@%@ train will leave around %@."],
        ["Test : %@", "Test: %@", "Prova: %@", "Test: %@"],
        ["Voici à quoi ressemblera une alerte de retard ou de suppression.", "So sieht eine Warnung bei Verspätung oder Ausfall aus.", "Ecco come apparirà un avviso di ritardo o soppressione.", "This is what a delay or cancellation alert will look like."],

        // MARK: Widget
        ["Mon trajet", "Meine Strecke", "Il mio tragitto", "My trip"],
        ["Retards, suppressions, perturbations et travaux sur ton prochain trajet.", "Verspätungen, Ausfälle, Störungen und Bauarbeiten auf deiner nächsten Strecke.", "Ritardi, soppressioni, perturbazioni e lavori sul tuo prossimo tragitto.", "Delays, cancellations, disruptions and works on your next trip."],
        ["Ajoute un trajet dans Red Alert", "Füge in Red Alert eine Strecke hinzu", "Aggiungi un tragitto in Red Alert", "Add a trip in Red Alert"],
        ["Horaire indisponible", "Fahrplan nicht verfügbar", "Orario non disponibile", "Timetable unavailable"],
        ["Alerte", "Meldung", "Avviso", "Alert"],
        [" · voie %@", " · Gleis %@", " · binario %@", " · platform %@"],
        ["Ensuite", "Danach", "Dopo", "Then"],
        ["prochain %@", "nächster %@", "prossimo %@", "next %@"],
        ["voie %@", "Gleis %@", "binario %@", "platform %@"],

        // MARK: Premier lancement et tutoriel
        ["Bienvenue sur Red Alert", "Willkommen bei Red Alert", "Benvenuto su Red Alert", "Welcome to Red Alert"],
        ["Red Alert surveille le réseau ferroviaire suisse et te prévient quand tes trajets sont touchés.", "Red Alert überwacht das Schweizer Bahnnetz und warnt dich, wenn deine Strecken betroffen sind.", "Red Alert sorveglia la rete ferroviaria svizzera e ti avvisa quando i tuoi tragitti sono interessati.", "Red Alert watches the Swiss rail network and warns you when your trips are affected."],
        ["La carte", "Die Karte", "La mappa", "The map"],
        ["Chaque triangle est une alerte : rouge = plus aucun train, jaune = service restreint. Le marteau indique des travaux. Touche un triangle pour zoomer et lire le détail.",
         "Jedes Dreieck ist eine Meldung: rot = kein Zugverkehr, gelb = eingeschränkter Betrieb. Der Hammer steht für Bauarbeiten. Tippe auf ein Dreieck, um hineinzuzoomen und die Details zu lesen.",
         "Ogni triangolo è un avviso: rosso = nessun treno, giallo = servizio limitato. Il martello indica lavori. Tocca un triangolo per ingrandire e leggere i dettagli.",
         "Each triangle is an alert: red = no trains, yellow = limited service. The hammer means construction work. Tap a triangle to zoom in and read the details."],
        ["Choisis ce que tu veux voir (perturbations, travaux) et ta région. Tes choix sont gardés.", "Wähle, was du sehen willst (Störungen, Bauarbeiten), und deine Region. Deine Auswahl bleibt gespeichert.", "Scegli cosa vuoi vedere (perturbazioni, lavori) e la tua regione. Le tue scelte vengono salvate.", "Choose what you want to see (disruptions, works) and your region. Your choices are saved."],
        ["Liste des alertes", "Meldungsliste", "Elenco degli avvisi", "Alert list"],
        ["Toutes les alertes affichées, sous forme de liste. Touche-en une pour la voir sur la carte.", "Alle angezeigten Meldungen als Liste. Tippe auf eine, um sie auf der Karte zu sehen.", "Tutti gli avvisi mostrati, sotto forma di elenco. Toccane uno per vederlo sulla mappa.", "All displayed alerts as a list. Tap one to see it on the map."],
        ["Langue, notifications et sources des données. Tu peux aussi relancer ce tutoriel d'ici.", "Sprache, Mitteilungen und Datenquellen. Hier kannst du diese Anleitung auch erneut starten.", "Lingua, notifiche e fonti dei dati. Da qui puoi anche rivedere questo tutorial.", "Language, notifications and data sources. You can also replay this tutorial from here."],
        ["Tes trajets", "Deine Strecken", "I tuoi tragitti", "Your trips"],
        ["Ajoute les trajets que tu fais souvent, avec ton heure habituelle. Red Alert surveille le train, les perturbations et les travaux sur tout le parcours.",
         "Füge die Strecken hinzu, die du oft fährst, mit deiner üblichen Zeit. Red Alert überwacht den Zug sowie Störungen und Bauarbeiten auf der ganzen Strecke.",
         "Aggiungi i tragitti che fai spesso, con il tuo orario abituale. Red Alert sorveglia il treno, le perturbazioni e i lavori su tutto il percorso.",
         "Add the trips you take often, with your usual time. Red Alert watches the train, disruptions and construction work along the whole route."],
        ["Sur l'écran verrouillé", "Auf dem Sperrbildschirm", "Sulla schermata di blocco", "On the lock screen"],
        ["Autorise les notifications pour être prévenu, et ajoute le widget « Mon trajet » à ton écran verrouillé pour voir l'état de ton train d'un coup d'œil.",
         "Erlaube Mitteilungen, um gewarnt zu werden, und füge das Widget «Meine Strecke» zu deinem Sperrbildschirm hinzu, um den Zustand deines Zuges auf einen Blick zu sehen.",
         "Consenti le notifiche per essere avvisato e aggiungi il widget «Il mio tragitto» alla schermata di blocco per vedere lo stato del tuo treno a colpo d'occhio.",
         "Allow notifications to be warned, and add the “My trip” widget to your lock screen to see your train's status at a glance."],
        ["Suivant", "Weiter", "Avanti", "Next"],
        ["Passer", "Überspringen", "Salta", "Skip"],
        ["Terminer", "Fertig", "Fine", "Done"],
        ["Commencer", "Los geht's", "Iniziamo", "Get started"],
        ["Plus tard", "Später", "Più tardi", "Later"],
        ["Activer les notifications", "Mitteilungen aktivieren", "Attiva le notifiche", "Turn on notifications"],
        ["Notifications activées", "Mitteilungen aktiviert", "Notifiche attivate", "Notifications on"],
        ["Ajouter mon premier trajet", "Erste Strecke hinzufügen", "Aggiungi il mio primo tragitto", "Add my first trip"],
        ["Touche la zone éclairée pour continuer", "Tippe auf den hervorgehobenen Bereich, um fortzufahren", "Tocca l'area evidenziata per continuare", "Tap the highlighted area to continue"],
    ]
}
