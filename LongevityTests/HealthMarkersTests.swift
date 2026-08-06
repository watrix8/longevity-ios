import Foundation
import Testing

@testable import Longevity

@Suite("Ręczny wpis markerów")
struct HealthMarkersTests {
    /// Klawiatura numeryczna przy polskiej lokalizacji daje przecinek,
    /// a `Double("92,5")` zwraca nil — bez tego wpis cicho przepadał.
    @Test("Przecinek dziesiętny jest akceptowany")
    func parsesComma() {
        #expect(HealthMarkers.parse("92,5") == 92.5)
        #expect(HealthMarkers.parse("92.5") == 92.5)
        #expect(HealthMarkers.parse(" 47 ") == 47)
    }

    @Test("Puste pole daje nil, nie zero")
    func parsesEmpty() {
        #expect(HealthMarkers.parse("") == nil)
        #expect(HealthMarkers.parse("   ") == nil)
        #expect(HealthMarkers.parse("abc") == nil)
    }

    @Test("Pusty formularz jest pusty")
    func detectsEmpty() {
        #expect(HealthMarkers().isEmpty)

        var markers = HealthMarkers()
        markers.hipCm = 101
        #expect(!markers.isEmpty)
    }

    @Test("Potwierdzenie pokazuje wartości, nie nazwy kolumn")
    func buildsSummary() {
        var markers = HealthMarkers()
        markers.vo2max = 47.2
        markers.waistCm = 92
        markers.hipCm = 101

        #expect(markers.summary == "VO₂max 47.2 · talia 92 cm · biodra 101 cm")
    }

    /// Pola niewypełnione muszą zniknąć z JSON-a. Jawny null wyczyściłby
    /// wcześniejszy wpis, bo serwer scala żądanie z zapisanym wierszem.
    @Test("Niewypełnione pola nie trafiają do żądania")
    func omitsEmptyFields() throws {
        var markers = HealthMarkers()
        markers.vo2max = 47.2

        let data = try JSONEncoder().encode(markers)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["vo2max"] as? Double == 47.2)
        #expect(json.keys.count == 1)
    }

    @Test("Klucze zgadzają się z kolumnami health_metrics")
    func encodesSnakeCase() throws {
        var markers = HealthMarkers()
        markers.hrvSdnnMs = 61
        markers.restingHeartRate = 48
        markers.bodyFatPct = 18.4
        markers.leanBodyMassKg = 66.2
        markers.waistCm = 92
        markers.hipCm = 101

        let data = try JSONEncoder().encode(markers)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["hrv_sdnn_ms"] as? Double == 61)
        #expect(json["resting_heart_rate"] as? Double == 48)
        #expect(json["body_fat_pct"] as? Double == 18.4)
        #expect(json["lean_body_mass_kg"] as? Double == 66.2)
        #expect(json["waist_cm"] as? Double == 92)
        #expect(json["hip_cm"] as? Double == 101)
    }
}

@Suite("Wskaźniki pochodne w trendach")
@MainActor
struct DerivedMetricTests {
    @Test("Udział snu głębokiego liczy się od czasu snu")
    func deepShare() {
        #expect(TrendsViewModel.deepSleepShare(deep: 90, asleep: 450) == 20)
        #expect(TrendsViewModel.deepSleepShare(deep: 55, asleep: 500) == 11)
    }

    @Test("Brak którejkolwiek składowej daje nil")
    func deepShareMissing() {
        #expect(TrendsViewModel.deepSleepShare(deep: nil, asleep: 450) == nil)
        #expect(TrendsViewModel.deepSleepShare(deep: 90, asleep: nil) == nil)
        #expect(TrendsViewModel.deepSleepShare(deep: 90, asleep: 0) == nil)
    }

    @Test("WHR liczy się z obu obwodów")
    func whr() {
        #expect(TrendsViewModel.waistToHipRatio(waist: 92, hip: 101) == 0.91)
        #expect(TrendsViewModel.waistToHipRatio(waist: 100, hip: 100) == 1)
    }

    /// Biodra przychodzą wyłącznie z ręcznego wpisu, więc sam obwód talii
    /// z HealthKit nie wystarcza — i nie wolno tego udawać.
    @Test("Sama talia nie daje WHR")
    func whrNeedsBoth() {
        #expect(TrendsViewModel.waistToHipRatio(waist: 92, hip: nil) == nil)
        #expect(TrendsViewModel.waistToHipRatio(waist: nil, hip: 101) == nil)
        #expect(TrendsViewModel.waistToHipRatio(waist: 92, hip: 0) == nil)
    }
}
