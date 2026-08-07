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

@Suite("Grupowanie Trendów")
@MainActor
struct MetricGroupTests {
    private static func metric(_ id: String, _ role: MetricRole) -> Metric {
        Metric(id: id, title: id, unit: "", positiveHigher: true, role: role,
               points: [SeriesPoint(date: "2026-08-01", value: 1)])
    }

    @Test("Nagłówek sekcji podaje komponent i wagę")
    func groupHeader() {
        let scored = MetricGroup(id: "Sen", title: "Sen", weight: 0.30, metrics: [])
        let side = MetricGroup(id: "informational", title: "Poza wynikiem", weight: nil, metrics: [])

        #expect(scored.header == "Sen · 30%")
        #expect(side.header == "Poza wynikiem")
    }

    @Test("Rola wskazuje sekcję, do której trafia metryka")
    func roleMapsToGroup() {
        let sleep = MetricRole.feeds(component: "Sen", weight: 0.30)

        #expect(sleep.groupID == "Sen")
        #expect(sleep.groupTitle == "Sen")
        #expect(sleep.groupWeight == 0.30)

        #expect(MetricRole.informational.groupID == "informational")
        #expect(MetricRole.informational.groupWeight == nil)
        #expect(MetricRole.total.groupTitle == "Wynik")
    }

    /// Kolejność sekcji ma wynikać z kolejności metryk, żeby układ listy
    /// w `build` był jedynym miejscem, które o niej decyduje.
    @Test("Metryki tej samej roli trafiają razem, bez rozbijania sekcji")
    func groupsFollowFirstAppearance() {
        let sleep = MetricRole.feeds(component: "Sen", weight: 0.30)
        let body = MetricRole.feeds(component: "Ciało", weight: 0.20)

        let groups = TrendsViewModel.grouped([
            Self.metric("a", .total),
            Self.metric("b", sleep),
            Self.metric("c", sleep),
            Self.metric("d", body),
            Self.metric("e", .informational),
        ])

        #expect(groups.map(\.id) == ["total", "Sen", "Ciało", "informational"])
        #expect(groups[1].metrics.map(\.id) == ["b", "c"])
    }

    @Test("Pusta lista nie tworzy pustych sekcji")
    func emptyInput() {
        #expect(TrendsViewModel.grouped([]).isEmpty)
    }
}

@Suite("Odświeżanie ekranów")
@MainActor
struct RefreshTests {
    /// Model z wstrzykniętym stanem to podgląd albo test — `refresh()` nie może
    /// go podmienić na ekran błędu przy pierwszej próbie sięgnięcia do sieci.
    @Test("Wstrzyknięty stan przeżywa odświeżenie")
    func injectedStateSurvivesRefresh() async {
        let trends = TrendsViewModel(state: .loaded([]))
        await trends.refresh()

        if case .loaded = trends.state {} else {
            Issue.record("Trendy zmieniły stan mimo wstrzykniętych danych")
        }

        let dashboard = DashboardViewModel(state: .loaded(.sample))
        await dashboard.refresh()

        if case .loaded = dashboard.state {} else {
            Issue.record("Dashboard zmienił stan mimo wstrzykniętych danych")
        }
    }
}
