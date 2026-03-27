
import SwiftUI

struct RootView: View {
    // You can still use AppState for deep links / reset sheet, but it does NOT hold rates/tax.
    @EnvironmentObject private var appState: AppState

    // Persist your editable rates in memory for this run.
    @State private var rates = Rates()

    // Persist the default tax between launches.
    @AppStorage("tax.default") private var taxDefault: Double = 0.0

    var body: some View {
        // Your ContentView already takes bindings for these:
        ContentView(
            rates: $rates,
            taxDefault: $taxDefault
        )
    }
}

#Preview("RootView") {
    RootView()
        .environmentObject(AppState())
        // If your preview’d ContentView expects AdminAuthManager somewhere,
        // keep providing it in previews:
        .environmentObject(AdminAuthManager())
}
