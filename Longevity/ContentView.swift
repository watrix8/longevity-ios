import SwiftUI

/// Powłoka po zalogowaniu. Tryb jasny wymusza `RootView`.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RootTabView()
            // Sync HealthKit po zalogowaniu i po każdym powrocie z tła. Model
            // sam odpuszcza, gdy nie ma zgody albo gdy ostatni sync był niedawno,
            // więc to tutaj nie potrzebuje żadnych warunków.
            .task { await HealthSyncModel.shared.syncIfStale() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await HealthSyncModel.shared.syncIfStale() }
            }
    }
}

#Preview {
    ContentView()
}
