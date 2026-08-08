import AuthenticationServices
import SwiftUI
import Supabase

struct AuthView: View {
    private enum Status {
        case error(String)
        case info(String)
    }

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var status: Status?
    @State private var needsConfirmation = false
    /// Surowa liczba jednorazowa bieżącej próby logowania Apple. Musi przeżyć
    /// między złożeniem żądania a jego zamknięciem — Supabase dostaje ją
    /// w oryginale, a Apple tylko jej skrót.
    @State private var appleNonce: String?
    @FocusState private var focused: Field?

    private enum Field { case name, email, password }

    private var hasInput: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        // Imię zbieramy już tutaj, tak jak `app/sign-up/page.tsx`. Reszta profilu
        // idzie osobnym ekranem, bo bez sesji nie ma do czego jej zapisać.
        return !isSignUp || !fullName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSubmit: Bool {
        !isLoading && hasInput
    }

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    fields
                    statusMessage
                    primaryButton
                    appleSection
                    secondaryActions
                }
                .padding(.horizontal, 28)
                .padding(.top, 72)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .statusBarCover()
        }
    }

    // MARK: - Sekcje

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                Text("LONGEVITY")
                Text(".").foregroundStyle(Palette.ochre)
            }
            .font(AtlasFont.display(26, .heavy))
            .tracking(3.6)
            .foregroundStyle(Palette.ink)

            Kicker(text: isSignUp ? "załóż konto" : "zaloguj się", size: 11)
        }
        .padding(.bottom, 40)
    }

    private var fields: some View {
        VStack(spacing: 12) {
            if isSignUp {
                field {
                    TextField("Imię", text: $fullName)
                        .textContentType(.givenName)
                        .submitLabel(.next)
                        .focused($focused, equals: .name)
                        .onSubmit { focused = .email }
                }
            }

            field {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .submitLabel(.next)
                    .focused($focused, equals: .email)
                    .onSubmit { focused = .password }
            }

            field {
                SecureField("Hasło", text: $password)
                    .textContentType(isSignUp ? .newPassword : .password)
                    .submitLabel(.go)
                    .focused($focused, equals: .password)
                    .onSubmit { if canSubmit { Task { await authenticate() } } }
            }
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let status {
            let (text, color): (String, Color) = switch status {
            case .error(let message): (message, .red)
            case .info(let message): (message, Palette.pine)
            }

            Text(text)
                .font(AtlasFont.body(12.5))
                .foregroundStyle(color)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
        }
    }

    private var primaryButton: some View {
        Button {
            focused = nil
            Task { await authenticate() }
        } label: {
            Group {
                if isLoading {
                    ProgressView().tint(Palette.card)
                } else {
                    Text(isSignUp ? "Zarejestruj się" : "Zaloguj się")
                }
            }
            .font(AtlasFont.body(15, .semibold))
            // Stan wyglądu zależy od `hasInput`, nie `canSubmit` — inaczej
            // podczas ładowania tło blednie i biały spinner znika.
            .foregroundStyle(hasInput ? Palette.card : Palette.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            // Pine, nie ochra: to akcja, a akcje w tej apce są zielone — tak
            // samo wygląda przycisk wysyłania w czacie i „Spróbuj ponownie".
            // Stan wyłączony dostaje biel z obwódką zamiast bladej ochry:
            // `ochreSoft` na tle strony ma kontrast 1,07:1, więc przycisk
            // po prostu przestawał być widoczny. Wcześniej blady CTA stał obok
            // pełnoczarnego przycisku Apple i wizualnie to Apple było główną
            // drogą, a własna rejestracja szeptem.
            .background(
                hasInput ? Palette.pine : Palette.card,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                if !hasInput {
                    RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .padding(.top, 20)
    }

    /// Przycisk musi być systemowy — Apple wymaga własnego kształtu, napisu
    /// i zachowania, a `SignInWithAppleButton` daje je razem z tłumaczeniem
    /// napisu na język telefonu.
    private var appleSection: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                separatorLine
                Text("albo")
                    .font(AtlasFont.body(12))
                    .foregroundStyle(Palette.muted)
                separatorLine
            }

            SignInWithAppleButton(isSignUp ? .signUp : .signIn) { request in
                let nonce = AppleSignIn.randomNonce()
                appleNonce = nonce
                AppleSignIn.prepare(request, nonce: nonce)
            } onCompletion: { result in
                Task { await authenticateWithApple(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(isLoading)
            // Etykietę systemowy przycisk ustala przy tworzeniu i nie zmienia
            // jej przy przerysowaniu. Bez własnej tożsamości w trybie rejestracji
            // dalej pisałby „Zaloguj się".
            .id(isSignUp)
        }
        .padding(.top, 24)
    }

    private var separatorLine: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(height: 1)
    }

    private var secondaryActions: some View {
        VStack(spacing: 16) {
            if needsConfirmation {
                Button("Wyślij link potwierdzający ponownie") {
                    Task { await resendConfirmation() }
                }
                .font(AtlasFont.body(13))
                .foregroundStyle(Palette.pine)
                .disabled(isLoading)
            }

            Button {
                // Pole imienia znika przy przełączeniu na logowanie — fokus musi
                // zejść razem z nim, inaczej klawiatura zostaje bez kursora.
                focused = nil
                isSignUp.toggle()
                status = nil
                needsConfirmation = false
            } label: {
                Text(isSignUp ? "Masz już konto? " : "Nie masz konta? ")
                    .foregroundStyle(Palette.muted)
                + Text(isSignUp ? "Zaloguj się" : "Zarejestruj się")
                    .foregroundStyle(Palette.pine)
            }
            .font(AtlasFont.body(13))
        }
        .padding(.top, 22)
    }

    private func field<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .font(AtlasFont.body(15))
            .tint(Palette.pine)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
    }

    // MARK: - Logika

    private func authenticate() async {
        isLoading = true
        status = nil
        needsConfirmation = false
        defer { isLoading = false }

        do {
            if isSignUp {
                // Imię ląduje w `user_metadata`, nie od razu w `profiles` — przy
                // włączonym potwierdzaniu maila nie ma jeszcze sesji, a więc i
                // uprawnień do zapisu. Onboarding wyciąga je stamtąd, tak jak web.
                let response = try await AppSupabase.client.auth.signUp(
                    email: email,
                    password: password,
                    data: ["full_name": .string(fullName.trimmingCharacters(in: .whitespaces))]
                )
                // Gdy w Supabase włączone jest "Confirm email", signUp nie tworzy sesji —
                // zwraca samego użytkownika, a zalogowanie wymaga kliknięcia linku z maila.
                if response.session == nil {
                    needsConfirmation = true
                    status = .info(
                        String(localized: "Konto utworzone. Wysłaliśmy link potwierdzający na \(email) — kliknij go, a potem zaloguj się.")
                    )
                }
            } else {
                _ = try await AppSupabase.client.auth.signIn(
                    email: email,
                    password: password
                )
            }
        } catch {
            if (error as? AuthError)?.errorCode == .emailNotConfirmed {
                needsConfirmation = true
            }
            status = .error(localizedError(error))
        }
    }

    private func authenticateWithApple(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        status = nil
        needsConfirmation = false
        defer {
            isLoading = false
            appleNonce = nil
        }

        do {
            // Rezygnacja nie zostawia śladu na ekranie — użytkownik właśnie
            // powiedział, że nie chce, więc komunikat byłby wyrzutem.
            _ = try await AppleSignIn.signIn(with: result, nonce: appleNonce)
        } catch {
            status = .error(localizedError(error))
        }
    }

    private func resendConfirmation() async {
        isLoading = true
        status = nil
        defer { isLoading = false }

        do {
            try await AppSupabase.client.auth.resend(email: email, type: .signup)
            status = .info(String(localized: "Wysłaliśmy link ponownie na \(email)."))
        } catch {
            status = .error(localizedError(error))
        }
    }

    private func localizedError(_ error: Error) -> String {
        // Błędy arkusza Apple niosą kody systemowe, nie treść dla użytkownika.
        // Rezygnacja tu nie dociera — `AppleSignIn.signIn` zdejmuje ją wcześniej.
        if error is ASAuthorizationError || error is AppleSignIn.Failure {
            return String(localized: "Nie udało się zalogować kontem Apple. Spróbuj ponownie.")
        }

        guard let authError = error as? AuthError else {
            let message = error.localizedDescription.lowercased()
            if message.contains("network") || message.contains("connection") || message.contains("offline") {
                return String(localized: "Brak połączenia z internetem")
            }
            let detail = error.localizedDescription
            return String(localized: "Wystąpił błąd: \(detail)")
        }

        switch authError.errorCode {
        case .invalidCredentials:
            return String(localized: "Nieprawidłowy email lub hasło")
        case .emailNotConfirmed:
            return String(localized: "Email nie został potwierdzony — sprawdź skrzynkę i kliknij link.")
        case .userAlreadyExists, .emailExists:
            return String(localized: "Ten email jest już zarejestrowany")
        case .weakPassword:
            return String(localized: "Hasło jest za słabe (min. 6 znaków)")
        case .validationFailed:
            return String(localized: "Nieprawidłowy adres email")
        case .overEmailSendRateLimit, .overRequestRateLimit:
            return String(localized: "Za dużo prób. Odczekaj chwilę i spróbuj ponownie.")
        case .signupDisabled:
            return String(localized: "Rejestracja jest wyłączona")
        default:
            let detail = authError.localizedDescription
            return String(localized: "Wystąpił błąd: \(detail)")
        }
    }
}

#Preview {
    AuthView()
}
