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
    /// Norma dnia — średnia z maks. 7 dni POPRZEDZAJĄCYCH ten dzień.
    ///
    /// `nil` w pierwszym dniu szeregu: nie ma jeszcze z czym porównywać,
    /// a linia sklejona z wynikiem dnia udawałaby normę, której nie ma.
    let norm: Double?
}

/// Wszystko, co ekran renderuje, policzone raz przy wczytaniu.
struct DashboardData: Sendable {
    let dateLabel: String
    let headline: Int
    let stateText: String

    /// Norma dzisiejszego dnia — dokładnie ta sama liczba, którą rysuje
    /// zielona linia na wykresie. Jedna definicja, jedno źródło.
    let norm: Int?
    /// Ile dni faktycznie weszło do normy (maks. 7).
    let normDays: Int
    /// Dziś minus norma. `nil` razem z `norm`.
    let normDelta: Int?

    let points: [DayPoint]
    let breakdown: [ScoreComponentRow]

    /// Ile dni z ostatnich 30 ma snapshot — odpowiednik "pewności" z makiety.
    let coverageDays: Int
    let note: String?

    /// Dni, po których wykres zaczyna cokolwiek znaczyć.
    static let warmupDays = 7

    /// Poniżej progu wykres wprowadza w błąd: dwa punkty odległe o 1 pkt
    /// rysują się jak stromy podjazd, cokolwiek zrobić ze skalą.
    var isWarmingUp: Bool { coverageDays < Self.warmupDays }

    var confidence: Int { Int((Double(coverageDays) / 30.0 * 100).rounded()) }
}

extension DashboardData {
    /// Dane poglądowe dla SwiftUI Previews — kształt jak z prawdziwych snapshotów.
    static var sample: DashboardData {
        preview(
            totals: [61, 58, 66, 70, 63, 72, 68, 74, 59, 71, 77, 65, 80, 73],
            stateText: "Solidnie. Trzymaj tempo — nic nie musisz zmieniać.",
            note: "Score policzony z 65% wag. Brakuje: VO₂max, Metabolizm."
        )
    }

    /// Świeże konto: za mało dni, żeby wykres cokolwiek znaczył.
    static var warmingUp: DashboardData {
        preview(
            totals: [90, 91, 89],
            stateText: "Świetna forma. Dziś możesz spokojnie docisnąć trening.",
            note: "Score policzony z 65% wag. Brakuje: VO₂max, Metabolizm."
        )
    }

    /// Liczy to samo co `build`, tylko z gołych wartości — dzięki temu podgląd
    /// nie może rozjechać się z produkcyjną definicją normy.
    private static func preview(totals: [Double], stateText: String, note: String?) -> DashboardData {
        let norms = DashboardViewModel.norms(for: totals)
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let points = totals.indices.map { i in
            DayPoint(
                date: dayFormatter.string(
                    from: Calendar.current.date(
                        byAdding: .day, value: i - totals.count + 1, to: Date()
                    ) ?? Date()
                ),
                total: totals[i],
                norm: norms[i]
            )
        }

        let headline = Int(totals.last ?? 0)
        let todayNorm = norms.last.flatMap { $0 }

        return DashboardData(
            dateLabel: "czwartek · 6 sierpnia",
            headline: headline,
            stateText: stateText,
            norm: todayNorm.map { Int($0.rounded()) },
            normDays: min(max(0, totals.count - 1), DashboardViewModel.normWindow),
            normDelta: todayNorm.map { Int((Double(headline) - $0).rounded()) },
            points: Array(points.suffix(14)),
            breakdown: [
                // Podwagi i kolejność jak w `sleepParts`/`bodyParts` z
                // `lib/scoring-v3.ts` — podgląd ma pokazywać kształt, który
                // naprawdę przychodzi w snapshocie.
                ScoreComponentRow(
                    id: "sleep", label: "Sen", weight: 0.30, value: 84,
                    parts: [
                        ScorePartRow(id: "duration", label: "Długość snu", weight: 0.5, value: 94),
                        ScorePartRow(id: "deep", label: "Sen głęboki", weight: 0.2, value: 71),
                        ScorePartRow(id: "regularity", label: "Regularność pory snu", weight: 0.2, value: 78),
                        ScorePartRow(id: "consistency", label: "Równa długość snu", weight: 0.1, value: 62),
                    ]
                ),
                ScoreComponentRow(
                    id: "body", label: "Ciało", weight: 0.20, value: 72,
                    parts: [
                        ScorePartRow(id: "whr", label: "Talia/biodra", weight: 0.5, value: nil),
                        ScorePartRow(id: "body_fat", label: "Tkanka tłuszczowa", weight: 0.3, value: 68),
                        ScorePartRow(id: "bmi", label: "BMI", weight: 0.2, value: 72),
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
            coverageDays: totals.count,
            note: note
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

    /// Ile dni wstecz uśrednia norma.
    nonisolated static let normWindow = 7

    /// Norma dnia liczona WYŁĄCZNIE z dni wcześniejszych.
    ///
    /// Gdyby do okna wchodził dzisiejszy wynik, porównanie „dziś vs norma"
    /// byłoby po części porównaniem liczby z samą sobą i tłumiło odchylenie
    /// o 1/7. Pierwszy dzień szeregu nie ma normy — stąd opcjonalność.
    ///
    /// `nonisolated`, bo to czysta matematyka — podgląd składa z niej dane
    /// bez wchodzenia na main actora.
    nonisolated static func norms(for totals: [Double]) -> [Double?] {
        totals.indices.map { i in
            let window = totals[max(0, i - normWindow)..<i]
            guard !window.isEmpty else { return nil }
            return window.reduce(0, +) / Double(window.count)
        }
    }

    /// Internal, nie private — to jedyna nietrywialna logika w tym pliku
    /// i chcemy ją mieć pod testami bez dotykania sieci.
    static func build(from rows: [ScoreSnapshot], current: ScoreSnapshot) -> DashboardData {
        // rows przychodzą malejąco po dacie; do wykresu chcemy rosnąco.
        let ascending = rows.reversed().map { $0 }
        let totals = ascending.map { Double($0.scoreTotal) }

        let points = zip(ascending, norms(for: totals)).map { snap, norm in
            DayPoint(date: snap.scoreDate, total: Double(snap.scoreTotal), norm: norm)
        }

        // Norma dzisiejsza = norma ostatniego punktu szeregu. Ta sama liczba
        // ląduje pod dużą cyfrą i na końcu zielonej linii wykresu.
        let todayNorm = points.last?.norm

        return DashboardData(
            dateLabel: polishDate(current.scoreDate),
            headline: current.scoreTotal,
            stateText: stateText(for: current.scoreTotal),
            norm: todayNorm.map { Int($0.rounded()) },
            normDays: min(max(0, totals.count - 1), normWindow),
            normDelta: todayNorm.map { Int((Double(current.scoreTotal) - $0).rounded()) },
            points: Array(points.suffix(14)),
            breakdown: current.components.breakdown,
            coverageDays: rows.count,
            note: Self.missingNote(current.components)
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
