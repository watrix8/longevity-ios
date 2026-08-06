import Foundation
import Observation

struct SeriesPoint: Sendable {
    let date: String
    let value: Double
}

/// Skąd metryka bierze się w score. Kafelek bez tej informacji wygląda tak
/// samo ważnie jak ten, który realnie waży 30% wyniku.
enum MetricRole: Sendable, Equatable {
    /// Wchodzi do komponentu score'u — etykieta komponentu i jego waga.
    case feeds(component: String, weight: Double)
    /// Nie wchodzi do wyniku, ale opisuje dzień.
    case informational
    /// Sam wynik — nie jest ani składnikiem, ani metryką poboczną.
    case total

    var badge: String {
        switch self {
        case .feeds(let component, let weight):
            "\(component) · \(Int((weight * 100).rounded()))%"
        case .informational:
            "poza wynikiem"
        case .total:
            "wynik"
        }
    }

    var countsToScore: Bool {
        if case .feeds = self { return true }
        return false
    }
}

/// Jedna karta metryki — odpowiednik `MetricCard` z `app/trends/page.tsx`.
struct Metric: Identifiable, Sendable {
    let id: String
    let title: String
    let unit: String
    /// Rosnąco po dacie.
    let points: [SeriesPoint]
    /// Czy wyższa wartość jest lepsza (waga, WHR i tętno spoczynkowe odwrotnie).
    let positiveHigher: Bool
    let role: MetricRole

    var last: Double? { points.last?.value }
    var previous: Double? { points.dropLast().last?.value }
    var avg7: Double? { Self.average(points.suffix(7).map(\.value)) }
    var avg30: Double? { Self.average(points.map(\.value)) }

    /// Strzałka jak w webie: porównanie z poprzednim punktem, odwrócona
    /// dla metryk, w których mniej znaczy lepiej.
    var arrow: String { arrow(at: points.indices.last) }

    /// Kierunek dla dowolnego dnia — przy przeciąganiu po wykresie strzałka ma
    /// opisywać wskazany punkt, a nie w kółko ostatni.
    func arrow(at index: Int?) -> String {
        guard let index, points.indices.contains(index), index > 0 else { return "→" }
        let current = points[index].value
        let earlier = points[index - 1].value
        let raw = current > earlier ? "↗" : (current < earlier ? "↘" : "→")
        guard !positiveHigher else { return raw }
        return raw == "↗" ? "↘" : (raw == "↘" ? "↗" : "→")
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return (values.reduce(0, +) / Double(values.count) * 10).rounded() / 10
    }
}

// MARK: - Wiersze z Supabase

private struct ScoreRow: Decodable {
    let scoreDate: String
    let scoreTotal: Double
    enum CodingKeys: String, CodingKey {
        case scoreDate = "score_date", scoreTotal = "score_total"
    }
}

private struct WeightRow: Decodable {
    let measuredAt: String
    let weightKg: Double
    enum CodingKeys: String, CodingKey {
        case measuredAt = "measured_at", weightKg = "weight_kg"
    }
}


private struct ActivityRow: Decodable {
    let loggedDate: String
    let activityMinutes: Double
    enum CodingKeys: String, CodingKey {
        case loggedDate = "logged_date", activityMinutes = "activity_minutes"
    }
}

/// Podzbiór `health_metrics` potrzebny na wykresy. Reszta kolumn (fazy snu poza
/// deep, SpO2, temperatura) jest w bazie, ale na razie nie ma własnego kafelka.
private struct HealthRow: Decodable {
    let metricDate: String
    let sleepAsleepMinutes: Int?
    let sleepDeepMinutes: Int?
    let sleepRegularityIndex: Double?
    let vo2max: Double?
    let restingHeartRate: Double?
    let hrvSdnnMs: Double?
    let steps: Int?
    let bodyFatPct: Double?
    let waistCm: Double?
    let hipCm: Double?

    enum CodingKeys: String, CodingKey {
        case metricDate = "metric_date"
        case sleepAsleepMinutes = "sleep_asleep_minutes"
        case sleepDeepMinutes = "sleep_deep_minutes"
        case sleepRegularityIndex = "sleep_regularity_index"
        case vo2max
        case restingHeartRate = "resting_heart_rate"
        case hrvSdnnMs = "hrv_sdnn_ms"
        case steps
        case bodyFatPct = "body_fat_pct"
        case waistCm = "waist_cm"
        case hipCm = "hip_cm"
    }
}

private struct MealRow: Decodable {
    let loggedDate: String
    let kcalMin: Double?
    let kcalMax: Double?
    enum CodingKeys: String, CodingKey {
        case loggedDate = "logged_date", kcalMin = "kcal_min", kcalMax = "kcal_max"
    }
}

@MainActor
@Observable
final class TrendsViewModel {
    enum State {
        case loading
        case loaded([Metric])
        case failed(String)
    }

    private(set) var state: State

    /// Okno jak `DAYS_WINDOW` w webie.
    private let daysWindow = 30

    init(state: State = .loading) {
        self.state = state
    }

    func load() async {
        do {
            let from = Self.isoDate(daysAgo: daysWindow)
            let db = AppSupabase.client

            async let scores: [ScoreRow] = db.from("score_snapshots")
                .select("score_date, score_total")
                .gte("score_date", value: from)
                .order("score_date").execute().value
            async let weights: [WeightRow] = db.from("weight_log")
                .select("measured_at, weight_kg")
                .gte("measured_at", value: from)
                .order("measured_at").execute().value
            async let activity: [ActivityRow] = db.from("activity_logs")
                .select("logged_date, activity_minutes")
                .gte("logged_date", value: from)
                .order("logged_date").execute().value
            async let meals: [MealRow] = db.from("meal_logs")
                .select("logged_date, kcal_min, kcal_max")
                .gte("logged_date", value: from)
                .order("logged_date").execute().value
            async let health: [HealthRow] = db.from("health_metrics")
                .select("""
                    metric_date, sleep_asleep_minutes, sleep_deep_minutes, \
                    sleep_regularity_index, vo2max, resting_heart_rate, hrv_sdnn_ms, \
                    steps, body_fat_pct, waist_cm, hip_cm
                    """)
                .gte("metric_date", value: from)
                .order("metric_date").execute().value

            state = .loaded(
                try await Self.build(
                    scores: scores, weights: weights,
                    activity: activity, meals: meals, health: health
                )
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Kolejność kafelków idzie za wagami z formuły v3: najpierw score, potem
    /// sen (30%), wydolność (25%), skład ciała (20%), regeneracja (15%),
    /// a na końcu ruch i posiłki — v3 ich nie punktuje, ale opisują dzień.
    ///
    /// Metryki bez ani jednego punktu są odsiewane — kafelek metryki, której
    /// nigdy nie zmierzono, nie niesie żadnej informacji. Pojawi się sam, gdy
    /// pierwsza wartość wejdzie z zegarka albo z „Pomiarów" w czacie.
    private static func build(
        scores: [ScoreRow],
        weights: [WeightRow],
        activity: [ActivityRow],
        meals: [MealRow],
        health: [HealthRow]
    ) -> [Metric] {
        let kcalPoints = dailyKcal(meals.map { ($0.loggedDate, $0.kcalMin, $0.kcalMax) })

        return [
            Metric(id: "score", title: "Longevity Score", unit: "/100", positiveHigher: true, role: .total,
                   points: scores.map { SeriesPoint(date: $0.scoreDate, value: $0.scoreTotal) }),

            // Sen — 30% w v3
            Metric(id: "sleep_hours", title: "Sen", unit: "h", positiveHigher: true, role: .feeds(component: "Sen", weight: 0.30),
                   points: series(health) { $0.sleepAsleepMinutes.map { round1(Double($0) / 60) } }),
            Metric(id: "sleep_deep", title: "Sen głęboki", unit: "%", positiveHigher: true, role: .feeds(component: "Sen", weight: 0.30),
                   points: series(health) {
                       deepSleepShare(deep: $0.sleepDeepMinutes, asleep: $0.sleepAsleepMinutes)
                   }),
            Metric(id: "sleep_regularity", title: "Regularność snu (SRI)", unit: "", positiveHigher: true, role: .informational,
                   points: series(health) { $0.sleepRegularityIndex }),

            // Wydolność — 25%
            Metric(id: "vo2max", title: "VO₂max", unit: "ml/kg/min", positiveHigher: true, role: .feeds(component: "VO₂max", weight: 0.25),
                   points: series(health) { $0.vo2max }),

            // Skład ciała — 20%
            Metric(id: "weight", title: "Waga", unit: "kg", positiveHigher: false, role: .feeds(component: "Ciało", weight: 0.20),
                   points: weights.map { SeriesPoint(date: $0.measuredAt, value: $0.weightKg) }),
            Metric(id: "whr", title: "WHR (talia/biodra)", unit: "", positiveHigher: false, role: .feeds(component: "Ciało", weight: 0.20),
                   points: series(health) { waistToHipRatio(waist: $0.waistCm, hip: $0.hipCm) }),
            Metric(id: "body_fat", title: "Tkanka tłuszczowa", unit: "%", positiveHigher: false, role: .informational,
                   points: series(health) { $0.bodyFatPct }),

            // Regeneracja — 15%
            Metric(id: "resting_hr", title: "Tętno spoczynkowe", unit: "bpm", positiveHigher: false, role: .feeds(component: "Regeneracja", weight: 0.15),
                   points: series(health) { $0.restingHeartRate }),
            Metric(id: "hrv", title: "HRV (SDNN)", unit: "ms", positiveHigher: true, role: .feeds(component: "Regeneracja", weight: 0.15),
                   points: series(health) { $0.hrvSdnnMs }),

            // Ruch
            Metric(id: "steps", title: "Kroki", unit: "", positiveHigher: true, role: .informational,
                   points: series(health) { $0.steps.map(Double.init) }),
            Metric(id: "activity", title: "Ruch", unit: "min", positiveHigher: true, role: .informational,
                   points: activity.map { SeriesPoint(date: $0.loggedDate, value: $0.activityMinutes) }),

            Metric(id: "kcal", title: "Kalorie (est.)", unit: "kcal", positiveHigher: true, role: .informational,
                   points: kcalPoints),
        ].filter { !$0.points.isEmpty }
    }

    /// `health_metrics` ma prawie wszystkie kolumny opcjonalne, więc każdy
    /// szereg powstaje z pominięciem dni bez pomiaru.
    private static func series(
        _ rows: [HealthRow],
        _ value: (HealthRow) -> Double?
    ) -> [SeriesPoint] {
        rows.compactMap { row in
            value(row).map { SeriesPoint(date: row.metricDate, value: $0) }
        }
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    /// Udział snu głębokiego w całości snu. Internal, nie private — razem z WHR
    /// to jedyne miejsca w tym pliku, gdzie coś się liczy, a nie przepisuje.
    ///
    /// Mianownikiem jest czas SNU, nie czas w łóżku — inaczej wynik zależałby od
    /// tego, jak długo ktoś czyta przed zaśnięciem.
    static func deepSleepShare(deep: Int?, asleep: Int?) -> Double? {
        guard let deep, let asleep, asleep > 0 else { return nil }
        return round1(Double(deep) / Double(asleep) * 100)
    }

    /// Waist-to-hip ratio. Biodra mogą przyjść tylko z ręcznego wpisu, więc
    /// najczęstszym wynikiem jest `nil` i to jest poprawne zachowanie.
    static func waistToHipRatio(waist: Double?, hip: Double?) -> Double? {
        guard let waist, let hip, hip > 0 else { return nil }
        return (waist / hip * 100).rounded() / 100
    }

    /// Kalorie: środek widełek kcal zsumowany per dzień — ta sama arytmetyka
    /// co `kcalMidSum` w `app/trends/page.tsx`. Wydzielone i internal, żeby
    /// dało się przetestować bez wystawiania typów wierszy z Supabase.
    static func dailyKcal(_ meals: [(date: String, min: Double?, max: Double?)]) -> [SeriesPoint] {
        var byDay: [String: Double] = [:]
        for meal in meals {
            byDay[meal.date, default: 0] += ((meal.min ?? 0) + (meal.max ?? 0)) / 2
        }
        return byDay
            .sorted { $0.key < $1.key }
            .map { SeriesPoint(date: $0.key, value: $0.value.rounded()) }
    }

    private static func isoDate(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

extension Metric {
    /// Sortowanie po dacie jest w inicjalizatorze, bo szeregi sklejają się
    /// z kilku tabel i nie wszystkie przychodzą uporządkowane.
    init(
        id: String,
        title: String,
        unit: String,
        positiveHigher: Bool,
        role: MetricRole,
        points: [SeriesPoint]
    ) {
        self.id = id
        self.title = title
        self.unit = unit
        self.positiveHigher = positiveHigher
        self.role = role
        self.points = points.sorted { $0.date < $1.date }
    }
}
