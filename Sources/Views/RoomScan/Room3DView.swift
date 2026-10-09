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
            // The room's own walls are seen from inside only, like a doll's
            // house: whichever way it's turned, the near walls drop away.
            let inside = faceSign(w, face: 0, room: room)
            for cell in cells(Rect(x0: 0, x1: w.lengthFt, y0: 0, y1: w.heightFt), minus: holes) {
                if w.planned {
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
                    let side = faceSign(w, face: p.face, room: room)
                    for cell in cells(Rect(x0: p.fromFt, x1: p.toFt, y0: 0, y1: p.heightIn / 12), minus: holes) {
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
            let side = Double(faceSign(w, face: item.face, room: room))
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
                let back = SCNPlane(width: item.widthFt, height: item.heightIn / 12)
                back.firstMaterial = plain(UIColor(white: 0.22, alpha: 1))
                let n = SCNNode(geometry: back)
                n.position = SCNVector3((item.fromFt + item.toFt) / 2, (item.bottomIn + item.heightIn / 2) / 12, side * (t / 2 + 0.012))
                if side < 0 { n.eulerAngles.y = .pi }
                node.addChildNode(n)
                // Its base shelf and dividers.
                let shelfColor = item.stone == .tile ? UIColor(white: 0.9, alpha: 1) : stoneColor
                for k in 0...item.dividers {
                    let y = (item.bottomIn + item.heightIn * Double(k) / Double(item.dividers + 1)) / 12
                    let shelf = SCNBox(width: item.widthFt, height: 0.06, length: 0.12, chamferRadius: 0)
                    shelf.firstMaterial = plain(shelfColor)
                    let s = SCNNode(geometry: shelf)
                    s.position = SCNVector3((item.fromFt + item.toFt) / 2, y, side * (t / 2 + 0.06))
                    node.addChildNode(s)
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
            if item.id == c.selectedItem {
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

    private static func thickness(_ w: ScannedRoom.Wall) -> Double {
        w.planned ? max(w.thicknessIn, 1) / 12 : 4.0 / 12
    }

    /// Which side of the wall (+1 its first face, −1 the other) a piece's tile is on:
    /// a planned wall's chosen face; a scanned wall's side toward the room.
    private static func faceSign(_ w: ScannedRoom.Wall, face: Int, room: ScannedRoom) -> Float {
        if w.planned { return face == 0 ? 1 : -1 }
        let dx = w.end.x - w.start.x, dy = w.end.y - w.start.y
        let pts = room.floorOutline.isEmpty ? room.walls.flatMap { [$0.start, $0.end] } : room.floorOutline
        let cx = pts.map(\.x).reduce(0, +) / Double(max(pts.count, 1))
        let cy = pts.map(\.y).reduce(0, +) / Double(max(pts.count, 1))
        let mid = ScannedRoom.Point(x: (w.start.x + w.end.x) / 2, y: (w.start.y + w.end.y) / 2)
        return (cx - mid.x) * -dy + (cy - mid.y) * dx >= 0 ? 1 : -1
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

    static let stoneColor = UIColor(red: 0.88, green: 0.84, blue: 0.76, alpha: 1)

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
        let sx = widthFt * 12 / pattern.periodIn.width, sy = heightFt * 12 / pattern.periodIn.height
        let tx = x0 * 12 / pattern.periodIn.width, ty = y0 * 12 / pattern.periodIn.height
        m.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(Float(sx), Float(sy), 1), Float(tx), Float(ty), 0)
        m.lightingModel = .lambert
        return m
    }
}

/// One repeat of a tile pattern as an image: the tile's colour, its size
/// (the long side across) and layout, with grout lines.
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
        }
        let a = w ?? l ?? fallback.0, b = l ?? w ?? fallback.1
        return (max(a, b, 0.5), max(min(a, b), 0.5))
    }

    static func make(_ t: TileChoice?) -> Made {
        let (long, short) = size(t)
        let layout = t?.layout ?? .straightStacked
        let key = "\(t?.tileType.rawValue ?? "-")|\(long)|\(short)|\(layout.rawValue)"
        if let m = cache[key] { return m }

        // Tiles as rectangles (inches) in one repeat of the pattern.
        var rects: [CGRect] = []
        var rotated = false
        var period: CGSize
        switch layout {
        case .runningBond:
            period = CGSize(width: long, height: short * 2)
            rects = [CGRect(x: 0, y: 0, width: long, height: short),
                     CGRect(x: -long / 2, y: short, width: long, height: short),
                     CGRect(x: long / 2, y: short, width: long, height: short)]
        case .herringbone:
            // Staircase strips of one flat and one upright tile, each strip
            // shifted (long, −long): repeats every 2·long·short/gcd both ways.
            let L = long.rounded(), W = max(short.rounded(), 1)
            let g = gcd(Int(L), Int(W))
            let p = 2 * L * W / Double(max(g, 1))
            period = CGSize(width: p, height: p)
            let steps = Int((2 * p) / W) + 4
            for strip in -steps...steps {
                let ox = Double(strip) * L, oy = Double(-strip) * L
                for k in -steps...steps {
                    let x = ox + Double(k) * W, y = oy + Double(k) * W
                    rects.append(CGRect(x: x, y: y, width: L, height: W))
                    rects.append(CGRect(x: x, y: y + W, width: W, height: L))
                }
            }
            rects = rects.filter { $0.maxX > 0 && $0.minX < p && $0.maxY > 0 && $0.minY < p }
        case .diagonal:
            period = CGSize(width: short * 2.squareRoot(), height: short * 2.squareRoot())
            rotated = true
        default:
            period = CGSize(width: long, height: short)
            rects = [CGRect(x: 0, y: 0, width: long, height: short)]
        }

        let ppi = min(10, 900 / max(period.width, period.height))
        let px = CGSize(width: max(8, period.width * ppi), height: max(8, period.height * ppi))
        let grout = max(1.2, 0.125 * ppi)
        let face = color(t?.tileType)
        let joint = UIColor(white: (t?.tileType == .slate || t?.tileType == .granite) ? 0.3 : 0.62, alpha: 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: px, format: format).image { ctx in
            let g = ctx.cgContext
            joint.setFill()
            g.fill(CGRect(origin: .zero, size: px))
            face.setFill()
            if rotated {
                // Squares turned 45°: a diamond, with its neighbours' corners.
                let s = px.width
                for (cx, cy) in [(s / 2, s / 2), (0.0, 0.0), (s, 0.0), (0.0, s), (s, s)] {
                    let d = s / 2 - grout / 2
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: cx, y: cy - d))
                    path.addLine(to: CGPoint(x: cx + d, y: cy))
                    path.addLine(to: CGPoint(x: cx, y: cy + d))
                    path.addLine(to: CGPoint(x: cx - d, y: cy))
                    path.close()
                    path.fill()
                }
            } else {
                for r in rects {
                    // Each tile, and its copies one repeat over, so edges wrap.
                    for dx in [-period.width, 0, period.width] {
                        for dy in [-period.height, 0, period.height] {
                            let rr = CGRect(x: (r.minX + dx) * ppi + grout / 2, y: (r.minY + dy) * ppi + grout / 2,
                                            width: r.width * ppi - grout, height: r.height * ppi - grout)
                            g.fill(rr)
                        }
                    }
                }
            }
        }
        let made = Made(image: image, periodIn: period)
        cache[key] = made
        return made
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }
}
