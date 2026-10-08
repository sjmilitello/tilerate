import CoreGraphics
import Foundation

// Taken from FabSpecPro (Model2/FeatureDrag.swift and EditorViewport.swift),
// owner's call 2026-10-08: on a phone the thumb covers what it drags, so a
// thing is chosen with a tap and then steered by a drag anywhere, at a gain
// that depends on the finger's speed.

enum Steering {
    /// How far the thing moves per point of finger travel, by speed: slow is
    /// fine (0.3) for sixteenths, a sweep is 1:1 and never more — anything
    /// faster outruns the hand and can't be walked back.
    static func gain(forSpeed speed: Double) -> Double {
        let t = min(max((speed - slowFinger) / (fastFinger - slowFinger), 0), 1)
        return fineGain + (coarseGain - fineGain) * t
    }

    static let slowFinger = 2.0
    static let fastFinger = 16.0
    static let fineGain = 0.3
    static let coarseGain = 1.0

    /// A finger step (points), scaled by its speed's gain.
    static func steered(_ delta: CGSize) -> CGSize {
        let k = gain(forSpeed: Double(hypot(delta.width, delta.height)))
        return CGSize(width: delta.width * k, height: delta.height * k)
    }

    /// Rounded to the sixteenth of an inch, in feet.
    static func sixteenth(_ feet: Double) -> Double { (feet * 192).rounded() / 192 }
}

/// Zoom and pan as one transform that both drawing and tapping go through:
/// view = fitted × zoom + pan (from FabSpecPro's EditorViewport).
struct PlanViewport: Equatable {
    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 8
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    var isFitted: Bool { zoom == 1 && pan == .zero }

    /// Zoomed about a point that stays put (the middle of a pinch).
    func zoomed(to newZoom: CGFloat, about anchor: CGPoint) -> PlanViewport {
        let clamped = min(max(newZoom, Self.minZoom), Self.maxZoom)
        let factor = clamped / zoom
        return PlanViewport(zoom: clamped,
                            pan: CGSize(width: anchor.x - (anchor.x - pan.width) * factor,
                                        height: anchor.y - (anchor.y - pan.height) * factor))
    }

    func panned(by d: CGSize) -> PlanViewport {
        PlanViewport(zoom: zoom, pan: CGSize(width: pan.width + d.width, height: pan.height + d.height))
    }

    /// Never dragged off the screen: half a screen of overscroll at most.
    func clamped(in size: CGSize) -> PlanViewport {
        let slackX = size.width * max(0, zoom - 1) + size.width / 2
        let slackY = size.height * max(0, zoom - 1) + size.height / 2
        return PlanViewport(zoom: zoom,
                            pan: CGSize(width: min(max(pan.width, -slackX), size.width / 2),
                                        height: min(max(pan.height, -slackY), size.height / 2)))
    }

    /// The least pan that brings a point on screen (with a margin): a thing
    /// being steered isn't lost off the edge.
    func keeping(_ p: CGPoint, in size: CGSize, margin: CGFloat = 24) -> PlanViewport {
        var d = CGSize.zero
        if p.x < margin { d.width = margin - p.x } else if p.x > size.width - margin { d.width = size.width - margin - p.x }
        if p.y < margin { d.height = margin - p.y } else if p.y > size.height - margin { d.height = size.height - margin - p.y }
        return d == .zero ? self : panned(by: d)
    }
}
