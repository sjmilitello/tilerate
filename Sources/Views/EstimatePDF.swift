import UIKit

/// Builds the estimate PDF. Both designs call this, so they produce the same
/// document from the same estimate.
enum EstimatePDF {
    /// One block per section: its sentence, its installation price and its
    /// labor and material lines.
    static func blocks(_ totals: EstimateTotals) -> [InstallationBlock] {
        totals.sections.map { item in
            .init(description: estimateSentence(room: item.room, section: item.section),
                  amount: item.core.total,
                  labor: item.section.additionsLabor,
                  materials: item.section.additionsMaterials)
        }
    }

    /// Renders the PDF and writes it to a temporary file for sharing.
    /// `fallbackDescription` is used when the estimate has no sections.
    static func make(document: EstimateDocument,
                     totals: EstimateTotals,
                     biz: PartyInfo,
                     cust: PartyInfo,
                     logo: UIImage?,
                     estimateNumber: Int,
                     forceSinglePage: Bool,
                     fallbackDescription: String) throws -> (data: Data, url: URL) {
        let blocks = blocks(totals)
        let sentences = totals.sections.map { estimateSentence(room: $0.room, section: $0.section) }
        let description = sentences.isEmpty ? fallbackDescription : sentences.joined(separator: "  •  ")
        let sections = document.rooms.flatMap { $0.sections }

        let pdfRoot = ExportedFormPDFView(
            biz: biz,
            cust: cust,
            estimateNumber: estimateNumber,
            date: Date(),
            descriptionLine: description,
            forceSinglePage: forceSinglePage,
            logo: logo,
            subtotal: totals.subtotal,
            shipping: totals.shipping,
            taxPercent: totals.taxPercent,
            taxBase: totals.taxableBase,
            additionalLabor: sections.flatMap { $0.additionsLabor },
            materials: sections.flatMap { $0.additionsMaterials },
            blocks: blocks
        )

        let data = try PDFGenerator.render(
            view: pdfRoot,
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
