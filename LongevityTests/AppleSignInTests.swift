import Foundation
import Testing

@testable import Longevity

@Suite("Liczba jednorazowa Apple")
struct AppleSignInNonceTests {
    /// Wektor kontrolny SHA-256 dla „abc". Skrót musi zgadzać się z tym, co
    /// policzy Apple po swojej stronie — inaczej Supabase odrzuci token.
    @Test("Skrót zgadza się z wektorem kontrolnym")
    func matchesKnownVector() {
        #expect(
            AppleSignIn.sha256("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("Skrót jest szesnastkowy i ma stałą długość")
    func hexOfFixedLength() {
        let digest = AppleSignIn.sha256(AppleSignIn.randomNonce())
        #expect(digest.count == 64)
        #expect(digest.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("Losowanie oddaje zadaną długość")
    func honoursLength() {
        #expect(AppleSignIn.randomNonce().count == 32)
        #expect(AppleSignIn.randomNonce(length: 8).count == 8)
    }

    /// Alfabet ma 64 znaki właśnie po to, żeby 256 dzieliło się przez niego bez
    /// reszty. Gdyby ktoś dołożył znak, rozkład przestałby być równomierny —
    /// ten test przypilnuje, że alfabet został przy bezpiecznym rozmiarze.
    @Test("Znaki pochodzą z alfabetu bezpiecznego w URL-u")
    func staysWithinURLSafeAlphabet() {
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_")
        let nonce = AppleSignIn.randomNonce(length: 256)
        #expect(nonce.allSatisfy { allowed.contains($0) })
    }

    @Test("Dwie próby nie dostają tej samej liczby")
    func differsBetweenAttempts() {
        #expect(AppleSignIn.randomNonce() != AppleSignIn.randomNonce())
    }
}

@Suite("Imię z konta Apple")
struct AppleSignInNameTests {
    private func components(given: String?, family: String? = nil) -> PersonNameComponents {
        var c = PersonNameComponents()
        c.givenName = given
        c.familyName = family
        return c
    }

    /// Reszta aplikacji operuje na samym imieniu, więc nazwisko zostaje z boku.
    @Test("Bierze się imię, nazwisko zostaje pominięte")
    func takesGivenNameOnly() {
        #expect(AppleSignIn.givenName(from: components(given: "Tomasz", family: "Watras")) == "Tomasz")
    }

    /// Apple oddaje imię wyłącznie przy pierwszej autoryzacji — przy kolejnych
    /// przychodzi puste i nie ma czym nadpisywać tego, co już zapisane.
    @Test("Brak imienia daje nil, nie pusty string")
    func missingNameIsNil() {
        #expect(AppleSignIn.givenName(from: nil) == nil)
        #expect(AppleSignIn.givenName(from: components(given: nil)) == nil)
        #expect(AppleSignIn.givenName(from: components(given: "")) == nil)
        #expect(AppleSignIn.givenName(from: components(given: "   ")) == nil)
    }

    @Test("Spacje po bokach są obcinane")
    func trimsWhitespace() {
        #expect(AppleSignIn.givenName(from: components(given: "  Anna  ")) == "Anna")
    }
}

@Suite("Sposób logowania a reset hasła")
struct PasswordIdentityTests {
    @Test("Konto mailowe widzi reset hasła")
    func emailAccountKeepsReset() {
        #expect(SettingsViewModel.hasPasswordIdentity(providers: ["email"]))
    }

    @Test("Konto tylko z Apple nie widzi resetu")
    func appleOnlyHidesReset() {
        #expect(!SettingsViewModel.hasPasswordIdentity(providers: ["apple"]))
    }

    /// Konto połączone obiema drogami ma hasło, więc reset ma sens.
    @Test("Apple obok maila nie zabiera resetu")
    func linkedAccountKeepsReset() {
        #expect(SettingsViewModel.hasPasswordIdentity(providers: ["apple", "email"]))
    }

    /// Brak listy to niewiedza, nie brak hasła. Ukrycie resetu komuś, kto loguje
    /// się mailem, odcięłoby jedyną drogę do zmiany hasła.
    @Test("Pusta lista zostawia reset widoczny")
    func unknownIdentitiesKeepReset() {
        #expect(SettingsViewModel.hasPasswordIdentity(providers: []))
    }
}
