import Foundation
import Observation

struct SeriesPoint: Sendable {
    let date: String
    let value: Double
}

/// Jedna karta metryki — odpowiednik `MetricCard` z `app/trends/page.tsx`.
struct Metric: Identifiable, Sendable {
    let id: String
    let title: String
    let unit: String
    /// Rosnąco po dacie.
    let points: [SeriesPoint]
    /// Czy wyższa wartość jest lepsza (waga i stres mają odwrotnie).
    let positiveHigher: Bool

    var last: Double? { points.last?.value }
    var previous: Double? { points.dropLast().last?.value }
    var avg7: Double? { Self.average(points.suffix(7).map(\.value)) }
    var avg30: Double? { Self.average(points.map(\.value)) }

    /// Strzałka jak w webie: porównanie z poprzednim punktem, odwrócona
    /// dla metryk, w których mniej znaczy lepiej.
    var arrow: String {
        guard let last, let previous else { return "→" }
        let raw = last > previous ? "↗" : (last < previous ? "↘" : "→")
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

private struct CheckinRow: Decodable {
    let checkinDate: String
    let sleepQuality: Double
    let nutritionQuality: Double
    let stressLevel: Double
    let mood: Double
    enum CodingKeys: String, CodingKey {
        case checkinDate = "checkin_date"
        case sleepQuality = "sleep_quality"
        case nutritionQuality = "nutrition_quality"
        case stressLevel = "stress_level"
        case mood
    }
}

private struct ActivityRow: Decodable {
    let loggedDate: String
    let activityMinutes: Double
    enum CodingKeys: String, CodingKey {
        case loggedDate = "logged_date", activityMinutes = "activity_minutes"
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
            async let checkins: [CheckinRow] = db.from("daily_checkins")
                .select("checkin_date, sleep_quality, nutrition_quality, stress_level, mood")
                .gte("checkin_date", value: from)
                .order("checkin_date").execute().value
            async let activity: [ActivityRow] = db.from("activity_logs")
                .select("logged_date, activity_minutes")
                .gte("logged_date", value: from)
                .order("logged_date").execute().value
            async let meals: [MealRow] = db.from("meal_logs")
                .select("logged_date, kcal_min, kcal_max")
                .gte("logged_date", value: from)
                .order("logged_date").execute().value

            state = .loaded(
                try await Self.build(
                    scores: scores, weights: weights, checkins: checkins,
                    activity: activity, meals: meals
                )
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private static func build(
        scores: [ScoreRow],
        weights: [WeightRow],
        checkins: [CheckinRow],
        activity: [ActivityRow],
        meals: [MealRow]
    ) -> [Metric] {
        let kcalPoints = dailyKcal(meals.map { ($0.loggedDate, $0.kcalMin, $0.kcalMax) })

        return [
            Metric(id: "score", title: "Longevity Score", unit: "/100", positiveHigher: true,
                   points: scores.map { SeriesPoint(date: $0.scoreDate, value: $0.scoreTotal) }),
            Metric(id: "weight", title: "Waga", unit: "kg", positiveHigher: false,
                   points: weights.map { SeriesPoint(date: $0.measuredAt, value: $0.weightKg) }),
            Metric(id: "sleep", title: "Sen", unit: "/5", positiveHigher: true,
                   points: checkins.map { SeriesPoint(date: $0.checkinDate, value: $0.sleepQuality) }),
            Metric(id: "activity", title: "Ruch", unit: "min", positiveHigher: true,
                   points: activity.map { SeriesPoint(date: $0.loggedDate, value: $0.activityMinutes) }),
            Metric(id: "nutrition", title: "Odżywianie", unit: "/5", positiveHigher: true,
                   points: checkins.map { SeriesPoint(date: $0.checkinDate, value: $0.nutritionQuality) }),
            Metric(id: "stress", title: "Stres", unit: "/5", positiveHigher: false,
                   points: checkins.map { SeriesPoint(date: $0.checkinDate, value: $0.stressLevel) }),
            Metric(id: "mood", title: "Nastrój", unit: "/5", positiveHigher: true,
                   points: checkins.map { SeriesPoint(date: $0.checkinDate, value: $0.mood) }),
            Metric(id: "kcal", title: "Kalorie (est.)", unit: "kcal", positiveHigher: true,
                   points: kcalPoints),
        ]
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
    init(id: String, title: String, unit: String, positiveHigher: Bool, points: [SeriesPoint]) {
        self.id = id
        self.title = title
        self.unit = unit
        self.positiveHigher = positiveHigher
        self.points = points.sorted { $0.date < $1.date }
    }
}
