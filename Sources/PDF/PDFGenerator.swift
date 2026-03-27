import SwiftUI
import UIKit

enum PDFGenerator {
    static func render<V: View>(
        view: V,
        pageSize: CGSize = CGSize(width: 612, height: 792),
        forceSinglePage: Bool
    ) throws -> Data {
        let controller = UIHostingController(rootView: view)
        let hostingView = controller.view!
        hostingView.backgroundColor = .white

        controller.overrideUserInterfaceStyle = .light

        let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: pageSize.width, height: pageSize.height)))
        window.rootViewController = controller
        window.isHidden = false

        let targetWidth = pageSize.width
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.widthAnchor.constraint(equalToConstant: targetWidth)
        ])
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let contentSize = hostingView.systemLayoutSizeFitting(
            CGSize(width: targetWidth, height: UIView.layoutFittingExpandedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        let contentHeight = ceil(max(contentSize.height, pageSize.height))
        hostingView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: contentHeight)
        hostingView.setNeedsLayout()
        hostingView.layoutIfNeeded()

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)

        let data = renderer.pdfData { ctx in
            if forceSinglePage {
                ctx.beginPage()
                let scale = min(pageSize.width / targetWidth, pageSize.height / contentHeight)
                let dx = (pageSize.width  - targetWidth  * scale) / 2.0
                let dy = (pageSize.height - contentHeight * scale) / 2.0
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: dx, y: dy)
                ctx.cgContext.scaleBy(x: scale, y: scale)
                hostingView.layer.render(in: ctx.cgContext)
                ctx.cgContext.restoreGState()
            } else {
                let dpi72: CGFloat = 72.0
                let margin: CGFloat = 0.5 * dpi72
                let bottomMarginAll: CGFloat = margin
                let topMarginFirst: CGFloat = 0
                let topMarginOther: CGFloat = margin

                let guardTop: CGFloat = 4
                let guardBottom: CGFloat = 14

                let renderScale: CGFloat = 2.0
                let imgSizePts = CGSize(width: targetWidth, height: contentHeight)
                let imgSizePx = CGSize(width: imgSizePts.width * renderScale, height: imgSizePts.height * renderScale)

                let rendererFmt = UIGraphicsImageRendererFormat()
                rendererFmt.scale = renderScale
                rendererFmt.opaque = true
                let imageRenderer = UIGraphicsImageRenderer(size: imgSizePts, format: rendererFmt)

                let fullImage = imageRenderer.image { _ in
                    hostingView.layer.render(in: UIGraphicsGetCurrentContext()!)
                }

                guard let fullCG = fullImage.cgImage else { return }
                var yPts: CGFloat = 0
                var pageIndex = 0

                while yPts < contentHeight - 0.1 {
                    ctx.beginPage()

                    let topM: CGFloat = (pageIndex == 0) ? topMarginFirst : topMarginOther
                    let pageHeightPts = max(0, pageSize.height - topM - bottomMarginAll)
                    let visibleHeightPts = max(0, pageHeightPts - guardTop - guardBottom)

                    let srcXpx: CGFloat = 0
                    let srcYpx: CGFloat = floor((yPts) * renderScale)
                    let srcWpx: CGFloat = floor(targetWidth * renderScale)
                    let sliceHpx: CGFloat = floor(visibleHeightPts * renderScale)

                    let maxSliceHpx = max(0, min(sliceHpx, (imgSizePx.height - srcYpx)))
                    if maxSliceHpx <= 0 { break }

                    let srcRectPx = CGRect(x: srcXpx, y: srcYpx, width: srcWpx, height: maxSliceHpx)
                    guard let slice = fullCG.cropping(to: srcRectPx) else { break }

                    let dest = CGRect(x: 0, y: topM + guardTop, width: pageSize.width, height: maxSliceHpx / renderScale)

                    ctx.cgContext.saveGState()
                    ctx.cgContext.interpolationQuality = .high
                    ctx.cgContext.translateBy(x: 0, y: pageSize.height)
                    ctx.cgContext.scaleBy(x: 1, y: -1)

                    let flippedDest = CGRect(
                        x: dest.origin.x,
                        y: pageSize.height - (dest.origin.y + dest.size.height),
                        width: dest.size.width,
                        height: dest.size.height
                    )

                    ctx.cgContext.draw(slice, in: flippedDest)
                    ctx.cgContext.restoreGState()

                    yPts += dest.height
                    pageIndex += 1
                }
            }
        }
        return data
    }

    static func writeToTempFile(_ data: Data, suggestedName: String = "Estimate.pdf") throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suggestedName)
        try data.write(to: url, options: .atomic)
        return url
    }
}
