import Foundation
import Observation

enum PL {
    /// Dopełniacz po przyimku "z": z 1 dnia, z 14 dni.
    static func daysGenitive(_ n: Int) -> String { n == 1 ? "dnia" : "dni" }

    /// Nagłówek zakresu: ostatni dzień / ostatnie 14 dni.
    static func lastDays(_ n: Int) -> String {
        n == 1 ? "ostatni dzień" : "ostatnie \(n) dni"
    }
}

/// Widok pojedynczego dnia na pasku 14 dni.
struct DayPoint: Sendable {
    let date: String
    let total: Double
    /// Krocząca średnia 7-dniowa — "wolna" linia, odpowiednik Fundamentu z makiety.
    let baseline: Double
}

/// Wszystko, co ekran renderuje, policzone raz przy wczytaniu.
struct DashboardData: Sendable {
    let dateLabel: String
    let headline: Int
    let stateText: String

    let baseline: Int
    let baselineDelta: Int
    let baselineSeries: [Double]

    let today: Int
    let todayWord: String

    let points: [DayPoint]
    let breakdown: [ScoreComponentRow]

    /// Ile dni z ostatnich 30 ma snapshot — odpowiednik "pewności" z makiety.
    let coverageDays: Int
    let note: String?

    var confidence: Int { Int((Double(coverageDays) / 30.0 * 100).rounded()) }
}

extension DashboardData {
    /// Dane poglądowe dla SwiftUI Previews — kształt jak z prawdziwych snapshotów.
    static var sample: DashboardData {
        let totals: [Double] = [61, 58, 66, 70, 63, 72, 68, 74, 59, 71, 77, 65, 80, 73]
        let baselines = totals.indices.map { i -> Double in
            let w = totals[max(0, i - 6)...i]
            return w.reduce(0, +) / Double(w.count)
        }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let points = totals.indices.map { i in
            DayPoint(
                date: dayFormatter.string(
                    from: Calendar.current.date(byAdding: .day, value: i - 13, to: Date()) ?? Date()
                ),
                total: totals[i],
                baseline: baselines[i]
            )
        }

        return DashboardData(
            dateLabel: "czwartek · 6 sierpnia",
            headline: 73,
            stateText: "Solidnie. Trzymaj tempo — nic nie musisz zmieniać.",
            baseline: 68,
            baselineDelta: 3,
            baselineSeries: baselines,
            today: 73,
            todayWord: "dobrze",
            points: points,
            breakdown: [
                ScoreComponentRow(
                    id: "sleep", label: "Sen", weight: 0.30, value: 84,
                    parts: [
                        ScorePartRow(id: "duration", label: "Długość snu", weight: 0.6, value: 94),
                        ScorePartRow(id: "deep", label: "Sen głęboki", weight: 0.25, value: 71),
                        ScorePartRow(id: "consistency", label: "Równa długość snu", weight: 0.15, value: 62),
                    ]
                ),
                ScoreComponentRow(
                    id: "body", label: "Ciało", weight: 0.20, value: 72,
                    parts: [
                        ScorePartRow(id: "bmi", label: "BMI", weight: 0.5, value: 72),
                        ScorePartRow(id: "whr", label: "Talia/biodra", weight: 0.5, value: nil),
                    ]
                ),
                ScoreComponentRow(
                    id: "regeneration", label: "Regeneracja", weight: 0.15, value: 75,
                    parts: [
                        ScorePartRow(id: "resting_heart_rate", label: "Tętno spoczynkowe", weight: 0.4, value: 100),
                        ScorePartRow(id: "hrv_trend", label: "Trend HRV", weight: 0.6, value: nil),
                    ]
                ),
            ],
            coverageDays: 14,
            note: "Score policzony z 65% wag. Brakuje: VO₂max, Metabolizm."
        )
    }
}

@MainActor
@Observable
final class DashboardViewModel {
    enum State {
        case loading
        case empty
        case loaded(DashboardData)
        case failed(String)
    }

    private(set) var state: State

    /// Podgląd wstrzykuje gotowy stan i nie ma czego dociągać — bez tej flagi
    /// każdy `#Preview` uderzałby w sieć i kończył na ekranie błędu.
    private let autoLoads: Bool

    init(state: State = .loading) {
        self.state = state
        autoLoads = { if case .loading = state { true } else { false } }()
    }

    /// Wołane przy każdym wejściu na zakładkę.
    ///
    /// Ekran wczytywał się dotąd raz na uruchomienie, więc wpis zrobiony
    /// w czacie nie pojawiał się tu aż do pull-to-refresh. `load()` nie cofa
    /// stanu do `.loading`, więc dane zostają na ekranie, dopóki nie przyjdą nowe.
    func refresh() async {
        guard autoLoads else { return }
        await load()
    }

    func load() async {
        do {
            let from = Self.isoDate(daysAgo: 29)
            let rows: [ScoreSnapshot] = try await AppSupabase.client
                .from("score_snapshots")
                .select("score_date, score_total, components")
                .gte("score_date", value: from)
                .order("score_date", ascending: false)
                .limit(30)
                .execute()
                .value

            guard let current = rows.first else {
                state = .empty
                return
            }
            state = .loaded(Self.build(from: rows, current: current))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Wyliczenia

    /// Internal, nie private — to jedyna nietrywialna logika w tym pliku
    /// i chcemy ją mieć pod testami bez dotykania sieci.
    static func build(from rows: [ScoreSnapshot], current: ScoreSnapshot) -> DashboardData {
        // rows przychodzą malejąco po dacie; do wykresu chcemy rosnąco.
        let ascending = rows.reversed().map { $0 }
        let totals = ascending.map { Double($0.scoreTotal) }

        let baselines = totals.indices.map { i -> Double in
            let lower = max(0, i - 6)
            let window = totals[lower...i]
            return window.reduce(0, +) / Double(window.count)
        }

        let points = zip(ascending, baselines).map { snap, base in
            DayPoint(date: snap.scoreDate, total: Double(snap.scoreTotal), baseline: base)
        }
        let last14 = Array(points.suffix(14))

        let avg30 = totals.isEmpty ? 0 : totals.reduce(0, +) / Double(totals.count)
        let last7 = totals.suffix(7)
        let avg7 = last7.isEmpty ? 0 : last7.reduce(0, +) / Double(last7.count)

        let note = Self.missingNote(current.components)

        return DashboardData(
            dateLabel: polishDate(current.scoreDate),
            headline: current.scoreTotal,
            stateText: stateText(for: current.scoreTotal),
            baseline: Int(avg30.rounded()),
            baselineDelta: Int((avg7 - avg30).rounded()),
            baselineSeries: last14.map(\.baseline),
            today: current.scoreTotal,
            todayWord: scoreLabel(current.scoreTotal),
            points: last14,
            breakdown: current.components.breakdown,
            coverageDays: rows.count,
            note: note
        )
    }

    /// Score v3 pomija komponenty bez danych i przenormowuje wagi, więc liczba
    /// bywa policzona z części obrazu. Notka mówi z jakiej — bez tego 82/100
    /// z samego snu wygląda identycznie jak 82/100 z kompletu pomiarów.
    static func missingNote(_ components: ScoreComponents) -> String? {
        let missing = components.missing
        guard !missing.isEmpty else { return nil }

        guard let coverage = components.coveragePercent else {
            return "Brakuje danych: \(missing.joined(separator: ", "))."
        }
        return "Score policzony z \(coverage)% wag. Brakuje: \(missing.joined(separator: ", "))."
    }

    /// Progi zgodne z `scoreLabel()` z lib/scoring.ts w repo webowym.
    private static func scoreLabel(_ total: Int) -> String {
        switch total {
        case 80...: "świetnie"
        case 60..<80: "dobrze"
        case 40..<60: "przeciętnie"
        default: "nisko"
        }
    }

    private static func stateText(for total: Int) -> String {
        switch total {
        case 80...: "Świetna forma. Dziś możesz spokojnie docisnąć trening."
        case 60..<80: "Solidnie. Trzymaj tempo — nic nie musisz zmieniać."
        case 40..<60: "Przeciętnie. Jeden spokojny dzień zrobi różnicę."
        default: "Lekki dzień. Twój organizm prosi o odpoczynek."
        }
    }

    private static func isoDate(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func polishDate(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return iso }

        let out = DateFormatter()
        out.locale = Locale(identifier: "pl_PL")
        out.dateFormat = "EEEE · d MMMM"
        return out.string(from: date)
    }
}
