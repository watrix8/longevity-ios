import Foundation
import Observation

/// Widok pojedynczego dnia na pasku 14 dni.
///
/// Jeden punkt to jeden dzień KALENDARZA, także taki bez pomiarów. Wcześniej
/// szereg szedł po kolejnych snapshotach, więc tydzień przerwy zwijał się do
/// zera pikseli i zmiana z trzech tygodni rysowała się tak stromo jak zmiana
/// z trzech dni.
struct DayPoint: Sendable {
    let date: String
    /// `nil` = dzień bez pomiarów. Pasek zostawia w tym miejscu dziurę,
    /// zamiast udawać, że tego dnia nie było.
    let total: Double?
    /// Trend dnia — średnia wyników z 7 DNI KALENDARZA przed tym dniem.
    ///
    /// `nil`, gdy w oknie jest mniej niż `trendMinDays` dni z pomiarami:
    /// średnia z jednego dnia to nie trend, tylko wynik wczorajszy.
    let trend: Double?
}

/// Wszystko, co ekran renderuje, policzone raz przy wczytaniu.
struct DashboardData: Sendable {
    let dateLabel: String
    let headline: Int
    let stateText: String

    /// Trend na dzisiejszy dzień — dokładnie ta sama liczba, którą rysuje
    /// zielona linia na wykresie. Jedna definicja, jedno źródło.
    let trend: Int?
    /// Ile dni faktycznie weszło do trendu (maks. 7).
    let trendDays: Int
    /// Dziś minus trend. `nil` razem z `trend`.
    let trendDelta: Int?
    /// Ilu dni z pomiarami brakuje, żeby trend się pojawił. Liczone razem
    /// z dzisiejszym, bo on wejdzie do jutrzejszego okna — przy zerze trend
    /// zapala się jutro, bez dokładania czegokolwiek.
    let trendMissingDays: Int

    let points: [DayPoint]
    let breakdown: [ScoreComponentRow]

    /// Ile dni z ostatnich 30 ma snapshot — odpowiednik "pewności" z makiety.
    let coverageDays: Int
    let note: String?

    /// Dni, po których wykres zaczyna cokolwiek znaczyć.
    static let warmupDays = 7

    /// Szerokość paska — dni kalendarza, nie pomiarów.
    static let stripDays = 14

    /// Poniżej progu wykres wprowadza w błąd: dwa punkty odległe o 1 pkt
    /// rysują się jak stromy podjazd, cokolwiek zrobić ze skalą.
    var isWarmingUp: Bool { coverageDays < Self.warmupDays }
}

extension DashboardData {
    /// Dane poglądowe dla SwiftUI Previews — kształt jak z prawdziwych snapshotów.
    static var sample: DashboardData {
        preview(
            totals: [61, 58, 66, 70, 63, 72, 68, 74, 59, 71, 77, 65, 80, 73],
            stateText: DashboardViewModel.stateText(for: 73),
            note: previewNote
        )
    }

    /// Świeże konto: za mało dni, żeby wykres cokolwiek znaczył.
    static var warmingUp: DashboardData {
        preview(
            totals: [90, 91, 89],
            stateText: DashboardViewModel.stateText(for: 89),
            note: previewNote
        )
    }

    /// Ta sama składanka co w `missingNote` — podgląd nie dorabia własnego
    /// zdania, tylko przechodzi przez ten sam klucz tłumaczenia.
    private static var previewNote: String {
        let missing = ["VO₂max", String(localized: "Metabolizm")].joined(separator: ", ")
        return String(localized: "Score policzony z \(65)% wag. Brakuje: \(missing).")
    }

    /// Tydzień noszenia, tydzień przerwy, powrót — pasek ma pokazać dziurę,
    /// a linia trendu urwać się tam, gdzie zabrakło dni.
    static var withGap: DashboardData {
        preview(
            totals: [72, 75, 71, 78, 74, nil, nil, nil, nil, nil, 61, 66, 70, 73],
            stateText: DashboardViewModel.stateText(for: 73),
            note: nil
        )
    }

    /// Liczy to samo co `build`, tylko z gołych wartości — dzięki temu podgląd
    /// nie może rozjechać się z produkcyjną definicją trendu.
    ///
    /// `nil` w `totals` to dzień bez pomiarów, dokładnie jak brakujący
    /// snapshot z Supabase.
    private static func preview(totals: [Double?], stateText: String, note: String?) -> DashboardData {
        // Kolejne dni kalendarza wstecz od dziś — ta sama droga co w `build`,
        // żeby podgląd nie miał własnej definicji trendu.
        let today = Date()
        let scores = Dictionary(
            uniqueKeysWithValues: totals.indices.compactMap { i -> (String, Double)? in
                guard let total = totals[i] else { return nil }
                let day = CalendarDays.calendar.date(
                    byAdding: .day, value: i - totals.count + 1, to: today
                ) ?? today
                return (CalendarDays.isoString(day), total)
            }
        )

        let end = CalendarDays.isoString(today)
        let points = DashboardViewModel.series(scores: scores, endingAt: end)
        let headline = Int(totals.compactMap { $0 }.last ?? 0)
        let todayTrend = CalendarDays.date(fromISO: end).map {
            DashboardViewModel.trend(before: $0, scores: scores)
        }

        return DashboardData(
            dateLabel: DashboardViewModel.displayDate("2026-08-06"),
            headline: headline,
            stateText: stateText,
            trend: todayTrend?.value.map { Int($0.rounded()) },
            trendDays: todayTrend?.days ?? 0,
            trendDelta: todayTrend?.value.map { Int((Double(headline) - $0).rounded()) },
            trendMissingDays: max(
                0,
                DashboardViewModel.trendMinDays - (CalendarDays.date(fromISO: end).map {
                    DashboardViewModel.measuredDays(upTo: $0, scores: scores)
                } ?? 0)
            ),
            points: points,
            breakdown: [
                // Podwagi i kolejność jak w `sleepParts`/`bodyParts` z
                // `lib/scoring-v3.ts` — podgląd ma pokazywać kształt, który
                // naprawdę przychodzi w snapshocie.
                ScoreComponentRow(
                    id: "sleep", label: ScoreComponents.label(forComponent: "sleep"), weight: 0.30, value: 84,
                    parts: [
                        ScorePartRow(id: "duration", label: ScoreComponents.label(forPart: "duration"), weight: 0.5, value: 94),
                        ScorePartRow(id: "deep", label: ScoreComponents.label(forPart: "deep"), weight: 0.2, value: 71),
                        ScorePartRow(id: "regularity", label: ScoreComponents.label(forPart: "regularity"), weight: 0.2, value: 78),
                        ScorePartRow(id: "consistency", label: ScoreComponents.label(forPart: "consistency"), weight: 0.1, value: 62),
                    ]
                ),
                ScoreComponentRow(
                    id: "body", label: ScoreComponents.label(forComponent: "body"), weight: 0.20, value: 72,
                    parts: [
                        ScorePartRow(id: "whr", label: ScoreComponents.label(forPart: "whr"), weight: 0.5, value: nil),
                        ScorePartRow(id: "body_fat", label: ScoreComponents.label(forPart: "body_fat"), weight: 0.3, value: 68),
                        ScorePartRow(id: "bmi", label: ScoreComponents.label(forPart: "bmi"), weight: 0.2, value: 72),
                    ]
                ),
                ScoreComponentRow(
                    id: "regeneration", label: ScoreComponents.label(forComponent: "regeneration"), weight: 0.15, value: 75,
                    parts: [
                        ScorePartRow(id: "resting_heart_rate", label: ScoreComponents.label(forPart: "resting_heart_rate"), weight: 0.4, value: 100),
                        ScorePartRow(id: "hrv_trend", label: ScoreComponents.label(forPart: "hrv_trend"), weight: 0.6, value: nil),
                    ]
                ),
            ],
            coverageDays: scores.count,
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

    /// Ile DNI KALENDARZA wstecz sięga okno trendu.
    nonisolated static let trendWindow = 7

    /// Ile z tych dni musi mieć pomiar, żeby średnia zasłużyła na nazwę trendu.
    /// Przy jednym czy dwóch to jeszcze pojedyncze dni, nie kierunek.
    nonisolated static let trendMinDays = 3

    /// Trend dnia liczony z SIEDMIU DNI KALENDARZA przed nim.
    ///
    /// Dzień bez pomiaru nie wchodzi do średniej, ale zajmuje miejsce w oknie.
    /// Dzięki temu tydzień przerwy przesuwa okno w czasie, zamiast po cichu
    /// dokleić do trendu wyniki sprzed przerwy — wcześniej okno liczyło
    /// „siedem ostatnich pomiarów", więc przy dziurach sięgało trzy tygodnie
    /// wstecz i pokazywało formę, której już nie ma.
    ///
    /// Sam dzień do okna nie wchodzi: inaczej porównanie „dziś vs trend"
    /// byłoby po części porównaniem liczby z samą sobą.
    ///
    /// `nonisolated`, bo to czysta matematyka — podgląd składa z niej dane
    /// bez wchodzenia na main actora.
    nonisolated static func trend(
        before day: Date,
        scores: [String: Double]
    ) -> (value: Double?, days: Int) {
        let values = (1...trendWindow).compactMap { offset -> Double? in
            guard let earlier = CalendarDays.calendar.date(byAdding: .day, value: -offset, to: day)
            else { return nil }
            return scores[CalendarDays.isoString(earlier)]
        }

        guard values.count >= trendMinDays else { return (nil, values.count) }
        return (values.reduce(0, +) / Double(values.count), values.count)
    }

    /// Ile z ostatnich 7 dni kalendarza RAZEM z `day` ma pomiar — dokładnie
    /// tyle wejdzie do jutrzejszego okna trendu.
    nonisolated static func measuredDays(upTo day: Date, scores: [String: Double]) -> Int {
        (0..<trendWindow).count { offset in
            guard let earlier = CalendarDays.calendar.date(byAdding: .day, value: -offset, to: day)
            else { return false }
            return scores[CalendarDays.isoString(earlier)] != nil
        }
    }

    /// Internal, nie private — to jedyna nietrywialna logika w tym pliku
    /// i chcemy ją mieć pod testami bez dotykania sieci.
    static func build(from rows: [ScoreSnapshot], current: ScoreSnapshot) -> DashboardData {
        let scores = Dictionary(
            rows.map { ($0.scoreDate, Double($0.scoreTotal)) },
            uniquingKeysWith: { first, _ in first }
        )

        let points = series(scores: scores, endingAt: current.scoreDate)
        let today = CalendarDays.date(fromISO: current.scoreDate)
        let todayTrend = today.map { trend(before: $0, scores: scores) }

        return DashboardData(
            dateLabel: displayDate(current.scoreDate),
            headline: current.scoreTotal,
            stateText: stateText(for: current.scoreTotal),
            trend: todayTrend?.value.map { Int($0.rounded()) },
            trendDays: todayTrend?.days ?? 0,
            trendDelta: todayTrend?.value.map { Int((Double(current.scoreTotal) - $0).rounded()) },
            trendMissingDays: max(
                0,
                trendMinDays - (today.map { measuredDays(upTo: $0, scores: scores) } ?? 0)
            ),
            points: points,
            breakdown: current.components.breakdown,
            coverageDays: rows.count,
            note: Self.missingNote(current.components)
        )
    }

    /// Ostatnie `stripDays` dni kalendarza zakończone dniem `end`, ale nie
    /// wcześniej niż pierwszy pomiar — puste sloty sprzed założenia konta
    /// byłyby dziurą, której nikt nie zawinił.
    nonisolated static func series(
        scores: [String: Double],
        endingAt end: String,
        stripDays: Int = DashboardData.stripDays
    ) -> [DayPoint] {
        guard let endDate = CalendarDays.date(fromISO: end) else { return [] }

        let firstMeasured = scores.keys.min().flatMap { CalendarDays.date(fromISO: $0) } ?? endDate
        let span = CalendarDays.days(from: firstMeasured, to: endDate)
        let length = min(stripDays, max(1, span + 1))

        return (0..<length).reversed().compactMap { offset in
            guard let day = CalendarDays.calendar.date(byAdding: .day, value: -offset, to: endDate)
            else { return nil }
            return DayPoint(
                date: CalendarDays.isoString(day),
                total: scores[CalendarDays.isoString(day)],
                trend: trend(before: day, scores: scores).value
            )
        }
    }

    /// Score v3 pomija komponenty bez danych i przenormowuje wagi, więc liczba
    /// bywa policzona z części obrazu. Notka mówi z jakiej — bez tego 82/100
    /// z samego snu wygląda identycznie jak 82/100 z kompletu pomiarów.
    static func missingNote(_ components: ScoreComponents) -> String? {
        let missing = components.missing
        guard !missing.isEmpty else { return nil }

        let list = missing.joined(separator: ", ")
        guard let coverage = components.coveragePercent else {
            return String(localized: "Brakuje danych: \(list).")
        }
        return String(localized: "Score policzony z \(coverage)% wag. Brakuje: \(list).")
    }

    /// Progi zgodne z `scoreLabel()` z lib/scoring.ts w repo webowym.
    ///
    /// Zdanie schodzi z modelu przetłumaczone, a nie jako klucz — `DashboardData`
    /// jest gotowym materiałem dla widoku i nie ma powodu, żeby ekran znał progi.
    nonisolated static func stateText(for total: Int) -> String {
        switch total {
        case 80...: String(localized: "Świetna forma. Dziś możesz spokojnie docisnąć trening.")
        case 60..<80: String(localized: "Solidnie. Trzymaj tempo — nic nie musisz zmieniać.")
        case 40..<60: String(localized: "Przeciętnie. Jeden spokojny dzień zrobi różnicę.")
        default: String(localized: "Lekki dzień. Twój organizm prosi o odpoczynek.")
        }
    }

    private static func isoDate(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// „czwartek · 6 sierpnia", a po angielsku „Thursday · August 6".
    ///
    /// Kolejność dnia i miesiąca różni się między językami, więc obie części
    /// formatuje `FormatStyle` osobno — sztywne „d MMMM" dałoby po angielsku
    /// „6 August".
    nonisolated static func displayDate(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return iso }

        let locale = Locale.autoupdatingCurrent
        let weekday = date.formatted(.dateTime.locale(locale).weekday(.wide))
        let day = date.formatted(.dateTime.locale(locale).day().month(.wide))
        return "\(weekday) · \(day)"
    }
}
