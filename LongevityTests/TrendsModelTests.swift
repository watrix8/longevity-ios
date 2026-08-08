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

    @Test("Średnia 7-dniowa bierze ostatnie siedem DNI, nie siedem pomiarów")
    func avg7UsesCalendarWindow() {
        // 10 kolejnych dni: 1...10. Okno 08-04...08-10 → średnia 7.
        let m = metric((1...10).map(Double.init))

        #expect(m.avg7 == 7)
        #expect(m.avgAll == 5.5)
    }

    /// Sedno przejścia na kalendarz: pomiar co kilka dni nie może wciągać
    /// do „średniej 7 dni" wyników sprzed miesiąca.
    @Test("Pomiary rzadsze niż codzienne nie rozciągają okna średniej")
    func avg7IgnoresOlderMeasurements() {
        let sparse = [
            SeriesPoint(date: "2026-07-01", value: 100),
            SeriesPoint(date: "2026-07-10", value: 100),
            SeriesPoint(date: "2026-08-05", value: 40),
            SeriesPoint(date: "2026-08-08", value: 60),
        ]
        let m = Metric(id: "t", title: "T", unit: "", positiveHigher: true,
                       role: .informational, points: sparse)

        // Okno 08-02...08-08 obejmuje tylko dwa ostatnie pomiary.
        #expect(m.avg7 == 50)
        #expect(m.avgAll == 75)
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

@Suite("Okno czasu na Trendach")
@MainActor
struct TrendWindowTests {
    @Test("Szerokość okna nie przekracza kwartału")
    func windowWidths() {
        #expect(TrendWindow.month.days == 30)
        #expect(TrendWindow.quarter.days == 90)
        #expect(TrendWindow.allCases.allSatisfy { $0.days <= 90 })
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Bieżące okno kończy się dziś")
    func currentWindowEndsToday() {
        let model = TrendsViewModel(state: .loaded([]))
        let (from, to) = model.visibleRange(now: Self.now)

        #expect(to == Self.now)
        #expect(Calendar.current.dateComponents([.day], from: from, to: to).day == 29)
    }

    /// Sedno zmiany: okno jest wąskie, ale przesuwalne — cofnięcie o jedną
    /// stronę ma pokazać poprzedni, rozłączny okres.
    @Test("Cofnięcie przesuwa okno o pełną szerokość")
    func shiftMovesFullWindow() {
        let model = TrendsViewModel(state: .loaded([]))
        let before = model.visibleRange(now: Self.now).to

        model.shift(by: 1)
        let after = model.visibleRange(now: Self.now).to

        let days = Calendar.current.dateComponents([.day], from: after, to: before).day
        #expect(days == TrendWindow.month.days)
    }

    /// Przyszłości nie ma po co oglądać, więc krok w przód zatrzymuje się na dziś.
    @Test("Nie da się przesunąć poza teraźniejszość")
    func cannotGoBeyondNow() {
        let model = TrendsViewModel(state: .loaded([]))

        #expect(!model.canGoForward)
        model.shift(by: -5)
        #expect(!model.canGoForward)

        model.shift(by: 2)
        #expect(model.canGoForward)
    }

    @Test("Etykieta okresu podaje rok, żeby historia nie była dwuznaczna")
    func periodLabelHasYear() {
        let model = TrendsViewModel(state: .loaded([]))
        model.shift(by: 20)

        #expect(model.periodLabel.contains("–"))
        #expect(model.periodLabel.rangeOfCharacter(from: .decimalDigits) != nil)
    }
}

@Suite("Etykiety dat na wykresie")
@MainActor
struct AxisLabelTests {
    private static func metric(_ dates: [String]) -> Metric {
        Metric(
            id: "t", title: "T", unit: "", positiveHigher: true, role: .informational,
            points: dates.map { SeriesPoint(date: $0, value: 1) }
        )
    }

    /// Przy cofaniu się o lata „08-06" nie mówi, o który rok chodzi.
    @Test("Szereg przekraczający rok pokazuje rok na osi")
    func multiYearAxisShowsYear() {
        let across = Self.metric(["2025-12-30", "2026-01-02"])

        #expect(across.spansYears)
        #expect(across.axisLabel("2025-12-30") == "2025-12")
    }

    @Test("Szereg w jednym roku zostaje przy dniu i miesiącu")
    func singleYearAxisStaysShort() {
        let within = Self.metric(["2026-07-01", "2026-08-01"])

        #expect(!within.spansYears)
        #expect(within.axisLabel("2026-07-01") == "07-01")
    }

    @Test("Odczyt punktu dokłada rok tylko dla dat spoza bieżącego roku")
    func pointLabelYearOnlyWhenNeeded() {
        let metric = Self.metric(["2026-08-06"])
        let now = try! Date("2026-08-08T12:00:00Z", strategy: .iso8601)

        #expect(metric.pointLabel("2026-08-06", now: now) == "6 sierpnia")
        #expect(metric.pointLabel("2024-08-06", now: now).contains("2024"))
    }
}

@Suite("Oś czasu wykresu")
struct ChartCalendarAxisTests {
    private let span = DaySpan(from: "2026-08-01", to: "2026-08-31")

    @Test("Okno liczy obie granice")
    func spanLength() {
        #expect(span.days == 31)
        #expect(DaySpan(from: "2026-08-08", to: "2026-08-08").days == 1)
    }

    @Test("Pozycja dnia idzie po kalendarzu")
    func fractionFollowsCalendar() {
        #expect(span.fraction(of: "2026-08-01") == 0)
        #expect(span.fraction(of: "2026-08-31") == 1)
        #expect(span.fraction(of: "2026-08-16") == 0.5)
    }

    @Test("Dzień spoza okna przywiera do krawędzi")
    func fractionClamps() {
        #expect(span.fraction(of: "2026-07-20") == 0)
        #expect(span.fraction(of: "2026-09-10") == 1)
    }

    /// Wcześniej pozycja wynikała z numeru pomiaru, więc dwa punkty odległe
    /// o trzy tygodnie rysowały się obok siebie.
    @Test("Odstęp między punktami odpowiada odstępowi w dniach")
    func spacingFollowsGaps() {
        let points = [
            SeriesPoint(date: "2026-08-01", value: 10),
            SeriesPoint(date: "2026-08-02", value: 20),
            SeriesPoint(date: "2026-08-31", value: 30),
        ]
        let geometry = ChartGeometry(points: points, span: span, size: CGSize(width: 300, height: 100))

        #expect(geometry.point(at: 0).x == 0)
        #expect(geometry.point(at: 1).x == 10)
        #expect(geometry.point(at: 2).x == 300)
    }

    @Test("Palec trafia w dzień najbliższy w czasie")
    func touchPicksNearestDay() {
        let points = [
            SeriesPoint(date: "2026-08-01", value: 10),
            SeriesPoint(date: "2026-08-02", value: 20),
            SeriesPoint(date: "2026-08-31", value: 30),
        ]
        let geometry = ChartGeometry(points: points, span: span, size: CGSize(width: 300, height: 100))

        #expect(geometry.index(atX: 0) == 0)
        #expect(geometry.index(atX: 12) == 1)
        // Środek okna: bliżej 2 sierpnia niż 31 sierpnia.
        #expect(geometry.index(atX: 150) == 1)
        #expect(geometry.index(atX: 290) == 2)
    }
}
