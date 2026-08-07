import SwiftUI

/// Pierwsze trzy pozycje odpowiadają `NAV_ITEMS` z `app/components/AppShell.tsx`
/// w repo webowym. Emoji z weba zastąpione SF Symbols, bo to natywny
/// odpowiednik na iOS.
///
/// Czwarta pozycja nie ma odpowiednika na webie — to jedyne miejsce na
/// posiłki, aktywność, check-in i pytania do asystenta.
struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "square.grid.2x2.fill") {
                DashboardView()
            }
            Tab("Trendy", systemImage: "chart.line.uptrend.xyaxis") {
                TrendsView()
            }
            Tab("Asystent", systemImage: "bubble.left.and.text.bubble.right.fill") {
                ChatView()
            }
            Tab("Opcje", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .tint(Palette.ochre)
    }
}

#Preview {
    RootTabView()
}
