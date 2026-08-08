import Foundation
import Testing

@testable import Longevity

@Suite("Bramka rejestracji")
struct OnboardingProfileTests {
    private func profile(
        fullName: String? = "Anna Kowalska",
        birthDate: String? = "1990-01-01",
        sex: String? = "female",
        heightCm: Double? = 168,
        primaryGoal: String? = "longevity"
    ) -> OnboardingProfile {
        OnboardingProfile(
            fullName: fullName,
            birthDate: birthDate,
            sex: sex,
            heightCm: heightCm,
            primaryGoal: primaryGoal
        )
    }

    @Test("Komplet danych nie woła formularza")
    func completeProfilePasses() {
        #expect(profile().isComplete)
    }

    /// Konto tuż po `handle_new_user` ma sam identyfikator — to jest ten stan,
    /// dla którego bramka w ogóle powstała.
    @Test("Świeży profil jest niekompletny")
    func freshProfileIsIncomplete() {
        let empty = OnboardingProfile(
            fullName: nil, birthDate: nil, sex: nil, heightCm: nil, primaryGoal: nil
        )
        #expect(!empty.isComplete)
    }

    /// Web wypuszcza dalej każdego, kto ma `birth_date` i `primary_goal`
    /// (`app/app/page.tsx:113`). Bez płci `vo2maxScore` i `bodyFatScore` zwracają
    /// null, a bez wzrostu nie ma BMI — na iOS to za mało.
    @Test("Brak płci albo wzrostu zatrzymuje, mimo że web by przepuścił")
    func stricterThanWeb() {
        #expect(!profile(sex: nil).isComplete)
        #expect(!profile(heightCm: nil).isComplete)
    }

    @Test("Puste stringi liczą się jak brak")
    func blankStringsCountAsMissing() {
        #expect(!profile(birthDate: "").isComplete)
        #expect(!profile(sex: "   ").isComplete)
        #expect(!profile(primaryGoal: "").isComplete)
    }

    /// Wartość spoza `profiles_height_cm_range` i tak odbiłaby się od bazy,
    /// więc bramka traktuje ją jak brak i pyta ponownie.
    @Test("Wzrost spoza zakresu bazy nie domyka rejestracji")
    func outOfRangeHeightIsIncomplete() {
        #expect(!profile(heightCm: 40).isComplete)
        #expect(!profile(heightCm: 300).isComplete)
        #expect(profile(heightCm: 80).isComplete)
        #expect(profile(heightCm: 260).isComplete)
    }

    /// Imię nie wchodzi do wyniku, więc bramkowanie na nim wołałoby formularz
    /// u kont, którym nic nie brakuje.
    @Test("Brak imienia nie woła formularza")
    func missingNameDoesNotGate() {
        #expect(profile(fullName: nil).isComplete)
    }

    /// Waga nie jest cechą profilu, tylko pomiarem w `health_metrics` — bramka
    /// nie ma jej gdzie sprawdzić i nie może na niej stać.
    @Test("Bramka pyta tylko o kolumny z profiles")
    func gateReadsOnlyProfileColumns() {
        #expect(!OnboardingProfile.columns.contains("weight_kg"))
    }
}

@Suite("Parsowanie wagi")
struct OnboardingWeightTests {
    @Test("Przecinek działa jak kropka")
    func acceptsComma() {
        #expect(OnboardingViewModel.parseWeight("82,4") == 82.4)
    }

    /// Zakres z `lib/health-metrics.ts` — poza nim serwer odrzuciłby PATCH.
    @Test("Wartości spoza zakresu health_metrics dają nil")
    func rejectsOutOfRange() {
        #expect(OnboardingViewModel.parseWeight("24.9") == nil)
        #expect(OnboardingViewModel.parseWeight("400.1") == nil)
        #expect(OnboardingViewModel.parseWeight("25") == 25)
        #expect(OnboardingViewModel.parseWeight("400") == 400)
    }

    @Test("Pusta wartość i śmieci dają nil")
    func rejectsInvalid() {
        #expect(OnboardingViewModel.parseWeight("") == nil)
        #expect(OnboardingViewModel.parseWeight("—") == nil)
    }
}

@Suite("Parsowanie wzrostu")
struct OnboardingHeightTests {
    @Test("Przecinek działa jak kropka")
    func acceptsComma() {
        #expect(OnboardingViewModel.parseHeight("176,5") == 176.5)
        #expect(OnboardingViewModel.parseHeight("176.5") == 176.5)
    }

    @Test("Spacje po bokach nie przeszkadzają")
    func trimsWhitespace() {
        #expect(OnboardingViewModel.parseHeight(" 180 ") == 180)
    }

    /// `numeric(5,2)` w bazie i tak by to obcięło, a `profiles_height_cm_range`
    /// odrzuciło skrajności — lepiej powiedzieć to w formularzu niż błędem SQL.
    @Test("Wartości spoza zakresu i śmieci dają nil")
    func rejectsInvalid() {
        #expect(OnboardingViewModel.parseHeight("") == nil)
        #expect(OnboardingViewModel.parseHeight("—") == nil)
        #expect(OnboardingViewModel.parseHeight("79.9") == nil)
        #expect(OnboardingViewModel.parseHeight("260.1") == nil)
    }

    @Test("Zaokrągla do jednego miejsca")
    func roundsToOneDecimal() {
        #expect(OnboardingViewModel.parseHeight("176.44") == 176.4)
        #expect(OnboardingViewModel.parseHeight("176.46") == 176.5)
    }
}
