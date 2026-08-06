import SwiftUI

@main
struct LongevityApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    /// Trzeci stan jest istotny: `authStateChanges` dostarcza `.initialSession`
    /// asynchronicznie, więc bez niego każdy zimny start migał ekranem logowania
    /// zanim odtworzy się zapisana sesja.
    private enum AuthState {
        case resolving
        case signedIn
        case signedOut
    }

    @State private var authState: AuthState = .resolving

    var body: some View {
        Group {
            switch authState {
            case .resolving:
                SplashView()
            case .signedIn:
                ContentView()
            case .signedOut:
                AuthView()
            }
        }
        // Paleta ATLAS jest zaprojektowana pod jasne tło — wymuszamy ją, żeby
        // status bar i kontrolki systemowe nie rozjechały się w dark mode.
        .preferredColorScheme(.light)
        .task {
            for await (_, session) in AppSupabase.client.auth.authStateChanges {
                authState = session != nil ? .signedIn : .signedOut
            }
        }
    }
}

/// Ten sam wordmark co na ekranie logowania i w topbarze dashboardu,
/// żeby przejście po odtworzeniu sesji nie mrugało.
struct SplashView: View {
    var body: some View {
        ZStack {
            Palette.card.ignoresSafeArea()
            HStack(spacing: 0) {
                Text("LONGEVITY")
                Text(".").foregroundStyle(Palette.ochre)
            }
            .font(AtlasFont.display(26, .heavy))
            .tracking(3.6)
            .foregroundStyle(Palette.ink)
        }
    }
}
