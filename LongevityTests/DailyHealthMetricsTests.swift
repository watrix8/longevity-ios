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

        // Zero to pomiar, nie brak pomiaru — dzień bez ani jednego kroku jest
        // informacją i musi pojechać na serwer.
        metrics.steps = 0
        #expect(!metrics.isEmpty)
    }

    /// Każde pole ustawiane pojedynczo, bo `isEmpty` to ręcznie pisana koniunkcja
    /// dwudziestu kilku warunków. Pominięcie jednego oznacza dzień, który apka
    /// po cichu wyrzuca zamiast wysłać.
    private static let setters: [(String, @Sendable (inout DailyHealthMetrics) -> Void)] = [
        ("vo2max", { $0.vo2max = 47 }),
        ("resting_heart_rate", { $0.restingHeartRate = 48 }),
        ("hrv_sdnn_ms", { $0.hrvSdnnMs = 61 }),
        ("walking_heart_rate", { $0.walkingHeartRate = 96 }),
        ("sleep_start_at", { $0.sleepStartAt = "2026-08-05T21:00:00Z" }),
        ("sleep_end_at", { $0.sleepEndAt = "2026-08-06T05:00:00Z" }),
        ("sleep_asleep_minutes", { $0.sleepAsleepMinutes = 431 }),
        ("sleep_rem_minutes", { $0.sleepRemMinutes = 82 }),
        ("sleep_deep_minutes", { $0.sleepDeepMinutes = 55 }),
        ("sleep_core_minutes", { $0.sleepCoreMinutes = 294 }),
        ("sleep_awake_minutes", { $0.sleepAwakeMinutes = 30 }),
        ("sleep_segments", {
            $0.sleepSegments = [
                SleepSegmentPayload(stage: "core", start: "2026-08-05T21:00:00Z", end: "2026-08-06T02:00:00Z")
            ]
        }),
        ("steps", { $0.steps = 8431 }),
        ("exercise_minutes", { $0.exerciseMinutes = 44 }),
        ("active_energy_kcal", { $0.activeEnergyKcal = 620 }),
        ("stand_hours", { $0.standHours = 11 }),
        ("weight_kg", { $0.weightKg = 83.1 }),
        ("body_fat_pct", { $0.bodyFatPct = 18.4 }),
        ("lean_body_mass_kg", { $0.leanBodyMassKg = 66.2 }),
        ("waist_cm", { $0.waistCm = 92 }),
        ("hip_cm", { $0.hipCm = 101 }),
        ("respiratory_rate", { $0.respiratoryRate = 14.2 }),
        ("spo2_pct", { $0.spo2Pct = 97 }),
        ("wrist_temperature_c", { $0.wristTemperatureC = 34.12 }),
    ]

    @Test("Każde pole z osobna wystarcza, żeby dzień nie był pusty")
    func everyFieldCounts() {
        for (name, apply) in Self.setters {
            var metrics = DailyHealthMetrics(metricDate: "2026-08-06")
            apply(&metrics)
            #expect(!metrics.isEmpty, "isEmpty nie uwzględnia pola \(name)")
        }
    }

    /// Strażnik listy powyżej. Po dodaniu kolumny ten test pada pierwszy
    /// i przypomina, że `isEmpty` też trzeba rozszerzyć.
    @Test("Lista pól pokrywa wszystkie kolumny payloadu")
    func settersCoverEveryColumn() {
        let covered = Set(Self.setters.map(\.0))
        let all = Set(DailyHealthMetrics.CodingKeys.allCases.map(\.rawValue))
            // `metric_sources` celowo poza `isEmpty`: same nazwy urządzeń bez
            // ani jednego pomiaru nie opisują dnia i nie ma po co ich wysyłać.
            .subtracting(["metric_date", "metric_sources"])

        #expect(covered == all, "nieobjęte testem: \(all.subtracting(covered).sorted())")
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
