import Foundation
import Observation

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

    /// Pierwsze uruchomienie ciąga miesiąc wstecz, kolejne tylko ostatnie dni.
    /// Trzy, a nie jeden: dane z Watcha dochodzą z opóźnieniem, a sen z ostatniej
    /// nocy potrafi się doprecyzować jeszcze następnego dnia.
    private static let backfillDays = 30
    private static let incrementalDays = 3

    /// Auto-sync po powrocie z tła nie częściej niż raz na godzinę — HealthKit
    /// nie zmienia się co minutę, a każdy odczyt to kilkanaście zapytań.
    private static let autoSyncInterval: TimeInterval = 3600

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
            await sync(days: Self.backfillDays)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func syncNow() async {
        await sync(days: lastSyncedAt == nil ? Self.backfillDays : Self.incrementalDays)
    }

    /// Wejście apki na wierzch. Cicho odpuszcza, gdy nie ma zgody albo gdy
    /// poprzedni sync był niedawno — użytkownik nie ma tego zauważyć.
    func syncIfStale() async {
        guard !isSyncing else { return }

        await refreshConnection()
        guard isConnected else { return }

        if let lastSyncedAt, Date().timeIntervalSince(lastSyncedAt) < Self.autoSyncInterval {
            return
        }
        await syncNow()
    }

    // MARK: - Synchronizacja

    private func sync(days: Int) async {
        guard !isSyncing else { return }
        state = .syncing

        do {
            let metrics = try await HealthKitManager.shared.readMetrics(days: days)
            guard !metrics.isEmpty else {
                state = .done("Brak danych w Apple Health z ostatnich \(days) dni")
                return
            }

            let result = try await LongevityAPI.syncHealth(days: metrics)
            markSynced()
            // Aktywność z Watcha wchodzi do activity_logs, więc score trzeba przeliczyć —
            // ten sam krok co po zapisie check-inu czy posiłku.
            await LongevityAPI.refreshScore()

            state = .done(Self.summary(result))
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

    private static func summary(_ result: LongevityAPI.HealthSyncResult) -> String {
        var parts = ["Zapisano \(result.saved) \(dayWord(result.saved))"]
        if result.activitySynced > 0 { parts.append("aktywność \(result.activitySynced)") }
        if result.weightSynced > 0 { parts.append("waga \(result.weightSynced)") }
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
