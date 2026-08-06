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
    @State private var isAuthenticated = false

    var body: some View {
        Group {
            if isAuthenticated {
                ContentView()
            } else {
                AuthView()
            }
        }
        .task {
            for await (_, session) in AppSupabase.client.auth.authStateChanges {
                isAuthenticated = session != nil
            }
        }
    }
}
