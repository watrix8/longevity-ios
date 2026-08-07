import Foundation
import Testing

@testable import Longevity

/// Buduje snapshot tak, jak przychodzi z PostgREST.
func makeSnapshot(_ date: String, _ total: Int, components: String = "{}") throws -> ScoreSnapshot {
    let json = #"{"score_date":"\#(date)","score_total":\#(total),"components":\#(components)}"#
    return try JSONDecoder().decode(ScoreSnapshot.self, from: Data(json.utf8))
}

@Suite("Dekodowanie score_snapshots")
struct ScoreSnapshotTests {
    @Test("Pełny payload v3 dekoduje wszystkie komponenty")
    func fullV3Payload() throws {
        let snapshot = try makeSnapshot("2026-08-06", 78, components: """
        {"sleep":82,"vo2max":95,"body":70,"regeneration":88,"metabolic":60,
         "coverage":1,"score_model":"v3_measured"}
        """)

        #expect(snapshot.scoreDate == "2026-08-06")
        #expect(snapshot.scoreTotal == 78)
        #expect(snapshot.components.sleep == 82)
        #expect(snapshot.components.vo2max == 95)
        #expect(snapshot.components.regeneration == 88)
        #expect(snapshot.components.coveragePercent == 100)
        #expect(snapshot.components.scoreModel == "v3_measured")
    }

    /// `components jsonb not null default '{}'` — pusty obiekt musi przejść,
    /// inaczej dashboard wywala się na świeżym wierszu.
    @Test("Puste components nie wywracają dekodowania")
    func emptyComponents() throws {
        let snapshot = try makeSnapshot("2026-08-06", 0, components: "{}")

        #expect(snapshot.components.sleep == nil)
        #expect(snapshot.components.coveragePercent == nil)
        #expect(snapshot.components.breakdown.isEmpty)
    }

    /// Sedno v3: brak danych to `nil`, nie zero. Zero znaczy „zmierzone i źle",
    /// nil znaczy „nie zmierzone" — sprowadzenie ich do jednego dałoby pasek
    /// na dnie za nienoszenie zegarka.
    @Test("Brakujący komponent zostaje nilem, nie zerem")
    func missingIsNotZero() throws {
        let snapshot = try makeSnapshot("2026-08-06", 82, components: """
        {"sleep":82,"vo2max":null,"coverage":0.3,"score_model":"v3_measured"}
        """)

        #expect(snapshot.components.vo2max == nil)
        #expect(snapshot.components.sleep == 82)
    }

    @Test("Breakdown pomija komponenty bez danych")
    func breakdownSkipsMissing() throws {
        let snapshot = try makeSnapshot("2026-08-06", 80, components: """
        {"sleep":10,"body":30,"regeneration":40}
        """)

        #expect(snapshot.components.breakdown.map(\.label) == ["Sen", "Ciało", "Regeneracja"])
        #expect(snapshot.components.breakdown.map(\.value) == [10, 30, 40])
    }

    @Test("Breakdown trzyma kolejność wag z formuły")
    func breakdownOrder() throws {
        let snapshot = try makeSnapshot("2026-08-06", 50, components: """
        {"sleep":1,"vo2max":2,"body":3,"regeneration":4,"metabolic":5}
        """)

        #expect(snapshot.components.breakdown.map(\.label)
            == ["Sen", "VO₂max", "Ciało", "Regeneracja", "Metabolizm"])
        #expect(snapshot.components.breakdown.map(\.value) == [1, 2, 3, 4, 5])
    }

    @Test("Lista braków wymienia dokładnie nieobliczone komponenty")
    func missingList() throws {
        let snapshot = try makeSnapshot("2026-08-06", 82, components: """
        {"sleep":82,"regeneration":70}
        """)

        #expect(snapshot.components.missing == ["VO₂max", "Ciało", "Metabolizm"])
    }

    @Test("Pokrycie przelicza się na procenty")
    func coverageRounding() throws {
        let snapshot = try makeSnapshot("2026-08-06", 82, components: #"{"coverage":0.65}"#)
        #expect(snapshot.components.coveragePercent == 65)
    }

    @Test("Liczby całkowite z JSON-a wchodzą w Double")
    func integerCoercion() throws {
        let snapshot = try makeSnapshot("2026-08-06", 38, components: #"{"sleep":84}"#)
        #expect(snapshot.components.sleep == 84.0)
    }
}

@Suite("Notka o brakach na dashboardzie")
@MainActor
struct MissingNoteTests {
    private static func components(_ json: String) throws -> ScoreComponents {
        try makeSnapshot("2026-08-06", 50, components: json).components
    }

    @Test("Komplet komponentów nie generuje notki")
    func noNoteWhenComplete() throws {
        let full = try Self.components("""
        {"sleep":1,"vo2max":2,"body":3,"regeneration":4,"metabolic":5,"coverage":1}
        """)
        #expect(DashboardViewModel.missingNote(full) == nil)
    }

    /// Bez tej notki 82/100 z samego snu wygląda identycznie jak 82/100
    /// z kompletu pomiarów.
    @Test("Notka podaje pokrycie i wymienia braki")
    func noteListsGaps() throws {
        let partial = try Self.components("""
        {"sleep":82,"regeneration":70,"coverage":0.45}
        """)
        let note = try #require(DashboardViewModel.missingNote(partial))

        #expect(note.contains("45%"))
        #expect(note.contains("VO₂max"))
        #expect(note.contains("Metabolizm"))
    }

    @Test("Bez pola coverage notka nadal wymienia braki")
    func noteWithoutCoverage() throws {
        let partial = try Self.components(#"{"sleep":82}"#)
        let note = try #require(DashboardViewModel.missingNote(partial))

        #expect(note.contains("VO₂max"))
        #expect(!note.contains("%"))
    }
}

@Suite("Skład komponentów")
struct ScorePartsTests {
    private static let payload = """
    {"sleep":84,"regeneration":75,
     "coverage":0.45,
     "weights":{"sleep":0.3,"vo2max":0.25,"body":0.2,"regeneration":0.15,"metabolic":0.1},
     "parts":{
       "sleep":[{"key":"duration","weight":0.6,"value":94},
                {"key":"deep","weight":0.25,"value":71},
                {"key":"consistency","weight":0.15,"value":62}],
       "vo2max":[],
       "regeneration":[{"key":"resting_heart_rate","weight":0.4,"value":100},
                       {"key":"hrv_trend","weight":0.6,"value":null}]}}
    """

    private static func components() throws -> ScoreComponents {
        try makeSnapshot("2026-08-06", 80, components: payload).components
    }

    @Test("Wiersz komponentu niesie swoją wagę w całym score")
    func carriesWeight() throws {
        let sleep = try #require(try Self.components().breakdown.first { $0.id == "sleep" })
        #expect(sleep.weight == 0.3)
        #expect(sleep.value == 84)
    }

    @Test("Składowe mają polskie etykiety i wagi wewnątrz komponentu")
    func mapsPartLabels() throws {
        let regeneration = try #require(
            try Self.components().breakdown.first { $0.id == "regeneration" }
        )

        #expect(regeneration.parts.map(\.label) == ["Tętno spoczynkowe", "Trend HRV"])
        #expect(regeneration.parts.map(\.weight) == [0.4, 0.6])
    }

    /// Brak pomiaru w składowej zostaje nilem — widok pokazuje „nie zmierzono",
    /// a nie pasek na zerze.
    @Test("Niezmierzona składowa nie udaje zera")
    func missingPartStaysNil() throws {
        let regeneration = try #require(
            try Self.components().breakdown.first { $0.id == "regeneration" }
        )
        let hrv = try #require(regeneration.parts.first { $0.id == "hrv_trend" })

        #expect(hrv.value == nil)
    }

    @Test("Komponent bez składowych nie udaje rozwijalnego")
    func vo2maxHasNoParts() throws {
        let rows = try Self.components().breakdown
        #expect(rows.first { $0.id == "vo2max" } == nil)

        let sleep = try #require(rows.first { $0.id == "sleep" })
        #expect(sleep.hasParts)
    }

    /// Snapshoty sprzed tej zmiany nie mają ani wag, ani składu — rozbicie musi
    /// się dalej renderować, tylko bez rozwijania.
    @Test("Stary snapshot bez parts i weights nadal daje rozbicie")
    func legacySnapshot() throws {
        let old = try makeSnapshot("2026-08-01", 70, components: #"{"sleep":70,"body":60}"#).components
        let rows = old.breakdown

        #expect(rows.map(\.label) == ["Sen", "Ciało"])
        #expect(rows.allSatisfy { $0.weight == nil })
        #expect(rows.allSatisfy { !$0.hasParts })
    }

    @Test("Nieznany klucz składowej pokazuje się surowy, zamiast znikać")
    func unknownKeyFallsBack() throws {
        let odd = try makeSnapshot("2026-08-06", 50, components: """
        {"sleep":50,"parts":{"sleep":[{"key":"nowa_metryka","weight":1,"value":50}]}}
        """).components
        let sleep = try #require(odd.breakdown.first)

        #expect(sleep.parts.first?.label == "nowa_metryka")
    }
}

@Suite("Nowe składowe w rozbiciu")
struct NewPartLabelTests {
    /// Oba składniki opisują rytm snu, ale co innego: jeden długość, drugi porę.
    /// Etykiety muszą to rozróżniać, bo w rozwiniętym wierszu stoją obok siebie.
    @Test("Regularność pory i równa długość mają osobne nazwy")
    func sleepPartsAreDistinct() throws {
        let snapshot = try makeSnapshot("2026-08-07", 80, components: """
        {"sleep":80,"parts":{"sleep":[
          {"key":"duration","weight":0.5,"value":100},
          {"key":"deep","weight":0.2,"value":80},
          {"key":"regularity","weight":0.2,"value":65},
          {"key":"consistency","weight":0.1,"value":0}]}}
        """)
        let sleep = try #require(snapshot.components.breakdown.first)

        #expect(sleep.parts.map(\.label)
            == ["Długość snu", "Sen głęboki", "Regularność pory snu", "Równa długość snu"])
        #expect(sleep.parts.map(\.weight) == [0.5, 0.2, 0.2, 0.1])
    }

    @Test("Skład ciała ma trzy składowe z tkanką tłuszczową")
    func bodyHasThreeParts() throws {
        let snapshot = try makeSnapshot("2026-08-07", 80, components: """
        {"body":86,"parts":{"body":[
          {"key":"whr","weight":0.5,"value":null},
          {"key":"body_fat","weight":0.3,"value":90},
          {"key":"bmi","weight":0.2,"value":86}]}}
        """)
        let body = try #require(snapshot.components.breakdown.first)

        #expect(body.parts.map(\.label) == ["Talia/biodra", "Tkanka tłuszczowa", "BMI"])
        #expect(body.parts.first?.value == nil)
    }
}
