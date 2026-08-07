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
        #expect(m.avgAll == 5.5)
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
        #expect(m.avgAll == nil)
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
        #expect(metric([1, 2]).avgAll == 1.5)
        #expect(metric([1, 1, 2]).avgAll == 1.3)
    }
}

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

@Suite("Zakres i agregacja Trendów")
@MainActor
struct TrendRangeTests {
    private static func metric(_ values: [Double]) -> Metric {
        Metric(
            id: "t", title: "T", unit: "", positiveHigher: true, role: .informational,
            points: values.enumerated().map {
                SeriesPoint(date: String(format: "2026-08-%02d", $0.offset + 1), value: $0.element)
            }
        )
    }

    @Test("Dzienny zakres nie rusza punktów")
    func dailyUntouched() {
        let metric = Self.metric([1, 2, 3, 4])
        #expect(metric.bucketed(by: 1).points.count == 4)
        #expect(TrendRange.month.bucketDays == 1)
        #expect(TrendRange.quarter.bucketDays == 1)
    }

    @Test("Kubełki uśredniają wartości i skracają szereg")
    func averagesIntoBuckets() {
        // Cztery tygodnie po siedem dni: 1…7, 8…14, itd.
        let metric = Self.metric((1...28).map(Double.init))
        let weekly = metric.bucketed(by: 7)

        #expect(weekly.points.count == 4)
        #expect(weekly.points.map(\.value) == [4, 11, 18, 25])
    }

    /// Liczenie od najnowszego: ostatni kubełek ma być pełnym, świeżym
    /// tygodniem, a nie ogryzkiem zależnym od tego, kiedy zaczyna się historia.
    @Test("Niepełny kubełek ląduje na początku, nie na końcu")
    func partialBucketGoesFirst() {
        let metric = Self.metric((1...10).map(Double.init))
        let weekly = metric.bucketed(by: 7)

        #expect(weekly.points.count == 2)
        // Ostatnie siedem dni (4…10) daje 7; pierwsze trzy (1…3) dają 2.
        #expect(weekly.points.map(\.value) == [2, 7])
    }

    @Test("Oś czasu zostaje rosnąca")
    func keepsChronology() {
        let weekly = Self.metric((1...28).map(Double.init)).bucketed(by: 7)
        let dates = weekly.points.map(\.date)

        #expect(dates == dates.sorted())
    }

    @Test("Zakres wybiera głębokość i sposób agregacji")
    func rangeMapping() {
        #expect(TrendRange.month.days == 30)
        #expect(TrendRange.year.days == 365)
        #expect(TrendRange.all.days == nil)
        #expect(TrendRange.year.bucketDays == 7)
        #expect(TrendRange.all.bucketDays == 30)
        #expect(TrendRange.month.bucketNote == nil)
        #expect(TrendRange.all.bucketNote != nil)
    }

    @Test("Pojedynczy punkt przeżywa agregację")
    func singlePoint() {
        #expect(Self.metric([5]).bucketed(by: 30).points.count == 1)
    }
}
