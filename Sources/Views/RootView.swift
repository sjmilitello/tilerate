
import SwiftUI

/// Which design the app shows. Both work on the same saved estimate, rates
/// and saved-estimates list, so switching never loses anything.
enum DesignPreference {
    static let key = "ui.newDesign"
}

struct RootView: View {
    // Persist your editable rates in memory for this run.
    @State private var rates = Rates()

    // Persist the default tax between launches.
    @AppStorage("tax.default") private var taxDefault: Double = 0.0

    @AppStorage(DesignPreference.key) private var useNewDesign = false

    var body: some View {
        if useNewDesign {
            NewEstimateView()
        } else {
            // Your ContentView already takes bindings for these:
            ContentView(
                rates: $rates,
                taxDefault: $taxDefault
            )
        }
    }
}

#Preview("RootView") {
    RootView()
}
