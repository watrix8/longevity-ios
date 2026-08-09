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

/// Składniki score v3 — cztery komponenty liczone z pomiarów.
///
/// Każdy jest OPCJONALNY i to jest istota modelu: komponent bez danych nie
/// wchodzi do score'u, a wagi pozostałych są przenormowane. Zero i brak to
/// dwie różne rzeczy, więc nie sprowadzamy ich do wspólnego fallbacku.
///
/// Piątym był „metabolic" z markerów krwi i wypadł razem z formułą: badanie
/// robione raz na pół roku wchodziło do KAŻDEGO kolejnego dnia jako stała.
/// Snapshoty przeliczono backfillem, więc klucz nie przychodzi już z serwera —
/// a gdyby przyszedł ze starego wiersza, `Decodable` go po prostu pominie.
struct ScoreComponents: Decodable, Sendable {
    let sleep: Double?
    let vo2max: Double?
    let body: Double?
    let regeneration: Double?

    /// Suma wag komponentów, które miały dane (0–1).
    let coverage: Double?
    let scoreModel: String?

    /// Skład każdego komponentu i wagi — jedno i drugie liczy serwer, aplikacja
    /// tylko renderuje. Opcjonalne, bo snapshoty sprzed tej zmiany ich nie mają.
    let parts: [String: [ScorePart]]?
    let weights: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case sleep, vo2max, body, regeneration, coverage, parts, weights
        case scoreModel = "score_model"
    }

    /// Kolejność wg wag z formuły v3. Komponenty bez danych są pomijane —
    /// pasek na zerze czytałby się jak „zawaliłeś", a nie „nie zmierzono".
    var breakdown: [ScoreComponentRow] {
        Self.order.compactMap { key in
            guard let value = self[key] else { return nil }
            return ScoreComponentRow(
                id: key,
                label: Self.label(forComponent: key),
                weight: weights?[key],
                value: value,
                parts: partRows(for: key)
            )
        }
    }

    /// Etykiety komponentów, których nie dało się policzyć — dashboard mówi
    /// wprost, czego brakuje, zamiast udawać komplet.
    var missing: [String] {
        Self.order.compactMap { key in self[key] == nil ? Self.label(forComponent: key) : nil }
    }

    /// Ile procent wag score faktycznie objął. `nil` dla starych snapshotów.
    var coveragePercent: Int? {
        coverage.map { Int(($0 * 100).rounded()) }
    }

    // MARK: - Słowniki

    private static let order = ["sleep", "vo2max", "body", "regeneration"]

    /// Nazwa komponentu w języku użytkownika. Klucze przychodzą z serwera,
    /// nazwy zostają tutaj — baza nie jest miejscem na napisy dla ludzi.
    static func label(forComponent key: String) -> String {
        switch key {
        case "sleep": String(localized: "Sen")
        case "vo2max": String(localized: "VO₂max")
        case "body": String(localized: "Ciało")
        case "regeneration": String(localized: "Regeneracja")
        default: key
        }
    }

    /// Nazwy składowych. Nieznany klucz wraca surowy — nowy element policzony
    /// przez serwer ma się pokazać, a nie zniknąć z rozbicia.
    static func label(forPart key: String) -> String {
        switch key {
        case "duration": String(localized: "Długość snu")
        case "deep": String(localized: "Sen głęboki")
        // Dwa różne wymiary rytmu i oba wchodzą do wyniku: `consistency` to
        // rozrzut DŁUGOŚCI snu, `regularity` to stałość PORY zasypiania.
        // Można spać co noc osiem godzin, kładąc się o losowych porach.
        case "consistency": String(localized: "Równa długość snu")
        case "regularity": String(localized: "Regularność pory snu")
        case "bmi": String(localized: "BMI")
        case "whr": String(localized: "Talia/biodra")
        case "body_fat": String(localized: "Tkanka tłuszczowa")
        case "resting_heart_rate": String(localized: "Tętno spoczynkowe")
        case "hrv_trend": String(localized: "Trend HRV")
        default: key
        }
    }

    private subscript(key: String) -> Double? {
        switch key {
        case "sleep": sleep
        case "vo2max": vo2max
        case "body": body
        case "regeneration": regeneration
        default: nil
        }
    }

    private func partRows(for key: String) -> [ScorePartRow] {
        (parts?[key] ?? []).map { part in
            ScorePartRow(
                id: part.key,
                label: Self.label(forPart: part.key),
                weight: part.weight,
                value: part.value
            )
        }
    }
}
