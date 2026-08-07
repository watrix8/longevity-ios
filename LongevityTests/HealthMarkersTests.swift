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

@Suite("Odczyt dnia z wykresu")
struct ChartGeometryTests {
    private static let size = CGSize(width: 300, height: 92)
    private static let values: [Double] = [10, 40, 25, 60, 30]

    private static var geometry: ChartGeometry {
        ChartGeometry(values: values, size: size)
    }

    @Test("Pierwszy punkt siedzi na lewej krawędzi, ostatni na prawej")
    func spansFullWidth() {
        #expect(Self.geometry.point(at: 0).x == 0)
        #expect(Self.geometry.point(at: Self.values.count - 1).x == Self.size.width)
    }

    /// To jest test, dla którego geometria jest osobnym typem: kropka pod palcem
    /// musi trafiać dokładnie tam, gdzie narysowana jest linia.
    @Test("Trafienie w narysowany punkt zwraca jego indeks")
    func hitTestMatchesDrawing() {
        for index in Self.values.indices {
            let x = Self.geometry.point(at: index).x
            #expect(Self.geometry.index(atX: x) == index)
        }
    }

    @Test("Wybierany jest punkt najbliższy, nie ten po lewej")
    func snapsToNearest() {
        let step = Self.size.width / CGFloat(Self.values.count - 1)

        #expect(Self.geometry.index(atX: step * 0.4) == 0)
        #expect(Self.geometry.index(atX: step * 0.6) == 1)
    }

    @Test("Poza wykresem przywiera do skrajnego dnia")
    func clampsOutside() {
        #expect(Self.geometry.index(atX: -50) == 0)
        #expect(Self.geometry.index(atX: 5000) == Self.values.count - 1)
    }

    @Test("Wyższa wartość leży wyżej, czyli ma mniejsze y")
    func higherValueSitsHigher() {
        #expect(Self.geometry.point(at: 3).y < Self.geometry.point(at: 0).y)
    }

    @Test("Jeden punkt albo zero punktów nie wywraca wyliczeń")
    func degenerateInputs() {
        #expect(ChartGeometry(values: [], size: Self.size).index(atX: 100) == 0)
        #expect(ChartGeometry(values: [5], size: Self.size).index(atX: 100) == 0)
        #expect(ChartGeometry(values: [], size: Self.size).point(at: 0) == .zero)
    }
}

@Suite("Źródła danych z HealthKit")
@MainActor
struct MetricSourceTests {
    @Test("Jedno źródło nie jest konfliktem")
    func singleSource() throws {
        let summary = try #require(
            HealthSyncModel.summarize([
                ["steps": ["Garmin Connect"], "sleep": ["Garmin Connect"]],
                ["steps": ["Garmin Connect"]],
            ])
        )

        #expect(summary.names == ["Garmin Connect"])
        #expect(!summary.hasConflict)
    }

    /// Sedno tej funkcji: dzień, w którym do jednej metryki piszą dwa
    /// urządzenia. Kroki i kalorie mogą się wtedy zsumować, a tętno uśrednić
    /// między różnymi metodami pomiaru.
    @Test("Dwa urządzenia przy jednej metryce to konflikt")
    func detectsConflict() throws {
        let summary = try #require(
            HealthSyncModel.summarize([
                ["steps": ["Garmin Connect", "Apple Watch"], "sleep": ["Apple Watch"]],
            ])
        )

        #expect(summary.names == ["Apple Watch", "Garmin Connect"])
        #expect(summary.conflicting == ["steps"])
        #expect(summary.hasConflict)
    }

    /// Dwa źródła w bazie, ale każde przy innej metryce — to normalny stan
    /// przejściowy, a nie dublowanie wartości.
    @Test("Różne źródła przy różnych metrykach to nie konflikt")
    func differentMetricsDifferentSources() throws {
        let summary = try #require(
            HealthSyncModel.summarize([
                ["steps": ["Apple Watch"], "sleep": ["Garmin Connect"]],
            ])
        )

        #expect(summary.names.count == 2)
        #expect(!summary.hasConflict)
    }

    @Test("Konflikt widać także wtedy, gdy źródła rozkładają się na różne dni")
    func conflictAcrossDays() throws {
        let summary = try #require(
            HealthSyncModel.summarize([
                ["steps": ["Apple Watch"]],
                ["steps": ["Garmin Connect"]],
            ])
        )

        #expect(summary.conflicting == ["steps"])
    }

    @Test("Brak danych o źródłach daje nil, nie pustą listę")
    func emptyInput() {
        #expect(HealthSyncModel.summarize([]) == nil)
        #expect(HealthSyncModel.summarize([[:]]) == nil)
    }
}
