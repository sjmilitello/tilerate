import SwiftUI
import UIKit

// The estimate PDF drawn for a layout (roadmap Phase 4). With the Classic
// layout it is drawn exactly as `ExportedFormPDFView` drew it before layouts
// (EstimateLayoutTests compares the two page by page).

extension EstimateTemplate.Accent {
    /// The title colour and the table header's tint.
    var colors: (strong: Color, tint: Color) {
        switch self {
        case .blue: (Color(red: 0.19, green: 0.53, blue: 0.75), Color(red: 0.92, green: 0.97, blue: 1.0))
        case .teal: (Color(red: 0.08, green: 0.50, blue: 0.52), Color(red: 0.90, green: 0.97, blue: 0.97))
        case .green: (Color(red: 0.18, green: 0.50, blue: 0.28), Color(red: 0.91, green: 0.97, blue: 0.92))
        case .slate: (Color(red: 0.28, green: 0.34, blue: 0.42), Color(red: 0.93, green: 0.94, blue: 0.96))
        case .burgundy: (Color(red: 0.52, green: 0.13, blue: 0.21), Color(red: 0.98, green: 0.92, blue: 0.93))
        case .black: (Color(red: 0.10, green: 0.10, blue: 0.10), Color(red: 0.93, green: 0.93, blue: 0.93))
        }
    }
}

struct TemplatePDFView: View {
    let template: EstimateTemplate
    let biz: PartyInfo
    let cust: PartyInfo
    let estimateNumber: Int
    let date: Date
    let logo: UIImage?
    let rows: [EstimateRow]

    let subtotal: Double
    let shipping: Double
    let taxPercent: Double
    let taxBase: Double

    var style: PDFStyle = .standard

    private var taxAmount: Double { taxBase * (taxPercent / 100.0) }
    private var grandTotal: Double { subtotal + shipping + taxAmount }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(biz.name).font(style.fonts.businessBlockName)
                    Text(biz.address).font(style.fonts.businessBlockLine).fixedSize(horizontal: false, vertical: true)
                    if !biz.address2.isEmpty { Text(biz.address2).font(style.fonts.businessBlockLine) }
                    if !biz.cityStateZip.isEmpty { Text(biz.cityStateZip).font(style.fonts.businessBlockLine) }
                    Text("\(biz.phone)").font(style.fonts.businessBlockLine)
                }
                Spacer(minLength: 20)
                if let uiImg = logo {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 90)
                        .alignmentGuide(.top) { d in d[.top] }
                }
            }
            .padding(.top, style.spacing.pageTop)
            .padding(.horizontal, style.spacing.pageHorizontal)

            Text(template.title)
                .font(style.fonts.pageTitle)
                .foregroundStyle(template.accent.colors.strong)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, style.spacing.titleTop)
                .padding(.horizontal, style.spacing.pageHorizontal)

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ADDRESS").font(style.fonts.sectionCaps)
                    Text(cust.name).font(style.fonts.businessBlockLine)
                    Text(cust.address).font(style.fonts.businessBlockLine)
                    if !cust.address2.isEmpty { Text(cust.address2).font(style.fonts.businessBlockLine) }
                    if !cust.cityStateZip.isEmpty { Text(cust.cityStateZip).font(style.fonts.businessBlockLine) }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(template.title.uppercased()) #  \(String(estimateNumber))")
                        .font(style.fonts.metaSmallBold)
                    Text("DATE  \(dateFormatted(date))")
                        .font(style.fonts.metaSmall)
                    if template.validForDays > 0,
                       let until = Calendar.current.date(byAdding: .day, value: template.validForDays, to: date) {
                        Text("VALID UNTIL  \(dateFormatted(until))")
                            .font(style.fonts.metaSmall)
                    }
                }
            }
            .padding(.top, style.spacing.addressBlockTop)
            .padding(.horizontal, style.spacing.pageHorizontal)

            Divider().padding(.top, style.spacing.betweenMajorBlocks)

            HStack {
                Text("ACTIVITY").font(style.fonts.tableHeader).frame(maxWidth: .infinity, alignment: .leading)
                if template.showQuantities {
                    Text("QTY").font(style.fonts.tableHeader).frame(width: style.layout.qtyWidth, alignment: .trailing)
                    Text("RATE").font(style.fonts.tableHeader).frame(width: style.layout.rateWidth, alignment: .trailing)
                }
                Text("AMOUNT").font(style.fonts.tableHeader).frame(width: style.layout.amountWidth, alignment: .trailing)
            }
            .padding(.horizontal, style.spacing.pageHorizontal)
            .padding(.vertical, style.spacing.tableHeaderVPad)
            .background(template.accent.colors.tint)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    switch row.style {
                    case .block: blockRow(row)
                    case .line: lineRow(row)
                    }
                    Divider()
                }
            }
            .padding(.horizontal, style.spacing.pageHorizontal)

            VStack(spacing: 6) {
                totalLine("SUBTOTAL", subtotal)
                totalLine("SHIPPING", shipping)
                HStack {
                    Spacer()
                    Text("TAX (\(taxPercent, specifier: "%.2f")%)").font(style.fonts.metaSmall)
                    Text(currency(taxAmount))
                        .font(style.fonts.metaSmall)
                        .frame(width: style.layout.amountWidth, alignment: .trailing)
                }
                HStack {
                    Spacer()
                    Text("TOTAL").font(style.fonts.totalLabel)
                    Text(currency(grandTotal))
                        .font(style.fonts.totalLabel)
                        .frame(width: style.layout.amountWidth, alignment: .trailing)
                }
            }
            .padding(.top, style.spacing.totalsTop)
            .padding(.horizontal, style.spacing.pageHorizontal)

            let sections = template.sections.filter { !$0.heading.isEmpty || !$0.body.isEmpty }
            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 3) {
                            if !section.heading.isEmpty {
                                Text(section.heading.uppercased()).font(style.fonts.sectionCaps)
                                    .foregroundStyle(template.accent.colors.strong)
                            }
                            if !section.body.isEmpty {
                                Text(section.body).font(style.fonts.rowBody)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 22)
                .padding(.horizontal, style.spacing.pageHorizontal)
            }

            Spacer()

            if template.showSignature {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Accepted By").font(style.fonts.footerSmall)
                        Rectangle().fill(Color(.separator)).frame(width: 220, height: 1)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Accepted Date").font(style.fonts.footerSmall)
                        Rectangle().fill(Color(.separator)).frame(width: 220, height: 1)
                    }
                }
                .padding(.horizontal, style.spacing.pageHorizontal)
                .padding(.bottom, style.spacing.footerBottom)
                // Room to sign below any text sections (none in Classic).
                .padding(.top, template.sections.contains { !$0.heading.isEmpty || !$0.body.isEmpty } ? 36 : 0)
            } else {
                Color.clear.frame(height: style.spacing.footerBottom)
            }
        }
        .frame(width: 612, alignment: .topLeading)
        .background(Color.white)
    }

    /// An area: its title over its description, the numbers beside the title.
    private func blockRow(_ row: EstimateRow) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: style.spacing.innerDescriptionSpacing) {
                Text(row.title).font(style.fonts.rowTitle)
                if !row.description.isEmpty {
                    Text(row.description)
                        .font(style.fonts.rowBody)
                        .foregroundStyle(style.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !row.details.isEmpty { details(row) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if template.showQuantities {
                Text(row.qty)
                    .frame(width: style.layout.qtyWidth, alignment: .trailing)
                    .font(style.fonts.rowBody)
                Text(currency(row.rate))
                    .frame(width: style.layout.rateWidth, alignment: .trailing)
                    .font(style.fonts.rowBody)
            }
            amount(row)
        }
        .padding(.vertical, style.spacing.rowVPadLarge)
    }

    /// An extra: its title and numbers on one line, its description under it.
    private func lineRow(_ row: EstimateRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(row.title).font(style.fonts.rowTitle)
                Spacer()
                if template.showQuantities {
                    Text(row.qty)
                        .frame(width: style.layout.qtyWidth, alignment: .trailing)
                        .font(style.fonts.rowBody)
                    Text(currency(row.rate))
                        .frame(width: style.layout.rateWidth, alignment: .trailing)
                        .font(style.fonts.rowBody)
                }
                amount(row)
            }
            if !row.description.isEmpty {
                Text(row.description)
                    .font(style.fonts.rowBody)
                    .foregroundStyle(style.colors.textPrimary)
                    .padding(.leading, 4)
            }
            if !row.details.isEmpty { details(row).padding(.leading, 4) }
        }
        .padding(.vertical, style.spacing.rowVPad)
    }

    @ViewBuilder
    private func details(_ row: EstimateRow) -> some View {
        if !row.details.isEmpty {
            Text(row.details.joined(separator: " · "))
                .font(style.fonts.footerSmall)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func amount(_ row: EstimateRow) -> some View {
        if row.taxable {
            HStack(spacing: 2) {
                Text(currency(row.amount)).font(style.fonts.amount)
                Text("T").font(style.fonts.amount)
            }
            .frame(width: style.layout.amountWidth, alignment: .trailing)
        } else {
            Text(currency(row.amount))
                .frame(width: style.layout.amountWidth, alignment: .trailing)
                .font(style.fonts.amount)
        }
    }

    private func totalLine(_ label: String, _ value: Double) -> some View {
        HStack {
            Spacer()
            Text(label).font(style.fonts.metaSmall)
            Text(currency(value))
                .font(style.fonts.metaSmall)
                .frame(width: style.layout.amountWidth, alignment: .trailing)
        }
    }

    private func currency(_ v: Double) -> String { currencyString(v) }
    private func dateFormatted(_ d: Date) -> String {
        let df = DateFormatter(); df.dateStyle = .medium; return df.string(from: d)
    }
}
