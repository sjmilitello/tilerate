import PDFKit
import UIKit

/// A 3-D view for the PDF: its caption, and how to draw it at a size.
struct PDFPicture {
    let caption: String
    let draw: (CGSize) -> UIImage?
}

/// Builds the estimate PDF. Both designs call this, so they produce the same
/// document from the same estimate. `blocks` feeds `ExportedFormPDFView`, the
/// PDF as drawn before layouts, kept only as the reference the Classic layout
/// is checked against (EstimateLayoutTests).
enum EstimatePDF {
    /// One block per section: its sentence, its installation price and its
    /// labor and material lines.
    static func blocks(_ totals: EstimateTotals) -> [InstallationBlock] {
        totals.sections.map { item in
            .init(description: item.sentence,
                  amount: item.core.total,
                  labor: item.laborItems,
                  materials: item.materialItems)
        }
    }

    /// The PDF's view for a layout.
    static func view(totals: EstimateTotals, template: EstimateTemplate, biz: PartyInfo, cust: PartyInfo,
                     logo: UIImage?, estimateNumber: Int, date: Date = Date(),
                     onEditWording: ((UUID) -> Void)? = nil) -> TemplatePDFView {
        TemplatePDFView(template: template, biz: biz, cust: cust, estimateNumber: estimateNumber, date: date,
                        logo: logo, rows: estimateRows(totals, template: template),
                        subtotal: totals.subtotal, shipping: totals.shipping,
                        taxPercent: totals.taxPercent, taxBase: totals.taxableBase,
                        onEditWording: onEditWording)
    }

    /// Renders the PDF in the given layout and writes it to a temporary file
    /// for sharing.
    static func make(totals: EstimateTotals,
                     template: EstimateTemplate,
                     biz: PartyInfo,
                     cust: PartyInfo,
                     logo: UIImage?,
                     estimateNumber: Int,
                     forceSinglePage: Bool,
                     pictures: [PDFPicture] = []) throws -> (data: Data, url: URL) {
        var data = try PDFGenerator.render(
            view: view(totals: totals, template: template, biz: biz, cust: cust, logo: logo,
                       estimateNumber: estimateNumber),
            pageSize: CGSize(width: 612, height: 792),
            forceSinglePage: forceSinglePage
        )
        if template.include3DViews, !pictures.isEmpty {
            data = appending(picturePages(pictures, perPage: template.picturesPerPage), to: data)
        }
        let suffix = forceSinglePage ? "Single" : "Multi"
        let url = try PDFGenerator.writeToTempFile(
            data,
            suggestedName: "TileRate_Installation_Estimate_\(estimateNumber)_\(suffix).pdf"
        )
        return (data, url)
    }

    /// Letter pages of 3-D views under "Your project", one, two or four to a
    /// page, each captioned.
    static func picturePages(_ pictures: [PDFPicture], perPage: Int) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 36, top: CGFloat = 78, captionH: CGFloat = 26
        let per = [1, 2, 4].contains(perPage) ? perPage : 2
        let columns = per == 4 ? 2 : 1, rows = per == 1 ? 1 : 2
        let gap: CGFloat = 16
        let cellW = (page.width - 2 * margin - CGFloat(columns - 1) * gap) / CGFloat(columns)
        let cellH = (page.height - top - margin - CGFloat(rows - 1) * gap) / CGFloat(rows)
        let imageSize = CGSize(width: cellW, height: cellH - captionH)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            for (n, picture) in pictures.enumerated() {
                let slot = n % per
                if slot == 0 {
                    ctx.beginPage()
                    let title = NSAttributedString(string: "Your project", attributes: [
                        .font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor.black])
                    title.draw(at: CGPoint(x: margin, y: 36))
                }
                let x = margin + CGFloat(slot % columns) * (cellW + gap)
                let y = top + CGFloat(slot / columns) * (cellH + gap)
                let frame = CGRect(x: x, y: y, width: imageSize.width, height: imageSize.height)
                if let image = picture.draw(CGSize(width: imageSize.width * 2, height: imageSize.height * 2)) {
                    image.draw(in: frame)
                }
                UIColor(white: 0.8, alpha: 1).setStroke()
                UIBezierPath(rect: frame).stroke()
                let caption = NSAttributedString(string: picture.caption, attributes: [
                    .font: UIFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: UIColor.darkGray])
                caption.draw(in: CGRect(x: x, y: frame.maxY + 6, width: cellW, height: captionH - 6))
            }
        }
    }

    /// One PDF's pages added after another's.
    static func appending(_ extra: Data, to data: Data) -> Data {
        guard let doc = PDFDocument(data: data), let more = PDFDocument(data: extra) else { return data }
        for i in 0..<more.pageCount {
            if let p = more.page(at: i) { doc.insert(p, at: doc.pageCount) }
        }
        return doc.dataRepresentation() ?? data
    }
}
