import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Longevity")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Score: --")
                    .font(.system(size: 64, weight: .thin, design: .rounded))

                Text("Passive health tracking")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Wyloguj") {
                        Task {
                            try? await AppSupabase.client.auth.signOut()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
