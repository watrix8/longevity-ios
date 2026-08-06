import Foundation
import Testing

@testable import Longevity

@Suite("Wyliczenia dashboardu")
@MainActor
struct DashboardModelTests {
    /// Supabase zwraca malejąco po dacie — `build` musi to odwrócić,
    /// inaczej wykres i średnia krocząca liczą się od końca.
    @Test("Punkty wychodzą rosnąco mimo malejącego wejścia")
    func reversesDescendingInput() throws {
        let rows = [
            try makeSnapshot("2026-08-06", 80),
            try makeSnapshot("2026-08-05", 70),
            try makeSnapshot("2026-08-04", 60),
        ]
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.points.map(\.date) == ["2026-08-04", "2026-08-05", "2026-08-06"])
        #expect(data.points.map(\.total) == [60, 70, 80])
    }

    @Test("Headline bierze się z bieżącego snapshotu")
    func headlineFromCurrent() throws {
        let rows = [try makeSnapshot("2026-08-06", 38), try makeSnapshot("2026-08-05", 90)]
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.headline == 38)
        #expect(data.today == 38)
    }

    /// Regresja z symulatora: przy jednym snapshocie karta pokazywała
    /// „średnia z 30 dni", choć uśredniała jeden dzień.
    @Test("Pojedynczy snapshot daje pokrycie 1 i zerowy trend")
    func singleSnapshot() throws {
        let rows = [try makeSnapshot("2026-08-06", 38)]
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.coverageDays == 1)
        #expect(data.baseline == 38)
        #expect(data.baselineDelta == 0)
        #expect(data.points.count == 1)
    }

    @Test("Średnia krocząca liczy się z okna 7 dni")
    func rollingBaseline() throws {
        // 10 dni po 10, 20, ... 100 — malejąco, jak z Supabase.
        let rows = try (1...10).reversed().map {
            try makeSnapshot(String(format: "2026-08-%02d", $0), $0 * 10)
        }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        // Pierwszy punkt: okno ma tylko jego samego.
        #expect(data.points.first?.baseline == 10)
        // Ósmy punkt (wartość 80): średnia z 20...80.
        #expect(data.points[7].baseline == 50)
        // Ostatni: średnia z 40...100.
        #expect(data.points.last?.baseline == 70)
    }

    @Test("Pasek przycina się do 14 dni")
    func stripCapsAtFourteen() throws {
        let rows = try (1...20).reversed().map {
            try makeSnapshot(String(format: "2026-08-%02d", $0), 50)
        }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.points.count == 14)
        #expect(data.coverageDays == 20)
        // Zostaje ogon, nie początek.
        #expect(data.points.first?.date == "2026-08-07")
        #expect(data.points.last?.date == "2026-08-20")
    }

    @Test("Delta trendu to różnica średnich 7 i 30 dni")
    func trendDelta() throws {
        // 7 dni po 40 (starsze) + 7 dni po 60 (nowsze) → avg7 = 60, avg30 = 50.
        let older = try (1...7).map { try makeSnapshot(String(format: "2026-08-%02d", $0), 40) }
        let newer = try (8...14).map { try makeSnapshot(String(format: "2026-08-%02d", $0), 60) }
        let rows = (older + newer).reversed().map { $0 }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.baseline == 50)
        #expect(data.baselineDelta == 10)
    }

    @Test("Pewność to pokrycie danymi w 30 dniach")
    func confidence() throws {
        let rows = try (1...15).reversed().map {
            try makeSnapshot(String(format: "2026-08-%02d", $0), 50)
        }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.coverageDays == 15)
        #expect(data.confidence == 50)
    }

    @Test("Notka pojawia się przy niepełnym pokryciu komponentów")
    func coverageNote() throws {
        let partial = try makeSnapshot("2026-08-06", 82, components: """
        {"sleep":82,"regeneration":70,"coverage":0.45}
        """)
        let complete = try makeSnapshot("2026-08-06", 78, components: """
        {"sleep":82,"vo2max":95,"body":70,"regeneration":88,"metabolic":60,"coverage":1}
        """)

        #expect(DashboardViewModel.build(from: [partial], current: partial).note != nil)
        #expect(DashboardViewModel.build(from: [complete], current: complete).note == nil)
    }

    /// Breakdown na dashboardzie ma tyle pasków, ile komponentów dało się
    /// policzyć — reszta znika, zamiast leżeć na zerze.
    @Test("Breakdown pokazuje tylko policzone komponenty")
    func breakdownSkipsMissing() throws {
        let partial = try makeSnapshot("2026-08-06", 82, components: """
        {"sleep":82,"regeneration":70,"coverage":0.45}
        """)
        let data = DashboardViewModel.build(from: [partial], current: partial)

        #expect(data.breakdown.map(\.label) == ["Sen", "Regeneracja"])
    }

    @Test("Progi opisu stanu", arguments: [
        (95, "Świetna"), (80, "Świetna"), (79, "Solidnie"), (60, "Solidnie"),
        (59, "Przeciętnie"), (40, "Przeciętnie"), (39, "Lekki"), (0, "Lekki"),
    ])
    func stateTextThresholds(total: Int, expectedPrefix: String) throws {
        let snapshot = try makeSnapshot("2026-08-06", total)
        let data = DashboardViewModel.build(from: [snapshot], current: snapshot)

        #expect(data.stateText.hasPrefix(expectedPrefix))
    }

    @Test("Progi etykiety słownej", arguments: [
        (80, "świetnie"), (60, "dobrze"), (40, "przeciętnie"), (39, "nisko"),
    ])
    func scoreLabelThresholds(total: Int, expected: String) throws {
        let snapshot = try makeSnapshot("2026-08-06", total)
        let data = DashboardViewModel.build(from: [snapshot], current: snapshot)

        #expect(data.todayWord == expected)
    }

    @Test("Data formatuje się po polsku")
    func polishDateLabel() throws {
        let snapshot = try makeSnapshot("2026-08-06", 38)
        let data = DashboardViewModel.build(from: [snapshot], current: snapshot)

        #expect(data.dateLabel == "czwartek · 6 sierpnia")
    }
}

@Suite("Odmiana liczebników")
struct PolishPluralTests {
    /// Po przyimku "z" potrzebny dopełniacz — "średnia z 1 dnia", nie "z 1 dzień".
    @Test("Dopełniacz", arguments: [(1, "dnia"), (2, "dni"), (5, "dni"), (22, "dni")])
    func genitive(count: Int, expected: String) {
        #expect(PL.daysGenitive(count) == expected)
    }

    @Test("Nagłówek zakresu")
    func lastDaysHeader() {
        #expect(PL.lastDays(1) == "ostatni dzień")
        #expect(PL.lastDays(2) == "ostatnie 2 dni")
        #expect(PL.lastDays(14) == "ostatnie 14 dni")
    }
}
