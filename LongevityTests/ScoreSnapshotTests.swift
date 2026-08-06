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
