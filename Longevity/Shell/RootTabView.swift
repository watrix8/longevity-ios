import SwiftUI

/// Pierwsze trzy pozycje odpowiadają `NAV_ITEMS` z `app/components/AppShell.tsx`
/// w repo webowym. Emoji z weba zastąpione SF Symbols, bo to natywny
/// odpowiednik na iOS.
///
/// Czwarta pozycja nie ma odpowiednika na webie — to jedyne miejsce na
/// posiłki, aktywność, check-in i pytania do asystenta.
struct RootTabView: View {
    private enum RootTab: Hashable {
        case dashboard, trends, assistant, settings
    }

    @State private var selection: RootTab = .dashboard

    /// Rośnie przy każdym tapnięciu w aktywną już zakładkę asystenta.
    @State private var chatBottomRequest = 0

    /// iOS sam obsługuje ponowne tapnięcie w aktywną zakładkę i przewija
    /// zawartość na samą górę. W czacie to prowadzi do najstarszej wiadomości,
    /// czyli dokładnie tam, gdzie nikt nie chce trafić. Przechwytujemy więc
    /// ponowny wybór i odsyłamy widok na dół.
    private var tab: Binding<RootTab> {
        Binding(
            get: { selection },
            set: { picked in
                if picked == .assistant, selection == .assistant {
                    chatBottomRequest += 1
                }
                selection = picked
            }
        )
    }

    var body: some View {
        TabView(selection: tab) {
            Tab("Dashboard", systemImage: "square.grid.2x2.fill", value: .dashboard) {
                DashboardView()
            }
            Tab("Trendy", systemImage: "chart.line.uptrend.xyaxis", value: .trends) {
                TrendsView()
            }
            Tab("Asystent", systemImage: "bubble.left.and.text.bubble.right.fill", value: .assistant) {
                ChatView(bottomRequest: chatBottomRequest)
            }
            Tab("Opcje", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
        }
        .tint(Palette.ochre)
    }
}

#Preview {
    RootTabView()
}
