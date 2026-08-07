import Foundation
import Observation

/// Ile dni ciągnąć przy danym wywołaniu — i czy w ogóle.
///
/// Wydzielone z modelu, bo to jedyna decyzja w tym pliku, która ma warianty.
/// Reszta jest sekwencją wywołań, której bez HealthKit i tak nie da się odpalić
/// w teście.
enum HealthSyncPlan: Equatable {
    case sync(days: Int)
    case skip

    /// Pierwsze uruchomienie ciąga całą dostępną historię, nie miesiąc.
    ///
    /// HealthKit trzyma dane, które Garmin zapisywał tam od lat — sen, tętno
    /// spoczynkowe, kroki. Przy oknie 30 dni cała ta historia zostawała poza
    /// zasięgiem na zawsze, bo kolejne synchronizacje biorą już tylko ostatnie
    /// dni. Puste doby i tak odpadają, więc żądanie głębsze niż realne dane
    /// nic nie kosztuje.
    static let backfillDays = 1095

    /// Kolejne tylko ostatnie dni. Trzy, a nie jeden: dane z Watcha dochodzą
    /// z opóźnieniem, a sen z ostatniej nocy potrafi się doprecyzować jeszcze
    /// następnego dnia.
    static let incrementalDays = 3

    /// Auto-sync po powrocie z tła nie częściej niż raz na godzinę — HealthKit
    /// nie zmienia się co minutę, a każdy odczyt to kilkanaście zapytań.
    static let autoSyncInterval: TimeInterval = 3600

    /// Odcinki snu wysyłamy tylko dla świeżych dni.
    ///
    /// Służą wyłącznie do liczenia SRI z okna ośmiu dób, a trzy lata historii
    /// to około 22 tysiące obiektów w JSON-ie — ciężar bez wartości.
    static let sleepSegmentsWithinDays = 30

    /// Ile dni mieści jeden POST. Musi zgadzać się z `MAX_SYNC_DAYS` na serwerze —
    /// większa paczka wraca błędem 400, nie obcięciem.
    static let daysPerRequest = 90

    /// `automatic` odróżnia powrót apki na wierzch od kliknięcia w Opcjach.
    /// Odstęp obowiązuje wyłącznie automat — jeśli użytkownik prosi, to
    /// synchronizujemy, choćby minutę po poprzednim razie.
    static func next(
        lastSyncedAt: Date?,
        now: Date = Date(),
        automatic: Bool
    ) -> HealthSyncPlan {
        guard let lastSyncedAt else { return .sync(days: backfillDays) }
        if automatic, now.timeIntervalSince(lastSyncedAt) < autoSyncInterval { return .skip }
        return .sync(days: incrementalDays)
    }
}

/// Spina odczyt z HealthKit z wysyłką do backendu i trzyma stan widoczny
/// w Opcjach. Jedna instancja na aplikację, bo synchronizację odpalają dwa
/// miejsca: przycisk w ustawieniach i powrót apki na wierzch.
@MainActor
@Observable
final class HealthSyncModel {
    static let shared = HealthSyncModel()

    enum State: Equatable {
        case idle
        case syncing
        case done(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var isConnected = false
    private(set) var lastSyncedAt: Date?
    private(set) var sources: SourceSummary?

    /// Postęp głębokiego backfillu. Trzy lata to kilkanaście żądań i kilkadziesiąt
    /// sekund — bez tego ekran stoi na samym spinnerze i wygląda na zawieszony.
    private(set) var progress: String?

    /// Co pisze do Zdrowia. Interesuje nas głównie moment, w którym pojawia się
    /// drugie urządzenie — wtedy suma kroków może się zdublować, a średnia
    /// tętna zmieszać dwie różne metody pomiaru.
    struct SourceSummary: Sendable, Equatable {
        let names: [String]
        /// Metryki opisane przez więcej niż jedno źródło.
        let conflicting: [String]

        var hasConflict: Bool { !conflicting.isEmpty }
    }

    private static let lastSyncKey = "health.lastSyncedAt"

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        lastSyncedAt = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    // MARK: - Stan dla widoku

    var isSyncing: Bool { state == .syncing }

    var statusMessage: String? {
        switch state {
        case .idle, .syncing: nil
        case .done(let text), .failed(let text): text
        }
    }

    var statusIsError: Bool {
        if case .failed = state { return true }
        return false
    }

    var lastSyncedLabel: String {
        guard let lastSyncedAt else { return "—" }
        return Self.relativeFormatter.localizedString(for: lastSyncedAt, relativeTo: Date())
    }

    // MARK: - Akcje

    func refreshConnection() async {
        isConnected = await HealthKitManager.shared.hasRequestedAccess()
        await loadSources()
    }

    private struct SourceRow: Decodable {
        let metricSources: [String: [String]]?
        enum CodingKeys: String, CodingKey { case metricSources = "metric_sources" }
    }

    private func loadSources() async {
        let rows: [SourceRow]? = try? await AppSupabase.client
            .from("health_metrics")
            .select("metric_sources")
            .order("metric_date", ascending: false)
            .limit(7)
            .execute()
            .value

        sources = Self.summarize((rows ?? []).compactMap(\.metricSources))
    }

    /// Internal, nie private — to jedyne miejsce, gdzie z surowych map robi się
    /// wniosek „dwa urządzenia piszą to samo", i chcemy je mieć pod testami.
    static func summarize(_ rows: [[String: [String]]]) -> SourceSummary? {
        var all: Set<String> = []
        var perMetric: [String: Set<String>] = [:]

        for row in rows {
            for (metric, names) in row {
                all.formUnion(names)
                perMetric[metric, default: []].formUnion(names)
            }
        }
        guard !all.isEmpty else { return nil }

        return SourceSummary(
            names: all.sorted(),
            conflicting: perMetric.filter { $0.value.count > 1 }.keys.sorted()
        )
    }

    /// Pokazuje systemowe okno zgody. Wołane tylko z przycisku — automat nigdy
    /// nie zaczepia użytkownika oknem uprawnień.
    func connect() async {
        guard HealthKitManager.shared.isAvailable else {
            state = .failed(HealthKitError.unavailable.localizedDescription)
            return
        }

        do {
            try await HealthKitManager.shared.requestAuthorization()
            isConnected = true
            await sync(days: HealthSyncPlan.backfillDays)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func syncNow() async {
        guard case .sync(let days) = HealthSyncPlan.next(lastSyncedAt: lastSyncedAt, automatic: false)
        else { return }
        await sync(days: days)
    }

    /// Wejście apki na wierzch. Cicho odpuszcza, gdy nie ma zgody albo gdy
    /// poprzedni sync był niedawno — użytkownik nie ma tego zauważyć.
    func syncIfStale() async {
        guard !isSyncing else { return }

        await refreshConnection()
        guard isConnected else { return }

        guard case .sync(let days) = HealthSyncPlan.next(lastSyncedAt: lastSyncedAt, automatic: true)
        else { return }
        await sync(days: days)
    }

    // MARK: - Synchronizacja

    private func sync(days: Int) async {
        guard !isSyncing else { return }
        state = .syncing
        progress = nil
        defer { progress = nil }

        do {
            let metrics = try await HealthKitManager.shared.readMetrics(
                days: days,
                segmentsWithinDays: HealthSyncPlan.sleepSegmentsWithinDays
            )
            guard !metrics.isEmpty else {
                state = .done("Brak danych w Apple Health z ostatnich \(days) dni")
                return
            }

            // Paczkowanie, bo serwer przyjmuje najwyżej 90 dni na żądanie,
            // a backfill potrafi przynieść trzy lata naraz.
            let batches = metrics.chunked(into: HealthSyncPlan.daysPerRequest)
            var saved = 0
            var activity = 0
            var weight = 0

            for (index, batch) in batches.enumerated() {
                if batches.count > 1 { progress = "Wysyłam \(index + 1)/\(batches.count)…" }
                let result = try await LongevityAPI.syncHealth(days: batch)
                saved += result.saved
                activity += result.activitySynced
                weight += result.weightSynced
            }

            markSynced()
            // Aktywność z Watcha wchodzi do activity_logs, więc score trzeba przeliczyć —
            // ten sam krok co po zapisie check-inu czy posiłku.
            await LongevityAPI.refreshScore()
            await loadSources()

            state = .done(Self.summary(saved: saved, activity: activity, weight: weight))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Wołane przy wylogowaniu. Znacznik ostatniego syncu jest per urządzenie,
    /// nie per konto — bez wyczyszczenia następny użytkownik dostałby sync
    /// przyrostowy z trzech dni zamiast pełnego backfillu.
    func reset() {
        state = .idle
        lastSyncedAt = nil
        UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
    }

    private func markSynced() {
        let now = Date()
        lastSyncedAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastSyncKey)
    }

    private static func summary(saved: Int, activity: Int, weight: Int) -> String {
        var parts = ["Zapisano \(saved) \(dayWord(saved))"]
        if activity > 0 { parts.append("aktywność \(activity)") }
        if weight > 0 { parts.append("waga \(weight)") }
        return parts.joined(separator: " · ")
    }

    private static func dayWord(_ count: Int) -> String { count == 1 ? "dzień" : "dni" }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.unitsStyle = .full
        return f
    }()
}
