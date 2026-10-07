import SwiftUI

// Admin → Estimate wording (roadmap Phase 3): the templates each area's
// sentence on the estimate is built from, with a live example for each area.

struct WordingSection: View {
    @Binding var wording: WordingTemplates

    var body: some View {
        Section {
            NavigationLink {
                WordingEditor(wording: $wording)
            } label: {
                LabeledContent("Estimate wording", value: WordingSuggestions.all().isEmpty
                               ? (wording == .standard ? "Standard" : "Customized")
                               : "Suggestion waiting")
            }
        } header: {
            Text("Wording")
        } footer: {
            Text("How each area is described on the estimate. Saved estimates keep the wording they were saved with.")
        }
    }
}

struct WordingEditor: View {
    @Binding var wording: WordingTemplates
    @State private var confirmReset = false
    @State private var suggestions: [Area: String] = [:]

    var body: some View {
        Form {
            Section {
                TextField("Tile", text: $wording.tile, axis: .vertical)
                    .font(.callout.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if wording.tile != WordingTemplates.standardTile {
                    Button("Reset to standard") { wording.tile = WordingTemplates.standardTile }
                        .font(.footnote)
                }
            } header: {
                Text("Each tile")
            } footer: {
                placeholderHelp(WordingTemplates.tilePlaceholders)
            }

            Section {
                ForEach(Area.allCases) { area in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(area.rawValue).font(.subheadline.weight(.semibold))
                        TextField("Sentence", text: sentence(area), axis: .vertical)
                            .font(.callout.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Text(describeSection(Self.example(area), wording: wording))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if wording.sentence(for: area) != WordingTemplates.standardSentence {
                            Button("Reset to standard") { wording.areas[area] = WordingTemplates.standardSentence }
                                .font(.footnote)
                                .buttonStyle(.borderless)
                        }
                        if let suggestion = suggestions[area] {
                            suggestionBox(area, suggestion)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Sentence for each area, with an example")
            } footer: {
                placeholderHelp(WordingTemplates.sentencePlaceholders)
            }

            Section {
                Button("Use the Shower sentence for every area") {
                    let shower = wording.sentence(for: .shower)
                    for a in Area.allCases { wording.areas[a] = shower }
                }
                Button("Back to the standard wording", role: .destructive) { confirmReset = true }
                    .disabled(wording == .standard)
            } footer: {
                Text("A word in braces, like {material}, is filled in from the area. A part in square brackets is left out when every brace word in it is empty: \"[ in {layout} pattern]\" disappears for a mosaic, which has no layout. A misspelt brace word is printed as typed, so it shows in the example.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { suggestions = WordingSuggestions.all() }
        .navigationTitle("Estimate wording")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Go back to the standard wording?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Use the standard wording", role: .destructive) { wording = .standard }
        } message: {
            Text("Saved estimates keep the wording they were saved with.")
        }
    }

    /// A sentence suggested from wording typed on an estimate.
    private func suggestionBox(_ area: Area, _ suggestion: String) -> some View {
        var w = wording
        w.areas[area] = suggestion
        return VStack(alignment: .leading, spacing: 6) {
            Label("Suggested from an estimate", systemImage: "lightbulb").font(.footnote.weight(.semibold))
            Text(suggestion).font(.footnote.monospaced())
            Text("Example: " + describeSection(Self.example(area), wording: w))
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 20) {
                Button("Use this suggestion") {
                    wording.areas[area] = suggestion
                    WordingSuggestions.remove(area)
                    suggestions = WordingSuggestions.all()
                }
                Button("Dismiss", role: .destructive) {
                    WordingSuggestions.remove(area)
                    suggestions = WordingSuggestions.all()
                }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sentence(_ area: Area) -> Binding<String> {
        Binding(get: { wording.sentence(for: area) }, set: { wording.areas[area] = $0 })
    }

    private func placeholderHelp(_ list: [(name: String, meaning: String)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(list, id: \.name) { p in
                Text("{\(p.name)}").font(.footnote.monospaced()) + Text("  \(p.meaning)").font(.footnote)
            }
        }
    }

    /// A typical area of each kind, for the examples.
    static func example(_ area: Area) -> EstimateSection {
        var s = EstimateSection()
        s.area = area
        s.tileType = .porcelain
        s.tileSize = .rectangle
        s.layout = .runningBond
        s.tileWidthIn = 12
        s.tileLengthIn = 24
        switch area {
        case .shower:
            s.measurements.showerWallsSqft = 80
            s.measurements.showerFloorSqft = 15
            s.showerFloorTile = TileChoice(tileType: .porcelain, tileSize: .mosaic, layout: .straightStacked,
                                           mosaicStyle: .hexagon)
            s.features.niches = 1
            s.features.benches = 1
        case .tub:
            s.tileType = .ceramic
            s.tileWidthIn = 3; s.tileLengthIn = 6
            s.measurements.sqft = 60
            s.features.niches = 1
        case .floor:
            s.layout = .herringbone
            s.measurements.sqft = 120
        case .wall:
            s.measurements.sqft = 60
        case .backsplash:
            s.tileType = .marble
            s.tileSize = .mosaic
            s.mosaicStyle = .pennyRound
            s.measurements.sqft = 30
        case .fireplace:
            s.tileWidthIn = 24; s.tileLengthIn = 48
            s.layout = .straightStacked
            s.measurements.sqft = 40
        }
        return s
    }
}
