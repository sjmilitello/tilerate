import SwiftUI

/// Shown on an estimate opened from the saved list: it is priced as it was
/// saved, and can be converted to the current rates. Estimates saved before
/// 2026-10-05 carry no rates, so they are priced at the current ones.
struct OpenedPricingBanner: View {
    @ObservedObject var store: Store
    /// The estimate's totals at the given rates (same shipping and tax).
    let totals: (Rates) -> EstimateTotals

    @State private var confirmConvert = false

    var body: some View {
        if let opened = store.opened {
            let date = opened.savedAt.formatted(date: .abbreviated, time: .omitted)
            VStack(alignment: .leading, spacing: 10) {
                if opened.rates != nil {
                    Label {
                        Text("Priced as saved on \(date). Changes to your rates in Admin don't affect it.")
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                    Button("Convert to current pricing") { confirmConvert = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                } else {
                    Label {
                        Text("Saved on \(date), before prices were kept with estimates, so it is priced at your current rates. Saving it again keeps today's prices with it.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .confirmationDialog("Convert to current pricing?", isPresented: $confirmConvert, titleVisibility: .visible) {
                Button("Convert") { store.convertToCurrentPricing() }
            } message: {
                Text(convertMessage)
            }
        }
    }

    private var convertMessage: String {
        let saved = totals(store.pricingRates).grandTotal
        let current = totals(store.rates).grandTotal
        return "Saved price: \(currencyString(saved))\nAt current rates: \(currencyString(current))\n\n"
            + "The saved estimate in the list keeps its price. Save this one again to keep the new price."
    }
}
