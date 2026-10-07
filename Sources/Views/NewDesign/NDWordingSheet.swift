import SwiftUI

/// Editing what one area says on the estimate (roadmap Phase 3): the typed
/// words replace the generated sentence on this estimate only. The sheet
/// also shows what the edit would be as a template, and can leave it as a
/// suggestion in Admin → Estimate wording, where it is made permanent.
struct NDWordingSheet: View {
    let section: EstimateSection
    /// The templates this estimate is worded with.
    let wording: WordingTemplates
    let onSave: (String) -> Void
    let onUseGenerated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var suggested = false

    private var current: AreaWording { areaWording(section, wording: wording) }
    private var areaName: String { section.area?.rawValue ?? "area" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Wording", text: $text, axis: .vertical)
                        .lineLimit(3...12)
                } header: {
                    Text("What this \(areaName.lowercased()) says on the estimate")
                } footer: {
                    Text("Changes apply to this estimate only and are saved with it.")
                }

                if text != current.generated {
                    Section {
                        Text(current.generated).font(.footnote).foregroundStyle(.secondary)
                        Button("Use this generated wording instead") {
                            onUseGenerated()
                            dismiss()
                        }
                    } header: {
                        Text("Generated wording")
                    }
                }

                if section.area != nil {
                    templateSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit wording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
            .onAppear { text = current.text }
            .onChange(of: text) { _, _ in suggested = false }
        }
        .preferredColorScheme(.dark)
    }

    /// What the edit would be as this kind of area's template, explained,
    /// with a way to leave it as a suggestion in Admin.
    @ViewBuilder
    private var templateSection: some View {
        let template = templateFromEdit(text, section: section, wording: wording)
        Section {
            if text == current.generated {
                Text("Change the wording above to see how it would read as the wording for every \(areaName.lowercased()).")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if let template, let area = section.area {
                Text(template).font(.callout.monospaced())
                ForEach(templateExplanation(template), id: \.self) { line in
                    Text(line).font(.footnote).foregroundStyle(.secondary)
                }
                Text(example(area, template)).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if suggested {
                    Label("Suggested. To use it for every \(areaName.lowercased()), open Admin → Estimate wording.",
                          systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(.green)
                } else {
                    Button("Suggest this in Admin") {
                        WordingSuggestions.suggest(template, for: area)
                        suggested = true
                    }
                }
            } else {
                Text("The tile description was changed, so this can't become the wording for every \(areaName.lowercased()). How tiles are described is changed in Admin → Estimate wording → Each tile.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("As wording for future estimates")
        } footer: {
            Text("This estimate keeps your wording either way. Wording for future estimates is only changed in Admin, and can always be put back to the standard wording there.")
        }
    }

    /// One line for each brace word in a template, and for brackets.
    private func templateExplanation(_ template: String) -> [String] {
        var lines = WordingTemplates.sentencePlaceholders
            .filter { template.contains("{\($0.name)}") }
            .map { "{\($0.name)} is filled in for each \(areaName.lowercased()): \($0.meaning.lowercased())." }
        if template.contains("[") {
            lines.append("A part in [square brackets] is left out when it has nothing to show.")
        }
        lines.append("Everything else is printed as written.")
        return lines
    }

    /// The template applied to a typical area of this kind.
    private func example(_ area: Area, _ template: String) -> String {
        var w = wording
        w.areas[area] = template
        return "Example: " + describeSection(WordingEditor.example(area), wording: w)
    }
}
