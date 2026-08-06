import Foundation
import Testing

@testable import Longevity

@Suite("Ładunek HealthKit")
struct DailyHealthMetricsTests {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    @Test("Dzień bez pomiarów jest pusty")
    func emptyDay() {
        var metrics = DailyHealthMetrics(metricDate: "2026-08-06")
        #expect(metrics.isEmpty)

        metrics.steps = 0
        #expect(!metrics.isEmpty)
    }

    /// Klucze muszą się zgadzać z kolumnami `health_metrics` — literówka nie
    /// wywala żądania, tylko po cichu gubi metrykę.
    @Test("Kodowanie używa snake_case zgodnego ze schematem bazy")
    func encodesSnakeCase() throws {
        var metrics = DailyHealthMetrics(metricDate: "2026-08-06")
        metrics.vo2max = 48.3
        metrics.restingHeartRate = 52
        metrics.hrvSdnnMs = 61.25
        metrics.sleepAsleepMinutes = 431
        metrics.sleepRegularityIndex = 82.5
        metrics.exerciseMinutes = 44
        metrics.weightKg = 78.4
        metrics.wristTemperatureC = 34.12

        let data = try JSONEncoder().encode(metrics)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["metric_date"] as? String == "2026-08-06")
        #expect(json["vo2max"] as? Double == 48.3)
        #expect(json["resting_heart_rate"] as? Double == 52)
        #expect(json["hrv_sdnn_ms"] as? Double == 61.25)
        #expect(json["sleep_asleep_minutes"] as? Int == 431)
        #expect(json["sleep_regularity_index"] as? Double == 82.5)
        #expect(json["exercise_minutes"] as? Int == 44)
        #expect(json["weight_kg"] as? Double == 78.4)
        #expect(json["wrist_temperature_c"] as? Double == 34.12)
    }

    /// Brak pomiaru nie może pojechać jako `null` — serwer scala nowy odczyt ze
    /// starym wierszem, a jawny null wyczyściłby wartość sprzed tygodnia.
    @Test("Brakujące pomiary znikają z JSON-a zamiast lecieć jako null")
    func omitsMissingValues() throws {
        var metrics = DailyHealthMetrics(metricDate: "2026-08-06")
        metrics.steps = 8431

        let data = try JSONEncoder().encode(metrics)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["steps"] as? Int == 8431)
        #expect(json["vo2max"] == nil)
        #expect(json.keys.count == 2)
    }

    @Test("Znaczniki snu kodują się jako ISO 8601")
    func encodesSleepTimestamps() throws {
        var metrics = DailyHealthMetrics(metricDate: "2026-08-06")
        metrics.sleepStartAt = HealthDates.iso(Date(timeIntervalSince1970: 1_785_100_800))

        let data = try JSONEncoder().encode(metrics)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let value = try #require(json["sleep_start_at"] as? String)

        #expect(value.hasSuffix("Z"))
        #expect(ISO8601DateFormatter().date(from: value) != nil)
    }

    @Test("Klucz dnia jest datą lokalną, nie UTC")
    func formatsLocalDay() {
        // 2026-08-06 00:30 czasu warszawskiego to jeszcze 5 sierpnia w UTC.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Self.calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let midnightish = f.date(from: "2026-08-06 00:30")!

        #expect(HealthDates.day(midnightish, calendar: Self.calendar) == "2026-08-06")
    }
}
