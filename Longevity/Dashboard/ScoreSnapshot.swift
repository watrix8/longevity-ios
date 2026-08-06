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

    enum CodingKeys: String, CodingKey {
        case sleep, vo2max, body, regeneration, metabolic, coverage
        case scoreModel = "score_model"
    }

    /// Kolejność wg wag z formuły v3. Komponenty bez danych są pomijane —
    /// pasek na zerze czytałby się jak „zawaliłeś", a nie „nie zmierzono".
    var breakdown: [(label: String, value: Double)] {
        [
            ("Sen", sleep),
            ("VO₂max", vo2max),
            ("Ciało", body),
            ("Regeneracja", regeneration),
            ("Metabolizm", metabolic),
        ].compactMap { label, value in
            value.map { (label: label, value: $0) }
        }
    }

    /// Etykiety komponentów, których nie dało się policzyć — dashboard mówi
    /// wprost, czego brakuje, zamiast udawać komplet.
    var missing: [String] {
        [
            ("Sen", sleep),
            ("VO₂max", vo2max),
            ("Ciało", body),
            ("Regeneracja", regeneration),
            ("Metabolizm", metabolic),
        ].compactMap { label, value in
            value == nil ? label : nil
        }
    }

    /// Ile procent wag score faktycznie objął. `nil` dla starych snapshotów.
    var coveragePercent: Int? {
        coverage.map { Int(($0 * 100).rounded()) }
    }
}
