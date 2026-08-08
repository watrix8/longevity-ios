import Foundation
import Observation
import Supabase

/// Wycinek `profiles`, który decyduje o tym, czy rejestracja jest domknięta.
///
/// Web bramkuje onboarding na `birth_date && primary_goal`
/// (`app/app/page.tsx:113`), a płeć i wzrost trzyma jako opcjonalne. Na iOS to
/// za mało — `scoring-v3` bez płci zwraca `null` z `vo2maxScore` i `bodyFatScore`,
/// a bez wzrostu nie policzy BMI. Te cztery pola to dokładnie te, których brak
/// wycina kawałki Longevity Score.
///
/// Imię celowo nie wchodzi do warunku: nigdzie nie liczy się z niego wynik,
/// a bramkowanie na nim wołałoby formularz u kont, którym nic nie brakuje.
struct OnboardingProfile: Decodable, Equatable {
    var fullName: String?
    var birthDate: String?
    var sex: String?
    var heightCm: Double?
    var primaryGoal: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case birthDate = "birth_date"
        case sex
        case heightCm = "height_cm"
        case primaryGoal = "primary_goal"
    }

    static let columns = "full_name, birth_date, sex, height_cm, primary_goal"

    /// Zakres z `profiles_height_cm_range`. Zapis poza nim odbija się od bazy,
    /// więc pilnujemy go tutaj, żeby zamiast surowego błędu SQL pokazać zdanie.
    static let heightRange: ClosedRange<Double> = 80...260

    /// Waga świadomie nie wchodzi do warunku: nie jest atrybutem profilu, tylko
    /// pomiarem, i mieszka w `health_metrics`. Formularz o nią pyta, ale bramkę
    /// otwierają pola, które faktycznie stoją w `profiles`.
    var isComplete: Bool {
        guard let heightCm, Self.heightRange.contains(heightCm) else { return false }
        return !isBlank(birthDate) && !isBlank(sex) && !isBlank(primaryGoal)
    }

    private func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}

/// Payload rejestracji. Węższy niż `app/onboarding/page.tsx` o trzy pola:
///
/// - `weight_kg` — waga to pomiar, nie cecha profilu. Formularz o nią pyta, ale
///   trafia tam, gdzie reszta pomiarów: `PATCH /api/v1/health/sync` dopisuje ją
///   do `health_metrics` i `weight_log` i oznacza jako wpis ręczny, więc zegarek
///   jej nie nadpisze.
/// - `body_type` — karmi wyłącznie scoring posiłków, a te są web-only. Zostaje
///   w Opcjach, gdzie można je uzupełnić świadomie.
/// - `onboarding_completed_at` — martwa kolumna. Web ją zapisuje i nigdy nie czyta;
///   własną bramkę opiera na `birth_date && primary_goal`.
private struct ProfilePayload: Encodable {
    let id: String
    let full_name: String
    let birth_date: String
    let sex: String
    let height_cm: Double
    let primary_goal: String
}

/// Druga połowa rejestracji: dane, bez których Longevity Score liczy się na pół gwizdka.
///
/// Odpowiednik `app/onboarding/page.tsx`, ale bramka siedzi w aplikacji, a nie
/// w routingu — `check()` decyduje, czy formularz w ogóle się pokaże.
@MainActor
@Observable
final class OnboardingViewModel {
    var isPresented = false

    var fullName = ""
    /// Wartość startowa jest neutralna, a nie „dziś" — data urodzenia równa
    /// dzisiejszej czytałaby się jak realna wartość, gdy jej po prostu nie ma.
    var birthDate = OnboardingViewModel.fallbackBirthDate
    /// Sam `birthDate` nie odróżnia wartości podanej od podstawionej, a tu
    /// akurat trzeba: przepuszczony placeholder to cichy błąd w wieku.
    private(set) var birthDateIsSet = false
    var sex = ""
    var heightCm = ""
    var weightKg = ""
    var primaryGoal = ""

    private(set) var isSaving = false
    var errorMessage: String?

    /// Bramka odpala się raz na zalogowanie. Po zapisaniu profilu nie ma czego
    /// sprawdzać, a przy błędzie sieci następne wejście na wierzch spróbuje znów.
    private var isSatisfied = false

    var canSubmit: Bool {
        guard !isSaving, birthDateIsSet, !sex.isEmpty, !primaryGoal.isEmpty else { return false }
        return !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Self.parseHeight(heightCm) != nil
            && Self.parseWeight(weightKg) != nil
    }

    // MARK: - Bramka

    func check() async {
        guard !isSatisfied else { return }

        do {
            let session = try await AppSupabase.client.auth.session
            let profile: OnboardingProfile = try await AppSupabase.client
                .from("profiles")
                .select(OnboardingProfile.columns)
                .eq("id", value: session.user.id.uuidString)
                .single()
                .execute()
                .value

            guard !profile.isComplete else {
                isSatisfied = true
                return
            }

            prefill(from: profile, metadata: session.user.userMetadata)
            isPresented = true
        } catch {
            // Offline albo chwilowa awaria odczytu. Nie zasłaniamy aplikacji
            // formularzem, którego i tak nie dałoby się zapisać — bramka
            // spróbuje ponownie, gdy apka wróci na wierzch.
        }
    }

    /// Web podpiera się `user_metadata.full_name`, gdy rejestracja poszła
    /// z włączonym potwierdzaniem maila i profil nie zdążył dostać imienia.
    private func prefill(from profile: OnboardingProfile, metadata: [String: AnyJSON]) {
        let saved = profile.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        fullName = saved.isEmpty ? (metadata["full_name"]?.stringValue ?? "") : saved
        sex = profile.sex ?? ""
        heightCm = profile.heightCm.map(Self.trimZero) ?? ""
        primaryGoal = profile.primaryGoal ?? ""
        // Wagi nie podstawiamy. Zapis idzie pod dzisiejszą datę, więc wpisana
        // z pamięci sprzed miesięcy byłaby pomiarem, którego nikt nie zrobił.
        if let iso = profile.birthDate, let parsed = Self.dateParser.date(from: iso) {
            birthDate = parsed
            birthDateIsSet = true
        }
    }

    // MARK: - Zapis

    func save() async {
        guard let height = Self.parseHeight(heightCm) else {
            errorMessage = String(localized: "Wzrost musi mieścić się w zakresie 80–260 cm")
            return
        }
        guard let weight = Self.parseWeight(weightKg) else {
            errorMessage = String(localized: "Waga musi mieścić się w zakresie 25–400 kg")
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let userId = try await AppSupabase.client.auth.session.user.id.uuidString
            let payload = ProfilePayload(
                id: userId,
                full_name: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                birth_date: Self.dateParser.string(from: birthDate),
                sex: sex,
                height_cm: height,
                primary_goal: primaryGoal
            )

            // `upsert`, nie `update` — wiersz zwykle tworzy trigger
            // `handle_new_user`, ale konto założone zanim go dodano nie ma czego
            // aktualizować i cichy `update` nie zapisałby niczego.
            try await AppSupabase.client
                .from("profiles")
                .upsert(payload, onConflict: "id")
                .execute()

            // Waga tą samą drogą, co pomiary dopisywane w czacie. Serwer
            // upsertuje po dniu, więc ponowienie po błędzie nie zdublowuje wpisu.
            try await LongevityAPI.saveHealthMarkers(HealthMarkers(weightKg: weight))

            isSatisfied = true
            isPresented = false

            // Wiek, płeć, wzrost i waga wchodzą wprost do wyniku, więc snapshot
            // policzony przed chwilą jest już nieaktualny.
            await LongevityAPI.refreshScore()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        HealthSyncModel.shared.reset()
        ChatHistoryCache.clear()
        try? await AppSupabase.client.auth.signOut()
    }

    /// Ustawienie daty z UI oznacza ją jako realnie podaną.
    func setBirthDate(_ date: Date) {
        birthDate = date
        birthDateIsSet = true
    }

    // MARK: - Parsowanie

    nonisolated static func parseHeight(_ text: String) -> Double? {
        parse(text, in: OnboardingProfile.heightRange)
    }

    /// Zakres z `lib/health-metrics.ts:64`, nie z `profiles` — waga jedzie
    /// do `health_metrics`, więc to ta walidacja odrzuciłaby wpis.
    nonisolated static let weightRange: ClosedRange<Double> = 25...400

    nonisolated static func parseWeight(_ text: String) -> Double? {
        parse(text, in: weightRange)
    }

    /// Zwraca `nil` dla wartości, których baza i tak by nie przyjęła.
    /// `nonisolated`, bo to czysta funkcja — inaczej klasa z `@MainActor`
    /// wciągnęłaby ją na główny aktor i testy nie mogłyby jej zawołać wprost.
    private nonisolated static func parse(_ text: String, in range: ClosedRange<Double>) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized), range.contains(value) else { return nil }
        return (value * 10).rounded() / 10
    }

    static let fallbackBirthDate: Date = {
        dateParser.date(from: "1990-01-01") ?? Date()
    }()

    private static func trimZero(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
