import SwiftUI

/// Powłoka po zalogowaniu. Tryb jasny wymusza `RootView`.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var onboarding = OnboardingViewModel()

    var body: some View {
        RootTabView()
            // Sync HealthKit po zalogowaniu i po każdym powrocie z tła. Model
            // sam odpuszcza, gdy nie ma zgody albo gdy ostatni sync był niedawno,
            // więc to tutaj nie potrzebuje żadnych warunków.
            .task { await HealthSyncModel.shared.syncIfStale() }
            // Bramka rejestracji chodzi tym samym rytmem: sprawdza raz, a przy
            // nieudanym odczycie próbuje znów po powrocie apki na wierzch.
            .task { await onboarding.check() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await HealthSyncModel.shared.syncIfStale() }
                Task { await onboarding.check() }
            }
            .fullScreenCover(isPresented: $onboarding.isPresented) {
                OnboardingView(model: onboarding)
                    // Formularz jest obowiązkowy — zsunięcie w dół zostawiłoby
                    // konto bez wieku, płci i wzrostu, a wynik bez trzech składników.
                    .interactiveDismissDisabled()
            }
    }
}

#Preview {
    ContentView()
}
