import Foundation

/// Jeden dzień metryk z HealthKit. Kształt 1:1 z wierszem `health_metrics`
/// i z body `POST /api/v1/health/sync`, dlatego klucze są snake_case.
///
/// Wszystko poza datą jest opcjonalne — żaden dzień nie ma kompletu. VO2max
/// Watch przelicza tylko przy outdoor walk/run/hike, waga pojawia się w dniu
/// ważenia, a sen bywa po prostu nie zmierzony.
struct DailyHealthMetrics: Codable, Sendable, Equatable {
    /// "yyyy-MM-dd" w strefie lokalnej — ten sam format co `score_date`.
    let metricDate: String

    // Wydolność i serce
    var vo2max: Double?
    var restingHeartRate: Double?
    var hrvSdnnMs: Double?
    var walkingHeartRate: Double?

    // Sen — doba przypisana do dnia pobudki
    var sleepStartAt: String?
    var sleepEndAt: String?
    var sleepAsleepMinutes: Int?
    var sleepRemMinutes: Int?
    var sleepDeepMinutes: Int?
    var sleepCoreMinutes: Int?
    var sleepAwakeMinutes: Int?
    var sleepRegularityIndex: Double?

    // Ruch
    var steps: Int?
    var exerciseMinutes: Int?
    var activeEnergyKcal: Double?
    var standHours: Int?

    // Skład ciała
    var weightKg: Double?
    var bodyFatPct: Double?
    var leanBodyMassKg: Double?

    // Regeneracja
    var respiratoryRate: Double?
    var spo2Pct: Double?
    var wristTemperatureC: Double?

    init(metricDate: String) {
        self.metricDate = metricDate
    }

    enum CodingKeys: String, CodingKey {
        case metricDate = "metric_date"
        case vo2max
        case restingHeartRate = "resting_heart_rate"
        case hrvSdnnMs = "hrv_sdnn_ms"
        case walkingHeartRate = "walking_heart_rate"
        case sleepStartAt = "sleep_start_at"
        case sleepEndAt = "sleep_end_at"
        case sleepAsleepMinutes = "sleep_asleep_minutes"
        case sleepRemMinutes = "sleep_rem_minutes"
        case sleepDeepMinutes = "sleep_deep_minutes"
        case sleepCoreMinutes = "sleep_core_minutes"
        case sleepAwakeMinutes = "sleep_awake_minutes"
        case sleepRegularityIndex = "sleep_regularity_index"
        case steps
        case exerciseMinutes = "exercise_minutes"
        case activeEnergyKcal = "active_energy_kcal"
        case standHours = "stand_hours"
        case weightKg = "weight_kg"
        case bodyFatPct = "body_fat_pct"
        case leanBodyMassKg = "lean_body_mass_kg"
        case respiratoryRate = "respiratory_rate"
        case spo2Pct = "spo2_pct"
        case wristTemperatureC = "wrist_temperature_c"
    }

    /// Dzień bez jednego pomiaru nie jest wysyłany — serwer i tak by go odrzucił,
    /// a przy backfillu to bywa większość paczki.
    var isEmpty: Bool {
        vo2max == nil && restingHeartRate == nil && hrvSdnnMs == nil && walkingHeartRate == nil
            && sleepStartAt == nil && sleepEndAt == nil && sleepAsleepMinutes == nil
            && sleepRemMinutes == nil && sleepDeepMinutes == nil && sleepCoreMinutes == nil
            && sleepAwakeMinutes == nil && sleepRegularityIndex == nil
            && steps == nil && exerciseMinutes == nil && activeEnergyKcal == nil && standHours == nil
            && weightKg == nil && bodyFatPct == nil && leanBodyMassKg == nil
            && respiratoryRate == nil && spo2Pct == nil && wristTemperatureC == nil
    }
}

/// Formatowanie dat bez `DateFormatter`. HealthKit woła handlery zapytań na
/// własnej kolejce, a `DateFormatter` nie jest `Sendable` — składanie łańcucha
/// z komponentów kalendarza (typ wartościowy) omija problem i jest szybsze.
enum HealthDates {
    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func iso(_ date: Date) -> String { date.formatted(.iso8601) }
}
