import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

/// Logowanie kontem Apple.
///
/// Cała ochrona opiera się na liczbie jednorazowej: do Apple leci jej skrót,
/// a do Supabase wartość surowa. Serwer liczy skrót ponownie i porównuje
/// z tym, co Apple wpisało do podpisanego tokenu — token przechwycony po
/// drodze nie da się więc użyć do założenia innej sesji.
enum AppleSignIn {
    enum Failure: LocalizedError {
        /// Autoryzacja wróciła bez tokenu albo bez pasującej liczby jednorazowej.
        case malformedCredential

        var errorDescription: String? {
            String(localized: "Apple nie odesłało kompletnych danych logowania")
        }
    }

    /// Wynik zamknięcia arkusza. Rezygnacja nie jest awarią i nie ma o niej
    /// czego pisać na ekranie.
    enum Outcome {
        case signedIn
        case cancelled
    }

    // MARK: - Przepływ

    static func prepare(_ request: ASAuthorizationAppleIDRequest, nonce: String) {
        // O imię trzeba poprosić TERAZ. Apple oddaje je wyłącznie przy pierwszej
        // autoryzacji konta w tej aplikacji i nigdy więcej.
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    static func signIn(with result: Result<ASAuthorization, Error>, nonce: String?) async throws -> Outcome {
        let authorization: ASAuthorization

        switch result {
        case .success(let value):
            authorization = value
        case .failure(let error):
            // Zamknięcie arkusza to decyzja użytkownika, nie błąd.
            if (error as? ASAuthorizationError)?.code == .canceled { return .cancelled }
            throw error
        }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce
        else {
            throw Failure.malformedCredential
        }

        try await AppSupabase.client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )

        // Imię przychodzi raz w życiu konta, więc nieprzechwycone przepada.
        // Ląduje w `user_metadata`, tak samo jak przy rejestracji mailem —
        // stamtąd podnosi je onboarding.
        if let name = givenName(from: credential.fullName) {
            try? await AppSupabase.client.auth.update(
                user: UserAttributes(data: ["full_name": .string(name)])
            )
        }

        return .signedIn
    }

    // MARK: - Liczba jednorazowa

    /// Alfabet ma równo 64 znaki i to nie przypadek: 256 dzieli się przez 64
    /// bez reszty, więc `% count` nie faworyzuje początkowych znaków. Przy 65
    /// znakach rozkład przestałby być równomierny.
    private static let alphabet = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
    )

    static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess else {
            // Awaryjnie generator Swifta — też CSPRNG, tylko bez pośrednictwa Keychaina.
            return String((0..<length).map { _ in alphabet.randomElement() ?? "0" })
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Imię

    /// Samo imię, bez nazwiska — reszta aplikacji operuje wyłącznie na nim.
    static func givenName(from components: PersonNameComponents?) -> String? {
        let given = components?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let given, !given.isEmpty else { return nil }
        return given
    }
}
