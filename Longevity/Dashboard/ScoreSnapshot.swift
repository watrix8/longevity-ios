import Foundation

/// Wiersz `score_snapshots` z Supabase. Czytamy tabelę wprost — RLS
/// (`auth.uid() = user_id`) ogranicza wynik do zalogowanego użytkownika.
struct ScoreSnapshot: Decodable, Sendable {
    /// Format "YYYY-MM-DD" — sortuje się leksykograficznie, więc trzymamy String.
    let scoreDate: String
    let scoreTotal: Int
    let components: ScoreComponents

    enum CodingKeys: String, CodingKey {
        case scoreDate = "score_date"
        case scoreTotal = "score_total"
        case components
    }
}

/// Składniki score v2. Wszystko opcjonalne z fallbackiem na 0 — starsze
/// snapshoty (v1) nie mają pól dopisanych w v2, a `components` ma w schemacie
/// default '{}'.
struct ScoreComponents: Decodable, Sendable {
    let sleep: Double
    let activity: Double
    let nutrition: Double
    let stress: Double
    let mood: Double
    let activityWeekMinutes: Double?
    let nutritionSource: String?
    let scoreModel: String?

    enum CodingKeys: String, CodingKey {
        case sleep, activity, nutrition, stress, mood
        case activityWeekMinutes = "activity_week_minutes"
        case nutritionSource = "nutrition_source"
        case scoreModel = "score_model"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sleep = try c.decodeIfPresent(Double.self, forKey: .sleep) ?? 0
        activity = try c.decodeIfPresent(Double.self, forKey: .activity) ?? 0
        nutrition = try c.decodeIfPresent(Double.self, forKey: .nutrition) ?? 0
        stress = try c.decodeIfPresent(Double.self, forKey: .stress) ?? 0
        mood = try c.decodeIfPresent(Double.self, forKey: .mood) ?? 0
        activityWeekMinutes = try c.decodeIfPresent(Double.self, forKey: .activityWeekMinutes)
        nutritionSource = try c.decodeIfPresent(String.self, forKey: .nutritionSource)
        scoreModel = try c.decodeIfPresent(String.self, forKey: .scoreModel)
    }

    /// Kolejność jak w makiecie: etykieta + wartość 0–100.
    var breakdown: [(label: String, value: Double)] {
        [
            ("Sen", sleep),
            ("Aktywność", activity),
            ("Odżywianie", nutrition),
            ("Stres", stress),
            ("Nastrój", mood),
        ]
    }
}
