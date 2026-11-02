import SwiftUI

/// Formulaire de création / modification d'un trajet.
struct TripEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let original: Trip?
    private let onSave: (Trip) -> Void
    /// Titre imposé (ex. « Trajet retour ») ; sinon « Nouveau trajet » ou « Modifier le trajet ».
    private let customTitle: String?

    @State private var from: Station?
    @State private var to: Station?
    @State private var hasUsualTime: Bool
    @State private var time: Date
    @State private var weekdays: Set<Int>
    @State private var notify: Bool
    @State private var threshold: Int

    /// `trip` : trajet à modifier, ou modèle prérempli (ex. trajet retour) quand `title` est donné.
    init(trip: Trip? = nil, title: String? = nil, onSave: @escaping (Trip) -> Void) {
        self.original = trip
        self.onSave = onSave
        self.customTitle = title
        _from = State(initialValue: trip?.from)
        _to = State(initialValue: trip?.to)
        _hasUsualTime = State(initialValue: trip?.hasUsualTime ?? true)
        let hour = trip?.usualHour ?? 7
        let minute = trip?.usualMinute ?? 30
        let initialTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        _time = State(initialValue: initialTime)
        _weekdays = State(initialValue: trip?.weekdays ?? [2, 3, 4, 5, 6])
        _notify = State(initialValue: trip?.notificationsEnabled ?? true)
        _threshold = State(initialValue: trip?.delayThreshold ?? 3)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(t("Trajet")) {
                    NavigationLink {
                        StationSearchView(title: t("Gare de départ")) { from = $0 }
                    } label: {
                        StationRow(label: t("Départ"), station: from, icon: "circle")
                    }
                    NavigationLink {
                        StationSearchView(title: t("Gare d'arrivée")) { to = $0 }
                    } label: {
                        StationRow(label: t("Arrivée"), station: to, icon: "mappin.circle.fill")
                    }
                    if from != nil || to != nil {
                        Button {
                            let previousFrom = from
                            from = to
                            to = previousFrom
                        } label: {
                            Label(t("Inverser le sens"), systemImage: "arrow.up.arrow.down")
                        }
                    }
                }

                Section {
                    Toggle(t("Heure habituelle"), isOn: $hasUsualTime.animation())
                    if hasUsualTime {
                        DatePicker(t("Départ vers"), selection: $time, displayedComponents: .hourAndMinute)
                            .environment(\.locale, AppLanguage.current.locale)
                        WeekdayPicker(selection: $weekdays)
                            .padding(.vertical, 4)
                    }
                } footer: {
                    Text(hasUsualTime
                         ? t("Red Alert surveille le train le plus proche de cette heure, les jours choisis.")
                         : t("Red Alert surveille simplement le prochain départ."))
                }

                Section {
                    Toggle(t("Notifications"), isOn: $notify)
                    Stepper(t("Alerte dès %ld min de retard", threshold), value: $threshold, in: 1...30)
                } header: {
                    Text(t("Alertes"))
                } footer: {
                    Text(t("Une suppression déclenche toujours une alerte."))
                }
            }
            .navigationTitle(customTitle ?? (original == nil ? t("Nouveau trajet") : t("Modifier le trajet")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Enregistrer")) { save() }
                        .disabled(from == nil || to == nil || from == to)
                }
            }
        }
    }

    private func save() {
        guard let from, let to else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        var trip = original ?? Trip(from: from, to: to)
        trip.from = from
        trip.to = to
        trip.usualHour = hasUsualTime ? components.hour : nil
        trip.usualMinute = hasUsualTime ? components.minute : nil
        trip.weekdays = weekdays
        trip.notificationsEnabled = notify
        trip.delayThreshold = threshold
        onSave(trip)
        dismiss()
    }
}

// MARK: - Ligne "Départ : Montreux"

private struct StationRow: View {
    let label: String
    let station: Station?
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(Theme.accent)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(station?.name ?? t("Choisir"))
                .foregroundStyle(station == nil ? Color.secondary : Color.primary)
        }
    }
}

// MARK: - Choix des jours

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    /// Ordre lundi → dimanche, avec les numéros de `Calendar` (1 = dimanche).
    private struct Day: Identifiable {
        let id: Int
        let letter: String
    }

    /// Nom complet du jour pour VoiceOver ("lundi", "Montag"...).
    private func fullName(_ weekday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLanguage.current.locale
        return calendar.standaloneWeekdaySymbols[weekday - 1]
    }

    /// Lundi → dimanche, avec l'initiale du jour dans la langue choisie ("L", "Mo", "L", "M"...).
    private var days: [Day] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLanguage.current.locale
        let letters = calendar.veryShortStandaloneWeekdaySymbols // index 0 = dimanche
        return [2, 3, 4, 5, 6, 7, 1].map { Day(id: $0, letter: letters[$0 - 1]) }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                let isOn = selection.contains(day.id)
                Button {
                    if isOn { selection.remove(day.id) } else { selection.insert(day.id) }
                } label: {
                    Text(day.letter)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? Theme.accent : Color.white.opacity(0.08), in: Circle())
                        .foregroundStyle(isOn ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fullName(day.id))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - Recherche de gare

struct StationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var onSelect: (Station) -> Void

    @State private var query = ""
    @State private var results: [Station] = []
    @State private var isSearching = false
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Text(errorText).foregroundStyle(Theme.redText).font(.footnote)
            }
            // Champ vide : on propose les dernières gares choisies (moins de frappe).
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                let recents = RecentStations.load()
                if !recents.isEmpty {
                    Section(t("Gares récentes")) {
                        ForEach(recents) { station in row(station, icon: "clock.arrow.circlepath") }
                    }
                }
            }
            ForEach(results) { station in row(station, icon: "tram.fill") }
        }
        .overlay {
            if isSearching && results.isEmpty { ProgressView() }
        }
        .navigationTitle(title)
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: t("Nom de la gare"))
        .autocorrectionDisabled()
        // Recherche déclenchée 0,3 s après la dernière frappe.
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
                results = []
                return
            }
            isSearching = true
            defer { isSearching = false }
            do {
                results = try await StationService.shared.search(query)
                errorText = nil
            } catch {
                if !Task.isCancelled { errorText = t("Recherche impossible : %@", error.localizedDescription) }
            }
        }
    }
}

private extension StationSearchView {
    func row(_ station: Station, icon: String) -> some View {
        Button {
            RecentStations.add(station)
            onSelect(station)
            dismiss()
        } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(station.name)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Les 6 dernières gares choisies, proposées quand le champ de recherche est vide.
enum RecentStations {
    private static let key = "recentStations"

    static func load() -> [Station] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stations = try? JSONDecoder().decode([Station].self, from: data)
        else { return [] }
        return stations
    }

    static func add(_ station: Station) {
        var stations = load().filter { $0.id != station.id }
        stations.insert(station, at: 0)
        if let data = try? JSONEncoder().encode(Array(stations.prefix(6))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
