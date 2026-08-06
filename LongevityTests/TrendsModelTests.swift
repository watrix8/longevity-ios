import Foundation
import Testing

@testable import Longevity

@Suite("Metryki trendów")
struct MetricTests {
    private func metric(
        _ values: [Double],
        positiveHigher: Bool = true
    ) -> Metric {
        let points = values.enumerated().map {
            SeriesPoint(date: String(format: "2026-08-%02d", $0.offset + 1), value: $0.element)
        }
        return Metric(id: "t", title: "T", unit: "", positiveHigher: positiveHigher,
                      role: .informational, points: points)
    }

    @Test("Init sortuje punkty po dacie")
    func initSorts() {
        let unsorted = [
            SeriesPoint(date: "2026-08-03", value: 3),
            SeriesPoint(date: "2026-08-01", value: 1),
            SeriesPoint(date: "2026-08-02", value: 2),
        ]
        let m = Metric(id: "t", title: "T", unit: "", positiveHigher: true, role: .informational, points: unsorted)

        #expect(m.points.map(\.value) == [1, 2, 3])
        #expect(m.last == 3)
        #expect(m.previous == 2)
    }

    @Test("Średnia 7-dniowa bierze tylko ogon")
    func avg7UsesTail() {
        // 10 punktów: 1...10. Ostatnie 7 to 4...10 → średnia 7.
        let m = metric((1...10).map(Double.init))

        #expect(m.avg7 == 7)
        #expect(m.avg30 == 5.5)
    }

    @Test("Strzałka w górę, gdy wyżej znaczy lepiej")
    func arrowPositiveHigher() {
        #expect(metric([10, 20]).arrow == "↗")
        #expect(metric([20, 10]).arrow == "↘")
        #expect(metric([10, 10]).arrow == "→")
    }

    /// Waga i stres: spadek jest dobry, więc strzałka leci odwrotnie.
    @Test("Strzałka odwraca się dla metryk, gdzie mniej znaczy lepiej")
    func arrowInverted() {
        #expect(metric([10, 20], positiveHigher: false).arrow == "↘")
        #expect(metric([20, 10], positiveHigher: false).arrow == "↗")
        #expect(metric([10, 10], positiveHigher: false).arrow == "→")
    }

    @Test("Brak danych nie wywraca wyliczeń")
    func emptySeries() {
        let m = metric([])

        #expect(m.last == nil)
        #expect(m.previous == nil)
        #expect(m.avg7 == nil)
        #expect(m.avg30 == nil)
        #expect(m.arrow == "→")
    }

    @Test("Jeden punkt nie ma poprzednika ani kierunku")
    func singlePoint() {
        let m = metric([42])

        #expect(m.last == 42)
        #expect(m.previous == nil)
        #expect(m.avg7 == 42)
        #expect(m.arrow == "→")
    }

    @Test("Średnie zaokrąglają się do jednego miejsca")
    func averageRounding() {
        #expect(metric([1, 2]).avg30 == 1.5)
        #expect(metric([1, 1, 2]).avg30 == 1.3)
    }
}

@Suite("Agregacja kalorii")
@MainActor
struct DailyKcalTests {
    @Test("Sumuje środki widełek w obrębie dnia")
    func sumsMidpointsPerDay() {
        let points = TrendsViewModel.dailyKcal([
            ("2026-08-01", 400, 600),   // 500
            ("2026-08-01", 200, 400),   // 300
            ("2026-08-02", 1000, 1200), // 1100
        ])

        #expect(points.map(\.date) == ["2026-08-01", "2026-08-02"])
        #expect(points.map(\.value) == [800, 1100])
    }

    @Test("Brakujące widełki liczą się jako zero")
    func nilBoundsCountAsZero() {
        let points = TrendsViewModel.dailyKcal([
            ("2026-08-01", nil, 600),  // 300
            ("2026-08-01", 400, nil),  // 200
            ("2026-08-02", nil, nil),  // 0
        ])

        #expect(points.map(\.value) == [500, 0])
    }

    @Test("Wynik jest posortowany rosnąco po dacie")
    func sortedAscending() {
        let points = TrendsViewModel.dailyKcal([
            ("2026-08-03", 100, 100),
            ("2026-08-01", 100, 100),
            ("2026-08-02", 100, 100),
        ])

        #expect(points.map(\.date) == ["2026-08-01", "2026-08-02", "2026-08-03"])
    }

    @Test("Pusta lista daje pustą serię")
    func emptyInput() {
        #expect(TrendsViewModel.dailyKcal([]).isEmpty)
    }
}

/// Strzałka przy przeciąganiu po wykresie. Musi opisywać wskazany dzień,
/// bo inaczej karta pokazuje wartość z 12 lipca i kierunek z dziś.
@Suite("Kierunek dla wybranego dnia")
struct MetricArrowAtIndexTests {
    private func metric(_ values: [Double], positiveHigher: Bool = true) -> Metric {
        let points = values.enumerated().map {
            SeriesPoint(date: String(format: "2026-08-%02d", $0.offset + 1), value: $0.element)
        }
        return Metric(id: "t", title: "T", unit: "", positiveHigher: positiveHigher,
                      role: .informational, points: points)
    }

    @Test("Porównanie idzie z dniem poprzedzającym wskazany, nie z ostatnim")
    func comparesWithPrecedingDay() {
        let m = metric([10, 30, 20, 50])

        #expect(m.arrow(at: 1) == "↗")
        #expect(m.arrow(at: 2) == "↘")
        #expect(m.arrow(at: 3) == "↗")
    }

    @Test("Odwrócenie działa też dla wskazanego dnia")
    func invertedAtIndex() {
        let m = metric([10, 30, 20], positiveHigher: false)

        #expect(m.arrow(at: 1) == "↘")
        #expect(m.arrow(at: 2) == "↗")
    }

    @Test("Pierwszy punkt nie ma z czym porównywać")
    func firstPointHasNoDirection() {
        #expect(metric([10, 30, 20]).arrow(at: 0) == "→")
    }

    /// `selection` przeżywa odświeżenie danych, więc indeks bywa poza zakresem
    /// krótszego szeregu. Nie może wtedy wysypać widoku.
    @Test("Indeks poza zakresem i nil dają neutralną strzałkę")
    func toleratesBadIndex() {
        let m = metric([10, 30, 20])

        #expect(m.arrow(at: 99) == "→")
        #expect(m.arrow(at: -1) == "→")
        #expect(m.arrow(at: nil) == "→")
    }

    @Test("Bez wskazania strzałka opisuje ostatni punkt")
    func defaultsToLastPoint() {
        let m = metric([10, 30, 20])

        #expect(m.arrow == m.arrow(at: 2))
        #expect(m.arrow == "↘")
    }

    @Test("Pusty szereg nie wywraca wyliczeń")
    func emptySeries() {
        #expect(metric([]).arrow == "→")
        #expect(metric([]).arrow(at: 0) == "→")
    }
}

@Suite("Rola metryki w wyniku")
struct MetricRoleTests {
    @Test("Etykieta składnika podaje komponent i jego wagę")
    func feedsBadge() {
        #expect(MetricRole.feeds(component: "Sen", weight: 0.30).badge == "Sen · 30%")
        #expect(MetricRole.feeds(component: "Regeneracja", weight: 0.15).badge == "Regeneracja · 15%")
    }

    /// Kroki, ruch i kalorie nie wchodzą dziś do v3 — kafelek ma to mówić
    /// wprost, zamiast wyglądać tak samo ważnie jak sen.
    @Test("Metryka poboczna jest oznaczona i nie liczy się do wyniku")
    func informationalBadge() {
        #expect(MetricRole.informational.badge == "poza wynikiem")
        #expect(!MetricRole.informational.countsToScore)
    }

    @Test("Sam wynik nie udaje ani składnika, ani metryki pobocznej")
    func totalBadge() {
        #expect(MetricRole.total.badge == "wynik")
        #expect(!MetricRole.total.countsToScore)
    }

    @Test("Tylko składniki liczą się do wyniku")
    func onlyFeedsCounts() {
        #expect(MetricRole.feeds(component: "Ciało", weight: 0.2).countsToScore)
    }
}
