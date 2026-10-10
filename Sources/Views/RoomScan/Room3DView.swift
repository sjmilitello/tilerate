import Metal
import SceneKit
import SwiftUI
import UIKit

// The scanned room in 3-D (owner asked 2026-10-07): walls at their heights
// with doors and windows cut out, walls drawn in, each area's tile with
// grout lines at its real size and pattern, benches, niches, windows, corner
// pieces, the curb, and — switchable — the fixtures the scanner found. Built
// from the scan and the areas' choices, not from Apple's own model, so every
// change shows. Plan feet → scene: x = x, z = y (down the plan), y = up.

/// What the 3-D view shows: the area being measured and the room's others.
struct Room3DContent: Equatable {
    var room: ScannedRoom
    var takeoff: AreaTakeoff
    var area: Area?
    var tile: TileChoice?
    var floorTile: TileChoice?
    var others: [OtherAreaPieces]
    var curbHeightIn: Double
    var stoneParts: Set<String>
    var showFixtures: Bool
    /// The chosen item, lit up.
    var selectedItem: UUID? = nil
    /// The curb's width: it stands just outside the floor's open sides.
    var curbWidthFt: Double = 4.5 / 12
}

extension Room3DContent {
    /// The rest of a room's areas measured from its scan, for drawing alongside one.
    static func otherAreas(in room: EstimateRoom, except id: UUID) -> [OtherAreaPieces] {
        room.sections.compactMap { other in
            guard other.id != id, other.roomScan == nil, let t = other.scanTakeoff,
                  !t.pieces.isEmpty || t.floor == .drawn || (other.area == .floor && t.floor == .room) else { return nil }
            return OtherAreaPieces(name: other.area?.rawValue ?? "Area", pieces: t.pieces,
                                   floor: t.floor == .drawn ? t.floorRect : nil,
                                   tile: other.mainTile, floorTile: other.showerFloorTile,
                                   roomFloor: other.area == .floor && t.floor == .room)
        }
    }

    /// An area of the estimate in 3-D, if it was measured from a scan.
    static func of(room: EstimateRoom, section s: EstimateSection, rates: Rates, fixtures: Bool = true) -> Room3DContent? {
        guard let scan = s.roomScan ?? room.scan, let t = s.scanTakeoff else { return nil }
        let curb = t.curbHeightIn ?? rates.curbHeightIn
        let stone = Set(t.trimPieces(in: scan, area: s.area, curbHeightIn: curb).filter(\.stone).map(\.key))
        return Room3DContent(room: scan, takeoff: t, area: s.area, tile: s.mainTile, floorTile: s.showerFloorTile,
                             others: s.roomScan == nil ? otherAreas(in: room, except: s.id) : [],
                             curbHeightIn: curb, stoneParts: stone, showFixtures: fixtures,
                             curbWidthFt: StonePrices(rates: rates).curbWidthFt)
    }
}

/// A tap in the 3-D view: a wall (where on it, in the scene) or an item.
struct Room3DHit {
    enum Target { case wall(UUID), item(UUID) }
    let target: Target
    /// Where it was tapped: x and z on the plan (feet), y up.
    let point: SCNVector3
    /// The surface's outward direction there.
    let normal: SCNVector3
}

struct Room3DView: View {
    let content: Room3DContent
    @Binding var showFixtures: Bool
    var onTap: (Room3DHit) -> Void = { _ in }
    /// "Add to estimate": the camera as it is now (eye, target).
    var onCapture: (([Double], [Double]) -> Void)? = nil
    @State private var view: Room3DScene.Preset = .area
    @State private var capture = 0
    @State private var captured = false

    var body: some View {
        Room3DSceneView(content: content, preset: view, onTap: onTap, captureToken: capture,
                        onCapture: { eye, target in
                            onCapture?(eye, target)
                            withAnimation { captured = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { captured = false } }
                        })
            .overlay(alignment: .bottomLeading) {
                if onCapture != nil {
                    Button { capture += 1 } label: {
                        Label(captured ? "Added to the estimate" : "Add to estimate",
                              systemImage: captured ? "checkmark" : "camera.viewfinder")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(8)
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Picker("View", selection: $view) {
                        Text(content.area == .shower ? "Shower" : "This area").tag(Room3DScene.Preset.area)
                        Text("Whole room").tag(Room3DScene.Preset.room)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                    if !content.room.fixtures.isEmpty || !content.room.tubOutline.isEmpty {
                        Toggle(isOn: $showFixtures) { Image(systemName: "toilet") }
                            .toggleStyle(.button)
                            .font(.caption)
                    }
                }
                .padding(8)
            }
    }
}

/// SceneKit, in SwiftUI: rebuilt when what it shows changes; the camera
/// moves only when the view is changed, so turning it by hand stays put.
struct Room3DSceneView: UIViewRepresentable {
    let content: Room3DContent
    let preset: Room3DScene.Preset
    var onTap: (Room3DHit) -> Void = { _ in }
    var captureToken = 0
    var onCapture: ([Double], [Double]) -> Void = { _, _ in }

    final class Coordinator: NSObject {
        var captureToken = 0
        var shown: Room3DContent?
        var preset: Room3DScene.Preset?
        var onTap: (Room3DHit) -> Void = { _ in }

        /// The nearest wall or item under the finger (walls seen from
        /// behind don't count: they're the ones dropped away).
        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? SCNView else { return }
            let hits = v.hitTest(g.location(in: v), options: [
                .backFaceCulling: true, .searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true,
            ])
            for h in hits {
                var node: SCNNode? = h.node
                while let n = node {
                    if let name = n.name {
                        let parts = name.split(separator: "|")
                        if parts.count == 2, let id = UUID(uuidString: String(parts[1])) {
                            let target: Room3DHit.Target = parts[0] == "item" ? .item(id) : .wall(id)
                            onTap(Room3DHit(target: target, point: h.worldCoordinates, normal: h.worldNormal))
                            return
                        }
                    }
                    node = n.parent
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        v.addGestureRecognizer(tap)
        v.backgroundColor = UIColor(white: 0.09, alpha: 1)
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        v.scene = SCNScene()
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        c.onTap = onTap
        if captureToken != c.captureToken {
            c.captureToken = captureToken
            if let cam = v.pointOfView {
                let p = cam.worldPosition
                // What it looks at: the orbit target, else 8′ ahead.
                var t = v.defaultCameraController.target
                if captureToken > 0, t.x == 0, t.y == 0, t.z == 0 {
                    let f = cam.worldFront
                    t = SCNVector3(p.x + f.x * 8, p.y + f.y * 8, p.z + f.z * 8)
                }
                let eye = [Double(p.x), Double(p.y), Double(p.z)], target = [Double(t.x), Double(t.y), Double(t.z)]
                let send = onCapture
                DispatchQueue.main.async { send(eye, target) }
            }
        }
        if c.shown != content {
            c.shown = content
            let scene = Room3DScene.build(content)
            let camera = v.pointOfView
            v.scene = scene
            // Keep the view where the owner turned it.
            if let camera, c.preset == preset {
                scene.rootNode.addChildNode(camera)
                v.pointOfView = camera
            } else {
                c.preset = nil
            }
        }
        if c.preset != preset {
            c.preset = preset
            let (camera, target) = Room3DScene.camera(for: preset, content: content)
            v.scene?.rootNode.addChildNode(camera)
            v.pointOfView = camera
            v.defaultCameraController.target = target
        }
    }
}

enum Room3DScene {
    enum Preset: Hashable { case area, room }

    // MARK: Building the scene

    static func build(_ c: Room3DContent) -> SCNScene {
        let scene = SCNScene()
        let root = scene.rootNode
        let room = c.room

        // Light: soft all round, and a key light from above.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 550
        root.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 700
        key.eulerAngles = SCNVector3(-1.0, 0.6, 0)
        root.addChildNode(key)

        // The floor.
        if room.floorOutline.count > 2 {
            let floor = flatShape(room.floorOutline, color: UIColor(white: 0.32, alpha: 1))
            root.addChildNode(floor)
        }

        // Areas' tile: this one and the room's others.
        var areas: [(pieces: [AreaTakeoff.Piece], tile: TileChoice?, floor: AreaTakeoff.FloorRect?, floorTile: TileChoice?, roomFloor: Bool)] = [
            (c.takeoff.pieces, c.tile, c.takeoff.floor == .drawn ? c.takeoff.floorRect : nil, c.floorTile ?? c.tile,
             c.area == .floor && c.takeoff.floor == .room),
        ]
        for o in c.others {
            areas.append((o.pieces, o.tile, o.floor, o.floorTile ?? o.tile, o.roomFloor))
        }
        for a in areas where a.roomFloor && room.floorOutline.count > 2 {
            let node = flatShape(room.floorOutline, color: .white, lift: 0.004)
            node.geometry?.firstMaterial = tileMaterial(a.floorTile, widthFt: bounds(room.floorOutline).w,
                                                       heightFt: bounds(room.floorOutline).h, x0: 0, y0: 0)
            root.addChildNode(node)
        }
        for a in areas {
            if let r = a.floor { root.addChildNode(floorRect(r, tile: a.floorTile)) }
        }

        // Walls, with their doors and windows cut out, and tile on them.
        let windows = c.takeoff.items.filter { $0.kind == .window }
        for w in room.walls {
            let node = wallFrame(w)
            node.name = "wall|\(w.id.uuidString)"
            let t = thickness(w)
            var holes: [Rect] = room.openings.filter { $0.wallID == w.id }.map { o in
                let s = room.span(of: o)
                return Rect(x0: s.lowerBound, x1: s.upperBound, y0: o.bottomFt, y1: o.bottomFt + o.heightFt)
            }
            holes += windows.filter { $0.wallID == w.id }.map {
                Rect(x0: $0.fromFt, x1: $0.toFt, y0: $0.bottomIn / 12, y1: ($0.bottomIn + $0.heightIn) / 12)
            }
            let wallColor = UIColor(white: w.planned ? 0.78 : 0.86, alpha: 1)
            // A partition has the room on both sides: drawn solid, so both faces show.
            let solid = w.planned || PlanDimensions.isPartition(w, in: room)
            // This area's niches in this wall: cut into the face they're on.
            let floorMid = c.takeoff.floor == .drawn ? c.takeoff.floorRect?.center : nil
            let niches: [(rect: Rect, side: Float)] = c.takeoff.items.filter { $0.kind == .niche && $0.wallID == w.id }.map {
                (Rect(x0: $0.fromFt, x1: $0.toFt, y0: $0.bottomIn / 12, y1: ($0.bottomIn + $0.heightIn) / 12),
                 faceSign(w, face: $0.face, room: room, toward: floorMid))
            }
            let inside0 = faceSign(w, face: 0, room: room)
            let bodyHoles = holes + niches.filter { solid || $0.side == inside0 }.map(\.rect)
            // The room's own walls are seen from inside only, like a doll's
            // house: whichever way it's turned, the near walls drop away.
            let inside = faceSign(w, face: 0, room: room)
            for cell in cells(Rect(x0: 0, x1: w.lengthFt, y0: 0, y1: w.heightFt), minus: bodyHoles) {
                if solid {
                    let box = SCNBox(width: cell.w, height: cell.h, length: t, chamferRadius: 0)
                    box.firstMaterial = plain(wallColor)
                    let n = SCNNode(geometry: box)
                    n.position = SCNVector3(cell.midX, cell.midY, 0)
                    node.addChildNode(n)
                } else {
                    let plane = SCNPlane(width: cell.w, height: cell.h)
                    plane.firstMaterial = plain(wallColor)
                    let n = SCNNode(geometry: plane)
                    n.position = SCNVector3(cell.midX, cell.midY, Double(inside) * t / 2)
                    if inside < 0 { n.eulerAngles.y = .pi }
                    node.addChildNode(n)
                }
            }
            // Behind each niche in a solid wall: the rest of the wall's thickness.
            if solid {
                for n in niches {
                    let left = max(t - Self.nicheDepthFt, 0.02)
                    let box = SCNBox(width: n.rect.w, height: n.rect.h, length: left, chamferRadius: 0)
                    box.firstMaterial = plain(wallColor)
                    let b = SCNNode(geometry: box)
                    b.position = SCNVector3(n.rect.midX, n.rect.midY, -Double(n.side) * (t - left) / 2)
                    node.addChildNode(b)
                }
            }
            // Glass in the windows.
            for h in holes where h.y0 > 0.05 {
                let glass = SCNPlane(width: h.w, height: h.h)
                let m = plain(UIColor(red: 0.6, green: 0.8, blue: 0.9, alpha: 0.35))
                m.isDoubleSided = true
                glass.firstMaterial = m
                let g = SCNNode(geometry: glass)
                g.position = SCNVector3(h.midX, h.midY, 0)
                node.addChildNode(g)
            }
            // Tile on this wall, from every area.
            for a in areas {
                for p in a.pieces where p.wallID == w.id {
                    // On the side toward the area's own floor (a shower behind a
                    // partition is on its far side from the room's middle).
                    let side = faceSign(w, face: p.face, room: room, toward: a.floor?.center)
                    let cut = holes + niches.filter { $0.side == side }.map(\.rect)
                    for cell in cells(Rect(x0: p.fromFt, x1: p.toFt, y0: 0, y1: p.heightIn / 12), minus: cut) {
                        let plane = SCNPlane(width: cell.w, height: cell.h)
                        plane.firstMaterial = tileMaterial(a.tile, widthFt: cell.w, heightFt: cell.h, x0: cell.x0, y0: cell.y0)
                        let n = SCNNode(geometry: plane)
                        n.position = SCNVector3(cell.midX, cell.midY, Double(side) * (t / 2 + 0.006))
                        if side < 0 { n.eulerAngles.y = .pi }
                        node.addChildNode(n)
                    }
                }
            }
            // A half wall's cap.
            if room.isKneeWall(w) {
                let cap = SCNBox(width: w.lengthFt, height: 0.06, length: t + 0.04, chamferRadius: 0)
                cap.firstMaterial = c.stoneParts.contains("cap:\(w.id)") ? plain(stoneColor) : tileMaterial(c.tile, widthFt: w.lengthFt, heightFt: t, x0: 0, y0: 0)
                let n = SCNNode(geometry: cap)
                n.position = SCNVector3(w.lengthFt / 2, w.heightFt + 0.03, 0)
                node.addChildNode(n)
            }
            root.addChildNode(node)
        }

        // Benches, niches and corner pieces.
        for item in c.takeoff.items {
            guard let w = room.wall(item.wallID) else { continue }
            let node = wallFrame(w)
            node.name = "item|\(item.id.uuidString)"
            let t = thickness(w)
            let side = Double(faceSign(w, face: item.face, room: room,
                                       toward: c.takeoff.floor == .drawn ? c.takeoff.floorRect?.center : nil))
            switch item.kind {
            case .framedBench, .floatingBench:
                let depth = item.depthIn / 12
                let top = item.heightIn / 12
                let slab = item.kind == .floatingBench ? 3.0 / 12 : top
                let box = SCNBox(width: item.widthFt, height: slab, length: depth, chamferRadius: 0)
                let stoneTop = c.stoneParts.contains("benchTop:\(item.id)")
                let material = tileMaterial(c.tile, widthFt: item.widthFt, heightFt: slab, x0: item.fromFt, y0: 0)
                box.materials = [material, material, material, material,
                                 stoneTop ? plain(stoneColor) : tileMaterial(c.tile, widthFt: item.widthFt, heightFt: depth, x0: item.fromFt, y0: 0),
                                 plain(.darkGray)]
                if c.stoneParts.contains("benchFront:\(item.id)") { box.materials[0] = plain(stoneColor) }
                let n = SCNNode(geometry: box)
                n.position = SCNVector3((item.fromFt + item.toFt) / 2, top - slab / 2, side * (t / 2 + depth / 2))
                if side < 0 { n.eulerAngles.y = .pi }
                node.addChildNode(n)
            case .niche:
                // A recess into the wall (owner, 2026-10-08): the back in the
                // wall's tile, grout lined up with the wall's; the top, sides
                // and sill in tile, or stone (all around: top, sides, sill and
                // dividers; shelves only: sill and dividers).
                let d = Self.nicheDepthFt, w0 = item.widthFt, h = item.heightIn / 12
                let x0 = item.fromFt, y0 = item.bottomIn / 12
                let face = side * t / 2, inner = side * (t / 2 - d)
                // Its own tile, else the wall's.
                let nicheTile = item.tile ?? c.tile
                func surface(_ width: Double, _ height: Double, stone: Bool, gx: Double, gy: Double) -> SCNPlane {
                    let p = SCNPlane(width: width, height: height)
                    // Seen from inside the recess only, so it doesn't show
                    // behind the wall from outside the room.
                    p.firstMaterial = stone ? plain(stoneColor) : tileMaterial(nicheTile, widthFt: width, heightFt: height, x0: gx, y0: gy)
                    return p
                }
                let sides = item.stone == .all, sill = item.stone != .tile
                // The back.
                let back = SCNNode(geometry: surface(w0, h, stone: false, gx: x0, gy: y0))
                back.position = SCNVector3(x0 + w0 / 2, y0 + h / 2, inner)
                if side < 0 { back.eulerAngles.y = .pi }
                node.addChildNode(back)
                // Left and right sides, facing in.
                for (x, turn) in [(x0, Float.pi / 2), (x0 + w0, -Float.pi / 2)] {
                    let n = SCNNode(geometry: surface(d, h, stone: sides, gx: 0, gy: y0))
                    n.position = SCNVector3(x, y0 + h / 2, (face + inner) / 2)
                    n.eulerAngles.y = turn
                    node.addChildNode(n)
                }
                // The top facing down, the sill facing up.
                for (y, stone, turn) in [(y0 + h, sides, Float.pi / 2), (y0, sill, -Float.pi / 2)] {
                    let n = SCNNode(geometry: surface(w0, d, stone: stone, gx: x0, gy: 0))
                    n.position = SCNVector3(x0 + w0 / 2, y, (face + inner) / 2)
                    n.eulerAngles.x = turn
                    node.addChildNode(n)
                }
                // Dividers.
                if item.dividers > 0 {
                    for k in 1...item.dividers {
                        let y = y0 + h * Double(k) / Double(item.dividers + 1)
                        let shelf = SCNBox(width: w0, height: 0.06, length: d, chamferRadius: 0)
                        shelf.firstMaterial = item.stone == .tile ? tileMaterial(nicheTile, widthFt: w0, heightFt: d, x0: x0, y0: 0) : plain(stoneColor)
                        let n = SCNNode(geometry: shelf)
                        n.position = SCNVector3(x0 + w0 / 2, y, (face + inner) / 2)
                        node.addChildNode(n)
                    }
                }
            case .cornerShelf, .cornerFootrest, .cornerSeat:
                let size = item.sizeIn / 12
                let x = item.atStart ? 0.0 : w.lengthFt
                let dir = item.atStart ? 1.0 : -1.0
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + dir * size, y: 0))
                path.addLine(to: CGPoint(x: x, y: -side * size))
                path.close()
                let shape = SCNShape(path: path, extrusionDepth: 1.5 / 12)
                shape.firstMaterial = plain(stoneColor)
                let n = SCNNode(geometry: shape)
                n.eulerAngles.x = -.pi / 2
                n.position = SCNVector3(0, item.bottomIn / 12 - 0.75 / 12, side * t / 2)
                node.addChildNode(n)
            case .window:
                break
            }
            if item.id == c.selectedItem, item.kind == .niche {
                // A green frame round the opening, so its tile or stone still shows.
                let w0 = item.widthFt, h = item.heightIn / 12, x0 = item.fromFt, y0 = item.bottomIn / 12
                let z = side * (t / 2 + 0.01), bar = 0.04
                for (x, y, bw, bh) in [(x0 + w0 / 2, y0 - bar / 2, w0 + 2 * bar, bar), (x0 + w0 / 2, y0 + h + bar / 2, w0 + 2 * bar, bar),
                                       (x0 - bar / 2, y0 + h / 2, bar, h), (x0 + w0 + bar / 2, y0 + h / 2, bar, h)] {
                    let b = SCNBox(width: bw, height: bh, length: 0.01, chamferRadius: 0)
                    b.firstMaterial = plain(.systemGreen)
                    let n = SCNNode(geometry: b)
                    n.position = SCNVector3(x, y, z)
                    node.addChildNode(n)
                }
            } else if item.id == c.selectedItem {
                node.enumerateHierarchy { n, _ in
                    n.geometry?.materials.forEach { $0.emission.contents = UIColor(red: 0.1, green: 0.45, blue: 0.35, alpha: 1) }
                }
            }
            root.addChildNode(node)
        }

        // The curb.
        if c.area == .shower {
            let curbStone = c.stoneParts.contains("curb") || c.stoneParts.contains { $0.hasPrefix("curb:") }
            // Just outside the floor: its inside face on the floor's edge.
            let mid = c.takeoff.floorRect?.center
            for (a, b) in c.takeoff.curbEdges(in: room) {
                let len = hypot(b.x - a.x, b.y - a.y)
                let h = c.curbHeightIn / 12, w = c.curbWidthFt
                var nx = -(b.y - a.y) / max(len, 1e-9), ny = (b.x - a.x) / max(len, 1e-9)
                if let m = mid, ((a.x + b.x) / 2 - m.x) * nx + ((a.y + b.y) / 2 - m.y) * ny < 0 { nx = -nx; ny = -ny }
                let box = SCNBox(width: len, height: h, length: w, chamferRadius: 0.01)
                box.firstMaterial = curbStone ? plain(stoneColor) : tileMaterial(c.tile, widthFt: len, heightFt: h, x0: 0, y0: 0)
                let n = SCNNode(geometry: box)
                n.position = SCNVector3((a.x + b.x) / 2 + nx * w / 2, h / 2, (a.y + b.y) / 2 + ny * w / 2)
                n.eulerAngles.y = Float(-atan2(b.y - a.y, b.x - a.x))
                root.addChildNode(n)
            }
            // The drain: a dark grate on the floor.
            if c.takeoff.floor == .drawn, let d = c.takeoff.drainShown() {
                let k = c.takeoff.drainOutline(d)
                if k.count == 4 {
                    let w = hypot(k[1].x - k[0].x, k[1].y - k[0].y), l = hypot(k[3].x - k[0].x, k[3].y - k[0].y)
                    let box = SCNBox(width: w, height: 0.01, length: l, chamferRadius: 0)
                    box.firstMaterial = plain(UIColor(white: 0.18, alpha: 1))
                    let n = SCNNode(geometry: box)
                    n.position = SCNVector3((k[0].x + k[2].x) / 2, 0.02, (k[0].y + k[2].y) / 2)
                    n.eulerAngles.y = Float(-atan2(k[1].y - k[0].y, k[1].x - k[0].x))
                    root.addChildNode(n)
                }
            }
        }

        // Fixtures the scanner found.
        if c.showFixtures {
            var found = room.fixtures
            if found.isEmpty, room.tubOutline.count == 4 {
                found = [ScannedRoom.Fixture(kind: "Bathtub", outline: room.tubOutline, heightFt: 1.75)]
            }
            for f in found where f.outline.count == 4 {
                let p = f.outline
                let wdt = hypot(p[1].x - p[0].x, p[1].y - p[0].y)
                let dep = hypot(p[3].x - p[0].x, p[3].y - p[0].y)
                let box = SCNBox(width: wdt, height: f.heightFt, length: dep, chamferRadius: min(0.15, f.heightFt / 4))
                box.firstMaterial = plain(UIColor(white: 0.97, alpha: 1))
                let n = SCNNode(geometry: box)
                let cx = p.map(\.x).reduce(0, +) / 4, cz = p.map(\.y).reduce(0, +) / 4
                n.position = SCNVector3(cx, f.heightFt / 2, cz)
                n.eulerAngles.y = Float(-atan2(p[1].y - p[0].y, p[1].x - p[0].x))
                root.addChildNode(n)
            }
        }
        return scene
    }

    // MARK: Pictures

    /// The scene drawn from a camera, off screen, on a light background (for the PDF).
    static func picture(_ c: Room3DContent, eye: [Double], target: [Double], size: CGSize) -> UIImage? {
        guard eye.count == 3, target.count == 3, let device = MTLCreateSystemDefaultDevice() else { return nil }
        let scene = build(c)
        scene.background.contents = UIColor(white: 0.96, alpha: 1)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 60
        cam.camera?.zNear = 0.1
        cam.position = SCNVector3(eye[0], eye[1], eye[2])
        cam.look(at: SCNVector3(target[0], target[1], target[2]))
        scene.rootNode.addChildNode(cam)
        let r = SCNRenderer(device: device, options: nil)
        r.scene = scene
        r.pointOfView = cam
        return r.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    /// A standard view's camera as saved with a picture.
    static func standard(_ preset: Preset, content: Room3DContent) -> (eye: [Double], target: [Double]) {
        let (cam, t) = camera(for: preset, content: content)
        return ([Double(cam.position.x), Double(cam.position.y), Double(cam.position.z)],
                [Double(t.x), Double(t.y), Double(t.z)])
    }

    // MARK: Cameras

    static func camera(for preset: Preset, content c: Room3DContent) -> (SCNNode, SCNVector3) {
        let room = c.room
        let pts = room.floorOutline.isEmpty ? room.walls.flatMap { [$0.start, $0.end] } : room.floorOutline
        let b = bounds(pts)
        let center = ScannedRoom.Point(x: b.x0 + b.w / 2, y: b.y0 + b.h / 2)
        let size = max(b.w, b.h, 4)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 60
        cam.camera?.zNear = 0.1

        var target = SCNVector3(center.x, 2.5, center.y)
        var eye = SCNVector3(center.x - 0.35 * size, 0.95 * size + 4, center.y + 0.75 * size)
        if preset == .area, let focus = focusPoint(c) {
            target = SCNVector3(focus.center.x, 3.5, focus.center.y)
            let out = focus.out
            let back = focus.reach + 4.5
            eye = SCNVector3(focus.center.x + out.x * back, 5.4, focus.center.y + out.y * back)
        }
        cam.position = eye
        cam.look(at: target)
        return (cam, target)
    }

    /// The middle of this area and the way out of it (toward its open side,
    /// else the room's middle), for the camera that looks into it.
    private static func focusPoint(_ c: Room3DContent) -> (center: ScannedRoom.Point, out: ScannedRoom.Point, reach: Double)? {
        let room = c.room
        var center: ScannedRoom.Point
        var reach = 3.0
        if c.takeoff.floor == .drawn, let r = c.takeoff.floorRect {
            let k = r.corners
            center = .init(x: (k[0].x + k[2].x) / 2, y: (k[0].y + k[2].y) / 2)
            reach = max(r.widthFt, r.depthFt) / 2
        } else {
            let mids = c.takeoff.pieces.compactMap { p in room.wall(p.wallID).map { room.point(on: $0, along: (p.fromFt + p.toFt) / 2) } }
            guard !mids.isEmpty else { return nil }
            center = .init(x: mids.map(\.x).reduce(0, +) / Double(mids.count), y: mids.map(\.y).reduce(0, +) / Double(mids.count))
        }
        var toward: ScannedRoom.Point
        if let side = c.takeoff.openSides(in: room).max(by: { $0.lengthFt < $1.lengthFt }) {
            toward = .init(x: (side.a.x + side.b.x) / 2, y: (side.a.y + side.b.y) / 2)
        } else {
            let b = bounds(room.floorOutline.isEmpty ? room.walls.flatMap { [$0.start, $0.end] } : room.floorOutline)
            toward = .init(x: b.x0 + b.w / 2, y: b.y0 + b.h / 2)
        }
        var out = ScannedRoom.Point(x: toward.x - center.x, y: toward.y - center.y)
        let l = hypot(out.x, out.y)
        out = l > 0.01 ? .init(x: out.x / l, y: out.y / l) : .init(x: 0, y: 1)
        return (center, out, reach)
    }

    // MARK: Pieces

    struct Rect {
        var x0: Double, x1: Double, y0: Double, y1: Double
        var w: Double { x1 - x0 }
        var h: Double { y1 - y0 }
        var midX: Double { (x0 + x1) / 2 }
        var midY: Double { (y0 + y1) / 2 }
    }

    /// A rectangle less some holes, as rectangles: split at the holes' sides,
    /// then each strip less the holes across it.
    static func cells(_ r: Rect, minus holes: [Rect]) -> [Rect] {
        let cuts = Set(([r.x0, r.x1] + holes.flatMap { [$0.x0, $0.x1] }).map { min(max($0, r.x0), r.x1) }).sorted()
        var out: [Rect] = []
        for (a, b) in zip(cuts, cuts.dropFirst()) where b - a > 0.002 {
            var spans = [(r.y0, r.y1)]
            for h in holes where h.x0 <= a + 0.001 && h.x1 >= b - 0.001 {
                spans = spans.flatMap { s -> [(Double, Double)] in
                    var parts: [(Double, Double)] = []
                    if h.y0 > s.0 { parts.append((s.0, min(s.1, h.y0))) }
                    if h.y1 < s.1 { parts.append((max(s.0, h.y1), s.1)) }
                    return parts.filter { $0.1 - $0.0 > 0.002 }
                }
            }
            out += spans.map { Rect(x0: a, x1: b, y0: $0.0, y1: $0.1) }
        }
        return out
    }

    /// A node whose x runs along the wall from its start, z out of its first face, y up.
    private static func wallFrame(_ w: ScannedRoom.Wall) -> SCNNode {
        let n = SCNNode()
        n.position = SCNVector3(w.start.x, 0, w.start.y)
        n.eulerAngles.y = Float(-atan2(w.end.y - w.start.y, w.end.x - w.start.x))
        return n
    }

    /// How deep a niche goes into the wall (`AreaTakeoff.nicheDepthIn`).
    static let nicheDepthFt = AreaTakeoff.nicheDepthIn / 12

    private static func thickness(_ w: ScannedRoom.Wall) -> Double {
        w.planned ? max(w.thicknessIn, 1) / 12 : 4.0 / 12
    }

    /// Which side of the wall (+1 its first face, −1 the other) a piece's tile is on:
    /// a planned wall's chosen face; a scanned wall's side toward `toward` (the
    /// area's floor), else toward the room's middle.
    private static func faceSign(_ w: ScannedRoom.Wall, face: Int, room: ScannedRoom,
                                 toward: ScannedRoom.Point? = nil) -> Float {
        if w.planned { return face == 0 ? 1 : -1 }
        let dx = w.end.x - w.start.x, dy = w.end.y - w.start.y
        let pts = room.floorOutline.isEmpty ? room.walls.flatMap { [$0.start, $0.end] } : room.floorOutline
        let cx = toward?.x ?? pts.map(\.x).reduce(0, +) / Double(max(pts.count, 1))
        let cy = toward?.y ?? pts.map(\.y).reduce(0, +) / Double(max(pts.count, 1))
        let mid = ScannedRoom.Point(x: (w.start.x + w.end.x) / 2, y: (w.start.y + w.end.y) / 2)
        let own: Float = (cx - mid.x) * -dy + (cy - mid.y) * dx >= 0 ? 1 : -1
        // A scanned divider's face 1 is the far side from the area (2026-10-09).
        return face == 1 ? -own : own
    }

    private static func bounds(_ pts: [ScannedRoom.Point]) -> (x0: Double, y0: Double, w: Double, h: Double) {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let x0 = xs.min() ?? 0, y0 = ys.min() ?? 0
        return (x0, y0, (xs.max() ?? 1) - x0, (ys.max() ?? 1) - y0)
    }

    /// A flat outline lying on the floor.
    private static func flatShape(_ outline: [ScannedRoom.Point], color: UIColor, lift: Double = 0) -> SCNNode {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: outline[0].x, y: -outline[0].y))
        for p in outline.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: -p.y)) }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: 0.02)
        shape.firstMaterial = plain(color)
        let n = SCNNode(geometry: shape)
        n.eulerAngles.x = -.pi / 2
        n.position.y = Float(lift)
        return n
    }

    private static func floorRect(_ r: AreaTakeoff.FloorRect, tile: TileChoice?) -> SCNNode {
        let plane = SCNPlane(width: r.widthFt, height: r.depthFt)
        plane.firstMaterial = tileMaterial(tile, widthFt: r.widthFt, heightFt: r.depthFt, x0: 0, y0: 0)
        let n = SCNNode(geometry: plane)
        let k = r.corners
        n.position = SCNVector3((k[0].x + k[2].x) / 2, 0.012, (k[0].y + k[2].y) / 2)
        // Lie flat, its width along u.
        n.eulerAngles = SCNVector3(-Float.pi / 2, Float(-atan2(r.u.y, r.u.x)), 0)
        return n
    }

    // MARK: Materials

    /// Stone: the tan the plan uses, so it reads apart from light tile.
    static let stoneColor = UIColor(red: 0.80, green: 0.70, blue: 0.53, alpha: 1)

    private static func plain(_ c: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = c
        m.lightingModel = .lambert
        return m
    }

    /// Tile with its grout lines, laid out from the wall's (or floor's) own
    /// corner so neighbouring cells line up.
    static func tileMaterial(_ tile: TileChoice?, widthFt: Double, heightFt: Double, x0: Double, y0: Double) -> SCNMaterial {
        let pattern = TilePattern.make(tile)
        let m = SCNMaterial()
        m.diffuse.contents = pattern.image
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.minificationFilter = .linear
        m.diffuse.magnificationFilter = .linear
        // Grout lines stay sharp on walls seen at an angle.
        m.diffuse.maxAnisotropy = 16
        let sx = widthFt * 12 / pattern.periodIn.width, sy = heightFt * 12 / pattern.periodIn.height
        let tx = x0 * 12 / pattern.periodIn.width, ty = y0 * 12 / pattern.periodIn.height
        m.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(Float(sx), Float(sy), 1), Float(tx), Float(ty), 0)
        m.lightingModel = .lambert
        return m
    }
}

/// One repeat of a tile pattern as an image: the tile's colour, its real
/// shape, size and layout, with grout lines (owner, 2026-10-09: "the
/// patterns should be accurate"; each one checked by the owner on a sheet).
enum TilePattern {
    struct Made { let image: UIImage; let periodIn: CGSize }
    private static var cache: [String: Made] = [:]

    static func color(_ t: TileType?) -> UIColor {
        switch t {
        case .porcelain: UIColor(red: 0.87, green: 0.85, blue: 0.81, alpha: 1)
        case .ceramic, nil: UIColor(white: 0.94, alpha: 1)
        case .glass: UIColor(red: 0.74, green: 0.87, blue: 0.9, alpha: 1)
        case .marble: UIColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1)
        case .limestone: UIColor(red: 0.87, green: 0.81, blue: 0.71, alpha: 1)
        case .slate: UIColor(red: 0.43, green: 0.45, blue: 0.48, alpha: 1)
        case .granite: UIColor(red: 0.55, green: 0.53, blue: 0.52, alpha: 1)
        case .quartzite: UIColor(red: 0.89, green: 0.89, blue: 0.86, alpha: 1)
        case .cement: UIColor(red: 0.7, green: 0.7, blue: 0.68, alpha: 1)
        case .terracotta: UIColor(red: 0.78, green: 0.5, blue: 0.36, alpha: 1)
        case .zellige: UIColor(red: 0.42, green: 0.63, blue: 0.6, alpha: 1)
        case .travertine: UIColor(red: 0.89, green: 0.83, blue: 0.72, alpha: 1)
        case .terrazzo: UIColor(red: 0.86, green: 0.85, blue: 0.82, alpha: 1)
        case .quarry: UIColor(red: 0.66, green: 0.36, blue: 0.27, alpha: 1)
        case .pearl: UIColor(red: 0.93, green: 0.92, blue: 0.95, alpha: 1)
        }
    }

    /// The tile's size, long side first, in inches: as entered, else usual for its shape.
    static func size(_ t: TileChoice?) -> (Double, Double) {
        guard let t else { return (12, 24) }
        var w = t.tileWidthIn, l = t.tileLengthIn
        if t.layout == .multiTile, let first = t.pieces.first { w = first.widthIn; l = first.lengthIn }
        let fallback: (Double, Double) = switch t.tileSize {
        case .square: (12, 12)
        case .rectangle: (12, 24)
        case .mosaic: (2, 2)
        case .hexagon: (8, 8)
        case .arabesque, .starCross: (6, 6)
        case .diamond: (4, 8)
        case .triangle, .fishscale: (6, 6)
        case .picket: (3, 12)
        case .pill: (2, 6)
        }
        let a = w ?? l ?? fallback.0, b = l ?? w ?? fallback.1
        return (max(a, b, 0.5), max(min(a, b), 0.5))
    }

    /// The shape a tile is drawn as: its shape and layout, or for a mosaic its style.
    enum Shape: String {
        case rect, hexagon, pennyRound, octagonDot, diamond, rhombus, cube, triangle,
             picket, pill, chevron, basketweave, pinwheel, hopscotch, fishscale, arabesque, starCross,
             pebble, randomStrip, mixedStick, miniBrick, herringbone, doubleHerringbone, versailles, waterjet
    }

    static func shape(_ t: TileChoice?) -> Shape {
        guard let t else { return .rect }
        switch t.tileSize {
        case .square, .rectangle:
            switch t.layout {
            case .chevron: return .chevron
            case .basketweave: return .basketweave
            case .versailles: return .versailles
            case .hopscotch: return .hopscotch
            case .doubleHerringbone: return .doubleHerringbone
            default: return .rect
            }
        case .hexagon: return .hexagon
        case .arabesque: return .arabesque
        case .starCross: return .starCross
        case .diamond: return .rhombus
        case .triangle: return .triangle
        case .fishscale: return .fishscale
        case .picket: return .picket
        case .pill: return .pill
        case .mosaic:
            switch t.mosaicStyle ?? .square {
            case .square, .rectangular: return .rect
            case .hexagon: return .hexagon
            case .octagonDot: return .octagonDot
            case .diamond: return .diamond
            case .waterjet: return .waterjet
            case .miniBrick: return .miniBrick
            case .picket: return .picket
            case .herringbone: return .herringbone
            case .chevron: return .chevron
            case .basketweave: return .basketweave
            case .pinwheel: return .pinwheel
            case .pennyRound: return .pennyRound
            case .fishscale: return .fishscale
            case .arabesque: return .arabesque
            case .pebble: return .pebble
            case .randomStrip: return .randomStrip
            case .cube: return .cube
            case .triangle: return .triangle
            case .mixedStick: return .mixedStick
            case .pill: return .pill
            }
        }
    }

    /// A mosaic piece's usual size (inches, long side first) when none was entered.
    private static func mosaicSize(_ style: MosaicStyle) -> (Double, Double) {
        switch style {
        case .square, .hexagon, .octagonDot, .diamond, .fishscale, .triangle: (2, 2)
        case .rectangular, .herringbone, .basketweave, .pinwheel: (2, 1)
        case .pennyRound: (0.75, 0.75)
        case .miniBrick: (2, 0.625)
        case .picket: (4, 1)
        case .chevron: (3, 1)
        case .arabesque: (2.3, 2)
        case .pebble: (1.5, 1)
        case .randomStrip, .mixedStick: (3, 0.625)
        case .pill: (3, 1)
        case .waterjet: (12, 12)
        case .cube: (1.5, 1.5)
        }
    }

    /// Waterjet designs: the owner chose Floral from five drawn on
    /// 2026-10-09 (floral, wave, quatrefoil, ogee, vine).
    enum WaterjetDesign: String, CaseIterable { case floral }
    static var waterjetDesign: WaterjetDesign = .floral

    /// One tile in the repeat: its outline (inches) and its tone (0 the
    /// tile's colour, 1 a darker shade, 2 darker still, 3 lighter).
    private struct Piece { var path: CGPath; var tone: Int = 0 }

    /// The size it's drawn at (long side first): as entered, else usual for
    /// its shape or mosaic style.
    static func drawnSize(_ t: TileChoice?) -> (Double, Double) {
        if t?.tileSize == .mosaic, t?.tileWidthIn == nil, t?.tileLengthIn == nil {
            return mosaicSize(t?.mosaicStyle ?? .square)
        }
        return size(t)
    }

    static func make(_ t: TileChoice?, waterjet: WaterjetDesign? = nil) -> Made {
        let shape = shape(t)
        let (long, short) = drawnSize(t)
        let layout = t?.layout ?? .straightStacked
        let design = waterjet ?? waterjetDesign
        let key = "\(t?.tileType.rawValue ?? "-")|\(long)|\(short)|\(layout.rawValue)|\(shape.rawValue)|\(design.rawValue)"
            + "|\(t?.vertical == true)|\(t?.photoID ?? "")|\(t?.turnedOver == true)"
        if let m = cache[key] { return m }

        var pieces: [Piece] = []
        var period = CGSize(width: long, height: short)
        /// The ground between pieces: grout, or a tone (crosses, a waterjet's field).
        var groundTone: Int? = nil
        /// Drawn in order with no copies at the edges (overlapping scales).
        var ordered = false

        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, tone: Int = 0) -> Piece {
            Piece(path: CGPath(rect: CGRect(x: x, y: y, width: w, height: h), transform: nil), tone: tone)
        }
        func poly(_ pts: [(Double, Double)], tone: Int = 0) -> Piece {
            let path = CGMutablePath()
            path.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
            path.closeSubpath()
            return Piece(path: path, tone: tone)
        }
        func circle(_ cx: Double, _ cy: Double, _ r: Double, tone: Int = 0) -> Piece {
            Piece(path: CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil), tone: tone)
        }
        /// Hexagons pointed left and right in columns half a height apart.
        func pointedHexes(p: Double, edge: Double, h: Double) {
            let pts = [(0.0, h / 2), (p, 0), (p + edge, 0), (2 * p + edge, h / 2), (p + edge, h), (p, h)]
            let dx = p + edge
            period = CGSize(width: 2 * dx, height: h)
            for (ox, oy) in [(0.0, 0.0), (dx, h / 2), (dx, -h / 2)] {
                pieces.append(poly(pts.map { ($0.0 + ox, $0.1 + oy) }))
            }
        }
        /// A base repeat turned 45°: whole tiles laid on the diagonal. The
        /// turned repeat is square, √2 × the base repeat's common multiple.
        func turned45(_ base: [Piece], _ bw: Double, _ bh: Double) {
            func eighths(_ v: Double) -> Int { max(1, Int((v * 8).rounded())) }
            let m = Double(lcm(eighths(bw), eighths(bh))) / 8
            let side = m * 2.squareRoot()
            period = CGSize(width: side, height: side)
            let reach = Int((side * 1.5 / min(bw, bh)).rounded(.up)) + 2
            let turn = CGAffineTransform(rotationAngle: .pi / 4)
            let box = CGRect(x: -1, y: -1, width: side + 2, height: side + 2)
            for i in -reach...reach {
                for j in -reach...reach {
                    var move = CGAffineTransform(translationX: Double(i) * bw, y: Double(j) * bh).concatenating(turn)
                    for p in base {
                        guard let moved = p.path.copy(using: &move), moved.boundingBox.intersects(box) else { continue }
                        pieces.append(Piece(path: moved, tone: p.tone))
                    }
                }
            }
        }
        /// Herringbone of l × w planks: staircases of one flat and one upright
        /// plank, each shifted (l, −l); it repeats every 2·l·w/gcd both ways.
        func herringbone(_ l: Double, _ w: Double, split: Int = 1) -> (Double, [Piece]) {
            func eighths(_ v: Double) -> Int { max(1, Int((v * 8).rounded())) }
            let g = gcd(eighths(l), eighths(w))
            let p = 2 * Double(eighths(l)) * Double(eighths(w)) / Double(max(g, 1)) / 8
            var out: [Piece] = []
            let steps = Int((2 * p) / w) + 4
            for strip in -steps...steps {
                let ox = Double(strip) * l, oy = Double(-strip) * l
                for k in -steps...steps {
                    let x = ox + Double(k) * w, y = oy + Double(k) * w
                    for (r, flat) in [(CGRect(x: x, y: y, width: l, height: w), true), (CGRect(x: x, y: y + w, width: w, height: l), false)]
                    where r.maxX > -l && r.minX < p + l && r.maxY > -l && r.minY < p + l {
                        // Double herringbone: each plank is `split` narrower planks side by side.
                        for s in 0..<split {
                            let f = Double(s) / Double(split), n = 1 / Double(split)
                            let part = flat ? CGRect(x: r.minX, y: r.minY + r.height * f, width: r.width, height: r.height * n)
                                            : CGRect(x: r.minX + r.width * f, y: r.minY, width: r.width * n, height: r.height)
                            out.append(Piece(path: CGPath(rect: part, transform: nil)))
                        }
                    }
                }
            }
            return (p, out)
        }
        var seed: UInt32 = 7
        func rnd() -> Double { seed = seed &* 1_664_525 &+ 1_013_904_223; return Double(seed >> 8) / Double(1 << 24) }

        switch shape {
        case .rect:
            switch layout {
            case .runningBond, .oneThirdOffset:
                // Each row shifted a half (or a third) of a tile.
                let rows = layout == .runningBond ? 2 : 3
                period = CGSize(width: long, height: short * Double(rows))
                for r in 0..<rows {
                    let shift = long * Double(r) / Double(rows)
                    pieces.append(rect(shift, short * Double(r), long, short))
                    pieces.append(rect(shift - long, short * Double(r), long, short))
                }
            case .herringbone:
                let (p, hb) = herringbone(long, short)
                period = CGSize(width: p, height: p); pieces = hb
            case .diagonalHerringbone:
                let (p, hb) = herringbone(long, short)
                turned45(hb, p, p)
            case .diagonal:
                // The tile itself on the diagonal (a 3 × 12 stays a 3 × 12), stacked.
                turned45([rect(0, 0, long, short)], long, short)
            default:
                period = CGSize(width: long, height: short)
                pieces = [rect(0, 0, long, short)]
            }
        case .doubleHerringbone:
            let (p, hb) = herringbone(long, short * 2, split: 2)
            period = CGSize(width: p, height: p); pieces = hb
        case .herringbone:
            let (p, hb) = herringbone(long, short)
            period = CGSize(width: p, height: p); pieces = hb
        case .miniBrick:
            period = CGSize(width: long, height: short * 2)
            pieces = [rect(0, 0, long, short), rect(-long / 2, short, long, short), rect(long / 2, short, long, short)]
        case .hexagon:
            // Regular hexagons, `short` across the flats.
            let r = short / 3.squareRoot()
            pointedHexes(p: r / 2, edge: r, h: short)
        case .picket:
            // Pickets: pointed ends, nested in the next row.
            pointedHexes(p: short / 2, edge: max(long - short, 0.1), h: short)
        case .pill:
            // Pills (capsules): fully rounded ends, rows offset half a pill so
            // each end sits against the side of the next row.
            period = CGSize(width: long, height: short * 2)
            func pill(_ x: Double, _ y: Double) -> Piece {
                Piece(path: CGPath(roundedRect: CGRect(x: x, y: y, width: long, height: short),
                                   cornerWidth: short / 2, cornerHeight: short / 2, transform: nil))
            }
            pieces = [pill(0, 0), pill(-long / 2, short), pill(long / 2, short)]
        case .pennyRound:
            let d = short
            period = CGSize(width: d, height: d * 3.squareRoot())
            pieces = [circle(0, 0, d / 2), circle(d / 2, d * 3.squareRoot() / 2, d / 2)]
        case .fishscale:
            // Fan-shaped scales, rows half a scale apart, each row lapping the
            // one before it the same way all over: round side up, or down
            // when turned over (both are installed; scallop is the same tile).
            let d = long, r = d / 2
            period = CGSize(width: d, height: d)
            ordered = true
            let rows = (-3...6).map { Double($0) }
            for row in (t?.turnedOver == true ? rows : rows.reversed()) {
                for col in -2...3 {
                    let cx = Double(col) * d + (Int(row).isMultiple(of: 2) ? 0 : r)
                    pieces.append(circle(cx, row * r, r))
                }
            }
        case .octagonDot:
            let d = short, c = d / (2 + 2.squareRoot())
            period = CGSize(width: d, height: d)
            pieces = [poly([(c, 0), (d - c, 0), (d, c), (d, d - c), (d - c, d), (c, d), (0, d - c), (0, c)]),
                      poly([(0, -c), (c, 0), (0, c), (-c, 0)], tone: 1)]
        case .diamond:
            // Squares turned 45°.
            let d = short * 2.squareRoot()
            period = CGSize(width: d, height: d)
            for (cx, cy) in [(d / 2, d / 2), (0.0, 0.0)] {
                pieces.append(poly([(cx, cy - d / 2), (cx + d / 2, cy), (cx, cy + d / 2), (cx - d / 2, cy)]))
            }
        case .rhombus:
            // Long diamonds: `long` the long diagonal (across), `short` the short one.
            let a = long, b = short
            period = CGSize(width: a, height: b)
            for (cx, cy) in [(a / 2, b / 2), (0.0, 0.0)] {
                pieces.append(poly([(cx, cy - b / 2), (cx + a / 2, cy), (cx, cy + b / 2), (cx - a / 2, cy)]))
            }
        case .cube:
            // Tumbling blocks: three 60° diamonds in each hexagon, light, mid and dark.
            let a = short, w = a * 3.squareRoot()
            period = CGSize(width: w, height: 3 * a)
            for (cx, cy) in [(0.0, 0.0), (w / 2, 1.5 * a), (w, 0.0), (0.0, 3 * a), (w, 3 * a), (w / 2, -1.5 * a)] {
                let top = (cx, cy - a), ur = (cx + w / 2, cy - a / 2), lr = (cx + w / 2, cy + a / 2)
                let bot = (cx, cy + a), ll = (cx - w / 2, cy + a / 2), ul = (cx - w / 2, cy - a / 2), c = (cx, cy)
                pieces.append(poly([top, ur, c, ul], tone: 3))
                pieces.append(poly([c, ur, lr, bot], tone: 2))
                pieces.append(poly([ul, c, bot, ll], tone: 1))
            }
        case .triangle:
            // Equilateral triangles, point up and point down.
            let a = long, h = a * 3.squareRoot() / 2
            period = CGSize(width: a, height: 2 * h)
            for row in 0..<2 {
                let y = Double(row) * h, shift = row == 0 ? 0 : a / 2
                for k in -1...1 {
                    let x = Double(k) * a + shift
                    pieces.append(poly([(x, y + h), (x + a / 2, y), (x + a, y + h)]))
                    pieces.append(poly([(x + a / 2, y), (x + a, y + h), (x + 1.5 * a, y)]))
                }
            }
        case .chevron:
            // Planks cut at 45°, leaning up in one column and down in the next.
            let c = long * 0.7071, h = short * 1.4142
            period = CGSize(width: 2 * c, height: h)
            for k in -2...2 {
                let y = Double(k) * h
                pieces.append(poly([(0, y + c), (c, y), (c, y + h), (0, y + c + h)]))
                pieces.append(poly([(c, y), (2 * c, y + c), (2 * c, y + c + h), (c, y + h)]))
            }
        case .basketweave:
            // Planks in pairs (or as many as fill a square), turned a quarter each square.
            let l = long, n = max(2, Int((long / short).rounded())), w = l / Double(n)
            period = CGSize(width: 2 * l, height: 2 * l)
            for (bx, by, flat) in [(0.0, 0.0, true), (l, 0.0, false), (0.0, l, false), (l, l, true)] {
                for k in 0..<n {
                    pieces.append(flat ? rect(bx, by + Double(k) * w, l, w) : rect(bx + Double(k) * w, by, w, l))
                }
            }
        case .pinwheel:
            // A small square with four planks turning round it, in blocks.
            let l = long, w = short, side = l + w
            period = CGSize(width: side, height: side)
            pieces = [rect(0, 0, l, w), rect(l, 0, w, l), rect(w, l, l, w), rect(0, w, w, l),
                      rect(w, w, max(l - w, 0.05), max(l - w, 0.05), tone: 1)]
        case .hopscotch:
            // Big squares, each with a small square at one corner's turn.
            let big = long, sm = long / 2
            period = CGSize(width: 5 * sm, height: 5 * sm)
            for i in -2...3 {
                for j in -2...3 {
                    let x = Double(i) * big - Double(j) * sm, y = Double(i) * sm + Double(j) * big
                    pieces.append(rect(x, y, big, big))
                    pieces.append(rect(x + big, y, sm, sm))
                }
            }
        case .versailles:
            // The French pattern as sold (a 16 sq ft set): 8×8, 8×16, 16×16
            // and 16×24 in the standard 12-piece motif, which repeats every
            // 48″ each way (u = half the long side, usually 8″).
            let u = max(long / 2, 2)
            let set: [(Double, Double, Double, Double)] =
                [(0, 1, 2, 3), (2, 0, 2, 2), (4, 0, 1, 1), (4, 1, 2, 2), (2, 2, 1, 2), (3, 2, 1, 1),
                 (3, 3, 3, 2), (0, 4, 1, 1), (1, 4, 2, 2), (3, 5, 2, 1), (5, 5, 2, 2), (1, 6, 1, 1)]
            period = CGSize(width: 6 * u, height: 6 * u)
            for (x, y, w, h) in set { pieces.append(rect(x * u, y * u, w * u, h * u)) }
        case .arabesque:
            // Lanterns: an onion point top and bottom, full round sides.
            // Laid on a diamond lattice, each edge an S-curve its neighbour
            // shares, so they lock together with no gaps.
            let w = short, h = max(long, short * 1.2)
            period = CGSize(width: w, height: h)
            func lantern(_ ox: Double, _ oy: Double) -> Piece {
                let top = CGPoint(x: ox, y: oy), right = CGPoint(x: ox + w / 2, y: oy + h / 2)
                let bottom = CGPoint(x: ox, y: oy + h), left = CGPoint(x: ox - w / 2, y: oy + h / 2)
                // The curve on edges running down-right (top→right, left→bottom),
                // and its mirror on edges running down-left.
                func edge(_ a: CGPoint, _ b: CGPoint, mirror: Bool) -> [CGPoint] {
                    let dx = b.x - a.x, dy = b.y - a.y, len = (dx * dx + dy * dy).squareRoot()
                    // Normal pointing up-right for down-right edges; mirrored for down-left.
                    var nx = dy / len, ny = -dx / len
                    if mirror { nx = -nx; ny = -ny }
                    return (1...24).map { i in
                        let s = Double(i) / 24
                        // In at the tip, out at the side: just enough that the
                        // curve leaves each tip straight up or down (a sharp
                        // onion point) and meets the side upright (smooth and
                        // widest there), as real arabesque tile is cut.
                        let f = -(w / (2 * .pi * h)) * len * sin(2 * .pi * s)
                        return CGPoint(x: a.x + dx * s + nx * f, y: a.y + dy * s + ny * f)
                    }
                }
                func back(_ a: CGPoint, _ b: CGPoint, mirror: Bool) -> [CGPoint] {
                    Array(([a] + edge(a, b, mirror: mirror)).reversed().dropFirst())
                }
                // One unbroken outline, clockwise from the top point.
                let outline = [top] + edge(top, right, mirror: false) + edge(right, bottom, mirror: true)
                    + back(left, bottom, mirror: false) + back(top, left, mirror: true)
                let path = CGMutablePath()
                path.addLines(between: outline)
                path.closeSubpath()
                return Piece(path: path)
            }
            pieces = [lantern(0, 0), lantern(w / 2, h / 2), lantern(-w / 2, h / 2), lantern(0, -h), lantern(w, 0)]
        case .starCross:
            // Eight-point stars (two squares, one turned 45°) touching tip to
            // tip; the four-armed crosses between them in a darker shade.
            let d = long
            period = CGSize(width: d, height: d)
            var pts: [(Double, Double)] = []
            for k in 0..<16 {
                let a = Double(k) * .pi / 8
                let r = k.isMultiple(of: 2) ? d * 0.5 : d * 0.5 * cos(.pi / 4) / cos(.pi / 8)
                pts.append((d / 2 + r * cos(a), d / 2 + r * sin(a)))
            }
            pieces = [poly(pts)]
            groundTone = 1
        case .pebble:
            // Flat river pebbles of mixed size and shade packed tight, thin
            // grout between: each pebble is the stone's own patch of ground
            // (the space nearer its middle than any other's), shrunk by the
            // grout and its corners rounded off.
            let cell = long * 0.85, n = 7
            period = CGSize(width: cell * Double(n), height: cell * Double(n))
            var seeds: [CGPoint] = []
            for i in 0..<n {
                for j in 0..<n {
                    seeds.append(CGPoint(x: (Double(i) + 0.5 + (rnd() - 0.5) * 0.8) * cell,
                                         y: (Double(j) + 0.5 + (rnd() - 0.5) * 0.8) * cell))
                }
            }
            // Every seed and its copies one repeat over, for the pebbles at the edges.
            var all: [CGPoint] = []
            for dx in [-1.0, 0, 1] { for dy in [-1.0, 0, 1] {
                all += seeds.map { CGPoint(x: $0.x + dx * period.width, y: $0.y + dy * period.height) }
            } }
            for c in seeds {
                // Start from a square round the seed, cut by each neighbour's halfway line.
                var poly = [CGPoint(x: c.x - 2 * cell, y: c.y - 2 * cell), CGPoint(x: c.x + 2 * cell, y: c.y - 2 * cell),
                            CGPoint(x: c.x + 2 * cell, y: c.y + 2 * cell), CGPoint(x: c.x - 2 * cell, y: c.y + 2 * cell)]
                for o in all where o != c && hypot(o.x - c.x, o.y - c.y) < 3 * cell {
                    let m = CGPoint(x: (c.x + o.x) / 2, y: (c.y + o.y) / 2), nx = o.x - c.x, ny = o.y - c.y
                    func inside(_ p: CGPoint) -> Bool { (p.x - m.x) * nx + (p.y - m.y) * ny <= 0 }
                    var out: [CGPoint] = []
                    for k in poly.indices {
                        let a = poly[k], b = poly[(k + 1) % poly.count]
                        if inside(a) { out.append(a) }
                        if inside(a) != inside(b) {
                            let t = ((m.x - a.x) * nx + (m.y - a.y) * ny) / ((b.x - a.x) * nx + (b.y - a.y) * ny)
                            out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                        }
                    }
                    poly = out
                }
                guard poly.count > 2 else { continue }
                // Shrink toward its middle by the grout, then round the corners (three passes).
                let mid = CGPoint(x: poly.map(\.x).reduce(0, +) / Double(poly.count), y: poly.map(\.y).reduce(0, +) / Double(poly.count))
                let shrink = 0.93 + rnd() * 0.03
                poly = poly.map { CGPoint(x: mid.x + ($0.x - mid.x) * shrink, y: mid.y + ($0.y - mid.y) * shrink) }
                for _ in 0..<3 {
                    var r: [CGPoint] = []
                    for k in poly.indices {
                        let a = poly[k], b = poly[(k + 1) % poly.count]
                        r.append(CGPoint(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25))
                        r.append(CGPoint(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75))
                    }
                    poly = r
                }
                let path = CGMutablePath()
                path.addLines(between: poly)
                path.closeSubpath()
                pieces.append(Piece(path: path, tone: [0, 0, 1, 3, 2, 0, 3][Int(rnd() * 7) % 7]))
            }
        case .randomStrip, .mixedStick:
            // Rows of strips of mixed lengths; mixed stick also mixes the row heights and shades.
            let rows = 8
            let heights = (0..<rows).map { _ in shape == .mixedStick ? short * (rnd() < 0.5 ? 1 : 1.6) : short }
            period = CGSize(width: long * 4, height: heights.reduce(0, +))
            var y = 0.0
            for r in 0..<rows {
                var x = -rnd() * long
                while x < period.width {
                    let len = long * (0.5 + rnd())
                    let a = max(x, 0), b = min(x + len, period.width)
                    if b - a > 0.2 {
                        let tone = shape == .mixedStick ? [0, 1, 3, 0][Int(rnd() * 4) % 4] : 0
                        pieces.append(rect(a, y, b - a, heights[r], tone: tone))
                    }
                    x += len
                }
                y += heights[r]
            }
        case .waterjet:
            let d = long
            period = CGSize(width: d, height: d)
            groundTone = 0
            // Floral, the owner's pick of five drawn designs (2026-10-09).
            switch design {
            case .floral:
                groundTone = 1
                // A flower of four petals round a round centre, a small leaf
                // flower at the corners, in a darker field.
                for (cx, cy, size, tone) in [(d / 2, d / 2, 1.0, 3), (0.0, 0.0, 0.45, 2)] {
                    for k in 0..<4 {
                        let a = Double(k) * .pi / 2 + .pi / 4
                        let path = CGMutablePath()
                        let pl = d * 0.24 * size, pw = d * 0.13 * size
                        path.move(to: .zero)
                        path.addQuadCurve(to: CGPoint(x: 2 * pl, y: 0), control: CGPoint(x: pl, y: -pw * 1.6))
                        path.addQuadCurve(to: .zero, control: CGPoint(x: pl, y: pw * 1.6))
                        var place = CGAffineTransform(rotationAngle: a).concatenating(CGAffineTransform(translationX: cx, y: cy))
                        if let p = path.copy(using: &place) { pieces.append(Piece(path: p, tone: tone)) }
                    }
                    pieces.append(circle(cx, cy, d * 0.07 * size, tone: 1))
                }
            }
        }

        // One image holds several repeats each way, so each tile can have its
        // own shade, as real tile does.
        let one = period
        let target = max(24, min(96, 4 * long))
        let rx = ordered ? 1 : max(1, min(6, Int((target / one.width).rounded(.up))))
        let ry = ordered ? 1 : max(1, min(6, Int((target / one.height).rounded(.up))))
        period = CGSize(width: one.width * Double(rx), height: one.height * Double(ry))
        var all: [Piece] = []
        for j in 0..<ry {
            for i in 0..<rx {
                var move = CGAffineTransform(translationX: one.width * Double(i), y: one.height * Double(j))
                all += pieces.compactMap { p in p.path.copy(using: &move).map { Piece(path: $0, tone: p.tone) } }
            }
        }
        if t?.vertical == true {
            // Vertical: the same pattern with its long side up.
            var flip = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
            all = all.compactMap { p in p.path.copy(using: &flip).map { Piece(path: $0, tone: p.tone) } }
            period = CGSize(width: period.height, height: period.width)
        }

        let ppi = min(24, 1024 / max(period.width, period.height))
        let px = CGSize(width: max(8, period.width * ppi), height: max(8, period.height * ppi))
        // Grout wide enough to see on a phone: 1/8″ (1/16″ on mosaics), never under 2 pixels.
        let grout = max(2, (long <= 4 ? 0.0625 : 0.125) * ppi)
        let face = color(t?.tileType)
        // Grout that stands out from the tile: light on darker tile, grey on light.
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        face.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        let lum = 0.299 * fr + 0.587 * fg + 0.114 * fb
        let joint = UIColor(white: lum > 0.75 ? 0.55 : 0.88, alpha: 1)
        // Each tile's own shade: a little lighter or darker, more for handmade tile.
        let spread: CGFloat = t?.tileType == .zellige || t?.tileType == .terracotta ? 0.12 : 0.05
        let toneFactor: [CGFloat] = [1, 0.8, 0.62, 1.12]
        func shade(_ k: Int, tone: Int) -> UIColor {
            var h = UInt32(truncatingIfNeeded: k &* 2_654_435_761)
            h ^= h >> 15
            let f = toneFactor[min(max(tone, 0), 3)] * (1 + spread * (CGFloat(h % 1000) / 500 - 1))
            return UIColor(red: min(1, fr * f), green: min(1, fg * f), blue: min(1, fb * f), alpha: 1)
        }
        let photo = TilePhotos.image(t?.photoID)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: px, format: format).image { ctx in
            let g = ctx.cgContext
            (groundTone.map { shade(-1, tone: $0) } ?? joint).setFill()
            g.fill(CGRect(origin: .zero, size: px))
            g.scaleBy(x: ppi, y: ppi)
            g.setLineWidth(grout / ppi)
            g.setLineJoin(.round)
            // Each tile filled (with the tile's photo when there is one), then
            // its edge drawn in grout — and its copies one repeat over, so the
            // edges wrap (not for overlapping scales, drawn in order).
            let shifts: [(Double, Double)] = ordered ? [(0, 0)]
                : [-1, 0, 1].flatMap { i in [-1, 0, 1].map { j in (Double(i) * period.width, Double(j) * period.height) } }
            for (k, p) in all.enumerated() {
                for (dx, dy) in shifts {
                    g.saveGState()
                    g.translateBy(x: dx, y: dy)
                    if let photo, let cg = photo.cgImage {
                        g.saveGState()
                        g.addPath(p.path)
                        g.clip()
                        let box = p.path.boundingBox
                        // Each tile shows a different part of the photo, as real tiles differ.
                        var h = UInt32(truncatingIfNeeded: k &* 2_246_822_519); h ^= h >> 13
                        let side = max(box.width, box.height)
                        let zoom = 1.0 + Double(h % 100) / 200
                        let draw = CGRect(x: box.midX - side * zoom / 2, y: box.midY - side * zoom / 2, width: side * zoom, height: side * zoom)
                        g.translateBy(x: 0, y: draw.minY * 2 + draw.height)
                        g.scaleBy(x: 1, y: -1)
                        g.draw(cg, in: draw)
                        g.restoreGState()
                        if p.tone != 0 {
                            g.addPath(p.path)
                            g.setFillColor(UIColor(white: 0, alpha: p.tone == 3 ? 0 : 0.12 * Double(p.tone)).cgColor)
                            g.fillPath()
                        }
                    } else {
                        g.addPath(p.path)
                        g.setFillColor(shade(k, tone: p.tone).cgColor)
                        g.fillPath()
                    }
                    g.addPath(p.path)
                    g.setStrokeColor(joint.cgColor)
                    g.strokePath()
                    g.restoreGState()
                }
            }
        }
        let made = Made(image: image, periodIn: period)
        cache[key] = made
        return made
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }
    private static func lcm(_ a: Int, _ b: Int) -> Int { a / max(gcd(a, b), 1) * b }
}
