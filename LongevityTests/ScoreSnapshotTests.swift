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
    @Test("Pełny payload v2 dekoduje wszystkie pola")
    func fullV2Payload() throws {
        let snapshot = try makeSnapshot("2026-08-06", 38, components: """
        {"sleep":50,"activity":0,"nutrition":50,"stress":50,"mood":50,
         "activity_week_minutes":120,"nutrition_source":"checkin_fallback",
         "nutrition_meal_score_avg":null,"score_model":"v2_weekly_activity"}
        """)

        #expect(snapshot.scoreDate == "2026-08-06")
        #expect(snapshot.scoreTotal == 38)
        #expect(snapshot.components.sleep == 50)
        #expect(snapshot.components.activity == 0)
        #expect(snapshot.components.activityWeekMinutes == 120)
        #expect(snapshot.components.nutritionSource == "checkin_fallback")
        #expect(snapshot.components.scoreModel == "v2_weekly_activity")
    }

    /// `components jsonb not null default '{}'` — pusty obiekt musi przejść,
    /// inaczej dashboard wywala się na świeżym wierszu.
    @Test("Puste components nie wywracają dekodowania")
    func emptyComponents() throws {
        let snapshot = try makeSnapshot("2026-08-06", 0, components: "{}")

        #expect(snapshot.components.sleep == 0)
        #expect(snapshot.components.mood == 0)
        #expect(snapshot.components.activityWeekMinutes == nil)
        #expect(snapshot.components.nutritionSource == nil)
        #expect(snapshot.components.scoreModel == nil)
    }

    /// Snapshoty sprzed score v2 nie mają pól dopisanych w v2.
    @Test("Snapshot v1 bez pól v2 dekoduje się poprawnie")
    func legacyV1Payload() throws {
        let snapshot = try makeSnapshot("2026-03-07", 61, components: """
        {"sleep":75,"activity":50,"nutrition":25,"stress":100,"mood":75}
        """)

        #expect(snapshot.components.sleep == 75)
        #expect(snapshot.components.stress == 100)
        #expect(snapshot.components.activityWeekMinutes == nil)
        #expect(snapshot.components.scoreModel == nil)
    }

    @Test("Breakdown zachowuje kolejność i etykiety")
    func breakdownOrder() throws {
        let snapshot = try makeSnapshot("2026-08-06", 38, components: """
        {"sleep":1,"activity":2,"nutrition":3,"stress":4,"mood":5}
        """)

        #expect(snapshot.components.breakdown.map(\.label)
            == ["Sen", "Aktywność", "Odżywianie", "Stres", "Nastrój"])
        #expect(snapshot.components.breakdown.map(\.value) == [1, 2, 3, 4, 5])
    }

    @Test("Liczby całkowite z JSON-a wchodzą w Double")
    func integerCoercion() throws {
        let snapshot = try makeSnapshot("2026-08-06", 38, components: #"{"sleep":84}"#)
        #expect(snapshot.components.sleep == 84.0)
    }
}
