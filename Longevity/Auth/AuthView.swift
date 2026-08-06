import SwiftUI

struct AuthView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Longevity")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 20)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)

            SecureField("Hasło", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await authenticate() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text(isSignUp ? "Zarejestruj się" : "Zaloguj się")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || email.isEmpty || password.isEmpty)

            Button(isSignUp ? "Masz już konto? Zaloguj się" : "Nie masz konta? Zarejestruj się") {
                isSignUp.toggle()
                errorMessage = nil
            }
            .font(.footnote)
        }
        .padding(24)
    }

    private func authenticate() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if isSignUp {
                _ = try await AppSupabase.client.auth.signUp(email: email, password: password)
            } else {
                _ = try await AppSupabase.client.auth.signIn(email: email, password: password)
            }
        } catch {
            errorMessage = localizedError(error)
        }
    }

    private func localizedError(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("invalid") || message.contains("credentials") {
            return "Nieprawidłowy email lub hasło"
        }
        if message.contains("already registered") || message.contains("already been registered") {
            return "Ten email jest już zarejestrowany"
        }
        if message.contains("password") && (message.contains("short") || message.contains("least")) {
            return "Hasło jest za krótkie (min. 6 znaków)"
        }
        if message.contains("network") || message.contains("connection") {
            return "Brak połączenia z internetem"
        }
        return "Wystąpił błąd: \(error.localizedDescription)"
    }
}

#Preview {
    AuthView()
}
