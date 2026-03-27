import SwiftUI
import UIKit

struct LogoCropper: View {
    let source: UIImage
    let cropAspect: CGFloat
    let outputTargetSize: CGSize
    let onDone: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var rotated: UIImage
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastDrag: CGSize = .zero
    @State private var startZoom: CGFloat = 1.0

    init(source: UIImage,
         cropAspect: CGFloat,
         outputTargetSize: CGSize,
         onDone: @escaping (UIImage) -> Void,
         onCancel: @escaping () -> Void) {
        self.source = source
        self.cropAspect = cropAspect
        self.outputTargetSize = outputTargetSize
        self.onDone = onDone
        self.onCancel = onCancel
        _rotated = State(initialValue: source)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()

                    let inset: CGFloat = 16
                    let safe = geo.safeAreaInsets
                    let avail = CGRect(
                        x: inset,
                        y: inset + safe.top,
                        width: geo.size.width - inset * 2,
                        height: geo.size.height - inset * 2 - safe.top - safe.bottom
                    )
                    let cropW = min(avail.width, avail.height * cropAspect)
                    let cropH = cropW / cropAspect
                    let cropRect = CGRect(
                        x: avail.midX - cropW / 2,
                        y: avail.midY - cropH / 2,
                        width: cropW,
                        height: cropH
                    )

                    CroppingCanvas(
                        image: rotated,
                        cropRectInView: cropRect,
                        zoom: $zoom,
                        offset: $offset,
                        lastDrag: $lastDrag,
                        startZoom: $startZoom
                    )

                    CropMask(cropRect: cropRect)
                }
                .navigationTitle("Crop Logo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Rotate") { rotated = rotated.rotatedBy90Degrees() }
                        Button("Use") {
                            if let output = renderCropped(
                                image: rotated,
                                in: geo.size,
                                safeInsets: geo.safeAreaInsets,
                                cropAspect: cropAspect,
                                outputSize: outputTargetSize,
                                zoom: zoom,
                                offset: offset
                            ) {
                                onDone(output)
                            } else {
                                onCancel()
                            }
                        }
                    }
                }
            }
        }
    }

    private func renderCropped(
        image: UIImage,
        in viewSize: CGSize,
        safeInsets: EdgeInsets,
        cropAspect: CGFloat,
        outputSize: CGSize,
        zoom: CGFloat,
        offset: CGSize
    ) -> UIImage? {
        let inset: CGFloat = 16
        let avail = CGRect(
            x: inset,
            y: inset + safeInsets.top,
            width: viewSize.width - inset * 2,
            height: viewSize.height - inset * 2 - safeInsets.top - safeInsets.bottom
        )
        let cropW = min(avail.width, avail.height * cropAspect)
        let cropH = cropW / cropAspect
        let cropRect = CGRect(
            x: avail.midX - cropW / 2,
            y: avail.midY - cropH / 2,
            width: cropW,
            height: cropH
        )

        let imgSizePts = image.size
        let scaled = CGSize(width: imgSizePts.width * zoom, height: imgSizePts.height * zoom)
        let imgOrigin = CGPoint(
            x: cropRect.midX - scaled.width / 2 + offset.width,
            y: cropRect.midY - scaled.height / 2 + offset.height
        )
        let imgFrameInView = CGRect(origin: imgOrigin, size: scaled)

        let intersect = cropRect.intersection(imgFrameInView)
        if intersect.isNull || intersect.isEmpty { return nil }

        let relInImage = CGRect(
            x: intersect.origin.x - imgFrameInView.origin.x,
            y: intersect.origin.y - imgFrameInView.origin.y,
            width: intersect.size.width,
            height: intersect.size.height
        )
        let imgRectPts = CGRect(
            x: relInImage.origin.x / zoom,
            y: relInImage.origin.y / zoom,
            width:  relInImage.size.width / zoom,
            height: relInImage.size.height / zoom
        )

        guard let cg = image.cgImage else { return nil }
        let scale = image.scale
        let imgRectPx = CGRect(
            x: max(0, imgRectPts.origin.x * scale),
            y: max(0, imgRectPts.origin.y * scale),
            width:  max(1, imgRectPts.size.width  * scale),
            height: max(1, imgRectPts.size.height * scale)
        ).integral

        guard let croppedCG = cg.cropping(to: imgRectPx) else { return nil }
        let cropped = UIImage(cgImage: croppedCG, scale: image.scale, orientation: .up)

        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1.0
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: fmt)
        return renderer.image { _ in
            cropped.draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }
}

private struct CropMask: View {
    let cropRect: CGRect
    var body: some View {
        GeometryReader { geo in
            let path = Path { p in
                p.addRect(CGRect(origin: .zero, size: geo.size))
                p.addRoundedRect(in: cropRect, cornerSize: .init(width: 8, height: 8))
            }
            path.fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct CroppingCanvas: View {
    let image: UIImage
    let cropRectInView: CGRect
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize
    @Binding var lastDrag: CGSize
    @Binding var startZoom: CGFloat

    var body: some View {
        GeometryReader { _ in
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: image.size.width, height: image.size.height)
                .scaleEffect(zoom, anchor: .center)
                .offset(x: offset.width, y: offset.height)
                .position(x: cropRectInView.midX, y: cropRectInView.midY)
                .gesture(
                    DragGesture()
                        .onChanged { g in
                            offset = CGSize(
                                width:  lastDrag.width  + g.translation.width,
                                height: lastDrag.height + g.translation.height
                            )
                        }
                        .onEnded { _ in lastDrag = offset }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = max(0.05, startZoom * value)
                        }
                        .onEnded { _ in startZoom = zoom }
                )
                .contentShape(Rectangle())
        }
        .ignoresSafeArea()
        .onAppear { startZoom = zoom }
    }
}

private extension UIImage {
    func rotatedBy90Degrees() -> UIImage {
        let newSize = CGSize(width: size.height, height: size.width)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            ctx.cgContext.rotate(by: .pi / 2)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
