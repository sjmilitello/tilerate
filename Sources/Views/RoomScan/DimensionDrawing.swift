import SwiftUI

/// Draws laid-out dimensions (`PlanDimensionPlacer.Placed`) the same way on
/// the plan and on the face-on wall: extension lines, slash ticks, and the
/// number on a dark patch along its line.
enum DimensionDrawing {
    /// 9.5 pt on the plan and the wall alike (owner's call, 2026-10-08: 11 pt crowded the plan).
    static let font = Font.system(size: 9.5, weight: .semibold).monospacedDigit()

    static func ink(_ i: PlanDimension.Ink) -> Color {
        switch i {
        case .wall: Color(red: 1, green: 0.8, blue: 0.3)
        case .floor: Color(red: 0.45, green: 0.9, blue: 0.5)
        case .curb: Color(red: 0.85, green: 0.78, blue: 0.62)
        case .bench: .mint
        case .opening: .cyan
        }
    }

    /// A number's size as drawn, for the placer.
    static func measure(_ ctx: GraphicsContext, _ text: String, font: Font = font) -> CGSize {
        ctx.resolve(Text(text).font(font)).measure(in: CGSize(width: 240, height: 40))
    }

    static func draw(_ ctx: GraphicsContext, _ placed: [PlanDimensionPlacer.Placed], font: Font = font) {
        for p in placed {
            let ink = ink(p.dimension.ink)
            var lines = Path()
            for w in p.witnesses { lines.move(to: w.0); lines.addLine(to: w.1) }
            lines.move(to: p.line.0); lines.addLine(to: p.line.1)
            ctx.stroke(lines, with: .color(ink.opacity(0.85)), lineWidth: 1)
            // Slash ticks where the extension lines meet the dimension line.
            let a = p.witnesses[0].1, b = p.witnesses[1].1
            let len = max(hypot(b.x - a.x, b.y - a.y), 1e-6)
            let ux = (b.x - a.x) / len, uy = (b.y - a.y) / len
            let w0 = p.witnesses[0]
            let wl = max(hypot(w0.1.x - w0.0.x, w0.1.y - w0.0.y), 1e-6)
            let nx = (w0.1.x - w0.0.x) / wl, ny = (w0.1.y - w0.0.y) / wl
            var ticks = Path()
            for w in p.witnesses {
                let q = CGPoint(x: w.1.x - nx * 5, y: w.1.y - ny * 5)
                let tx = (ux + nx) * 4, ty = (uy + ny) * 4
                ticks.move(to: CGPoint(x: q.x - tx, y: q.y - ty)); ticks.addLine(to: CGPoint(x: q.x + tx, y: q.y + ty))
            }
            ctx.stroke(ticks, with: .color(ink), lineWidth: 1.8)
            var c = ctx
            c.translateBy(x: p.labelCenter.x, y: p.labelCenter.y)
            c.rotate(by: .radians(p.angle))
            let size = p.labelSize
            c.fill(Path(roundedRect: CGRect(x: -size.width / 2 - 4, y: -size.height / 2 - 1,
                                            width: size.width + 8, height: size.height + 2), cornerRadius: 4),
                   with: .color(Color(white: 0.09)))
            c.draw(ctx.resolve(Text(p.dimension.text).font(font).foregroundColor(ink)), at: .zero)
        }
    }
}
