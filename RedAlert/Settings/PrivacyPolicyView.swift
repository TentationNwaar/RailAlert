import SwiftUI

/// Page « Politique de confidentialité », affichée dans la langue choisie.
/// Les informations personnelles (nom, contact, hébergeur) viennent de LegalInfo.swift.
struct PrivacyPolicyView: View {
    @Environment(\.openURL) private var openURL

    private var policy: PrivacyPolicyText.Policy { PrivacyPolicyText.policy(for: AppLanguage.current) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(PrivacyPolicyText.fill(policy.updated))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(PrivacyPolicyText.fill(policy.intro))
                    .font(.subheadline)

                ForEach(policy.sections.indices, id: \.self) { index in
                    let section = policy.sections[index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.lines.indices, id: \.self) { lineIndex in
                            line(section.lines[lineIndex])
                        }
                    }
                }

                if let url = URL(string: LegalInfo.privacyPolicyURL), !LegalInfo.privacyPolicyURL.isEmpty {
                    Button {
                        openURL(url)
                    } label: {
                        Label(t("Voir la version en ligne"), systemImage: "safari")
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(t("Confidentialité"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Une ligne commençant par « - » est affichée comme un point de liste. Le **gras** est pris en charge.
    @ViewBuilder
    private func line(_ raw: String) -> some View {
        let filled = PrivacyPolicyText.fill(raw)
        if filled.hasPrefix("- ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Theme.red)
                Text(markdown(String(filled.dropFirst(2))))
            }
            .font(.subheadline)
        } else {
            Text(markdown(filled))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

// MARK: - Texte de la politique (4 langues)

enum PrivacyPolicyText {
    struct Section {
        let title: String
        let lines: [String]
    }

    struct Policy {
        let updated: String
        let intro: String
        let sections: [Section]
    }

    /// Remplace {name}, {address}, {email}, {host} et {date} par les valeurs de LegalInfo.
    static func fill(_ text: String) -> String {
        func value(_ field: String) -> String {
            let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? t("[à compléter]") : trimmed
        }
        return text
            .replacingOccurrences(of: "{name}", with: value(LegalInfo.ownerName))
            .replacingOccurrences(of: "{address}", with: value(LegalInfo.ownerAddress))
            .replacingOccurrences(of: "{email}", with: value(LegalInfo.contactEmail))
            .replacingOccurrences(of: "{host}", with: value(LegalInfo.serverHost))
            .replacingOccurrences(of: "{date}", with: value(LegalInfo.lastUpdated))
    }

    static func policy(for language: AppLanguage) -> Policy {
        switch language {
        case .fr: return french
        case .de: return german
        case .it: return italian
        case .en: return english
        }
    }

    // MARK: Français

    static let french = Policy(
        updated: "Dernière mise à jour : {date}",
        intro: "Red Alert affiche les perturbations et travaux du réseau ferroviaire suisse et t'avertit quand tes trajets habituels sont touchés. Cette page explique quelles données sont traitées, pourquoi et où. Elle suit la loi fédérale sur la protection des données (nLPD).",
        sections: [
            Section(title: "Responsable", lines: [
                "{name}, {address}, Suisse",
                "Contact : {email}"
            ]),
            Section(title: "Données qui restent sur ton iPhone", lines: [
                "Ces données sont enregistrées **uniquement sur ton appareil** :",
                "- tes trajets (gare de départ, gare d'arrivée, heure habituelle, jours, seuil de retard) ;",
                "- tes réglages (langue, filtres de la carte, notifications) ;",
                "- l'historique de ponctualité de tes trajets (60 jours au maximum).",
                "Elles sont effacées quand tu supprimes un trajet ou l'application."
            ]),
            Section(title: "Données envoyées au serveur de notifications", lines: [
                "Pour t'envoyer des alertes même quand l'application est fermée, Red Alert transmet à son serveur :",
                "- le **jeton de notification** de ton iPhone (un identifiant technique fourni par Apple, qui ne permet pas de t'identifier) ;",
                "- ta **langue** ;",
                "- tes **trajets** (gares, heure habituelle, jours, seuil de retard) ;",
                "- si tu suis un trajet en direct, le jeton de cette **Live Activity**.",
                "Aucun nom, aucune adresse e-mail, aucun numéro de téléphone et aucune position GPS ne sont collectés. Ces données servent uniquement à envoyer tes alertes. Elles sont supprimées quand tu désinstalles l'application ou sur simple demande.",
                "Hébergement du serveur : {host}."
            ]),
            Section(title: "Services tiers", lines: [
                "Pour afficher les informations, l'application interroge directement :",
                "- **opentransportdata.swiss** : perturbations, travaux et horaires en temps réel ;",
                "- **data.sbb.ch** : liste officielle des gares ;",
                "- **transport.opendata.ch** : recherche de gares ;",
                "- **Apple Push Notification service** : acheminement des notifications.",
                "Ces services reçoivent l'adresse IP de ton appareil et le contenu de la requête, comme pour toute connexion Internet. Red Alert n'utilise aucun outil publicitaire ni de mesure d'audience, et ne fait aucun suivi (tracking)."
            ]),
            Section(title: "Achats", lines: [
                "Les achats (abonnement mensuel et achat à vie) sont traités entièrement par Apple. Red Alert ne reçoit ni ton nom ni tes données de paiement : l'application sait seulement si Red Alert+ est actif."
            ]),
            Section(title: "Traduction", lines: [
                "Si un texte officiel n'existe pas dans ta langue, il est traduit **sur ton iPhone** par le traducteur intégré d'Apple, sans envoi à un service externe."
            ]),
            Section(title: "Tes droits", lines: [
                "Tu peux demander à tout moment l'accès à tes données, leur rectification ou leur suppression en écrivant à {email}. Tu peux aussi supprimer toutes les données en désinstallant l'application."
            ]),
            Section(title: "Avertissement", lines: [
                "Red Alert n'est pas une application officielle des CFF ni d'une entreprise de transport. Les informations proviennent de données ouvertes et peuvent être incomplètes ou en retard : en cas de doute, vérifie sur sbb.ch ou dans l'application CFF."
            ])
        ]
    )

    // MARK: Deutsch

    static let german = Policy(
        updated: "Letzte Aktualisierung: {date}",
        intro: "Red Alert zeigt Störungen und Bauarbeiten im Schweizer Bahnnetz an und warnt dich, wenn deine üblichen Strecken betroffen sind. Diese Seite erklärt, welche Daten wo und wozu bearbeitet werden. Sie folgt dem Bundesgesetz über den Datenschutz (DSG).",
        sections: [
            Section(title: "Verantwortlich", lines: [
                "{name}, {address}, Schweiz",
                "Kontakt: {email}"
            ]),
            Section(title: "Daten, die auf deinem iPhone bleiben", lines: [
                "Diese Daten werden **nur auf deinem Gerät** gespeichert:",
                "- deine Strecken (Abfahrts- und Ankunftsbahnhof, übliche Uhrzeit, Tage, Verspätungsschwelle);",
                "- deine Einstellungen (Sprache, Kartenfilter, Mitteilungen);",
                "- der Pünktlichkeitsverlauf deiner Strecken (höchstens 60 Tage).",
                "Sie werden gelöscht, wenn du eine Strecke oder die App löschst."
            ]),
            Section(title: "An den Mitteilungsserver gesendete Daten", lines: [
                "Damit du auch bei geschlossener App gewarnt wirst, sendet Red Alert an seinen Server:",
                "- das **Mitteilungs-Token** deines iPhones (eine technische Kennung von Apple, die dich nicht identifiziert);",
                "- deine **Sprache**;",
                "- deine **Strecken** (Bahnhöfe, übliche Uhrzeit, Tage, Verspätungsschwelle);",
                "- wenn du eine Strecke live verfolgst, das Token dieser **Live-Aktivität**.",
                "Es werden weder Name, E-Mail-Adresse, Telefonnummer noch GPS-Standort erhoben. Diese Daten dienen nur dem Versand deiner Warnungen. Sie werden gelöscht, wenn du die App deinstallierst, oder auf Anfrage.",
                "Hosting des Servers: {host}."
            ]),
            Section(title: "Dienste Dritter", lines: [
                "Um Informationen anzuzeigen, fragt die App direkt ab:",
                "- **opentransportdata.swiss**: Störungen, Bauarbeiten und Echtzeit-Fahrpläne;",
                "- **data.sbb.ch**: offizielle Liste der Bahnhöfe;",
                "- **transport.opendata.ch**: Bahnhofsuche;",
                "- **Apple Push Notification service**: Zustellung der Mitteilungen.",
                "Diese Dienste erhalten die IP-Adresse deines Geräts und den Inhalt der Anfrage, wie bei jeder Internetverbindung. Red Alert verwendet keine Werbe- oder Analysetools und kein Tracking."
            ]),
            Section(title: "Käufe", lines: [
                "Käufe (Monatsabo und lebenslanger Zugang) werden vollständig von Apple abgewickelt. Red Alert erhält weder deinen Namen noch deine Zahlungsdaten: Die App weiss nur, ob Red Alert+ aktiv ist."
            ]),
            Section(title: "Übersetzung", lines: [
                "Wenn ein offizieller Text nicht in deiner Sprache vorliegt, wird er **auf deinem iPhone** mit der integrierten Übersetzung von Apple übersetzt, ohne Übermittlung an einen externen Dienst."
            ]),
            Section(title: "Deine Rechte", lines: [
                "Du kannst jederzeit Auskunft, Berichtigung oder Löschung deiner Daten verlangen, indem du an {email} schreibst. Du kannst auch alle Daten löschen, indem du die App deinstallierst."
            ]),
            Section(title: "Hinweis", lines: [
                "Red Alert ist keine offizielle App der SBB oder eines Transportunternehmens. Die Informationen stammen aus offenen Daten und können unvollständig oder verspätet sein: Prüfe im Zweifel auf sbb.ch oder in der SBB-App."
            ])
        ]
    )

    // MARK: Italiano

    static let italian = Policy(
        updated: "Ultimo aggiornamento: {date}",
        intro: "Red Alert mostra perturbazioni e lavori sulla rete ferroviaria svizzera e ti avvisa quando i tuoi tragitti abituali sono interessati. Questa pagina spiega quali dati sono trattati, perché e dove. Segue la legge federale sulla protezione dei dati (LPD).",
        sections: [
            Section(title: "Responsabile", lines: [
                "{name}, {address}, Svizzera",
                "Contatto: {email}"
            ]),
            Section(title: "Dati che restano sul tuo iPhone", lines: [
                "Questi dati sono salvati **solo sul tuo dispositivo**:",
                "- i tuoi tragitti (stazione di partenza e di arrivo, ora abituale, giorni, soglia di ritardo);",
                "- le tue impostazioni (lingua, filtri della mappa, notifiche);",
                "- lo storico di puntualità dei tuoi tragitti (al massimo 60 giorni).",
                "Vengono cancellati quando elimini un tragitto o l'app."
            ]),
            Section(title: "Dati inviati al server delle notifiche", lines: [
                "Per avvisarti anche quando l'app è chiusa, Red Alert invia al suo server:",
                "- il **token di notifica** del tuo iPhone (un identificativo tecnico fornito da Apple che non permette di identificarti);",
                "- la tua **lingua**;",
                "- i tuoi **tragitti** (stazioni, ora abituale, giorni, soglia di ritardo);",
                "- se segui un tragitto in diretta, il token di questa **Live Activity**.",
                "Non vengono raccolti nome, indirizzo e-mail, numero di telefono né posizione GPS. Questi dati servono solo a inviare i tuoi avvisi. Vengono cancellati quando disinstalli l'app o su semplice richiesta.",
                "Hosting del server: {host}."
            ]),
            Section(title: "Servizi di terzi", lines: [
                "Per mostrare le informazioni, l'app interroga direttamente:",
                "- **opentransportdata.swiss**: perturbazioni, lavori e orari in tempo reale;",
                "- **data.sbb.ch**: elenco ufficiale delle stazioni;",
                "- **transport.opendata.ch**: ricerca delle stazioni;",
                "- **Apple Push Notification service**: invio delle notifiche.",
                "Questi servizi ricevono l'indirizzo IP del tuo dispositivo e il contenuto della richiesta, come per qualsiasi connessione Internet. Red Alert non usa strumenti pubblicitari né di analisi e non effettua tracciamento."
            ]),
            Section(title: "Acquisti", lines: [
                "Gli acquisti (abbonamento mensile e acquisto a vita) sono gestiti interamente da Apple. Red Alert non riceve né il tuo nome né i tuoi dati di pagamento: l'app sa solo se Red Alert+ è attivo."
            ]),
            Section(title: "Traduzione", lines: [
                "Se un testo ufficiale non esiste nella tua lingua, viene tradotto **sul tuo iPhone** dal traduttore integrato di Apple, senza invio a un servizio esterno."
            ]),
            Section(title: "I tuoi diritti", lines: [
                "Puoi chiedere in qualsiasi momento l'accesso, la rettifica o la cancellazione dei tuoi dati scrivendo a {email}. Puoi anche cancellare tutti i dati disinstallando l'app."
            ]),
            Section(title: "Avvertenza", lines: [
                "Red Alert non è un'app ufficiale delle FFS né di un'impresa di trasporto. Le informazioni provengono da dati aperti e possono essere incomplete o in ritardo: in caso di dubbio, verifica su sbb.ch o nell'app FFS."
            ])
        ]
    )

    // MARK: English

    static let english = Policy(
        updated: "Last updated: {date}",
        intro: "Red Alert shows disruptions and construction work on the Swiss rail network and warns you when your usual trips are affected. This page explains which data is processed, why and where. It follows the Swiss Federal Act on Data Protection (FADP).",
        sections: [
            Section(title: "Controller", lines: [
                "{name}, {address}, Switzerland",
                "Contact: {email}"
            ]),
            Section(title: "Data that stays on your iPhone", lines: [
                "This data is stored **only on your device**:",
                "- your trips (departure and arrival stations, usual time, days, delay threshold);",
                "- your settings (language, map filters, notifications);",
                "- the punctuality history of your trips (60 days at most).",
                "It is deleted when you delete a trip or the app."
            ]),
            Section(title: "Data sent to the notification server", lines: [
                "To alert you even when the app is closed, Red Alert sends its server:",
                "- your iPhone's **notification token** (a technical identifier provided by Apple that does not identify you);",
                "- your **language**;",
                "- your **trips** (stations, usual time, days, delay threshold);",
                "- if you follow a trip live, the token of that **Live Activity**.",
                "No name, e-mail address, phone number or GPS location is collected. This data is used only to send your alerts. It is deleted when you uninstall the app or on request.",
                "Server hosting: {host}."
            ]),
            Section(title: "Third-party services", lines: [
                "To display information, the app directly queries:",
                "- **opentransportdata.swiss**: disruptions, construction work and real-time timetables;",
                "- **data.sbb.ch**: official list of stations;",
                "- **transport.opendata.ch**: station search;",
                "- **Apple Push Notification service**: delivery of notifications.",
                "These services receive your device's IP address and the content of the request, as with any Internet connection. Red Alert uses no advertising or analytics tools and does no tracking."
            ]),
            Section(title: "Purchases", lines: [
                "Purchases (monthly subscription and lifetime access) are handled entirely by Apple. Red Alert receives neither your name nor your payment details: the app only knows whether Red Alert+ is active."
            ]),
            Section(title: "Translation", lines: [
                "If an official text is not available in your language, it is translated **on your iPhone** by Apple's built-in translator, without sending it to an external service."
            ]),
            Section(title: "Your rights", lines: [
                "You can request access to, correction or deletion of your data at any time by writing to {email}. You can also delete all data by uninstalling the app."
            ]),
            Section(title: "Disclaimer", lines: [
                "Red Alert is not an official app of SBB or any transport company. Information comes from open data and may be incomplete or delayed: if in doubt, check sbb.ch or the SBB app."
            ])
        ]
    )
}
