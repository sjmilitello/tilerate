import UIKit

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
                     forceSinglePage: Bool) throws -> (data: Data, url: URL) {
        let data = try PDFGenerator.render(
            view: view(totals: totals, template: template, biz: biz, cust: cust, logo: logo,
                       estimateNumber: estimateNumber),
            pageSize: CGSize(width: 612, height: 792),
            forceSinglePage: forceSinglePage
        )
        let suffix = forceSinglePage ? "Single" : "Multi"
        let url = try PDFGenerator.writeToTempFile(
            data,
            suggestedName: "TileRate_Installation_Estimate_\(estimateNumber)_\(suffix).pdf"
        )
        return (data, url)
    }
}
