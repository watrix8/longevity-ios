import Foundation

/// Markery wpisywane ręcznie w czacie — body `PATCH /api/v1/health/sync`.
///
/// Węższy zestaw niż `DailyHealthMetrics`: tu są tylko rzeczy, których HealthKit
/// nie dostarcza albo dostarcza wybiórczo. Kroków ani kalorii nikt nie będzie
/// przepisywał z palca, a minuty ruchu mają w czacie własną akcję.
///
/// Serwer zapamiętuje, które pola przyszły tą drogą, i kolejny sync z zegarka
/// ich nie nadpisze.
struct HealthMarkers: Encodable, Sendable, Equatable {
    var vo2max: Double?
    var hrvSdnnMs: Double?
    var restingHeartRate: Double?
    var weightKg: Double?
    var bodyFatPct: Double?
    var leanBodyMassKg: Double?
    var waistCm: Double?
    /// Jedyna droga do bazy — HealthKit nie zna obwodu bioder.
    var hipCm: Double?

    enum CodingKeys: String, CodingKey {
        case vo2max
        case hrvSdnnMs = "hrv_sdnn_ms"
        case restingHeartRate = "resting_heart_rate"
        case weightKg = "weight_kg"
        case bodyFatPct = "body_fat_pct"
        case leanBodyMassKg = "lean_body_mass_kg"
        case waistCm = "waist_cm"
        case hipCm = "hip_cm"
    }

    var isEmpty: Bool {
        vo2max == nil && hrvSdnnMs == nil && restingHeartRate == nil && weightKg == nil
            && bodyFatPct == nil && leanBodyMassKg == nil && waistCm == nil && hipCm == nil
    }

    /// Treść potwierdzenia w czacie. Budowana lokalnie, a nie z odpowiedzi
    /// serwera, bo serwer odsyła nazwy kolumn — użytkownik ma zobaczyć wartości.
    var summary: String {
        var parts: [String] = []
        if let vo2max { parts.append("VO₂max \(Self.format(vo2max))") }
        if let hrvSdnnMs { parts.append("HRV \(Self.format(hrvSdnnMs)) ms") }
        if let restingHeartRate { parts.append("tętno \(Self.format(restingHeartRate)) bpm") }
        if let weightKg { parts.append("waga \(Self.format(weightKg)) kg") }
        if let bodyFatPct { parts.append("tłuszcz \(Self.format(bodyFatPct))%") }
        if let leanBodyMassKg { parts.append("masa beztł. \(Self.format(leanBodyMassKg)) kg") }
        if let waistCm { parts.append("talia \(Self.format(waistCm)) cm") }
        if let hipCm { parts.append("biodra \(Self.format(hipCm)) cm") }
        return parts.joined(separator: " · ")
    }

    /// Klawiatura numeryczna daje przecinek przy polskiej lokalizacji,
    /// a `Double("92,5")` zwraca nil.
    static func parse(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        return cleaned.isEmpty ? nil : Double(cleaned)
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
