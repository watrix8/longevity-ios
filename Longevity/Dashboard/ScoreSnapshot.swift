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

/// Składowa komponentu — to, z czego zrobił się jego wynik.
struct ScorePart: Decodable, Sendable, Equatable {
    let key: String
    let weight: Double
    /// `nil` = brak danych; część jest pomijana, a wagi pozostałych przenormowane.
    let value: Double?
}

/// Jeden wiersz rozbicia pod score'em, razem ze składem.
struct ScoreComponentRow: Sendable, Identifiable, Equatable {
    let id: String
    let label: String
    /// Udział w całym score, 0–1. `nil` dla starych snapshotów bez wag.
    let weight: Double?
    let value: Double
    let parts: [ScorePartRow]

    var hasParts: Bool { !parts.isEmpty }
}

struct ScorePartRow: Sendable, Identifiable, Equatable {
    let id: String
    let label: String
    /// Udział w komponencie, 0–1.
    let weight: Double
    /// `nil` = nie zmierzono; wiersz pokazuje to wprost zamiast zera.
    let value: Double?
}

/// Składniki score v3 — pięć komponentów liczonych z pomiarów.
///
/// Każdy jest OPCJONALNY i to jest istota modelu: komponent bez danych nie
/// wchodzi do score'u, a wagi pozostałych są przenormowane. Zero i brak to
/// dwie różne rzeczy, więc nie sprowadzamy ich do wspólnego fallbacku.
struct ScoreComponents: Decodable, Sendable {
    let sleep: Double?
    let vo2max: Double?
    let body: Double?
    let regeneration: Double?
    let metabolic: Double?

    /// Suma wag komponentów, które miały dane (0–1).
    let coverage: Double?
    let scoreModel: String?

    /// Skład każdego komponentu i wagi — jedno i drugie liczy serwer, aplikacja
    /// tylko renderuje. Opcjonalne, bo snapshoty sprzed tej zmiany ich nie mają.
    let parts: [String: [ScorePart]]?
    let weights: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case sleep, vo2max, body, regeneration, metabolic, coverage, parts, weights
        case scoreModel = "score_model"
    }

    /// Kolejność wg wag z formuły v3. Komponenty bez danych są pomijane —
    /// pasek na zerze czytałby się jak „zawaliłeś", a nie „nie zmierzono".
    var breakdown: [ScoreComponentRow] {
        Self.order.compactMap { key, label in
            guard let value = self[key] else { return nil }
            return ScoreComponentRow(
                id: key,
                label: label,
                weight: weights?[key],
                value: value,
                parts: partRows(for: key)
            )
        }
    }

    /// Etykiety komponentów, których nie dało się policzyć — dashboard mówi
    /// wprost, czego brakuje, zamiast udawać komplet.
    var missing: [String] {
        Self.order.compactMap { key, label in self[key] == nil ? label : nil }
    }

    /// Ile procent wag score faktycznie objął. `nil` dla starych snapshotów.
    var coveragePercent: Int? {
        coverage.map { Int(($0 * 100).rounded()) }
    }

    // MARK: - Słowniki

    private static let order: [(key: String, label: String)] = [
        ("sleep", "Sen"),
        ("vo2max", "VO₂max"),
        ("body", "Ciało"),
        ("regeneration", "Regeneracja"),
        ("metabolic", "Metabolizm"),
    ]

    /// Etykiety składowych. Klucze przychodzą z serwera, nazwy zostają tutaj —
    /// baza nie jest miejscem na polskie napisy.
    private static let partLabels: [String: String] = [
        "duration": "Długość snu",
        "deep": "Sen głęboki",
        // Dwa różne wymiary rytmu i oba wchodzą do wyniku: `consistency` to
        // rozrzut DŁUGOŚCI snu, `regularity` to stałość PORY zasypiania.
        // Można spać co noc osiem godzin, kładąc się o losowych porach.
        "consistency": "Równa długość snu",
        "regularity": "Regularność pory snu",
        "bmi": "BMI",
        "whr": "Talia/biodra",
        "body_fat": "Tkanka tłuszczowa",
        "resting_heart_rate": "Tętno spoczynkowe",
        "hrv_trend": "Trend HRV",
        "glucose_fasting": "Glukoza na czczo",
        "hba1c": "HbA1c",
        "crp": "CRP",
        "lipids": "Lipidy",
    ]

    private subscript(key: String) -> Double? {
        switch key {
        case "sleep": sleep
        case "vo2max": vo2max
        case "body": body
        case "regeneration": regeneration
        case "metabolic": metabolic
        default: nil
        }
    }

    private func partRows(for key: String) -> [ScorePartRow] {
        (parts?[key] ?? []).map { part in
            ScorePartRow(
                id: part.key,
                label: Self.partLabels[part.key] ?? part.key,
                weight: part.weight,
                value: part.value
            )
        }
    }
}
