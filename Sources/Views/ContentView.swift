
//
//  ContentView.swift
//  Integrity Tile Estimator
//
//  Created by Salvatore Militello on 8/20/25.
//
//  All‑in‑one SwiftUI file: models + state + pricing + UI.
//

import SwiftUI
import Foundation
import UIKit
import Photos
import SwiftUI
import Foundation
import SwiftData   // <- for the compatibility shim at the bottom
import PDFKit
// Dismiss the keyboard from anywhere
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
private struct DismissKeyboardBackground: View {
    var active: Bool
    var body: some View {
        Color.clear
            .contentShape(Rectangle()) // makes empty areas tappable
            .onTapGesture {
                guard active else { return }
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
    }
}
// MARK: - Activity (Share) Sheet
// ===== Share presenter (imperative UIKit) =====
private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first(where: { $0.isKeyWindow }) }
}


// MARK: - Robust Share Presenter (Main-Actor + no data races)
@MainActor
private func presentSystemShareSheet(for url: URL, pdfData: Data? = nil) {
    // Build the items array: PDF URL + (optional) rendered image
    var items: [Any] = [url]
    if let data = pdfData, let img = pdfToImage(data: data) {
        items.append(img)
    }

    // Resolve active scene, key window, and its root VC once (on main actor)
    guard
        let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
        let window = scene.windows.first(where: { $0.isKeyWindow }),
        let root   = window.rootViewController
    else { return }

    // Poll on the main actor until the SwiftUI sheet is fully dismissed
    Task { @MainActor in
        var presenter: UIViewController = root

        // Try for ~1.5s (30 * 50ms)
        for _ in 0..<30 {
            if root.presentedViewController == nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        presenter = root.presentedViewController ?? root

        let avc = UIActivityViewController(activityItems: items, applicationActivities: nil)

        // iPad popover (harmless on iPhone)
        avc.popoverPresentationController?.sourceView = window
        avc.popoverPresentationController?.sourceRect = CGRect(
            x: window.bounds.midX, y: window.bounds.maxY - 1, width: 1, height: 1
        )

        presenter.present(avc, animated: true)
    }
}
@MainActor
private func presentPDFShareSheet(url: URL) {
    guard
        let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
        let window = scene.windows.first(where: { $0.isKeyWindow }),
        let root   = window.rootViewController
    else { return }

    Task { @MainActor in
        for _ in 0..<30 {
            if root.presentedViewController == nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let presenter = root.presentedViewController ?? root
        let avc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        avc.popoverPresentationController?.sourceView = window
        avc.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.maxY - 1, width: 1, height: 1)
        presenter.present(avc, animated: true)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
// MARK: - PDFKit Preview (Data-based) + Tap Support
struct PDFKitPreview: UIViewRepresentable {
    let data: Data
    var onTap: (() -> Void)? = nil   // NEW

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

        // Add a tap recognizer directly to the PDFView
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false   // keep scrolling/zooming working
        v.addGestureRecognizer(tap)

        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Update the document only if changed
        if uiView.document?.dataRepresentation() != data {
            uiView.document = PDFDocument(data: data)
        }
    }
}
struct AdditionItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var activity: String = ""
    var qty: Double = 1
    var rate: Double = 0
    var taxable: Bool = false   // used for Materials; ignored for Labor
    var amount: Double { qty * rate }
}
// MARK: - PDF Style (centralized; values match your current UI exactly)
struct PDFStyle {
    struct Fonts {
        // EXACT values you currently use
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
        // EXACT values you currently use
        var headerBlue = Color(red: 0.92, green: 0.97, blue: 1.0)
        var brandBlue  = Color(red: 0.19, green: 0.53, blue: 0.75)
        var textPrimary = Color.primary
    }
    struct Spacing {
        // EXACT paddings/margins you currently use in the view
        var pageHorizontal: CGFloat = 36
        var pageTop: CGFloat = 28
        var pageBottom: CGFloat = 28

        var titleTop: CGFloat = 14
        var addressBlockTop: CGFloat = 10
        var tableHeaderVPad: CGFloat = 8

        var rowVPadLarge: CGFloat = 12  // installation summary row
        var rowVPad: CGFloat = 10       // other rows

        var totalsTop: CGFloat = 14
        var footerBottom: CGFloat = 28
        var innerDescriptionSpacing: CGFloat = 4
        var betweenMajorBlocks: CGFloat = 14
    }
    struct Layout {
        // EXACT column widths you currently use
        var qtyWidth: CGFloat    = 60
        var rateWidth: CGFloat   = 80
        var amountWidth: CGFloat = 110
    }

    var fonts = Fonts()
    var colors = Colors()
    var spacing = Spacing()
    var layout = Layout()

    // default style (same as your current look)
    static let standard = PDFStyle()
}

// MARK: - ExportedFormPDFView (now reads from PDFStyle, defaults to .standard)
struct ExportedFormPDFView: View {
    // Props
    let biz: PartyInfo
    let cust: PartyInfo
    let estimateNumber: Int
    let date: Date
    let descriptionLine: String
    let forceSinglePage: Bool

    // Money inputs
    let subtotal: Double
    let shipping: Double
    let taxPercent: Double
    let taxBase: Double

    // Additions
    let additionalLabor: [AdditionItem]
    let materials: [AdditionItem]

    // Centralized style (defaults keep visuals identical)
    var style: PDFStyle = .standard

    private var taxAmount: Double { taxBase * (taxPercent / 100.0) }
    private var grandTotal: Double { subtotal + shipping + taxAmount }

    var body: some View {
        VStack(spacing: 0) {

            // === HEADER (Business block left, Logo right) ===
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(biz.name).font(style.fonts.businessBlockName)
                    Text(biz.address).font(style.fonts.businessBlockLine).fixedSize(horizontal: false, vertical: true)
                    if !biz.address2.isEmpty { Text(biz.address2).font(style.fonts.businessBlockLine) }
                    if !biz.cityStateZip.isEmpty { Text(biz.cityStateZip).font(style.fonts.businessBlockLine) }
                    Text("+\(biz.phone)").font(style.fonts.businessBlockLine)
                }
                Spacer(minLength: 20)

                if let uiImg = UIImage(named: "PDFLogo") {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 90)
                        .alignmentGuide(.top) { d in d[.top] }
                } else {
                    Text(biz.name)
                        .font(style.fonts.logoTitle)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            .padding(.top, style.spacing.pageTop)
            .padding(.horizontal, style.spacing.pageHorizontal)

            // === BIG PAGE TITLE ===
            Text("Estimate")
                .font(style.fonts.pageTitle)
                .foregroundStyle(style.colors.brandBlue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, style.spacing.titleTop)
                .padding(.horizontal, style.spacing.pageHorizontal)

            // === ADDRESS + META ===
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

            // === TABLE HEADER ===
            HStack {
                Text("ACTIVITY").font(style.fonts.tableHeader).frame(maxWidth: .infinity, alignment: .leading)
                Text("QTY").font(style.fonts.tableHeader).frame(width: style.layout.qtyWidth, alignment: .trailing)
                Text("RATE").font(style.fonts.tableHeader).frame(width: style.layout.rateWidth, alignment: .trailing)
                Text("AMOUNT").font(style.fonts.tableHeader).frame(width: style.layout.amountWidth, alignment: .trailing)
            }
            .padding(.horizontal, style.spacing.pageHorizontal)
            .padding(.vertical, style.spacing.tableHeaderVPad)
            .background(style.colors.headerBlue)

            // === ROWS ===
            VStack(spacing: 0) {
                // Installation summary (computed base work line)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: style.spacing.innerDescriptionSpacing) {
                        Text("Installation").font(style.fonts.rowTitle)
                        Text(descriptionLine)
                            .font(style.fonts.rowBody)
                            .foregroundStyle(style.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    let installationOnly = subtotal
                        - additionalLabor.reduce(0){ $0 + $1.amount }
                        - materials.reduce(0){ $0 + $1.amount }

                    Text("1")
                        .frame(width: style.layout.qtyWidth, alignment: .trailing)
                        .font(style.fonts.rowBody)
                    Text(currency(installationOnly))
                        .frame(width: style.layout.rateWidth, alignment: .trailing)
                        .font(style.fonts.rowBody)
                    Text(currency(installationOnly))
                        .frame(width: style.layout.amountWidth, alignment: .trailing)
                        .font(style.fonts.amount)
                }
                .padding(.vertical, style.spacing.rowVPadLarge)
                Divider()

                // Additional Labor rows (as "Installation" + description under)
                if !additionalLabor.isEmpty {
                    ForEach(additionalLabor) { row in
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

                // Materials rows (as "Sales" + description under, with "T" for taxable)
                if !materials.isEmpty {
                    ForEach(materials) { row in
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
            .padding(.horizontal, style.spacing.pageHorizontal)

            // === TOTALS ===
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

            // === ACCEPTANCE LINES ===
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

    // Helpers
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
// File-scope currency helper for nested views
private func currencyString(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = Locale.current.currency?.identifier ?? "USD"
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}
private func pdfToImage(data: Data, pageIndex: Int = 0, scale: CGFloat = 2.0) -> UIImage? {
    guard let pdf = PDFDocument(data: data),
          let page = pdf.page(at: pageIndex) else { return nil }

    let pageRect = page.bounds(for: .mediaBox)
    let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
    UIGraphicsBeginImageContextWithOptions(scaledSize, true, 1.0)
    defer { UIGraphicsEndImageContext() }

    guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
    UIColor.white.setFill()
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: -scale)                  // flip vertically
    ctx.translateBy(x: 0, y: -pageRect.height)        // shift back into place
    page.draw(with: .mediaBox, to: ctx)
    ctx.restoreGState()
    return UIGraphicsGetImageFromCurrentImageContext()
}
// MARK: - PDF Rendering
enum PDFGenerator {
    /// Renders a SwiftUI view to PDF.
    /// - Parameters:
    ///   - view: SwiftUI view (can be arbitrarily tall)
    ///   - pageSize: PDF page size (Default US Letter @ 72 dpi)
    ///   - forceSinglePage: If true, the whole view is scaled to fit one page; otherwise it paginates.
    static func render<V: View>(
        view: V,
        pageSize: CGSize = CGSize(width: 612, height: 792),
        forceSinglePage: Bool
    ) throws -> Data {
        // 1) Host the SwiftUI view
        let controller = UIHostingController(rootView: view)
        let hostingView = controller.view!
        hostingView.backgroundColor = .white

        // Force Light so .primary/.secondary are dark on white
        controller.overrideUserInterfaceStyle = .light

        // Put it in a window so layout works
        let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: pageSize.width, height: pageSize.height)))
        window.rootViewController = controller
        window.isHidden = false

        // 2) Size the view to its natural (very tall) height at the fixed page width
        let targetWidth = pageSize.width
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.widthAnchor.constraint(equalToConstant: targetWidth)
        ])
        // Let Auto Layout compute the height
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        // Ask for the compressed size (height can expand)
        let contentSize = hostingView.systemLayoutSizeFitting(
            CGSize(width: targetWidth, height: UIView.layoutFittingExpandedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        // IMPORTANT: make contentHeight integral to avoid sub-pixel repeats
        let contentHeight = ceil(max(contentSize.height, pageSize.height))
        // Make sure the view has that full height so it can render beyond the first screenful
        hostingView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: contentHeight)
        hostingView.setNeedsLayout()
        hostingView.layoutIfNeeded()

        // 3) Render
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)

        let data = renderer.pdfData { ctx in
            if forceSinglePage {
                // Scale everything to fit into a single page
                ctx.beginPage()
                let scale = min(pageSize.width / targetWidth, pageSize.height / contentHeight)
                let dx = (pageSize.width  - targetWidth  * scale) / 2.0
                let dy = (pageSize.height - contentHeight * scale) / 2.0
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: dx, y: dy)
                ctx.cgContext.scaleBy(x: scale, y: scale)
                hostingView.layer.render(in: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
            // PAGINATED path — rasterize once, then slice per page (no repeats, no cut lines)
            else {
                let dpi72: CGFloat = 72.0
                let margin: CGFloat = 0.5 * dpi72   // 36pt = 1/2"
                let bottomMarginAll: CGFloat = margin
                let topMarginFirst: CGFloat = 0
                let topMarginOther: CGFloat = margin

                // Small “breathing” guards so rows are not clipped by the page edge
                let guardTop: CGFloat = 4
                let guardBottom: CGFloat = 14

                // 1) Rasterize the entire SwiftUI view once at 2x for sharp text
                let renderScale: CGFloat = 2.0
                let imgSizePts = CGSize(width: targetWidth, height: contentHeight)
                let imgSizePx = CGSize(width: imgSizePts.width * renderScale, height: imgSizePts.height * renderScale)

                let rendererFmt = UIGraphicsImageRendererFormat()
                rendererFmt.scale = renderScale
                rendererFmt.opaque = true
                let imageRenderer = UIGraphicsImageRenderer(size: imgSizePts, format: rendererFmt)

                let fullImage = imageRenderer.image { _ in
                    // Important: render the CALayer once into the bitmap
                    hostingView.layer.render(in: UIGraphicsGetCurrentContext()!)
                }
              
                guard let fullCG = fullImage.cgImage else { return }                // 2) Walk pages by *pixel-perfect* slices from the raster
                var yPts: CGFloat = 0
                var pageIndex = 0

                while yPts < contentHeight - 0.1 {
                    ctx.beginPage()

                    let topM: CGFloat = (pageIndex == 0) ? topMarginFirst : topMarginOther
                    let pageHeightPts = max(0, pageSize.height - topM - bottomMarginAll)
                    let visibleHeightPts = max(0, pageHeightPts - guardTop - guardBottom)

                    // Source rect in *pixels* (integral to avoid repeats)
                    let srcXpx: CGFloat = 0
                    let srcYpx: CGFloat = floor((yPts) * renderScale)
                    let srcWpx: CGFloat = floor(targetWidth * renderScale)
                    let sliceHpx: CGFloat = floor(visibleHeightPts * renderScale)

                    // Clamp last slice
                    let maxSliceHpx = max(0, min(sliceHpx, (imgSizePx.height - srcYpx)))
                    if maxSliceHpx <= 0 { break }

                    let srcRectPx = CGRect(x: srcXpx, y: srcYpx, width: srcWpx, height: maxSliceHpx)
                    guard let slice = fullCG.cropping(to: srcRectPx) else { break }

                    // Destination rect in *points* (exactly inside margins + guards)
                    let dest = CGRect(x: 0, y: topM + guardTop, width: pageSize.width, height: maxSliceHpx / renderScale)

                    // NEW — flip PDF coord system to UIKit-style before drawing
                    ctx.cgContext.saveGState()
                    ctx.cgContext.interpolationQuality = .high

                    // Flip the context vertically so y=0 is at the top
                    ctx.cgContext.translateBy(x: 0, y: pageSize.height)
                    ctx.cgContext.scaleBy(x: 1, y: -1)

                    // Because we flipped, we must also flip the destination rect’s y
                    let flippedDest = CGRect(
                        x: dest.origin.x,
                        y: pageSize.height - (dest.origin.y + dest.size.height),
                        width: dest.size.width,
                        height: dest.size.height
                    )

                    ctx.cgContext.draw(slice, in: flippedDest)
                    ctx.cgContext.restoreGState()                    // Advance by exactly what we drew (in points)
                    yPts += dest.height
                    pageIndex += 1
                }
            }
        }
                    return data
                }

                /// Save PDF data to a temporary file and return the file URL.
                static func writeToTempFile(_ data: Data, suggestedName: String = "Estimate.pdf") throws -> URL {
                    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suggestedName)
                    try data.write(to: url, options: .atomic)
                    return url
                }
            }
// MARK: - File-scope helpers (fixes: “Array has no member 'chunked'”)
private func intFormatter() -> NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .none
    f.minimum = 0
    f.maximum = 999
    return f
}

extension Array {
    /// Split array into consecutive chunks of a given size.
    /// If `size <= 0`, returns `[self]`.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var i = 0
        while i < count {
            let end = Swift.min(i + size, count)
            chunks.append(Array(self[i..<end]))
            i = end
        }
        return chunks
    }
}

/// Checkbox + numeric field row
private func quantityRow(_ title: String, value: Binding<Int>) -> some View {
    let isOn = Binding<Bool>(
        get: { value.wrappedValue > 0 },
        set: { on in
            if on {
                if value.wrappedValue == 0 { value.wrappedValue = 1 }
            } else {
                value.wrappedValue = 0
            }
        }
    )

    return VStack(alignment: .leading, spacing: 8) {
        Toggle("\(title)?", isOn: isOn)
        TextField("0", value: value, formatter: intFormatter())
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .disabled(!isOn.wrappedValue)
            .opacity(isOn.wrappedValue ? 1 : 0.5)
    }
}

// Rounded, full‑width numeric field with a title above it
private func measurementField(_ title: String,
                              value: Binding<Double>,
                              enabled: Bool = true) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline).fontWeight(.semibold)
        TextField("0", value: value, formatter: decimalFormatter())
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .disabled(!enabled)
    }
}


/// Toggle + field below it for ceiling input, bound to whether the value > 0.
private func ceilingBlock(title: String,
                          ceilingValue: Binding<Double>,
                          ceilingLabel: String) -> some View {
    let isOn = Binding<Bool>(
        get: { ceilingValue.wrappedValue > 0 },
        set: { on in
            if on {
                if ceilingValue.wrappedValue <= 0 { ceilingValue.wrappedValue = 1 }
            } else {
                ceilingValue.wrappedValue = 0
            }
        }
    )

    return VStack(alignment: .leading, spacing: 8) {
        Toggle(title, isOn: isOn)
        measurementField(ceilingLabel, value: ceilingValue, enabled: isOn.wrappedValue)
            .opacity(isOn.wrappedValue ? 1 : 0.5)
    }
}

/// Simple decimal formatter for sqft fields
private func decimalFormatter() -> NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 2
    f.minimum = 0
    return f
}
// Used by several places in the UI
private func numberField(_ title: String, value: Binding<Double>) -> some View {
    HStack {
        Text(title)
        Spacer()
        TextField("0", value: value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.leading)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 140)
    }
}






// MARK: - Domain Models

enum Area: String, CaseIterable, Codable, Identifiable {
    case floor = "Floor"
    case wall = "Wall"
    case tub = "Tub Surround"
    case shower = "Shower"
    case backsplash = "Backsplash"
    case fireplace = "Fireplace"
    var id: String { rawValue }
}

enum TileType: String, CaseIterable, Codable, Identifiable {
    case ceramic = "Ceramic"
    case porcelain = "Porcelain"
    case glass = "Glass"
    case marble = "Marble"
    case limestone = "Limestone/Travertine"
    case slate = "Slate"
    var id: String { rawValue }
}

enum TileSize: String, CaseIterable, Codable, Identifiable {
    case lt12     = "Square/Rectangle Less than 12\""
    case r12to24  = "Square/Rectangle 12\"-24\""
    case gt24     = "Square/Rectangle More than 24\""
    case shape    = "Shape (Hexagon, Triangle, Etc...)"
    case mosaic   = "Mosaic"
    var id: String { rawValue }
}

enum Layout: String, CaseIterable, Codable, Identifiable {
    case straight = "Straight"
    case runningBond = "Running Bond"
    case diagonal = "Diagonal"
    case herringbone = "Herringbone"
    case multiTile = "Multi-Tile"
    var id: String { rawValue }
}


// MARK: - Parties
struct PartyInfo {
    var name: String
    var address: String
    var address2: String = ""      // if you’ve added these fields
    var cityStateZip: String = ""  // safe defaults
    var phone: String
    var email: String
}
// MARK: - Editable Rates (Admin)

enum AdderUnit: String, Codable, CaseIterable, Identifiable {
    case perSqft = "per sqft"
    case percent = "%"
    var id: String { rawValue }
}

struct Rates: Codable {
    var base: [Area: Double] = [
        .floor: 23, .wall: 25, .tub: 26, .shower: 32, .backsplash: 22, .fireplace: 28
    ]
    var minimum: [Area: Double] = [
        .floor: 600, .wall: 600, .tub: 900, .shower: 1200, .backsplash: 300, .fireplace: 500
    ]

    var ceilingBase: Double = 23
    var ceilingMinimum: Double = 600

    var showerFloorBase: Double = 23
    var showerFloorMinimum: Double = 600

    // Adders (numbers are interpreted per the units below)
    var typeAdder: [TileType: Double] = [
        .ceramic: 0, .porcelain: 0, .glass: 0, .marble: 0, .limestone: 0, .slate: 0
    ]
    var sizeAdder: [TileSize: Double] = [
        .mosaic: 0, .lt12: 0, .r12to24: 0, .gt24: 0, .shape: 0
    ]
    var layoutAdder: [Layout: Double] = [
        .straight: 0, .runningBond: 0, .diagonal: 0, .herringbone: 0, .multiTile: 0
    ]

    // 🔹 NEW: units that control how the above numbers are interpreted
    var typeAdderUnit: AdderUnit = .perSqft
    var sizeAdderUnit: AdderUnit = .perSqft
    var layoutAdderUnit: AdderUnit = .perSqft

    var mosaicInlayRate: Double = 0 // still $/sqft

    var unitShelf: Double = 600
    var unitNiche: Double = 600
    var unitFootrest: Double = 200
    var unitBench: Double = 200

    var floorEscThresholdLower: Int = 50
    var floorEscThresholdUpper: Int = 99
    var floorEscAdjPerSqft: Double = 0
}
// Unit choices
var typeAdderUnit: AdderUnit = .perSqft
var sizeAdderUnit: AdderUnit = .perSqft
var layoutAdderUnit: AdderUnit = .perSqft
var floorEscUnit: AdderUnit = .perSqft
// MARK: - Measurements & Features

struct Measurements: Codable, Equatable, Hashable {
    var sqft: Double = 0
    var showerWallsSqft: Double = 0
    var showerFloorSqft: Double = 0
    var ceilingSqft: Double = 0
    var mosaicSqft: Double = 0
}

struct Features: Codable, Equatable, Hashable {
    var mosaicBand: Bool = false
    var shelves: Int = 0
    var niches: Int = 0
    var footrests: Int = 0
    var benches: Int = 0
}
struct EstimatorState: Codable {
    var stepIndex: Int = 0
    var area: Area? = nil
    var tileType: TileType? = nil
    var tileSize: TileSize? = nil
    var layout: Layout? = nil
    var features = Features()
    var measurements = Measurements()

    // NEW
    var additionsLabor: [AdditionItem] = []
    var additionsMaterials: [AdditionItem] = []
}

extension EstimatorState {
    var additionsLaborTotal: Double {
        additionsLabor.reduce(0) { $0 + $1.amount }
    }
    var additionsMaterialsTotal: Double {
        additionsMaterials.reduce(0) { $0 + $1.amount }
    }
    var additionsMaterialsTaxableBase: Double {
        additionsMaterials.filter { $0.taxable }.reduce(0) { $0 + $1.amount }
    }
}
// === Multi-room data model ===

struct EstimateSection: Identifiable, Codable, Hashable, Equatable {
    var id = UUID()
    var roomName: String = ""
     var area: Area? = nil
     var tileType: TileType? = nil
     var tileSize: TileSize? = nil
     var layout: Layout? = nil
     var features = Features()
     var measurements = Measurements()
     var additionsLabor: [AdditionItem] = []
     var additionsMaterials: [AdditionItem] = []
 }
struct EstimateRoom: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String = "Room"
    var sections: [EstimateSection] = []
}

struct EstimateDocument: Codable {
    var rooms: [EstimateRoom] = []
}
// MARK: - Store (Persistence)

final class Store: ObservableObject {
    // Existing single-state (kept so app still works if no rooms yet)
    @Published var state: EstimatorState { didSet { save() } }

    // Rates stay the same
    @Published var rates: Rates { didSet { saveRates() } }

    // NEW: multi-room document
    @Published var doc: EstimateDocument { didSet { saveDoc() } }

    private let stateKey = "integrity.state"
    private let ratesKey = "integrity.rates"
    private let docKey   = "integrity.document"     // NEW

    init() {
        if let s = Self.load(EstimatorState.self, key: stateKey) { state = s } else { state = EstimatorState() }
        if let r = Self.load(Rates.self, key: ratesKey) { rates = r } else { rates = Rates() }
        if let d = Self.load(EstimateDocument.self, key: docKey) { doc = d } else { doc = EstimateDocument() }
    }

    func reset() {
        state = EstimatorState()
        doc   = EstimateDocument()
    }

    private func save()     { Self.persist(state, key: stateKey) }
    private func saveRates(){ Self.persist(rates, key: ratesKey) }
    private func saveDoc()  { Self.persist(doc,   key: docKey) }

    private static func persist<T: Codable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
    private static func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
// MARK: - Pricing

struct Line: Identifiable {
    let id = UUID()
    let label: String
    var qty: Double = 0        // quantity (e.g., sqft or units)
    var rate: Double = 0       // unit rate
    let amount: Double         // extended amount
}

struct Summary {
    let lines: [Line]
    let total: Double
}
@inline(__always)
private func perSqftAdder(from raw: Double, unit: AdderUnit, baseRatePerSqft: Double) -> Double {
    switch unit {
    case .perSqft: return raw                      // already $/sf
    case .percent: return baseRatePerSqft * (raw / 100.0) // % of base rate per sqft
    }
}// Convert a stored adder (either $/sqft or %) to a per-sqft number
private func perSqft(from value: Double, unit: AdderUnit, baseRate: Double) -> Double {
    switch unit {
    case .perSqft: return value
    case .percent: return baseRate * (value / 100.0)
    }
}

// Build a single per-sqft “adder” from type/size/layout based on selected units
private func unitAwareAddersPerSq(baseRate: Double,
                                  type: TileType,
                                  size: TileSize,
                                  layout: Layout,
                                  rates: Rates) -> Double {
    let typePerSq   = perSqft(from: rates.typeAdder[type] ?? 0,
                              unit: rates.typeAdderUnit,
                              baseRate: baseRate)
    let sizePerSq   = perSqft(from: rates.sizeAdder[size] ?? 0,
                              unit: rates.sizeAdderUnit,
                              baseRate: baseRate)
    let layoutPerSq = perSqft(from: rates.layoutAdder[layout] ?? 0,
                              unit: rates.layoutAdderUnit,
                              baseRate: baseRate)
    return typePerSq + sizePerSq + layoutPerSq
}
// Escalator adjustment per sqft (always $/sqft now)
@inline(__always)
private func escalatorAdjPerSqft(rates: Rates) -> Double {
    rates.floorEscAdjPerSqft
}
func computeSummary(state: EstimatorState, rates: Rates) -> Summary {
    var lines: [Line] = []
    guard let area = state.area,
          let type = state.tileType,
          let size = state.tileSize,
          let layout = state.layout
    else { return Summary(lines: [], total: 0) }

    // Modified append to accept addersPerSq (we’ll pass it in per-component)
    @discardableResult
    func appendComponent(labelPrefix: String,
                         sqft: Double,
                         baseRate: Double,
                         minCharge: Double?,
                         addersPerSq: Double) -> Double {
        guard sqft > 0 else { return 0 }

        let baseOnlyRaw = baseRate * sqft
        let addersRaw   = addersPerSq * sqft
        let perSq       = baseRate + addersPerSq
        let raw         = perSq * sqft

        if let min = minCharge, baseOnlyRaw < min {
            lines.append(Line(label: "\(labelPrefix) — Minimum Applied", amount: min))
            if addersPerSq != 0 {
                lines.append(Line(label: "\(labelPrefix) adders @ \(currency(rates: rates, value: addersPerSq))/sqft × \(Int(sqft.rounded()))",
                                  amount: addersRaw))
            }
            return min + addersRaw
        } else {
            if let min = minCharge, min > raw {
                lines.append(Line(label: "\(labelPrefix) — Minimum Applied", amount: min))
                return min
            } else {
                lines.append(Line(label: "\(labelPrefix) @ \(currency(rates: rates, value: perSq))/sqft × \(Int(sqft.rounded()))",
                                  amount: raw))
                return raw
            }
        }
    }

    func currency(rates: Rates, value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    var running: Double = 0
    @inline(__always)
    func addUnits(_ label: String, qty: Int, rate: Double) {
        guard qty > 0, rate != 0 else { return }
        let amt = Double(qty) * rate
        lines.append(Line(label: "\(label) (\(qty)× @ \(currency(rates: rates, value: rate)))", amount: amt))
        running += amt
    }
    switch area {
    case .shower:
        let baseWalls = rates.base[.shower] ?? 0
        let addersWalls = unitAwareAddersPerSq(baseRate: baseWalls, type: type, size: size, layout: layout, rates: rates)
        running += appendComponent(labelPrefix: "Shower walls",
                                   sqft: state.measurements.showerWallsSqft,
                                   baseRate: baseWalls,
                                   minCharge: rates.minimum[.shower],
                                   addersPerSq: addersWalls)

        let baseShFloor = rates.showerFloorBase
        let addersShFloor = unitAwareAddersPerSq(baseRate: baseShFloor, type: type, size: size, layout: layout, rates: rates)
        running += appendComponent(labelPrefix: "Shower floor",
                                   sqft: state.measurements.showerFloorSqft,
                                   baseRate: baseShFloor,
                                   minCharge: rates.showerFloorMinimum,
                                   addersPerSq: addersShFloor)

    default:
        if area == .floor {
            let sqft      = state.measurements.sqft
            let sqftInt   = Int(floor(sqft))
            let baseFloor = rates.base[.floor] ?? 0
            let minCharge = rates.minimum[.floor] ?? 0

            // Per-sqft adders (type/size/layout) based on unit settings
            let addersPerSq = unitAwareAddersPerSq(
                baseRate: baseFloor,
                type: type,
                size: size,
                layout: layout,
                rates: rates
            )

            // Escalator window and per-sqft escalator (unit aware)
            let lower = max(0, rates.floorEscThresholdLower)        // e.g. 50
            let upper = max(lower, rates.floorEscThresholdUpper)    // e.g. 99
            let perSqEsc = escalatorAdjPerSqft(rates: rates)

            // Units over 'lower', capped by 'upper'
            let unitsOverLower = max(0, min(sqftInt, upper) - lower)
            let escalatorPart  = Double(unitsOverLower) * perSqEsc

            // ---- Base-before-adders candidates ----
            let baseOnlyRaw   = baseFloor * sqft
            let minOnlyRaw    = minCharge
            let minPlusEscRaw = minCharge + escalatorPart

            // Choose the greatest
            let baseBeforeAdders = max(baseOnlyRaw, max(minOnlyRaw, minPlusEscRaw))

            // Emit explanatory lines for base
            if baseBeforeAdders == baseOnlyRaw && baseOnlyRaw > max(minOnlyRaw, minPlusEscRaw) {
                // Base rate x sqft won
                lines.append(Line(
                    label: "Floor @ \(currency(rates: rates, value: baseFloor))/sqft × \(Int(sqft.rounded()))",
                    amount: baseOnlyRaw
                ))
            } else {
                // Minimum (and maybe escalator) drove the price
                if minCharge > 0 {
                    lines.append(Line(label: "Floor — Minimum Applied", amount: minCharge))
                }
                if escalatorPart > 0 {
                    lines.append(Line(
                        label: "Floor escalator @ \(currency(rates: rates, value: perSqEsc))/sqft × \(unitsOverLower)",
                        amount: escalatorPart
                    ))
                }
            }

            // ---- Adders go on top of the chosen base ----
            let addersRaw = addersPerSq * sqft
            if addersPerSq != 0 {
                lines.append(Line(
                    label: "Floor adders @ \(currency(rates: rates, value: addersPerSq))/sqft × \(Int(sqft.rounded()))",
                    amount: addersRaw
                ))
            }

            running += baseBeforeAdders + addersRaw

        } else {
            // All other areas use the standard component logic (unchanged)
            let baseRate = rates.base[area] ?? 0
            let adders   = unitAwareAddersPerSq(baseRate: baseRate, type: type, size: size, layout: layout, rates: rates)
            running += appendComponent(labelPrefix: area.rawValue,
                                       sqft: state.measurements.sqft,
                                       baseRate: baseRate,
                                       minCharge: rates.minimum[area],
                                       addersPerSq: adders)
        }
    }

    if state.measurements.ceilingSqft > 0 {
        let baseC = rates.ceilingBase
        let addersC = unitAwareAddersPerSq(baseRate: baseC, type: state.tileType!, size: state.tileSize!, layout: state.layout!, rates: rates)
        running += appendComponent(labelPrefix: "Ceiling",
                                   sqft: state.measurements.ceilingSqft,
                                   baseRate: baseC,
                                   minCharge: rates.ceilingMinimum,
                                   addersPerSq: addersC)
    }
    
    // ----- PRICED FEATURES (same behavior as before) -----
    addUnits("Shelves",   qty: state.features.shelves,   rate: rates.unitShelf)
    addUnits("Niches",    qty: state.features.niches,    rate: rates.unitNiche)
    addUnits("Footrests", qty: state.features.footrests, rate: rates.unitFootrest)
    addUnits("Benches",   qty: state.features.benches,   rate: rates.unitBench)
    
    if state.features.mosaicBand, state.measurements.mosaicSqft > 0, rates.mosaicInlayRate != 0 {
        let m = state.measurements.mosaicSqft * rates.mosaicInlayRate
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = Locale.current.currency?.identifier ?? "USD"
        let rateStr = f.string(from: NSNumber(value: rates.mosaicInlayRate)) ?? "$\(rates.mosaicInlayRate)"
        lines.append(Line(label: "Mosaic inlay @ \(rateStr)/sqft × \(Int(state.measurements.mosaicSqft.rounded()))", amount: m))
        running += m
    }

    return Summary(lines: lines, total: running)
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var store = Store()
    @State private var showAdmin = false
    @State private var adminUnlocked = false
    @State private var adminPassword = ""
    @State private var showShare = false
    @State private var showShareChoice = false
    @State private var lastTappedPDF: PDFPayload? = nil    // NEW: Export form state
    @State private var showExportForm = false
    @State private var exportPDFURL: URL?
    @State private var pdfData: Data? = nil
    @State private var pendingPDFData: Data? = nil      // ADD
    @State private var pendingPDFURL: URL? = nil
    @State private var showLaborList: Bool = false
    @State private var showSalesList: Bool = false
    @State private var showSaveAlert = false
    @State private var saveAlertMessage = "Saved."
    // === Multi-room selection state ===
    @State private var currentRoomIndex: Int = 0
    @State private var currentSectionIndex: Int = 0
    // --- Rooms selection state (adjust names if yours differ) ---

    // --- Room naming / renaming sheet state ---
    @State private var showRoomNameSheet = false
    @State private var isRenamingExistingRoom = false
    @State private var editingRoomIndex: Int? = nil
    @State private var roomNameBuffer: String = ""
    
    // === Rooms bar ===
    @ViewBuilder
    private var roomsBar: some View {
        if store.doc.rooms.isEmpty {
            // First room CTA
            HStack {
                Text("Rooms").font(.headline)
                Spacer()
                Button {
                    addRoomPrompt()
                } label: { Text("Add Room") }
                .buttonStyle(.bordered)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Rooms").font(.headline)
                    Spacer()
                    Button {
                        addRoomPrompt()
                    } label: { Text("Add Room") }
                    .buttonStyle(.bordered)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.doc.rooms.indices, id: \.self) { i in
                            let isSel = (i == currentRoomIndex)
                            
                            Button {
                            // SHORT TAP: switch room
                            currentRoomIndex = i
                                currentSectionIndex = 0                               } label: {
                            HStack(spacing: 6) {
                            Text(store.doc.rooms[i].name.isEmpty ? "Room \(i+1)" : store.doc.rooms[i].name)
                            .lineLimit(1)
                            if isSel { Image(systemName: "checkmark.circle.fill") }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(isSel ? Color.blue : Color(.systemBackground))
                            .foregroundStyle(isSel ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                            RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator), lineWidth: 1)
                            )
                                    }
                            .buttonStyle(.plain)
                            // LONG PRESS: show context menu
                            .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                            renameRoomPrompt(index: i)
                                }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                            deleteRoom(index: i)
                                }
                                                }
                                                    }
                                                }             .padding(.vertical, 2)
                }
            }
        }
    }
    
    // === Areas bar (sections inside the current room) ===
        @ViewBuilder
    private var areasBar: some View {
        if store.doc.rooms.indices.contains(currentRoomIndex) {
            let sections = store.doc.rooms[currentRoomIndex].sections

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Areas").font(.headline)
                    Spacer()
                    Button("Add Area") { addAreaToCurrentRoom() }
                        .buttonStyle(.bordered)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sections.indices, id: \.self) { j in
                            let sec   = sections[j]
                            let title = sec.area?.rawValue ?? "Area \(j + 1)"
                            let isSel = (j == currentSectionIndex)

                            Button {
                                // SHORT TAP: switch to this area
                                currentSectionIndex = j
                            } label: {
                                HStack(spacing: 6) {
                                    Text(title).lineLimit(1)
                                    if isSel { Image(systemName: "checkmark.circle.fill") }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isSel ? Color.blue : Color(.systemBackground))
                                .foregroundStyle(isSel ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(.separator), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    deleteArea(index: j)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } else {
            EmptyView()
        }
    }
    // Create a new room and focus it
    private func addRoom(named name: String) {
        store.doc.rooms.append(EstimateRoom(name: name, sections: [EstimateSection()]))
        currentRoomIndex = store.doc.rooms.count - 1
        currentSectionIndex = 0
    }
    // Create → prompt for name
    private func addRoomPrompt() {
        roomNameBuffer = "Room \( (store.doc.rooms.count + 1) )"
        isRenamingExistingRoom = false
        editingRoomIndex = nil
        showRoomNameSheet = true
    }

   
    // Start rename flow
    private func renameRoomPrompt(index: Int) {
        guard store.doc.rooms.indices.contains(index) else { return }
        roomNameBuffer = store.doc.rooms[index].name
        isRenamingExistingRoom = true
        editingRoomIndex = index
        showRoomNameSheet = true
    }

    // Commit rename
    private func commitRename() {
        guard isRenamingExistingRoom,
              let idx = editingRoomIndex,
              store.doc.rooms.indices.contains(idx) else { return }
        store.doc.rooms[idx].name = roomNameBuffer.isEmpty ? "Room \(idx+1)" : roomNameBuffer
    }

    // Optional: delete a room
    private func deleteRoom(index: Int) {
        guard store.doc.rooms.indices.contains(index) else { return }
        store.doc.rooms.remove(at: index)
        currentRoomIndex = min(currentRoomIndex, max(0, store.doc.rooms.count - 1))
        // (Optional) also reset currentSectionIndex if you track it per room
    }    // Add a new area/section to current room
    private func addAreaToCurrentRoom() {
        guard store.doc.rooms.indices.contains(currentRoomIndex) else { return }
        store.doc.rooms[currentRoomIndex].sections.append(EstimateSection())
        currentSectionIndex = store.doc.rooms[currentRoomIndex].sections.count - 1
    }

    private func deleteArea(index j: Int) {
        guard store.doc.rooms.indices.contains(currentRoomIndex),
              store.doc.rooms[currentRoomIndex].sections.indices.contains(j) else { return }
        store.doc.rooms[currentRoomIndex].sections.remove(at: j)
        currentSectionIndex = min(currentSectionIndex, max(0, store.doc.rooms[currentRoomIndex].sections.count - 1))
    }
    // Binding to the current section (nil until user adds a room/area)
    private func currentSectionBinding() -> Binding<EstimateSection>? {
        guard store.doc.rooms.indices.contains(currentRoomIndex),
              store.doc.rooms[currentRoomIndex].sections.indices.contains(currentSectionIndex)
        else { return nil }

        return Binding(
            get: { store.doc.rooms[currentRoomIndex].sections[currentSectionIndex] },
            set: { store.doc.rooms[currentRoomIndex].sections[currentSectionIndex] = $0 }
        )
    }

    // Reset fields when Area changes within a section
    private func resetForAreaChange(_ sec: inout EstimateSection) {
        sec.features = Features()
        sec.measurements = Measurements()
        sec.additionsLabor = []
        sec.additionsMaterials = []
    }

    // Convert a Section to a temporary EstimatorState (so existing pricing functions work)
    private func state(from sec: EstimateSection) -> EstimatorState {
        var s = EstimatorState()
        s.area         = sec.area
        s.tileType     = sec.tileType
        s.tileSize     = sec.tileSize
        s.layout       = sec.layout
        s.features     = sec.features
        s.measurements = sec.measurements
        // NOTE: additions are stored on section; pricing uses them separately
        return s
    }

    // Build the required sentence for PDF/summary
    private func sentence(for room: EstimateRoom, section: EstimateSection) -> String {
        let body = buildEstimateDescription(from: section)   // use the section-aware builder
        let areaText = section.area?.rawValue ?? "Area"
        return "\(room.name) - \(areaText) \(body)"
    }
    private func saveImageToPhotos(_ image: UIImage) {
        // iOS 14+: request add-only access if possible (falls back below)
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                switch status {
                case .authorized, .limited:
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    DispatchQueue.main.async {
                        saveAlertMessage = "Saved to Photos."
                        showSaveAlert = true
                    }
                case .denied, .restricted, .notDetermined:
                    DispatchQueue.main.async {
                        saveAlertMessage = "Permission needed to save to Photos. Enable in Settings > Privacy > Photos."
                        showSaveAlert = true
                    }
                @unknown default:
                    DispatchQueue.main.async {
                        saveAlertMessage = "Couldn’t save image."
                        showSaveAlert = true
                    }
                }
            }
        } else {
            // iOS 13 and below
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    DispatchQueue.main.async {
                        saveAlertMessage = "Saved to Photos."
                        showSaveAlert = true
                    }
                } else {
                    DispatchQueue.main.async {
                        saveAlertMessage = "Permission needed to save to Photos. Enable in Settings > Privacy > Photos."
                        showSaveAlert = true
                    }
                }
            }
        }
    }
    private struct PDFPayload: Identifiable {
        let id = UUID()
        let data: Data
        let url: URL
    }
    @State private var pdfPayload: PDFPayload? = nil;
    @AppStorage("biz.name") private var bizName: String = ""
    @AppStorage("biz.address") private var bizAddress: String = ""
    @AppStorage("biz.address2") private var bizAddress2: String = ""
    @AppStorage("biz.cityStateZip") private var bizCityStateZip: String = ""
    @AppStorage("biz.phone") private var bizPhone: String = ""
    @AppStorage("biz.email") private var bizEmail: String = ""
    @AppStorage("cust.name") private var custName: String = ""
    @AppStorage("cust.address") private var custAddress: String = ""
    @AppStorage("cust.address2") private var custAddress2: String = ""
    @AppStorage("cust.cityStateZip") private var custCityStateZip: String = ""
    @AppStorage("cust.phone") private var custPhone: String = ""
    @AppStorage("cust.email") private var custEmail: String = ""
    @AppStorage("estimate.counter") private var estimateCounter: Int = 1400;
    @AppStorage("export.shipping") private var exportShipping: Double = 0.0
    @AppStorage("export.taxPercent") private var exportTaxPercent: Double = 0.0
    @AppStorage("additions.shippingEnabled") private var additionsShippingEnabled: Bool = false
    @AppStorage("export.forceSinglePage") private var exportForceSinglePage: Bool = false
    var body: some View {
        NavigationStack {
            // Header pinned at top, no extra top padding beyond safe area
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    headerLeftGroup
                    Spacer(minLength: 12)
                    headerRightButtons
                }
                .padding(.horizontal, 16)
                
                // Main card
                card {
                    roomsBar
                    areasBar
                    stepBar
                    VStack(alignment: .leading, spacing: 12) {
                        switch store.state.stepIndex {
                            case 0: areaStep
                            case 1: tileTypeStep
                            case 2: sizeStep
                            case 3: layoutStep
                            case 4: featuresStep
                            case 5: measurementsStep
                            case 6: additionsStep
                            default: summaryStep
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationBarTitleDisplayMode(.inline)
            .background(
                DismissKeyboardBackground(active: store.state.stepIndex != 6) // 6 == Additions
            )
            .sheet(isPresented: $showAdmin) {
                AdminSheet(rates: $store.rates,
                           unlocked: $adminUnlocked,
                           password: $adminPassword,
                           taxPercentDefault: $exportTaxPercent)
                .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
            }
            // NEW: Export form sheet
            .sheet(isPresented: $showExportForm) {
                ExportFormView(
                    // Business
                    bizName: $bizName,
                    bizAddress: $bizAddress,
                    bizAddress2: $bizAddress2,
                    bizCityStateZip: $bizCityStateZip,
                    bizPhone: $bizPhone,
                    bizEmail: $bizEmail,
                    // Customer
                    custName: $custName,
                    custAddress: $custAddress,
                    custAddress2: $custAddress2,
                    custCityStateZip: $custCityStateZip,
                    custPhone: $custPhone,
                    custEmail: $custEmail,
                    // Charges
                    shipping: $exportShipping,
                    taxPercent: $exportTaxPercent,
                    // PDF option
                    forceSinglePage: $exportForceSinglePage,
                    // Action
                    onCreatePDF: {
                        // If no rooms created yet, fall back to legacy single-state export
                        let sections: [EstimateSection]
                        if store.doc.rooms.isEmpty {
                            sections = []
                        } else {
                            sections = store.doc.rooms.flatMap(\.sections)
                        }

                        // Compute across all sections
                        let coreSum  = sections.reduce(0) { acc, sec in
                            acc + computeSummary(state: state(from: sec), rates: store.rates).total
                        }
                        let laborSum = sections.reduce(0) { acc, sec in
                            acc + sec.additionsLabor.reduce(0) { $0 + $1.amount }
                        }
                        let matsSum  = sections.reduce(0) { acc, sec in
                            acc + sec.additionsMaterials.reduce(0) { $0 + $1.amount }
                        }
                        let taxableBase = sections.reduce(0) { acc, sec in
                            acc + sec.additionsMaterials.filter { $0.taxable }.reduce(0) { $0 + $1.amount }
                        }

                        // Build description lines (one bullet per section)
                        let descLines: [String] = store.doc.rooms.flatMap { room in
                            room.sections.map { sentence(for: room, section: $0) }
                        }
                        let descriptionCombined = descLines.isEmpty
                            ? buildDescription(fromState: store.state) // ✅ adapter
                            : descLines.joined(separator: "  •  ")
                        // Flatten additions (your PDF view expects arrays)
                        let allLabor = sections.flatMap(\.additionsLabor)
                        let allMats  = sections.flatMap(\.additionsMaterials)

                        // Subtotal before shipping/tax
                        let subtotalAll = coreSum + laborSum + matsSum

                        // Parties
                        let biz = PartyInfo(
                            name: bizName, address: bizAddress, address2: bizAddress2,
                            cityStateZip: bizCityStateZip, phone: bizPhone, email: bizEmail
                        )
                        let cust = PartyInfo(
                            name: custName, address: custAddress, address2: custAddress2,
                            cityStateZip: custCityStateZip, phone: custPhone, email: custEmail
                        )

                        // Estimate number
                        let nextNumber = estimateCounter + 1
                        estimateCounter = nextNumber

                        // Build PDF root
                        let pdfRoot = ExportedFormPDFView(
                            biz: biz,
                            cust: cust,
                            estimateNumber: nextNumber,
                            date: Date(),
                            descriptionLine: descriptionCombined,
                            forceSinglePage: exportForceSinglePage,
                            subtotal: subtotalAll,
                            shipping: additionsShippingEnabled ? exportShipping : 0.0,
                            taxPercent: exportTaxPercent,
                            taxBase: taxableBase,
                            additionalLabor: allLabor,
                            materials: allMats
                        )

                        // Render & present (kept as-is)
                        do {
                            let data = try PDFGenerator.render(
                                view: pdfRoot,
                                pageSize: CGSize(width: 612, height: 792),
                                forceSinglePage: exportForceSinglePage
                            )

                            let suffix = exportForceSinglePage ? "Single" : "Multi"
                            let url  = try PDFGenerator.writeToTempFile(
                                data,
                                suggestedName: "IntegrityTile_Estimate_\(nextNumber)_\(suffix).pdf"
                            )

                            self.showExportForm = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                self.pdfPayload = PDFPayload(data: data, url: url)
                            }
                        } catch {
                            print("PDF generation failed:", error)
                            self.showExportForm = false
                        }
                    }
                )
                .presentationDetents([.large])
            }
            // Share sheet for PDF URL
            .onChange(of: showExportForm) { _, isShowing in
                guard !isShowing else { return }
                guard let data = pendingPDFData, let url = pendingPDFURL else { return }
                
                // clear the stash first
                self.pendingPDFData = nil
                self.pendingPDFURL  = nil
                
                // Present via item once the first sheet is really gone
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.pdfPayload = PDFPayload(data: data, url: url)
                }
            }
            .sheet(item: $pdfPayload) { payload in
                PDFKitPreview(data: payload.data, onTap: {
                    // Keep the payload so we can choose how to share
                    lastTappedPDF = payload
                    showShareChoice = true
                })
                .ignoresSafeArea()
                .presentationDetents([PresentationDetent.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showRoomNameSheet) {
                NavigationStack {
                    Form {
                        Section(isRenamingExistingRoom ? "Rename Room" : "New Room") {
                            TextField("Room name", text: $roomNameBuffer)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                        }
                    }
                    .navigationTitle(isRenamingExistingRoom ? "Rename Room" : "Add Room")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showRoomNameSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                if isRenamingExistingRoom {
                                    commitRename()
                                } else {
                                    addRoom(named: roomNameBuffer.isEmpty ? "Room \(store.doc.rooms.count + 1)" : roomNameBuffer)
                                }
                                showRoomNameSheet = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .confirmationDialog("Share", isPresented: $showShareChoice, titleVisibility: .visible) {
                Button("Share PDF") {
                    guard let p = lastTappedPDF else { return }
                    // Dismiss the preview first
                    pdfPayload = nil
                    presentPDFShareSheet(url: p.url)
                }
                Button("Save to Photos") {
                    guard let p = lastTappedPDF,
                          let img = pdfToImage(data: p.data) else { return }
                    // Dismiss the preview first so UI is clean
                    pdfPayload = nil
                    // Give SwiftUI a tick to fully dismiss the sheet/dialog
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        saveImageToPhotos(img)
                    }
                }
                
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: store.state.area) { _, _ in
                // Reset ALL Features whenever Area changes
                store.state.features.mosaicBand = false
                store.state.features.shelves = 0
                store.state.features.niches = 0
                store.state.features.footrests = 0
                store.state.features.benches = 0
                
                // Always reset ceiling on ANY area change (including Shower/Tub)
                store.state.measurements.ceilingSqft = 0
                // Reset ALL measurements to 0 on ANY Area change
                store.state.measurements = Measurements()
                // 🔹 Reset ALL additions (Labor + Materials + Shipping)
                    store.state.additionsLabor.removeAll()
                    store.state.additionsMaterials.removeAll()
                    additionsShippingEnabled = false
                    exportShipping = 0.0
                }
            // Reset Shipping whenever Sales list becomes empty
            .onChange(of: store.state.additionsMaterials) { _, materials in
                if materials.isEmpty {
                    additionsShippingEnabled = false
                    exportShipping = 0.0
                }
            }

            // Also enforce the same rule on first load / when returning to the screen
            .onAppear {
                if store.state.additionsMaterials.isEmpty {
                    additionsShippingEnabled = false
                    exportShipping = 0.0
                }
            }            .alert("Save Image", isPresented: $showSaveAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveAlertMessage)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(            // <- add this block
            TapGesture().onEnded { hideKeyboard() }
        )
    }
    
    
    // MARK: Header
    
    private var headerLeftGroup: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("AppLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("EstiMate").font(.system(size: 22, weight: .heavy))
                Text("Installation").font(.system(size: 14, weight: .heavy))
                Text("Estimator").font(.system(size: 14, weight: .heavy))
            }
        }
    }
    
    private var headerRightButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Reset", action: resetAll)
                .buttonStyle(.bordered)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button("Export") { showExportForm = true }
                .buttonStyle(.bordered)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button("Admin") { showAdmin = true }
                .buttonStyle(.bordered)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: Step bar (1–8)
    
    private var stepBar: some View {
        let stepsTop = ["1. Area Type","2. Tile Type","3. Tile Size","4. Layout"]
        let stepsBottom = ["5. Features","6. Measure","7. Additions","8. Summary"]
        
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(stepsTop.indices, id: \.self) { i in
                    stepButton(title: stepsTop[i], index: i)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 8) {
                ForEach(stepsBottom.indices, id: \.self) { j in
                    let idx = j + stepsTop.count
                    stepButton(title: stepsBottom[j], index: idx)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.bottom, 4)
    }
    @ViewBuilder
    private func stepButton(title: String, index: Int) -> some View {
        let isSelected = store.state.stepIndex == index
        Button {
            store.state.stepIndex = index
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.blue : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 1)
                )
        )
        .foregroundStyle(isSelected ? .white : .primary)
    }
    
    // MARK: - Option grid (Floor/Wall/etc.)
    
    private func gridOptions<T: Identifiable & RawRepresentable>(
        _ items: [T],
        selection: Binding<T?>,
        columns: Int = 3,
        hSpacing: CGFloat = 8,
        vSpacing: CGFloat = 8
    ) -> some View where T.RawValue == String {
        let rows = items.chunked(into: columns)
        return VStack(alignment: .leading, spacing: vSpacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                let rowItems = rows[rowIndex]
                OptionRow(
                    titles: rowItems.map { $0.rawValue },
                    isSelecteds: rowItems.map { selection.wrappedValue?.id == $0.id },
                    onTaps: rowItems.map { item in
                        { selection.wrappedValue = item }
                    }
                )
            }
        }
    }
    
    private struct OptionRow: View {
        let titles: [String]
        let isSelecteds: [Bool]
        let onTaps: [() -> Void]
        
        @State private var rowHeight: CGFloat = 32
        
        var body: some View {
            HStack(spacing: 8) {
                ForEach(titles.indices, id: \.self) { i in
                    OptionButton(
                        title: titles[i],
                        isSelected: isSelecteds[i],
                        rowHeight: $rowHeight,
                        onTap: onTaps[i]
                    )
                }
            }
            .onPreferenceChange(OptionRowHeightPreferenceKey.self) { measured in
                if measured > 0, abs(measured - rowHeight) > 0.5 {
                    rowHeight = measured
                }
            }
        }
    }
    
    private struct OptionButton: View {
        let title: String
        let isSelected: Bool
        @Binding var rowHeight: CGFloat
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: OptionRowHeightPreferenceKey.self,
                                            value: geo.size.height)
                        }
                    )
            }
            .buttonStyle(.plain)
            .frame(height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
    }
    
    private struct OptionRowHeightPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
    
    // MARK: Card wrapper
    
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
    
    // MARK: Steps
    
    private var areaStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Choose the installation area.").foregroundStyle(.secondary)
            if let sec {
                gridOptions(Area.allCases, selection: Binding(
                    get: { sec.wrappedValue.area },
                    set: { newVal in
                        var s = sec.wrappedValue
                        let old = s.area
                        s.area = newVal
                        if newVal?.rawValue != old?.rawValue {
                            resetForAreaChange(&s)
                        }
                        sec.wrappedValue = s
                    }
                ))
            } else {
                Text("Add a Room and an Area to begin.").foregroundStyle(.secondary)
            }
        }
    }
    private var tileTypeStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Select the tile type.").foregroundStyle(.secondary)
            if let sec {
                gridOptions(TileType.allCases, selection: Binding(
                    get: { sec.wrappedValue.tileType },
                    set: { sec.wrappedValue.tileType = $0 }
                ))
            } else {
                Text("Add a Room and an Area to begin.").foregroundStyle(.secondary)
            }
        }
    }
    private var sizeStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Pick the tile size.").foregroundStyle(.secondary)
            if let sec {
                gridOptions(TileSize.allCases, selection: Binding(
                    get: { sec.wrappedValue.tileSize },
                    set: { sec.wrappedValue.tileSize = $0 }
                ))
            } else {
                Text("Add a Room and an Area to begin.").foregroundStyle(.secondary)
            }
        }
    }
    private var layoutStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Pick a layout.").foregroundStyle(.secondary)
            if let sec {
                gridOptions(Layout.allCases, selection: Binding(
                    get: { sec.wrappedValue.layout },
                    set: { sec.wrappedValue.layout = $0 }
                ))
            } else {
                Text("Add a Room and an Area to begin.").foregroundStyle(.secondary)
            }
        }
    }
    // REPLACE your current `featuresStep` with this scrollable version
    private var featuresStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            if let sec {
                Toggle("Decorative mosaic band or inlay?", isOn: Binding(
                    get: { sec.wrappedValue.features.mosaicBand },
                    set: { sec.wrappedValue.features.mosaicBand = $0 }
                ))
                Text("If checked, enter total mosaic sqft in Measurements.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                quantityRow("Shelves",   value: Binding(
                    get: { sec.wrappedValue.features.shelves },
                    set: { sec.wrappedValue.features.shelves = $0 }
                ))
                quantityRow("Niches",    value: Binding(
                    get: { sec.wrappedValue.features.niches },
                    set: { sec.wrappedValue.features.niches = $0 }
                ))
                quantityRow("Footrests", value: Binding(
                    get: { sec.wrappedValue.features.footrests },
                    set: { sec.wrappedValue.features.footrests = $0 }
                ))
                quantityRow("Benches",   value: Binding(
                    get: { sec.wrappedValue.features.benches },
                    set: { sec.wrappedValue.features.benches = $0 }
                ))
            } else {
                Text("Add a Room and an Area to begin.").foregroundStyle(.secondary)
            }
        }
    }
    // REPLACE your current `measurementsStep` with this scrollable version
    private var measurementsStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Enter measurements. Fields adapt to the Area selection.")
                .foregroundStyle(.secondary)

            if let sec {
                switch sec.wrappedValue.area {
                case .shower:
                    measurementField("Shower walls (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.showerWallsSqft },
                        set: { sec.wrappedValue.measurements.showerWallsSqft = $0 }
                    ))
                    measurementField("Shower floor (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.showerFloorSqft },
                        set: { sec.wrappedValue.measurements.showerFloorSqft = $0 }
                    ))
                    ceilingBlock(title: "Tile the ceiling?",
                                 ceilingValue: Binding(
                                    get: { sec.wrappedValue.measurements.ceilingSqft },
                                    set: { sec.wrappedValue.measurements.ceilingSqft = $0 }
                                 ),
                                 ceilingLabel: "Ceiling area (sqft)")

                case .tub:
                    measurementField("Tub surround (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.sqft },
                        set: { sec.wrappedValue.measurements.sqft = $0 }
                    ))
                    ceilingBlock(title: "Tile the ceiling?",
                                 ceilingValue: Binding(
                                    get: { sec.wrappedValue.measurements.ceilingSqft },
                                    set: { sec.wrappedValue.measurements.ceilingSqft = $0 }
                                 ),
                                 ceilingLabel: "Ceiling area (sqft)")

                case .wall:
                    measurementField("Wall area (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.sqft },
                        set: { sec.wrappedValue.measurements.sqft = $0 }
                    ))

                case .backsplash:
                    measurementField("Backsplash (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.sqft },
                        set: { sec.wrappedValue.measurements.sqft = $0 }
                    ))

                case .fireplace:
                    measurementField("Fireplace (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.sqft },
                        set: { sec.wrappedValue.measurements.sqft = $0 }
                    ))

                case .floor:
                    measurementField("Floor (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.sqft },
                        set: { sec.wrappedValue.measurements.sqft = $0 }
                    ))

                case .none:
                    Text("Pick an Area first.")
                        .foregroundStyle(.secondary)
                }

                if sec.wrappedValue.features.mosaicBand {
                    numberField("Mosaic inlay (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.mosaicSqft },
                        set: { sec.wrappedValue.measurements.mosaicSqft = $0 }
                    ))
                }
            } else {
                Text("Add a Room and an Area to begin.").foregroundStyle(.secondary)
            }
        }
    }
    // === Summary (per-area with additions under each area) ===
    private var summaryStep: some View {
        // If no rooms yet, show a gentle hint
        if store.doc.rooms.isEmpty {
            return AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    Text("No rooms added yet. Use 'Add Room' to begin.")
                        .foregroundStyle(.secondary)
                }
            )
        }

        // Build derived data without mutating inside the ViewBuilder
        let perSection: [(room: EstimateRoom,
                          section: EstimateSection,
                          core: Summary,
                          labor: Double,
                          mats: Double,
                          subtotal: Double)] = store.doc.rooms.flatMap { room in
            room.sections.map { sec in
                let sum = computeSummary(state: state(from: sec), rates: store.rates)
                let labor = sec.additionsLabor.reduce(0) { $0 + $1.amount }
                let mats  = sec.additionsMaterials.reduce(0) { $0 + $1.amount }
                return (room, sec, sum, labor, mats, sum.total + labor + mats)
            }
        }

        // Totals for the footer
        let preTaxSubtotal = perSection.reduce(0) { $0 + $1.subtotal }
        let taxBase = store.doc.rooms
            .flatMap { $0.sections }
            .flatMap { $0.additionsMaterials }
            .filter { $0.taxable }
            .reduce(0.0) { $0 + $1.amount }

        let hasAnySales = store.doc.rooms
            .flatMap { $0.sections }
            .contains { !$0.additionsMaterials.isEmpty }

        let shipping   = (hasAnySales && additionsShippingEnabled) ? exportShipping : 0.0
        let taxPercent = exportTaxPercent
        let taxAmount  = (hasAnySales && taxBase > 0) ? (taxBase * (taxPercent / 100.0)) : 0.0
        let grandTotal = preTaxSubtotal + shipping + taxAmount

        return AnyView(
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    // Group by room for display
                    ForEach(Array(store.doc.rooms.enumerated()), id: \.offset) { _, room in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(room.name).font(.headline)

                            // sections for this room
                            let sectionsForRoom = perSection.filter { $0.room.id == room.id }
                            ForEach(Array(sectionsForRoom.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Area description line
                                    Text(sentence(for: item.room, section: item.section))
                                        .font(.subheadline)

                                    // Base installation line (the computed core total for this area)
                                    HStack {
                                        Text("Installation")
                                        Spacer()
                                        Text(currencyString(item.core.total))
                                            .fontWeight(.semibold)
                                    }

                                    // --- Additions for this area ---

                                    // Additional Labor as "Installation"
                                    if !item.section.additionsLabor.isEmpty {
                                        ForEach(item.section.additionsLabor) { row in
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    Text("Additional Labor")
                                                    Spacer()
                                                    Text(currencyString(row.amount))
                                                }
                                                if !row.activity.isEmpty {
                                                    Text(row.activity)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }

                                    // Additional Sales as "Sales"
                                    if !item.section.additionsMaterials.isEmpty {
                                        ForEach(item.section.additionsMaterials) { row in
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    Text("Sales")
                                                    Spacer()
                                                    // Add a small taxable mark if needed
                                                    if row.taxable {
                                                        Text("T")
                                                            .font(.caption2)
                                                            .padding(.trailing, 4)
                                                    }
                                                    Text(currencyString(row.amount))
                                                }
                                                if !row.activity.isEmpty {
                                                    Text(row.activity)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }

                                    // Section subtotal (base + additions)
                                    Divider().padding(.vertical, 4)
                                    HStack {
                                        Text("Section Total")
                                        Spacer()
                                        Text(currencyString(item.subtotal))
                                            .fontWeight(.semibold)
                                    }
                                }
                                .padding(10)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    // Footer totals
                    Divider().padding(.vertical, 8)

                    // Subtotal
                    HStack {
                        Text("Subtotal").font(.headline.weight(.heavy))
                        Spacer()
                        Text(currencyString(preTaxSubtotal)).font(.headline.weight(.heavy))
                    }
                    .padding(.top, 4)

                    // Shipping (only when there are Sales)
                    if hasAnySales {
                        HStack {
                            Text("Shipping")
                            Spacer()
                            Text(currencyString(shipping))
                        }
                        .padding(.vertical, 4)
                    }

                    // Tax (only when there is a taxable base)
                    if hasAnySales && taxBase > 0 {
                        HStack {
                            Text("Tax (\(taxPercent, specifier: "%.2f")%)")
                            Spacer()
                            Text(currencyString(taxAmount))
                        }
                        .padding(.bottom, 6)
                    }

                    Divider()

                    // Grand Total
                    HStack {
                        Text("Total").font(.title3.weight(.black))
                        Spacer()
                        Text(currencyString(grandTotal)).font(.title3.weight(.black))
                    }
                    .padding(.top, 6)
                }
                .padding(.vertical, 8)
            }
        )
    }
    // Simple action used by the Reset button
    private func resetAll() { store.reset() }
    
    // Builds the description sentence used on the PDF
    private func buildEstimateDescription(from section: EstimateSection) -> String {
        // Room + Area
        let roomPrefix = section.roomName.isEmpty ? "" : "\(section.roomName) – "
        

        // Tile & Layout
        let typeText   = section.tileType?.rawValue ?? "Tile"
        let layoutText = section.layout?.rawValue ?? "Layout"

        // Surfaces based on entered measurements
        var surfaces: [String] = []
        switch section.area {
        case .some(.shower):
            if section.measurements.showerWallsSqft > 0 { surfaces.append("Walls") }
            if section.measurements.showerFloorSqft > 0 { surfaces.append("Floor") }
            if section.measurements.ceilingSqft > 0    { surfaces.append("Ceiling") }
            if surfaces.isEmpty { surfaces = ["Walls", "Floor"] }
        case .some(.tub):
            if section.measurements.sqft > 0          { surfaces.append("Walls") }
            if section.measurements.ceilingSqft > 0   { surfaces.append("Ceiling") }
            if surfaces.isEmpty { surfaces = ["Walls"] }
        case .some(.floor):
            if section.measurements.sqft > 0          { surfaces.append("Floor") }
        case .some(.wall), .some(.backsplash), .some(.fireplace):
            if section.measurements.sqft > 0          { surfaces.append("Walls") }
        case .none:
            break
        }
        let surfacesText = surfaces.isEmpty ? "" : " on " + surfaces.joined(separator: ", ")

        // Feature list with quantities + pluralization (capitalize nouns)
        var features: [String] = []

        let shelves = section.features.shelves
        if shelves > 0 {
            features.append(shelves == 1 ? "Shelf" : "\(shelves) Shelves")
        }

        let niches = section.features.niches
        if niches > 0 {
            features.append(niches == 1 ? "Niche" : "\(niches) Niches")
        }

        let footrests = section.features.footrests
        if footrests > 0 {
            features.append(footrests == 1 ? "Footrest" : "\(footrests) Footrests")
        }

        let benches = section.features.benches
        if benches > 0 {
            features.append(benches == 1 ? "Bench" : "\(benches) Benches")
        }

        if section.features.mosaicBand {
            if section.measurements.mosaicSqft > 0 {
                features.append("Mosaic Inlay (\(Int(section.measurements.mosaicSqft)) sqft)")
            } else {
                features.append("Mosaic Inlay")
            }
        }

        let featuresText = features.isEmpty ? "" : " with " + features.joined(separator: ", ")

        // Final
        return "\(roomPrefix)Tile installation consisting of \(typeText) in \(layoutText) pattern\(surfacesText)\(featuresText)."
    }
    // MARK: - Adapter for legacy calls that still pass EstimatorState
    @inline(__always)
    private func buildDescription(fromState state: EstimatorState) -> String {
        var tmp = EstimateSection()
        tmp.area         = state.area
        tmp.tileType     = state.tileType
        tmp.tileSize     = state.tileSize
        tmp.layout       = state.layout
        tmp.features     = state.features
        tmp.measurements = state.measurements
        tmp.additionsLabor = state.additionsLabor
        tmp.additionsMaterials = state.additionsMaterials
        return buildEstimateDescription(from: tmp)
    }
    // ----- Step-style button label reused in Additions -----
    @ViewBuilder
    private func stepStyleButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            )
    }
    // MARK: - Additions UI pieces (compact style)
    
    private struct AdditionsHeaderRow: View {
        let showTaxable: Bool
        var body: some View {
            HStack(spacing: 6) {
                Text("Description").font(.caption2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty").font(.caption2.bold())
                    .frame(width: 50, alignment: .trailing)
                Text("Rate").font(.caption2.bold())
                    .frame(width: 60, alignment: .trailing)
                Text("Amount").font(.caption2.bold())
                    .frame(width: 70, alignment: .trailing)
                if showTaxable {
                    Text("Tax").font(.caption2.bold())
                        .frame(width: 40, alignment: .center)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    private struct AdditionsEntryRow: View {
        @Binding var item: AdditionItem
        let showTaxable: Bool
        let onDelete: () -> Void
        
        var body: some View {
            HStack(spacing: 6) {
                // Delete button
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                
                // Description
                TextField("Desc", text: $item.activity)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Qty
                TextField("0", value: $item.qty, format: .number)
                    .font(.caption)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50, alignment: .trailing)
                
                // Rate
                TextField("0", value: $item.rate, format: .number)
                    .font(.caption)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60, alignment: .trailing)
                
                // Amount (read-only)
                Text(currencyString(item.qty * item.rate))
                    .font(.caption).fontWeight(.semibold)
                    .frame(width: 70, alignment: .trailing)
                
                // Optional taxable toggle
                if showTaxable {
                    Toggle("", isOn: $item.taxable)
                        .labelsHidden()
                        .frame(width: 40, alignment: .center)
                }
            }
            .padding(.vertical, 2)
        }
    }
    // MARK: Additions (headers appear only after first add)
    private var additionsStep: some View {
        let sec = currentSectionBinding()

        func stepStyleButton(_ title: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            )
            .foregroundStyle(.primary)
        }

        func listHeader(_ title: String) -> some View {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
            }
            .padding(.top, 10)
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let sec {
                    // Top add buttons for this section
                    HStack(spacing: 8) {
                        stepStyleButton("Add Labor") {
                            var s = sec.wrappedValue
                            s.additionsLabor.append(AdditionItem())
                            sec.wrappedValue = s
                        }
                        stepStyleButton("Add Sales") {
                            var s = sec.wrappedValue
                            s.additionsMaterials.append(AdditionItem()) // taxable false by default
                            sec.wrappedValue = s
                        }
                    }

                    // -------- Additional Labor --------
                    if !sec.wrappedValue.additionsLabor.isEmpty {
                        listHeader("Additional Labor")
                        AdditionsHeaderRow(showTaxable: false)
                        ForEach(sec.wrappedValue.additionsLabor) { item in
                            let binding = Binding<AdditionItem>(
                                get: {
                                    sec.wrappedValue.additionsLabor.first(where: { $0.id == item.id }) ?? item
                                },
                                set: { newValue in
                                    var s = sec.wrappedValue
                                    if let i = s.additionsLabor.firstIndex(where: { $0.id == item.id }) {
                                        s.additionsLabor[i] = newValue
                                    }
                                    sec.wrappedValue = s
                                }
                            )
                            AdditionsEntryRow(item: binding, showTaxable: false) {
                                var s = sec.wrappedValue
                                s.additionsLabor.removeAll { $0.id == item.id }
                                sec.wrappedValue = s
                            }
                        }
                    }

                    // -------- Sale of Materials --------
                    if !sec.wrappedValue.additionsMaterials.isEmpty {
                        listHeader("Sale of Materials")
                        AdditionsHeaderRow(showTaxable: true)

                        ForEach(sec.wrappedValue.additionsMaterials) { item in
                            let binding = Binding<AdditionItem>(
                                get: {
                                    sec.wrappedValue.additionsMaterials.first(where: { $0.id == item.id }) ?? item
                                },
                                set: { newValue in
                                    var s = sec.wrappedValue
                                    if let i = s.additionsMaterials.firstIndex(where: { $0.id == item.id }) {
                                        s.additionsMaterials[i] = newValue
                                    }
                                    sec.wrappedValue = s
                                }
                            )
                            AdditionsEntryRow(item: binding, showTaxable: true) {
                                var s = sec.wrappedValue
                                s.additionsMaterials.removeAll { $0.id == item.id }
                                sec.wrappedValue = s
                            }
                        }// === Shipping (section UI; enabled only if this section has Sales) ===
                        let hasSales = !sec.wrappedValue.additionsMaterials.isEmpty
                        Divider().padding(.vertical, 4)

                        HStack(spacing: 8) {
                            Toggle("Shipping", isOn: Binding<Bool>(
                                get: { additionsShippingEnabled && hasSales },
                                set: { newValue in
                                    additionsShippingEnabled = newValue && hasSales
                                    if !additionsShippingEnabled {
                                        exportShipping = 0
                                    }
                                }
                            ))
                            .font(.caption)
                            .disabled(!hasSales)                 // No Sales → can’t enable
                            .opacity(hasSales ? 1 : 0.4)

                            Spacer()

                            TextField("0", value: $exportShipping, format: .number)
                                .font(.caption)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .disabled(!(additionsShippingEnabled && hasSales))
                                .opacity((additionsShippingEnabled && hasSales) ? 1 : 0.4)
                        }
                        .padding(.horizontal, 2)
                    }
                } else {
                    Text("Add a Room and an Area to begin.").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
            .onChange(of: sec?.wrappedValue.additionsMaterials.count ?? 0) { _, count in
                if count == 0 {
                    additionsShippingEnabled = false
                    exportShipping = 0
                }
            }
        }
    }
    // MARK: Reusable UI bits
    private func stepperRow(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 10) {
                Text("\(value.wrappedValue)")
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 24, alignment: .trailing)
                Stepper("", value: value, in: 0...50)
                    .labelsHidden()
            }
        }
    }
    
    // MARK: Actions
    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
    
    // MARK: PDF Generator
    private func makeSummaryPDF(summary s: Summary, biz: PartyInfo, cust: PartyInfo) -> URL? {
        // ---- Page geometry (points) ----
        let pageW: CGFloat = 612, pageH: CGFloat = 792
        let marginL: CGFloat = 36, marginR: CGFloat = 36
        let firstTop: CGFloat = 36
        let firstBottom: CGFloat = 36
        let nextTop: CGFloat = 36
        let nextBottom: CGFloat = 36
        let contentW = pageW - marginL - marginR
        
        // ---- Fonts & paragraph styles ----
        let titleFont   = UIFont.boldSystemFont(ofSize: 18)
        let sectionFont = UIFont.boldSystemFont(ofSize: 14)
        let bodyFont    = UIFont.systemFont(ofSize: 12)
        
        let pLeft: NSMutableParagraphStyle = {
            let p = NSMutableParagraphStyle(); p.alignment = .left;  p.lineBreakMode = .byWordWrapping; return p
        }()
        let pRight: NSMutableParagraphStyle = {
            let p = NSMutableParagraphStyle(); p.alignment = .right; p.lineBreakMode = .byWordWrapping; return p
        }()
        
        // ---- Column layout ----
        let amountColW: CGFloat = 110
        let gap: CGFloat = 8
        let labelMaxW = contentW - amountColW - gap
        
        // ---- Row cosmetics ----
        let rowVPad: CGFloat = 6
        let dividerH: CGFloat = 1
        let dividerGap: CGFloat = 6
        let dividerTotal: CGFloat = dividerH + dividerGap
        let safety: CGFloat = 2     // buffer to avoid last-line clipping
        
        // ---- Helpers ----
        @inline(__always) func ceilH(_ x: CGFloat) -> CGFloat { CGFloat(ceil(Double(x))) }
        
        // Measure header+two-column block (varies by text length)
        func headerHeight() -> CGFloat {
            var y = firstTop
            
            // Logo/title/date line height
            let lineH: CGFloat = 28
            y += lineH
            
            // Two-column blocks
            let colW = (contentW / 2) - 12
            func blockHeight(_ header: String, _ lines: [String]) -> CGFloat {
                let headerH = ceilH(NSAttributedString(string: header, attributes: [.font: sectionFont]).size().height)
                let text = lines.joined(separator: "\n")
                let used = NSAttributedString(string: text,
                                              attributes: [.font: bodyFont, .paragraphStyle: pLeft])
                    .boundingRect(with: CGSize(width: colW, height: .greatestFiniteMagnitude),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                                  context: nil)
                return headerH + 18 + ceilH(used.height) + 1
            }
            
            let bizLines = [biz.name, biz.address, "Phone: \(biz.phone)", "Email: \(biz.email)"]
            let custLines = [cust.name, cust.address, "Phone: \(cust.phone)", "Email: \(cust.email)"]
            let twoColH = max(blockHeight("Business", bizLines), blockHeight("Customer", custLines))
            y += twoColH + 20
            
            // Divider under header
            y += dividerTotal
            return y
        }
        
        // Measure one summary row (label + amount) including vPadding and the following divider
        func measureRowHeight(label: String, amount: String, includeDivider: Bool) -> CGFloat {
            let labelAttr  = NSAttributedString(string: label,  attributes: [.font: bodyFont, .paragraphStyle: pLeft])
            let amountAttr = NSAttributedString(string: amount, attributes: [.font: bodyFont, .paragraphStyle: pRight])
            
            let labelRect = labelAttr.boundingRect(with: CGSize(width: labelMaxW, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                   context: nil)
            let rowTextH = max(ceilH(labelRect.height) + 1, ceilH(amountAttr.size().height))
            return rowVPad + rowTextH + rowVPad + (includeDivider ? dividerTotal : 0)
        }
        
        // Measure total block
        func measureTotalHeight(total: Double) -> CGFloat {
            let l = NSAttributedString(string: "Total",
                                       attributes: [.font: UIFont.boldSystemFont(ofSize: 14), .paragraphStyle: pLeft])
            let v = NSAttributedString(string: currency(total),
                                       attributes: [.font: UIFont.boldSystemFont(ofSize: 14), .paragraphStyle: pRight])
            return max(ceilH(l.size().height), ceilH(v.size().height)) + 10
        }
        
        // ---- Build layout items (heights only) ----
        struct Item {
            enum Kind { case row(label: String, amount: String), total }
            let kind: Kind
            let height: CGFloat
        }
        
        var items: [Item] = []
        
        if s.lines.isEmpty {
            // Single "no summary" row
            let msg = "No summary to display."
            let rowH = measureRowHeight(label: msg, amount: "", includeDivider: false)
            items.append(Item(kind: .row(label: msg, amount: ""), height: rowH))
        } else {
            for (_, line) in s.lines.enumerated() {
                let amount = currency(line.amount)
                let includeDivider = true // divider after each row; we’ll skip when it lands at top of a page
                let h = measureRowHeight(label: line.label, amount: amount, includeDivider: includeDivider)
                items.append(Item(kind: .row(label: line.label, amount: amount), height: h))
            }
        }
        items.append(Item(kind: .total, height: measureTotalHeight(total: s.total)))
        
        // ---- Paginate (pure measure; no drawing here) ----
        let headerH = headerHeight()
        var pages: [[Item]] = []
        
        var current: [Item] = []
        var avail = pageH - headerH - firstBottom
        
        func pushPage() {
            if !current.isEmpty { pages.append(current) }
            current = []
            avail = pageH - nextTop - nextBottom
        }
        
        for item in items {
            // If item doesn’t fit on this page, start a fresh page **before** it.
            if item.height + safety > avail {
                pushPage()
            }
            current.append(item)
            avail -= item.height
        }
        if !current.isEmpty { pages.append(current) }
        
        // ---- Render pass ----
        let fileName = "Integrity_Tile_Estimate_\(Int(Date().timeIntervalSince1970)).pdf"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH), format: format)
        
        do {
            try renderer.writePDF(to: url) { ctx in
                // Common painters
                func drawDivider(at y: CGFloat) {
                    ctx.cgContext.setStrokeColor(UIColor.separator.cgColor)
                    ctx.cgContext.setLineWidth(dividerH)
                    ctx.cgContext.move(to: CGPoint(x: marginL, y: y))
                    ctx.cgContext.addLine(to: CGPoint(x: pageW - marginR, y: y))
                    ctx.cgContext.strokePath()
                }
                
                func drawHeader() {
                    var y = firstTop
                    
                    if let logo = UIImage(named: "AppLogo") {
                        let h: CGFloat = 40
                        let aspect = (logo.size.height == 0) ? 1 : (logo.size.width / logo.size.height)
                        logo.draw(in: CGRect(x: marginL, y: y, width: h * aspect, height: h))
                    }
                    
                    NSAttributedString(string: "Installation Estimate", attributes: [.font: titleFont])
                        .draw(at: CGPoint(x: marginL, y: y))
                    
                    let df = DateFormatter(); df.dateStyle = .medium
                    let dateStr = df.string(from: Date())
                    let dateAttr: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.secondaryLabel]
                    let dateSize = NSAttributedString(string: "Date: \(dateStr)", attributes: dateAttr).size()
                    NSAttributedString(string: "Date: \(dateStr)", attributes: dateAttr)
                        .draw(at: CGPoint(x: pageW - marginR - dateSize.width, y: y))
                    
                    y += 28
                    
                    // Two columns
                    let colW = (contentW / 2) - 12
                    let leftX = marginL
                    let rightX = marginL + colW + 24
                    
                    func drawBlock(header: String, lines: [String], x: CGFloat, y: inout CGFloat) {
                        NSAttributedString(string: header, attributes: [.font: sectionFont])
                            .draw(at: CGPoint(x: x, y: y))
                        y += 18
                        let text = lines.joined(separator: "\n")
                        let attr = NSAttributedString(string: text, attributes: [.font: bodyFont, .paragraphStyle: pLeft])
                        let used = attr.boundingRect(with: CGSize(width: colW, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                     context: nil)
                        let h = ceilH(used.height) + 1
                        attr.draw(with: CGRect(x: x, y: y, width: colW, height: h),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                                  context: nil)
                        y += h
                    }
                    
                    var leftY = y, rightY = y
                    drawBlock(header: "Business",
                              lines: [biz.name, biz.address, "Phone: \(biz.phone)", "Email: \(biz.email)"],
                              x: leftX, y: &leftY)
                    drawBlock(header: "Customer",
                              lines: [cust.name, cust.address, "Phone: \(cust.phone)", "Email: \(cust.email)"],
                              x: rightX, y: &rightY)
                    
                    // place divider at max y + 20
                    let divY = max(leftY, rightY) + 20
                    drawDivider(at: divY)
                }
                
                func drawRow(label: String, amount: String, at yTop: CGFloat, drawTopDivider: Bool) -> CGFloat {
                    var y = yTop
                    if drawTopDivider {
                        drawDivider(at: y)
                        y += dividerTotal
                    }
                    
                    // label
                    let labelAttr  = NSAttributedString(string: label,  attributes: [.font: bodyFont, .paragraphStyle: pLeft])
                    let labelRectM = labelAttr.boundingRect(with: CGSize(width: labelMaxW, height: .greatestFiniteMagnitude),
                                                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                            context: nil)
                    let labelH = ceilH(labelRectM.height) + 1
                    
                    let amountAttr = NSAttributedString(string: amount, attributes: [.font: bodyFont, .paragraphStyle: pRight])
                    let amtSize = amountAttr.size()
                    let rowH = max(labelH, amtSize.height)
                    
                    // draw text
                    labelAttr.draw(with: CGRect(x: marginL, y: y + rowVPad, width: labelMaxW, height: labelH),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                   context: nil)
                    amountAttr.draw(at: CGPoint(x: pageW - marginR - amtSize.width, y: y + rowVPad))
                    
                    y += rowVPad + rowH + rowVPad
                    // trailing divider
                    drawDivider(at: y)
                    y += dividerGap
                    return y
                }
                
                // Render each page
                for (pageIdx, pageItems) in pages.enumerated() {
                    ctx.beginPage()
                    
                    var cursorY: CGFloat
                    if pageIdx == 0 {
                        drawHeader()
                        cursorY = headerHeight() - dividerTotal // start right after the header divider line’s gap
                    } else {
                        cursorY = nextTop
                    }
                    
                    var firstOnPage = true
                    for item in pageItems {
                        switch item.kind {
                        case .row(let label, let amount):
                            // If this is the first drawable thing on a page, do NOT draw a top divider.
                            cursorY = drawRow(label: label, amount: amount, at: cursorY, drawTopDivider: !firstOnPage)
                            firstOnPage = false
                        case .total:
                            // Total block (bold)
                            let l = NSAttributedString(string: "Total",
                                                       attributes: [.font: UIFont.boldSystemFont(ofSize: 14), .paragraphStyle: pLeft])
                            let v = NSAttributedString(string: currency(s.total),
                                                       attributes: [.font: UIFont.boldSystemFont(ofSize: 14), .paragraphStyle: pRight])
                            // top divider before total unless it's at the top of page
                            if !firstOnPage {
                                drawDivider(at: cursorY)
                                cursorY += dividerGap
                            }
                            l.draw(at: CGPoint(x: marginL, y: cursorY))
                            let vsz = v.size()
                            v.draw(at: CGPoint(x: pageW - marginR - vsz.width, y: cursorY))
                            cursorY += max(ceilH(l.size().height), ceilH(vsz.height)) + 10
                            firstOnPage = false
                        }
                    }
                }
            }
            return url
        } catch {
            print("PDF render error:", error)
            return nil
        }
    }
}

// MARK: - Admin Sheet (with Tax Settings)
struct AdminSheet: View {
    @Binding var rates: Rates
    @Binding var unlocked: Bool
    @Binding var password: String

    // default tax percent used by Export form
    @Binding var taxPercentDefault: Double

    var body: some View {
        NavigationStack {
            if unlocked {
                ZStack {
                    // 1) Full-screen tappable background to dismiss keyboard
                    DismissKeyboardBackground(active: true)

                    // 2) Your form
                    Form {
                        Section("Base Labor Rates ($/sqft)") {
                            baseRow("Floor", value: Binding(get: { rates.base[.floor] ?? 0 }, set: { rates.base[.floor] = $0 }))
                            baseRow("Wall", value: Binding(get: { rates.base[.wall] ?? 0 }, set: { rates.base[.wall] = $0 }))
                            baseRow("Tub Surround", value: Binding(get: { rates.base[.tub] ?? 0 }, set: { rates.base[.tub] = $0 }))
                            baseRow("Shower (walls)", value: Binding(get: { rates.base[.shower] ?? 0 }, set: { rates.base[.shower] = $0 }))
                            baseRow("Backsplash", value: Binding(get: { rates.base[.backsplash] ?? 0 }, set: { rates.base[.backsplash] = $0 }))
                            baseRow("Fireplace", value: Binding(get: { rates.base[.fireplace] ?? 0 }, set: { rates.base[.fireplace] = $0 }))
                            baseRow("Ceiling (tiled)", value: $rates.ceilingBase)
                            baseRow("Shower floor", value: $rates.showerFloorBase)
                        }

                        Section("Minimum Charges ($)") {
                            minRow("Floor", value: Binding(get: { rates.minimum[.floor] ?? 0 }, set: { rates.minimum[.floor] = $0 }))
                            minRow("Wall", value: Binding(get: { rates.minimum[.wall] ?? 0 }, set: { rates.minimum[.wall] = $0 }))
                            minRow("Tub Surround", value: Binding(get: { rates.minimum[.tub] ?? 0 }, set: { rates.minimum[.tub] = $0 }))
                            minRow("Shower (walls)", value: Binding(get: { rates.minimum[.shower] ?? 0 }, set: { rates.minimum[.shower] = $0 }))
                            minRow("Backsplash", value: Binding(get: { rates.minimum[.backsplash] ?? 0 }, set: { rates.minimum[.backsplash] = $0 }))
                            minRow("Fireplace", value: Binding(get: { rates.minimum[.fireplace] ?? 0 }, set: { rates.minimum[.fireplace] = $0 }))
                            minRow("Ceiling (tiled)", value: $rates.ceilingMinimum)
                            minRow("Shower floor", value: $rates.showerFloorMinimum)
                        }

                        Section("Tile Type Adders ($/sqft)") {
                            typeRow(.ceramic, "Ceramic")
                            typeRow(.porcelain, "Porcelain")
                            typeRow(.glass, "Glass")
                            typeRow(.marble, "Marble")
                            typeRow(.limestone, "Limestone/Travertine")
                            typeRow(.slate, "Slate")

                            Picker("Units", selection: $rates.typeAdderUnit) {
                                ForEach(AdderUnit.allCases) { u in
                                    Text(u.rawValue).tag(u)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Section("Tile Size Adders ($/sqft)") {
                            sizeRow(.mosaic, "Mosaic")
                            sizeRow(.lt12, "Square/Rectangle < 12\"")
                            sizeRow(.r12to24, "Square/Rectangle 12\"–24\"")
                            sizeRow(.gt24, "Square/Rectangle > 24\"")
                            sizeRow(.shape, "Shape (Hexagon, etc.)")

                            Picker("Units", selection: $rates.sizeAdderUnit) {
                                ForEach(AdderUnit.allCases) { u in
                                    Text(u.rawValue).tag(u)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Section("Layout Adders ($/sqft)") {
                            layoutRow(.straight, "Straight")
                            layoutRow(.runningBond, "Running Bond")
                            layoutRow(.diagonal, "Diagonal")
                            layoutRow(.herringbone, "Herringbone")
                            layoutRow(.multiTile, "Multi-Tile")

                            Picker("Units", selection: $rates.layoutAdderUnit) {
                                ForEach(AdderUnit.allCases) { u in
                                    Text(u.rawValue).tag(u)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Section("Mosaic Inlay") {
                            baseRow("Band / Inlay ($/sqft)", value: $rates.mosaicInlayRate)
                        }

                        Section("Per-Unit Adders ($ each)") {
                            baseRow("Shelf", value: $rates.unitShelf)
                            baseRow("Niche", value: $rates.unitNiche)
                            baseRow("Footrest", value: $rates.unitFootrest)
                            baseRow("Bench", value: $rates.unitBench)
                        }

                        Section("Floor Escalator") {
                            Stepper("Lower threshold \(rates.floorEscThresholdLower) sqft",
                                    value: $rates.floorEscThresholdLower, in: 0...999)
                            Stepper("Upper threshold \(rates.floorEscThresholdUpper) sqft",
                                    value: $rates.floorEscThresholdUpper, in: 0...999)
                            baseRow("Adj ($/sqft)", value: $rates.floorEscAdjPerSqft)
                            // ⛔️ Removed the stray `.pickerStyle(.segmented)` here (there's no Picker)
                            Text("Applies only when Floor sqft is between lower+1 and upper (e.g., 51–99). Shown as a separate line item.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Section("Tax Settings") {
                            HStack {
                                Text("Default Tax %")
                                Spacer()
                                TextField("0", value: $taxPercentDefault, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 120)
                            }
                            Text("Used as the starting value on the Export screen. You can still change it per estimate.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    // Make it behave like your other screens:
                    .scrollDismissesKeyboard(.immediately)
                }
                // Attach the tap to the ZStack so tapping anywhere dismisses:
                .simultaneousGesture(
                    TapGesture().onEnded { hideKeyboard() }
                )
                .navigationTitle("Admin Settings")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Lock") { unlocked = false; password = "" }
                    }
                }
            } else {
                 
                VStack(spacing: 16) {
                    Text("Enter Admin Password").font(.headline)
                    SecureField("Password (default: integrity)", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { check() }
                    Button("Unlock", action: check)
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .navigationTitle("Admin")
            }
        }
    }

    private func check() { unlocked = (password == "integrity") }

    // MARK: - Row helpers
    private func baseRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
        }
    }

    private func minRow(_ title: String, value: Binding<Double>) -> some View {
        baseRow(title, value: value)
    }

    private func typeRow(_ t: TileType, _ label: String) -> some View {
        baseRow(label, value: Binding(
            get: { rates.typeAdder[t] ?? 0 },
            set: { rates.typeAdder[t] = $0 }
        ))
    }

    private func sizeRow(_ s: TileSize, _ label: String) -> some View {
        baseRow(label, value: Binding(
            get: { rates.sizeAdder[s] ?? 0 },
            set: { rates.sizeAdder[s] = $0 }
        ))
    }

    private func layoutRow(_ l: Layout, _ label: String) -> some View {
        baseRow(label, value: Binding(
            get: { rates.layoutAdder[l] ?? 0 },
            set: { rates.layoutAdder[l] = $0 }
        ))
    }
}
// MARK: - Export Form
private struct ExportFormView: View {
    @Binding var bizName: String
    @Binding var bizAddress: String
    @Binding var bizAddress2: String
    @Binding var bizCityStateZip: String
    @Binding var bizPhone: String
    @Binding var bizEmail: String

    @Binding var custName: String
    @Binding var custAddress: String
    @Binding var custAddress2: String
    @Binding var custCityStateZip: String
    @Binding var custPhone: String
    @Binding var custEmail: String

        // Charges
    @Binding var shipping: Double
    @Binding var taxPercent: Double
    @Binding var forceSinglePage: Bool
    var onCreatePDF: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Business Info") {
                    TextField("Business Name", text: $bizName)
                    TextField("Address", text: $bizAddress)
                    TextField("Address Line 2", text: $bizAddress2)
                    TextField("City, State, Zip", text: $bizCityStateZip)
                    TextField("Phone #", text: $bizPhone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $bizEmail)
                        .keyboardType(.emailAddress)
                }

                Section("Customer Info") {
                    TextField("Customer Name", text: $custName)
                    TextField("Address", text: $custAddress)
                    TextField("Address Line 2", text: $custAddress2)
                    TextField("City, State, Zip", text: $custCityStateZip)
                    TextField("Phone #", text: $custPhone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $custEmail)
                        .keyboardType(.emailAddress)
                }

                    Toggle("Force Single Page PDF", isOn: $forceSinglePage)
                

                Section {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(Self.todayString).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Export Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create PDF") {
                        // Commit in‑progress edits so bindings are up-to-date
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                        DispatchQueue.main.async {
                            onCreatePDF()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private static var todayString: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: Date())
    }
}
// MARK: - Share Sheet
    
    struct ShareView: UIViewControllerRepresentable {
        let items: [Any]
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }
        func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
    }
    
    // MARK: - Preview
    
    #Preview {
        ContentView()
            .environment(\.locale, .init(identifier: "en_US"))
    }
    
    // --- Compatibility shim ---
    // Minimal SwiftData model so any existing
    // `.modelContainer(for: [AdminSettingsEntity.self])` in your App file compiles.
    // This model is not used by the ContentView.
    @Model
    final class AdminSettingsEntity {
        init() {}
    }
    

