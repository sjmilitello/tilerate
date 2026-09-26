
import SwiftUI

struct RootView: View {
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
}
