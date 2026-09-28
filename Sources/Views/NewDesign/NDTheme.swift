import SwiftUI

// The new design (preview): colours and the small pieces its screens share.
// It is dark by design, for use on job sites, and built on TileRate's blue.

enum ND {
    static let ground     = Color(red: 14/255, green: 19/255, blue: 22/255)
    static let surface    = Color(red: 22/255, green: 29/255, blue: 34/255)
    static let raised     = Color(red: 30/255, green: 39/255, blue: 46/255)
    static let border     = Color(red: 38/255, green: 49/255, blue: 58/255)
    static let footer     = Color(red: 17/255, green: 24/255, blue: 28/255)
    static let text       = Color(red: 238/255, green: 242/255, blue: 244/255)
    static let secondary  = Color(red: 185/255, green: 196/255, blue: 202/255)
    static let muted      = Color(red: 147/255, green: 161/255, blue: 170/255)
    static let brand      = Color(red: 28/255, green: 117/255, blue: 188/255)   // buttons
    static let link       = Color(red: 90/255, green: 174/255, blue: 240/255)   // links, selection
    static let selectedBg = Color(red: 19/255, green: 50/255, blue: 77/255)
    static let done       = Color(red: 63/255, green: 211/255, blue: 168/255)
    static let warning    = Color(red: 240/255, green: 162/255, blue: 75/255)
    static let warningBg  = Color(red: 43/255, green: 33/255, blue: 20/255)

    static func money(_ v: Double) -> String {
        v.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
    }

    static func number(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)))
    }
}

extension Font {
    static func ndTitle(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static let ndLabel = Font.system(size: 13, weight: .semibold)
}

/// Small uppercase section label.
struct NDLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.ndLabel)
            .tracking(1)
            .foregroundStyle(ND.muted)
    }
}

/// Rounded panel on the dark ground.
struct NDCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(ND.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ND.border))
    }
}

struct NDPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(ND.brand.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct NDSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(ND.link)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(ND.surface.opacity(configuration.isPressed ? 0.6 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ND.border))
    }
}

/// A pill that shows whether it is chosen.
struct NDChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : ND.secondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(selected ? ND.selectedBg : ND.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? ND.link : ND.border, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Chips that wrap onto as many lines as they need.
struct NDFlow: SwiftUI.Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Five-part progress through an area: finished steps turn green.
struct NDProgress: View {
    static let steps = ["Area", "Tile", "Measure", "Extras", "Review"]
    let current: Int
    let completed: Set<Int>
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.steps.indices, id: \.self) { i in
                Button { onSelect(i) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule()
                            .fill(i == current ? ND.link : (completed.contains(i) ? ND.done : ND.border))
                            .frame(height: 4)
                        Text(completed.contains(i) && i != current ? "\(Self.steps[i]) ✓" : Self.steps[i])
                            .font(.system(size: 12, weight: i == current ? .semibold : .regular))
                            .foregroundStyle(i == current ? ND.text : (completed.contains(i) ? ND.secondary : ND.muted))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Self.steps[i])\(completed.contains(i) ? ", done" : "")")
            }
        }
    }
}

/// − count + with large buttons.
struct NDCounter: View {
    let title: String
    @Binding var value: Int
    var enabled = true

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 16, weight: .medium))
            Spacer()
            HStack(spacing: 4) {
                button("minus", label: "One fewer \(title.lowercased())", disabled: value <= 0) { value -= 1 }
                Text("\(value)")
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(value == 0 ? ND.muted : ND.text)
                    .frame(width: 36)
                button("plus", label: "One more \(title.lowercased())", disabled: value >= 50) { value += 1 }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }

    private func button(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .background(ND.raised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? ND.muted : ND.text)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

/// A number box that saves as you type and shows empty instead of a 0 you
/// have to delete.
struct NDNumberField: View {
    let placeholder: String
    @Binding var value: Double
    var font: Font = .system(size: 18, weight: .semibold)
    var alignment: TextAlignment = .leading

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .font(font)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(ND.ground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focused ? ND.link : ND.border, lineWidth: focused ? 2 : 1))
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { _, newText in
                let parsed = Self.parse(newText)
                if parsed != value { value = parsed }
            }
            .onChange(of: value) { _, newValue in
                if Self.parse(text) != newValue { text = Self.format(newValue) }
            }
    }

    static func format(_ v: Double) -> String {
        v == 0 ? "" : v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    static func parse(_ s: String) -> Double {
        let sep = Locale.current.decimalSeparator ?? "."
        let cleaned = s.replacingOccurrences(of: sep, with: ".").filter { "0123456789.".contains($0) }
        return Double(cleaned) ?? 0
    }
}

/// A number field for an optional value such as a tile width.
extension Binding where Value == Double? {
    var orZero: Binding<Double> {
        Binding<Double>(get: { wrappedValue ?? 0 }, set: { wrappedValue = $0 > 0 ? $0 : nil })
    }
}

/// Orange notice with an optional fix-it action.
struct NDWarning: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ND.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(ND.warning)
                Text(message).font(.system(size: 14)).foregroundStyle(ND.secondary)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ND.warning)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(ND.warningBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension Area {
    var ndIcon: String {
        switch self {
        case .floor: "square.grid.3x3"
        case .wall: "square.split.2x2"
        case .tub: "bathtub"
        case .shower: "shower"
        case .backsplash: "rectangle.split.3x1"
        case .fireplace: "fireplace"
        }
    }
}

extension TileChoice {
    /// "Porcelain 12×24 · Running Bond"
    var ndSummary: String {
        let size = [tileWidthIn, tileLengthIn].compactMap { $0 }.map { ND.number($0) }.joined(separator: "×")
        let shapeName = tileSize == .mosaic ? [mosaicStyle?.rawValue, "Mosaic"].compactMap { $0 }.joined(separator: " ") : tileSize.rawValue
        let shape = tileSize == .square || tileSize == .rectangle ? size : [size, shapeName].filter { !$0.isEmpty }.joined(separator: " ")
        let name = tileType.rawValue + (shape.isEmpty ? "" : " " + shape)
        return tileSize == .mosaic ? name : [name, layout.rawValue].joined(separator: " · ")
    }
}

extension EstimateSection {
    /// The section's main tile, when it has been chosen.
    var ndMainTile: TileChoice? {
        guard let tileType, let tileSize, tileSize == .mosaic || layout != nil else { return nil }
        return TileChoice(tileType: tileType, tileSize: tileSize, layout: layout ?? .straightStacked,
                          tileWidthIn: tileWidthIn, tileLengthIn: tileLengthIn, mosaicStyle: mosaicStyle)
    }
}

/// Hides a bottom bar while the keyboard is up, so the keyboard's Done button
/// never sits on top of it.
struct NDHiddenWhileTyping: ViewModifier {
    @State private var keyboardUp = false
    func body(content: Content) -> some View {
        Group {
            if !keyboardUp { content }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
    }
}
