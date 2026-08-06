import SwiftUI

struct WatchContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Longevity")
                .font(.headline)

            Text("--")
                .font(.system(size: 48, weight: .thin, design: .rounded))

            Text("Score")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    WatchContentView()
}
