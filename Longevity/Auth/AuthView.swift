import SwiftUI
import Supabase

struct AuthView: View {
    private enum Status {
        case error(String)
        case info(String)
    }

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var status: Status?
    @State private var needsConfirmation = false
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    private var hasInput: Bool {
        !email.isEmpty && !password.isEmpty
    }

    private var canSubmit: Bool {
        !isLoading && hasInput
    }

    var body: some View {
        ZStack {
            Palette.card.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    fields
                    statusMessage
                    primaryButton
                    secondaryActions
                }
                .padding(.horizontal, 28)
                .padding(.top, 72)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
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
            .background(
                hasInput ? Palette.ochre : Palette.ochreSoft,
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .padding(.top, 20)
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
            .tint(Palette.ochre)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
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
                let response = try await AppSupabase.client.auth.signUp(
                    email: email,
                    password: password
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
