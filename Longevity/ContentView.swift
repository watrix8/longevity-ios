import SwiftUI

struct ContentView: View {
    var body: some View {
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
    }
}

#Preview {
    ContentView()
}
