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
        #expect(data.points.compactMap(\.total) == [60, 70, 80])
    }

    @Test("Headline bierze się z bieżącego snapshotu")
    func headlineFromCurrent() throws {
        let rows = [try makeSnapshot("2026-08-06", 38), try makeSnapshot("2026-08-05", 90)]
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.headline == 38)
    }

    /// Przy jednym dniu nie ma z czym porównywać — trend musi być pusty,
    /// a nie równy dzisiejszemu wynikowi. Sklejony udawałby, że istnieje.
    @Test("Pojedynczy snapshot nie ma trendu")
    func singleSnapshot() throws {
        let rows = [try makeSnapshot("2026-08-06", 38)]
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.coverageDays == 1)
        #expect(data.trend == nil)
        #expect(data.trendDelta == nil)
        #expect(data.trendDays == 0)
        #expect(data.points.count == 1)
        #expect(data.points.first?.trend == nil)
    }

    @Test("Trend liczy się z okna 7 dni poprzedzających")
    func rollingTrend() throws {
        // 10 dni po 10, 20, ... 100 — malejąco, jak z Supabase.
        let rows = try (1...10).reversed().map {
            try makeSnapshot(String(format: "2026-08-%02d", $0), $0 * 10)
        }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        // Pierwszy punkt nie ma dnia przed sobą.
        #expect(data.points.first?.trend == nil)
        // Ósmy punkt (wartość 80): średnia z siedmiu poprzednich, 10...70.
        #expect(data.points[7].trend == 40)
        // Ostatni (100): średnia z 30...90.
        #expect(data.points.last?.trend == 60)
    }

    /// Sedno przejścia na kalendarz: przerwa w noszeniu zegarka ma wypchnąć
    /// stare wyniki z okna, a nie dokleić je do dzisiejszego trendu.
    @Test("Przerwa wypycha stare dni z okna trendu")
    func gapPushesOldDaysOut() throws {
        // Trzy dni po 100 na początku sierpnia, tydzień przerwy, potem 10-12.
        let older = try (1...3).map { try makeSnapshot(String(format: "2026-08-%02d", $0), 100) }
        let newer = try (10...12).map { try makeSnapshot(String(format: "2026-08-%02d", $0), 40) }
        let rows = (older + newer).reversed().map { $0 }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        // Okno 08-05...08-11 obejmuje tylko dwa dni z pomiarem (10 i 11),
        // a setki sprzed przerwy są już poza nim. Poniżej progu — brak trendu.
        #expect(data.trendDays == 2)
        #expect(data.trend == nil)
        #expect(data.trendDelta == nil)
    }

    /// Poprzednia, pozycyjna wersja liczyła „siedem ostatnich pomiarów", więc
    /// przy dziurach sięgała wiele tygodni wstecz.
    @Test("Trend uśrednia tylko dni z okna, nie ostatnie pomiary")
    func trendIgnoresMeasurementsOutsideWindow() throws {
        // 100 dawno temu, potem trzy świeże dni po 40 tuż przed dzisiejszym.
        let old = try makeSnapshot("2026-07-20", 100)
        let recent = try (5...7).map { try makeSnapshot(String(format: "2026-08-%02d", $0), 40) }
        let today = try makeSnapshot("2026-08-08", 70)
        let rows = ([old] + recent + [today]).reversed().map { $0 }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        // Średnia z 05, 06 i 07 — lipcowa setka jest poza oknem.
        #expect(data.trend == 40)
        #expect(data.trendDays == 3)
        #expect(data.trendDelta == 30)
    }

    /// Dzień bez pomiaru zostaje w szeregu jako pusty slot — dzięki temu oś
    /// czasu na wykresie jest równa, a dziura widoczna.
    @Test("Dni bez pomiaru zostają w szeregu jako puste")
    func seriesKeepsEmptyDays() throws {
        let rows = [
            try makeSnapshot("2026-08-08", 70),
            try makeSnapshot("2026-08-05", 50),
        ]
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.points.map(\.date) == [
            "2026-08-05", "2026-08-06", "2026-08-07", "2026-08-08",
        ])
        #expect(data.points.map(\.total) == [50, nil, nil, 70])
        #expect(data.coverageDays == 2)
    }

    /// Ekran mówił „trend pojawi się po 3 dniach z pomiarami" komuś, kto miał
    /// dokładnie trzy dni z rzędu — bo próg dotyczy dni PRZED dzisiejszym,
    /// a licznik pokazywał sumę. Teraz liczy braki razem z dzisiejszym.
    @Test("Licznik braków wie, że dzisiejszy dzień wejdzie do jutrzejszego okna")
    func missingDaysCountsToday() throws {
        // Trzy dni z rzędu, ostatni dzisiaj: w oknie są dwa, ale jutro będą trzy.
        let rows = try (6...8).reversed().map {
            try makeSnapshot(String(format: "2026-08-%02d", $0), 89)
        }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.trend == nil)
        #expect(data.trendDays == 2)
        #expect(data.trendMissingDays == 0)
    }

    @Test("Przy jednym dniu brakuje jeszcze dwóch")
    func missingDaysOnFirstDay() throws {
        let rows = [try makeSnapshot("2026-08-08", 89)]
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.trendMissingDays == 2)
    }

    @Test("Próg trendu: trzy dni w oknie wystarczą, dwa nie")
    func trendMinimumDays() throws {
        func trend(days: [Int]) throws -> DashboardData {
            let older = try days.map { try makeSnapshot(String(format: "2026-08-%02d", $0), 60) }
            let today = try makeSnapshot("2026-08-08", 90)
            let rows = (older + [today]).reversed().map { $0 }
            return DashboardViewModel.build(from: rows, current: rows[0])
        }

        #expect(try trend(days: [5, 7]).trend == nil)
        #expect(try trend(days: [3, 5, 7]).trend == 60)
    }

    /// Sedno zmiany: gdyby dzisiejszy wynik wchodził do własnego trendu,
    /// odchylenie byłoby tłumione o 1/7 i „dziś vs trend" porównywałoby
    /// liczbę częściowo z samą sobą.
    @Test("Dzisiejszy wynik nie wchodzi do własnego trendu")
    func trendExcludesToday() throws {
        // Siedem dni po 50 i dzisiaj 100. Trend to czyste 50, delta 50.
        let older = try (1...7).map { try makeSnapshot(String(format: "2026-08-%02d", $0), 50) }
        let today = try makeSnapshot("2026-08-08", 100)
        let rows = (older + [today]).reversed().map { $0 }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.trend == 50)
        #expect(data.trendDelta == 50)
        #expect(data.trendDays == 7)
    }

    @Test("Okno trendu zatrzymuje się na siedmiu dniach")
    func trendWindowCaps() throws {
        // 20 dni: dziesięć po 100 (starsze) i dziesięć po 0 — trend ostatniego
        // dnia widzi wyłącznie zera, bo setki wypadły z okna.
        let older = try (1...10).map { try makeSnapshot(String(format: "2026-08-%02d", $0), 100) }
        let newer = try (11...20).map { try makeSnapshot(String(format: "2026-08-%02d", $0), 0) }
        let rows = (older + newer).reversed().map { $0 }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.trend == 0)
        #expect(data.trendDays == 7)
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

    @Test("Pokrycie liczy dni ze snapshotem, nie punkty wykresu")
    func coverageCountsSnapshots() throws {
        let rows = try (1...15).reversed().map {
            try makeSnapshot(String(format: "2026-08-%02d", $0), 50)
        }
        let data = DashboardViewModel.build(from: rows, current: rows[0])

        #expect(data.coverageDays == 15)
        #expect(data.points.count == 14)
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

    /// Porównanie do przetłumaczonego zdania, a nie do polskiego prefiksu —
    /// po lokalizacji test sprawdza próg, a nie język, w którym akurat
    /// uruchomiono symulator.
    @Test("Progi opisu stanu", arguments: [
        (95, 80), (80, 80), (79, 60), (60, 60),
        (59, 40), (40, 40), (39, 0), (0, 0),
    ])
    func stateTextThresholds(total: Int, band: Int) throws {
        let snapshot = try makeSnapshot("2026-08-06", total)
        let data = DashboardViewModel.build(from: [snapshot], current: snapshot)

        #expect(data.stateText == DashboardViewModel.stateText(for: band))
    }

    /// Cztery progi to cztery różne zdania — gdyby któreś się powtórzyło,
    /// test wyżej przechodziłby mimo sklejonych przedziałów.
    @Test("Każdy próg ma własne zdanie")
    func stateTextsDiffer() {
        let texts = [0, 40, 60, 80].map { DashboardViewModel.stateText(for: $0) }
        #expect(Set(texts).count == 4)
    }

    /// Data ma nieść dzień tygodnia i miesiąc słownie, w języku użytkownika.
    /// Sam napis zależy od lokalizacji, więc test pilnuje kształtu: dwie części
    /// rozdzielone kropką i miesiąc słowem, a nie cyfrą.
    @Test("Data jest opisowa i rozdzielona kropką")
    func dateLabelShape() throws {
        let snapshot = try makeSnapshot("2026-08-06", 38)
        let data = DashboardViewModel.build(from: [snapshot], current: snapshot)

        let parts = data.dateLabel.components(separatedBy: " · ")
        #expect(parts.count == 2)
        #expect(parts.first?.contains(where: \.isLetter) == true)
        #expect(parts.last?.contains(where: \.isLetter) == true)
    }
}

@Suite("String Catalog")
struct LocalizationTests {
    /// Polska odmiana „dzień/dni" siedzi teraz w katalogu jako warianty
    /// mnogości. Bez tego testu literówka w kategorii `few` przeszłaby cicho.
    @Test("Warianty mnogości po polsku")
    func polishPlurals() {
        #expect(localized("ostatnie \(1) dni", "pl") == "ostatni dzień")
        #expect(localized("ostatnie \(2) dni", "pl") == "ostatnie 2 dni")
        #expect(localized("ostatnie \(14) dni", "pl") == "ostatnie 14 dni")
        #expect(localized("trend z \(1) dni", "pl") == "trend z 1 dnia")
        #expect(localized("trend z \(7) dni", "pl") == "trend z 7 dni")
    }

    @Test("Angielski wchodzi z katalogu")
    func englishTranslations() {
        #expect(localized("ostatnie \(1) dni", "en") == "last day")
        #expect(localized("ostatnie \(14) dni", "en") == "last 14 days")
        #expect(localized("wynik dnia", "en") == "today's score")
        #expect(localized("Sen", "en") == "Sleep")
    }

    private func localized(_ resource: LocalizedStringResource, _ language: String) -> String {
        var resource = resource
        resource.locale = Locale(identifier: language)
        return String(localized: resource)
    }
}
