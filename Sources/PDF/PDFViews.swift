import PDFKit
import SwiftUI
import UIKit

struct PDFKitPreview: UIViewRepresentable {
    let data: Data
    var onTap: (() -> Void)? = nil

    final class Coordinator: NSObject {
        let onTap: (() -> Void)?
        init(onTap: (() -> Void)?) { self.onTap = onTap }
        @objc func handleTap(_ sender: UITapGestureRecognizer) { onTap?() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.document = PDFDocument(data: data)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        v.addGestureRecognizer(tap)

        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.dataRepresentation() != data {
            uiView.document = PDFDocument(data: data)
        }
    }
}

// MARK: - PDF Style

struct PDFStyle {
    struct Fonts {
        var businessBlockName   = Font.system(size: 15, weight: .semibold)
        var businessBlockLine   = Font.system(size: 13)
        var logoTitle           = Font.system(size: 28, weight: .bold)
        var pageTitle           = Font.system(size: 34, weight: .bold)
        var sectionCaps         = Font.system(size: 11, weight: .semibold)
        var metaSmall           = Font.system(size: 12)
        var metaSmallBold       = Font.system(size: 12, weight: .semibold)
        var tableHeader         = Font.system(size: 11, weight: .semibold)
        var rowTitle            = Font.system(size: 12, weight: .semibold)
        var rowBody             = Font.system(size: 11)
        var amount              = Font.system(size: 12)
        var totalLabel          = Font.system(size: 18, weight: .heavy)
        var footerSmall         = Font.system(size: 10)
    }
    struct Colors {
        var headerBlue = Color(red: 0.92, green: 0.97, blue: 1.0)
        var brandBlue  = Color(red: 0.19, green: 0.53, blue: 0.75)
        var textPrimary = Color.primary
    }
    struct Spacing {
        var pageHorizontal: CGFloat = 36
        var pageTop: CGFloat = 28
        var pageBottom: CGFloat = 28

        var titleTop: CGFloat = 14
        var addressBlockTop: CGFloat = 10
        var tableHeaderVPad: CGFloat = 8

        var rowVPadLarge: CGFloat = 12
        var rowVPad: CGFloat = 10

        var totalsTop: CGFloat = 14
        var footerBottom: CGFloat = 28
        var innerDescriptionSpacing: CGFloat = 4
        var betweenMajorBlocks: CGFloat = 14
    }
    struct Layout {
        var qtyWidth: CGFloat    = 60
        var rateWidth: CGFloat   = 80
        var amountWidth: CGFloat = 110
    }

    var fonts = Fonts()
    var colors = Colors()
    var spacing = Spacing()
    var layout = Layout()

    static let standard = PDFStyle()
}

struct InstallationBlock: Identifiable {
    let id = UUID()
    let description: String
    let amount: Double
    let labor: [AdditionItem]
    let materials: [AdditionItem]
}

struct ExportedFormPDFView: View {
    let biz: PartyInfo
    let cust: PartyInfo
    let estimateNumber: Int
    let date: Date
    let descriptionLine: String
    let forceSinglePage: Bool
    let logo: UIImage?

    let subtotal: Double
    let shipping: Double
    let taxPercent: Double
    let taxBase: Double

    let additionalLabor: [AdditionItem]
    let materials: [AdditionItem]

    let blocks: [InstallationBlock]

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

            Text("Estimate")
                .font(style.fonts.pageTitle)
                .foregroundStyle(style.colors.brandBlue)
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
                    Text("ESTIMATE #  \(String(estimateNumber))")
                        .font(style.fonts.metaSmallBold)
                    Text("DATE  \(dateFormatted(date))")
                        .font(style.fonts.metaSmall)
                }
            }
            .padding(.top, style.spacing.addressBlockTop)
            .padding(.horizontal, style.spacing.pageHorizontal)

            Divider().padding(.top, style.spacing.betweenMajorBlocks)

            HStack {
                Text("ACTIVITY").font(style.fonts.tableHeader).frame(maxWidth: .infinity, alignment: .leading)
                Text("QTY").font(style.fonts.tableHeader).frame(width: style.layout.qtyWidth, alignment: .trailing)
                Text("RATE").font(style.fonts.tableHeader).frame(width: style.layout.rateWidth, alignment: .trailing)
                Text("AMOUNT").font(style.fonts.tableHeader).frame(width: style.layout.amountWidth, alignment: .trailing)
            }
            .padding(.horizontal, style.spacing.pageHorizontal)
            .padding(.vertical, style.spacing.tableHeaderVPad)
            .background(style.colors.headerBlue)

            VStack(spacing: 0) {
                if !blocks.isEmpty {
                    ForEach(blocks) { b in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: style.spacing.innerDescriptionSpacing) {
                                Text("Installation").font(style.fonts.rowTitle)
                                Text(b.description)
                                    .font(style.fonts.rowBody)
                                    .foregroundStyle(style.colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("1")
                                .frame(width: style.layout.qtyWidth, alignment: .trailing)
                                .font(style.fonts.rowBody)
                            Text(currency(b.amount))
                                .frame(width: style.layout.rateWidth, alignment: .trailing)
                                .font(style.fonts.rowBody)
                            Text(currency(b.amount))
                                .frame(width: style.layout.amountWidth, alignment: .trailing)
                                .font(style.fonts.amount)
                        }
                        .padding(.vertical, style.spacing.rowVPadLarge)
                        Divider()

                        if !b.labor.isEmpty {
                            ForEach(b.labor) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Installation").font(style.fonts.rowTitle)
                                        Spacer()
                                        Text("\(row.qty, specifier: "%.2f")")
                                            .frame(width: style.layout.qtyWidth, alignment: .trailing)
                                            .font(style.fonts.rowBody)
                                        Text(currency(row.rate))
                                            .frame(width: style.layout.rateWidth, alignment: .trailing)
                                            .font(style.fonts.rowBody)
                                        Text(currency(row.amount))
                                            .frame(width: style.layout.amountWidth, alignment: .trailing)
                                            .font(style.fonts.amount)
                                    }
                                    if !row.activity.isEmpty {
                                        Text(row.activity)
                                            .font(style.fonts.rowBody)
                                            .foregroundStyle(style.colors.textPrimary)
                                            .padding(.leading, 4)
                                    }
                                }
                                .padding(.vertical, style.spacing.rowVPad)
                                Divider()
                            }
                        }

                        if !b.materials.isEmpty {
                            ForEach(b.materials) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Sales").font(style.fonts.rowTitle)
                                        Spacer()
                                        Text("\(row.qty, specifier: "%.2f")")
                                            .frame(width: style.layout.qtyWidth, alignment: .trailing)
                                            .font(style.fonts.rowBody)
                                        Text(currency(row.rate))
                                            .frame(width: style.layout.rateWidth, alignment: .trailing)
                                            .font(style.fonts.rowBody)
                                        HStack(spacing: 2) {
                                            Text(currency(row.amount)).font(style.fonts.amount)
                                            if row.taxable { Text("T").font(style.fonts.amount) }
                                        }
                                        .frame(width: style.layout.amountWidth, alignment: .trailing)
                                    }
                                    if !row.activity.isEmpty {
                                        Text(row.activity)
                                            .font(style.fonts.rowBody)
                                            .foregroundStyle(style.colors.textPrimary)
                                            .padding(.leading, 4)
                                    }
                                }
                                .padding(.vertical, style.spacing.rowVPad)
                                Divider()
                            }
                        }
                    }
                } else {
                    // Legacy fallback block unchanged in ContentView
                }
            }
            .padding(.horizontal, style.spacing.pageHorizontal)

            VStack(spacing: 6) {
                HStack {
                    Spacer()
                    Text("SUBTOTAL").font(style.fonts.metaSmall)
                    Text(currency(subtotal))
                        .font(style.fonts.metaSmall)
                        .frame(width: style.layout.amountWidth, alignment: .trailing)
                }
                HStack {
                    Spacer()
                    Text("SHIPPING").font(style.fonts.metaSmall)
                    Text(currency(shipping))
                        .font(style.fonts.metaSmall)
                        .frame(width: style.layout.amountWidth, alignment: .trailing)
                }
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

            Spacer()

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
        }
        .frame(width: 612, alignment: .topLeading)
        .background(Color.white)
    }

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
    private func dateFormatted(_ d: Date) -> String {
        let df = DateFormatter(); df.dateStyle = .medium; return df.string(from: d)
    }
}

func currencyString(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = Locale.current.currency?.identifier ?? "USD"
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}

func pdfToImage(data: Data, pageIndex: Int = 0, scale: CGFloat = 2.0) -> UIImage? {
    guard let pdf = PDFDocument(data: data),
          let page = pdf.page(at: pageIndex) else { return nil }

    let pageRect = page.bounds(for: .mediaBox)
    let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
    UIGraphicsBeginImageContextWithOptions(scaledSize, true, 1.0)
    defer { UIGraphicsEndImageContext() }

    guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
    UIColor.white.setFill()
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: 0, y: -pageRect.height)
    page.draw(with: .mediaBox, to: ctx)
    ctx.restoreGState()
    return UIGraphicsGetImageFromCurrentImageContext()
}

func decodeBase64Image(_ b64: String) -> UIImage? {
    guard !b64.isEmpty, let data = Data(base64Encoded: b64) else { return nil }
    return UIImage(data: data)
}
