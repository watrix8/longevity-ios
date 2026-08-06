import SwiftUI

/// Odpowiednik `NAV_ITEMS` z `app/components/AppShell.tsx` w repo webowym —
/// te same trzy pozycje i ta sama kolejność. Emoji z weba zastąpione
/// SF Symbols, bo to natywny odpowiednik na iOS.
struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "square.grid.2x2.fill") {
                DashboardView()
            }
            Tab("Trendy", systemImage: "chart.line.uptrend.xyaxis") {
                TrendsView()
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
