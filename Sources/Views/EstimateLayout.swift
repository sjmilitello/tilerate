import Foundation

// The rows of an estimate PDF for a layout (roadmap Phase 4). Only what is
// shown changes from one layout to another: every row's amount comes from the
// same EstimateTotals, and the rows always add up to its subtotal.

/// One row of the PDF table.
struct EstimateRow: Identifiable {
    enum Style {
        /// A title over a wrapping description, numbers beside the title
        /// (an area's installation).
        case block
        /// A title and its numbers on one line, the description under it
        /// (an extra).
        case line
    }
    let id = UUID()
    let style: Style
    let title: String
    let description: String
    /// Smaller lines under the description: the items in a grouped line.
    var details: [String] = []
    /// The area whose wording `description` is, so a preview can edit it.
    var sectionID: UUID? = nil
    let qty: String
    let rate: Double
    let amount: Double
    var taxable: Bool = false
}

/// "Demo: Tile walls" → ("Demo", "Tile walls"); nil for a name with no group.
func priceListGroup(of name: String) -> (group: String, item: String)? {
    let parts = name.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 2, !parts[0].isEmpty else { return nil }
    return (parts[0], parts[1])
}

/// How a price list group is named on menus and estimates.
func priceListGroupTitle(_ group: String) -> String {
    group == "Demo" ? "Demolition" : group
}

/// The extras of one kind (labor or materials) as rows: each on its own, or
/// with grouped items gathered into one line per group, placed where the
/// group's first item was. Taxable and non-taxable items never share a line.
func extraRows(_ items: [AdditionItem], title: String, template: EstimateTemplate) -> [EstimateRow] {
    func single(_ item: AdditionItem) -> EstimateRow {
        EstimateRow(style: .line, title: title, description: item.activity,
                    qty: String(format: "%.2f", item.qty), rate: item.rate, amount: item.amount, taxable: item.taxable)
    }
    guard template.groupPriceList else { return items.map(single) }

    struct Key: Hashable { let group: String; let taxable: Bool }
    var order: [Key] = []
    var members: [Key: [AdditionItem]] = [:]
    var rows: [(Key?, EstimateRow?)] = []
    for item in items {
        guard let g = priceListGroup(of: item.activity) else {
            rows.append((nil, single(item)))
            continue
        }
        let key = Key(group: g.group, taxable: item.taxable)
        if members[key] == nil { order.append(key); rows.append((key, nil)) }
        members[key, default: []].append(item)
    }
    return rows.map { key, row in
        if let row { return row }
        let list = members[key!] ?? []
        if list.count == 1, let only = list.first { return single(only) }
        let total = list.reduce(0) { $0 + $1.amount }
        return EstimateRow(style: .line, title: title, description: priceListGroupTitle(key!.group),
                           details: template.listGroupedItems ? list.map { priceListGroup(of: $0.activity)?.item ?? $0.activity } : [],
                           qty: String(format: "%.2f", 1.0), rate: total, amount: total, taxable: key!.taxable)
    }
}

/// Every row of the estimate for a layout.
func estimateRows(_ totals: EstimateTotals, template: EstimateTemplate) -> [EstimateRow] {
    var rows: [EstimateRow] = []
    for item in totals.sections {
        let labor = extraRows(item.laborItems, title: "Installation", template: template)
        let materials = extraRows(item.materialItems, title: "Sales", template: template)
        switch template.detail {
        case .everyLine:
            rows.append(EstimateRow(style: .block, title: "Installation", description: item.sentence,
                                    sectionID: item.section.id, qty: "1", rate: item.core.total, amount: item.core.total))
            rows += labor
            rows += materials
        case .laborAndMaterials:
            let laborTotal = item.core.total + item.labor
            rows.append(EstimateRow(style: .block, title: "Installation", description: item.sentence,
                                    details: labor.map(\.description), sectionID: item.section.id,
                                    qty: "1", rate: laborTotal, amount: laborTotal))
            if !item.materialItems.isEmpty {
                rows.append(EstimateRow(style: .block, title: "Materials", description: "",
                                        details: materials.map(\.description), qty: "1", rate: item.mats,
                                        amount: item.mats, taxable: item.materialItems.contains(where: \.taxable)))
            }
        case .areaTotals:
            rows.append(EstimateRow(style: .block, title: "Installation", description: item.sentence,
                                    details: (labor + materials).map(\.description), sectionID: item.section.id,
                                    qty: "1", rate: item.subtotal, amount: item.subtotal))
        }
    }
    return rows
}
