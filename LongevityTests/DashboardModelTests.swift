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
    }

    /// Przy jednym dniu nie ma z czym porównywać — norma musi być pusta,
    /// a nie równa dzisiejszemu wynikowi. Sklejona udawałaby, że istnieje.
    @Test("Pojedynczy snapshot nie ma normy")
    func singleSnapshot() throws {
        let rows = [try makeSnapshot("2026-08-06", 38)]
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.coverageDays == 1)
        #expect(data.norm == nil)
        #expect(data.normDelta == nil)
        #expect(data.normDays == 0)
        #expect(data.points.count == 1)
        #expect(data.points.first?.norm == nil)
    }

    @Test("Norma liczy się z okna 7 dni poprzedzających")
    func rollingNorm() throws {
        // 10 dni po 10, 20, ... 100 — malejąco, jak z Supabase.
        let rows = try (1...10).reversed().map {
            try makeSnapshot(String(format: "2026-08-%02d", $0), $0 * 10)
        }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        // Pierwszy punkt nie ma dnia przed sobą.
        #expect(data.points.first?.norm == nil)
        // Ósmy punkt (wartość 80): średnia z siedmiu poprzednich, 10...70.
        #expect(data.points[7].norm == 40)
        // Ostatni (100): średnia z 30...90.
        #expect(data.points.last?.norm == 60)
    }

    /// Sedno zmiany: gdyby dzisiejszy wynik wchodził do własnej normy,
    /// odchylenie byłoby tłumione o 1/7 i „dziś vs norma" porównywałoby
    /// liczbę częściowo z samą sobą.
    @Test("Dzisiejszy wynik nie wchodzi do własnej normy")
    func normExcludesToday() throws {
        // Siedem dni po 50 i dzisiaj 100. Norma to czyste 50, delta 50.
        let older = try (1...7).map { try makeSnapshot(String(format: "2026-08-%02d", $0), 50) }
        let today = try makeSnapshot("2026-08-08", 100)
        let rows = (older + [today]).reversed().map { $0 }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.norm == 50)
        #expect(data.normDelta == 50)
        #expect(data.normDays == 7)
    }

    @Test("Okno normy zatrzymuje się na siedmiu dniach")
    func normWindowCaps() throws {
        // 20 dni: dziesięć po 100 (starsze) i dziesięć po 0 — norma ostatniego
        // dnia widzi wyłącznie zera, bo setki wypadły z okna.
        let older = try (1...10).map { try makeSnapshot(String(format: "2026-08-%02d", $0), 100) }
        let newer = try (11...20).map { try makeSnapshot(String(format: "2026-08-%02d", $0), 0) }
        let rows = (older + newer).reversed().map { $0 }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.norm == 0)
        #expect(data.normDays == 7)
    }

    @Test("Rozgrzewka trwa do siódmego dnia z danymi")
    func warmupThreshold() throws {
        func data(days: Int) throws -> DashboardData {
            let rows = try (1...days).reversed().map {
                try makeSnapshot(String(format: "2026-08-%02d", $0), 60)
            }
            return DashboardViewModel.build(from: rows, current: rows[0])
        }

        #expect(try data(days: 6).isWarmingUp)
        #expect(try !data(days: 7).isWarmingUp)
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
