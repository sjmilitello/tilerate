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
    /// Walls with a tile of their own, by scanned wall.
    var wallTiles: [UUID: TileChoice] = [:]
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
            let shape: (outline: [ScannedRoom.Point], holes: [[ScannedRoom.Point]], continuous: [[ScannedRoom.Point]])? =
                other.area == .floor && t.floor == .room ? room.scan.map { scan in
                    floorShape(t, tile: other.mainTile, scan: scan,
                               showers: room.sections.filter { $0.id != other.id && $0.roomScan == nil }.compactMap { s in
                                   guard let st = s.scanTakeoff, st.floor == .drawn, let r = st.floorRect else { return nil }
                                   return (r.corners, st.curbless, s.showerFloorTile ?? s.mainTile)
                               })
                } : nil
            return OtherAreaPieces(sectionID: other.id, name: other.area?.rawValue ?? "Area", pieces: t.pieces,
                                   floor: t.floor == .drawn ? t.floorRect : nil,
                                   curbless: t.curbless,
                                   tile: other.mainTile, floorTile: other.showerFloorTile,
                                   wallTiles: room.scan.map { other.wallTiles(in: $0) } ?? [:],
                                   roomFloor: other.area == .floor && t.floor == .room,
                                   floorOutline: shape?.outline, floorHoles: shape?.holes ?? [],
                                   continuousFloors: shape?.continuous ?? [],
                                   curbs: other.area == .shower ? room.scan.map { scan in
                                       t.curbRuns(in: scan, widthFt: 4.5 / 12).map { OtherAreaPieces.CurbRun(a: $0.a, b: $0.b, key: $0.key) }
                                   } ?? [] : [],
                                   jambs: room.scan.map { scan in
                                       (other.area == .shower ? t.jambFaces(in: scan, curbHeightIn: t.curbHeightIn ?? 4) : [])
                                           + t.doorAndHeaderFaces(in: scan, curbHeightIn: t.curbHeightIn ?? 4).jambs
                                   } ?? [],
                                   headers: room.scan.map {
                                       t.doorAndHeaderFaces(in: $0, curbHeightIn: t.curbHeightIn ?? 4).headers
                                   } ?? [],
                                   soffits: other.area == .shower ? room.scan.map { t.soffitBoxes(in: $0) } ?? [] : [],
                                   curbHeightIn: t.curbHeightIn ?? 4,
                                   stoneParts: room.scan.map { scan in
                                       Set(t.trimPieces(in: scan, area: other.area, curbHeightIn: t.curbHeightIn ?? 4).filter(\.stone).map(\.key))
                                   } ?? [],
                                   takeoff: t)
        }
    }

    /// A Floor area's tiled shape: its outline; the holes in it (other areas'
    /// floors and curbs, "no tile" boxes, the tub when left out); and the
    /// curbless shower floors in the same tile, which its tile runs on into
    /// (owner, 2026-10-12: drawing only — they're priced apart).
    static func floorShape(_ t: AreaTakeoff, tile: TileChoice?, scan: ScannedRoom,
                           showers: [(corners: [ScannedRoom.Point], curbless: Bool, tile: TileChoice?)])
        -> (outline: [ScannedRoom.Point], holes: [[ScannedRoom.Point]], continuous: [[ScannedRoom.Point]]) {
        let continuous = showers.filter { $0.curbless && $0.tile == tile }.map(\.corners)
        var holes = t.cutouts.filter { !continuous.contains($0) } + t.skipBoxes.map(\.corners)
        if t.excludeTub, scan.tubOutline.count > 2 { holes.append(scan.tubOutline) }
        return (t.tiledOutline(in: scan), holes, continuous)
    }

    /// An area of the estimate in 3-D, if it was measured from a scan.
    static func of(room: EstimateRoom, section s: EstimateSection, rates: Rates, fixtures: Bool = true) -> Room3DContent? {
        guard let scan = s.roomScan ?? room.scan, let t = s.scanTakeoff else { return nil }
        let curb = t.curbHeightIn ?? rates.curbHeightIn
        let stone = Set(t.trimPieces(in: scan, area: s.area, curbHeightIn: curb).filter(\.stone).map(\.key))
        return Room3DContent(room: scan, takeoff: t, area: s.area, tile: s.mainTile, floorTile: s.showerFloorTile, wallTiles: s.wallTiles(in: scan),
                             others: s.roomScan == nil ? otherAreas(in: room, except: s.id) : [],
                             curbHeightIn: curb, stoneParts: stone, showFixtures: fixtures,
                             curbWidthFt: StonePrices(rates: rates).curbWidthFt)
    }
}

/// A tap in the 3-D view: a wall (where on it, in the scene) or an item.
struct Room3DHit {
    enum Target { case wall(UUID), item(UUID), area(UUID), ownFloor }
    let target: Target
    /// Where it was tapped: x and z on the plan (feet), y up.
    let point: SCNVector3
    /// The surface's outward direction there.
    let normal: SCNVector3
}

/// Where the 3-D camera was, kept while the room's areas switch (owner,
/// 2026-10-12): the view picked and the camera as it was last turned.
final class Room3DCameraMemory {
    var preset: Room3DScene.Preset = .area
    var transform: SCNMatrix4?
    var target: SCNVector3?
}

struct Room3DView: View {
    let content: Room3DContent
    @Binding var showFixtures: Bool
    var onTap: (Room3DHit) -> Void = { _ in }
    /// "Add to estimate": the camera as it is now (eye, target).
    var onCapture: (([Double], [Double]) -> Void)? = nil
    var memory: Room3DCameraMemory? = nil
    @State private var view: Room3DScene.Preset = .area
    @State private var capture = 0
    @State private var captured = false

    var body: some View {
        Room3DSceneView(content: content, preset: view, memory: memory, onTap: onTap, captureToken: capture,
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
            .onAppear { if let memory, memory.transform != nil { view = memory.preset } }
            .onChange(of: view) { _, now in memory?.preset = now }
    }
}

/// SceneKit, in SwiftUI: rebuilt when what it shows changes; the camera
/// moves only when the view is changed, so turning it by hand stays put.
struct Room3DSceneView: UIViewRepresentable {
    let content: Room3DContent
    let preset: Room3DScene.Preset
    var memory: Room3DCameraMemory? = nil
    var onTap: (Room3DHit) -> Void = { _ in }
    var captureToken = 0
    var onCapture: ([Double], [Double]) -> Void = { _, _ in }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        /// Keeps the camera in `memory` as it's turned (the next area's view
        /// opens before this one closes, so it can't wait till then).
        func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard memory != nil, preset != nil, let v = renderer as? SCNView, let cam = v.pointOfView else { return }
            let transform = cam.transform, target = v.defaultCameraController.target
            DispatchQueue.main.async { [weak self] in
                guard let m = self?.memory else { return }
                m.transform = transform
                m.target = target
            }
        }

        var captureToken = 0
        var shown: Room3DContent?
        var preset: Room3DScene.Preset?
        var memory: Room3DCameraMemory?
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
                    if n.name == "floor|mine" {
                        onTap(Room3DHit(target: .ownFloor, point: h.worldCoordinates, normal: h.worldNormal))
                        return
                    }
                    if let name = n.name {
                        let parts = name.split(separator: "|")
                        if parts.count == 2, let id = UUID(uuidString: String(parts[1])) {
                            let target: Room3DHit.Target = parts[0] == "item" ? .item(id) : parts[0] == "area" ? .area(id) : .wall(id)
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

    static func dismantleUIView(_ v: SCNView, coordinator: Coordinator) {
        guard let m = coordinator.memory, let cam = v.pointOfView else { return }
        m.transform = cam.transform
        m.target = v.defaultCameraController.target
        if let p = coordinator.preset { m.preset = p }
    }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        v.addGestureRecognizer(tap)
        v.backgroundColor = UIColor(white: 0.09, alpha: 1)
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        v.scene = SCNScene()
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        c.onTap = onTap
        c.memory = memory
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
        // Opened again after switching areas: the camera as it was left.
        if c.preset == nil, let m = memory, let transform = m.transform {
            let (camera, target) = Room3DScene.camera(for: m.preset, content: content)
            camera.transform = transform
            v.scene?.rootNode.addChildNode(camera)
            v.pointOfView = camera
            v.defaultCameraController.target = m.target ?? target
            c.preset = m.preset
            return
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
            // Slabs are 0.02′ thick about their lift: the bare floor's top at 0,
            // a Floor area's tile at 0.006, a shower floor's tile at 0.012 —
            // each above the one under it.
            let floor = flatShape(room.floorOutline, color: UIColor(white: 0.32, alpha: 1), lift: -0.01)
            root.addChildNode(floor)
        }

        // Areas' tile: this one and the room's others.
        typealias Shape = (outline: [ScannedRoom.Point], holes: [[ScannedRoom.Point]], continuous: [[ScannedRoom.Point]])
        var areas: [(pieces: [AreaTakeoff.Piece], tile: TileChoice?, floor: AreaTakeoff.FloorRect?, floorTile: TileChoice?, shape: Shape?, id: UUID?, wallTiles: [UUID: TileChoice])] = []
        let mineShape: Shape? = c.area == .floor && c.takeoff.floor == .room
            ? Room3DContent.floorShape(c.takeoff, tile: c.tile, scan: room,
                         showers: c.others.compactMap { o in o.floor.map { ($0.corners, o.curbless, o.floorTile ?? o.tile) } })
            : nil
        areas.append((c.takeoff.pieces, c.tile, c.takeoff.floor == .drawn ? c.takeoff.floorRect : nil, c.floorTile ?? c.tile, mineShape, nil, c.wallTiles))
        for o in c.others {
            let shape: Shape? = o.roomFloor ? (o.floorOutline ?? room.floorOutline, o.floorHoles, o.continuousFloors) : nil
            areas.append((o.pieces, o.tile, o.floor, o.floorTile ?? o.tile, shape, o.sectionID, o.wallTiles))
        }
        // A Floor area's tile, round its holes (owner, 2026-10-12).
        var covered: [[ScannedRoom.Point]] = []
        for a in areas {
            guard let s = a.shape, s.outline.count > 2 else { continue }
            // Built square to the room's walls and turned back, so the tile
            // lies square to the room, not to the scanner's axes (owner,
            // 2026-10-12: the floor tile wasn't square to the room).
            let turn = room.squaringAngle
            func squared(_ ring: [ScannedRoom.Point]) -> [ScannedRoom.Point] {
                ring.map { .init(x: $0.x * cos(-turn) - $0.y * sin(-turn), y: $0.x * sin(-turn) + $0.y * cos(-turn)) }
            }
            let node = SCNNode()
            // The tile over the whole outline, and what's left out laid on top
            // as bare floor: holes touching each other or the walls (a corner
            // shower's floor and curb strips) made SceneKit drop whole
            // triangles of tile (owner, 2026-10-13).
            let tileNode = flatShape(squared(s.outline), color: .white, lift: -0.004)
            // Laid square to the room's walls, not the scanner's axes
            // (owner, 2026-10-12: the floor tile wasn't square to the room).
            tileNode.geometry?.firstMaterial = tileMaterial(a.floorTile, widthFt: bounds(squared(s.outline)).w,
                                                            heightFt: bounds(squared(s.outline)).h, x0: 0, y0: 0)
            node.addChildNode(tileNode)
            for hole in s.holes where hole.count > 2 {
                node.addChildNode(flatShape(squared(hole), color: UIColor(white: 0.32, alpha: 1), lift: -0.002))
            }
            node.eulerAngles.y = Float(-turn)
            // Another area's floor: a tap on it switches to that area.
            node.name = a.id.map { "area|\($0.uuidString)" } ?? "floor|mine"
            root.addChildNode(node)
            covered += s.continuous
        }
        for a in areas {
            // A curbless shower floor the room's floor tile runs on into is drawn by the floor.
            if let r = a.floor, !covered.contains(r.corners) {
                let n = floorRect(r, tile: a.floorTile)
                n.name = a.id.map { "area|\($0.uuidString)" } ?? "floor|mine"
                root.addChildNode(n)
            }
        }

        // Every area's built-ins — benches, niches, windows, corner pieces,
        // drains — whichever area is open (owner, 2026-10-14: switching to the
        // Floor made the shower's disappear).
        typealias Source = (t: AreaTakeoff, stone: Set<String>, tile: TileChoice?, mine: Bool)
        let sources: [Source] = [(c.takeoff, c.stoneParts, c.tile, true)]
            + c.others.compactMap { o in o.takeoff.map { ($0, o.stoneParts, o.tile, false) } }
        func floorMid(_ t: AreaTakeoff) -> ScannedRoom.Point? { t.floor == .drawn ? t.floorRect?.center : nil }

        // Walls, with their doors and windows cut out, and tile on them.
        let windows = sources.flatMap { $0.t.items.filter { $0.kind == .window } }
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
            let niches: [(rect: Rect, side: Float)] = sources.flatMap { src in
                src.t.items.filter { $0.kind == .niche && $0.wallID == w.id }.map {
                    (Rect(x0: $0.fromFt, x1: $0.toFt, y0: $0.bottomIn / 12, y1: ($0.bottomIn + $0.heightIn) / 12),
                     faceSign(w, face: $0.face, room: room, toward: floorMid(src.t)))
                }
            }
            let inside0 = faceSign(w, face: 0, room: room)
            let bodyHoles = holes + niches.filter { solid || $0.side == inside0 }.map(\.rect)
            // The room's own walls are seen from inside only, like a doll's
            // house: whichever way it's turned, the near walls drop away.
            let inside = faceSign(w, face: 0, room: room)
            // Out to its corners: into a wall across each end (owner, 2026-10-13).
            let x0 = -room.endJoinFt(w, start: true), x1 = w.lengthFt + room.endJoinFt(w, start: false)
            for cell in cells(Rect(x0: x0, x1: x1, y0: 0, y1: w.heightFt), minus: bodyHoles) {
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
            // Where a wall drawn as its face alone stands: its footprint, so
            // with the wall dropped away (seen from outside) the floor under
            // its thickness doesn't show — e.g. a strip behind a bench
            // (owner, 2026-10-14).
            if !solid {
                let foot = SCNBox(width: x1 - x0, height: 0.03, length: t, chamferRadius: 0)
                foot.firstMaterial = plain(UIColor(white: 0.62, alpha: 1))
                let n = SCNNode(geometry: foot)
                n.position = SCNVector3((x0 + x1) / 2, 0.015, 0)
                node.addChildNode(n)
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
                    // Into an inside corner the tile stops at the other wall's
                    // face, not its line (owner, 2026-10-14: a strip showed where
                    // the dropped-away wall stood).
                    let lo = max(p.fromFt, insideCornerInset(w, side: side, atStart: true, room: room))
                    let hi = min(p.toFt, w.lengthFt - insideCornerInset(w, side: side, atStart: false, room: room))
                    guard hi - lo > 0.01 else { continue }
                    for cell in cells(Rect(x0: lo, x1: hi, y0: 0, y1: p.heightIn / 12), minus: cut) {
                        let plane = SCNPlane(width: cell.w, height: cell.h)
                        plane.firstMaterial = tileMaterial(a.wallTiles[w.id] ?? a.tile, widthFt: cell.w, heightFt: cell.h, x0: cell.x0, y0: cell.y0)
                        let n = SCNNode(geometry: plane)
                        n.position = SCNVector3(cell.midX, cell.midY, Double(side) * (t / 2 + 0.006))
                        if side < 0 { n.eulerAngles.y = .pi }
                        node.addChildNode(n)
                    }
                }
            }
            // A wall drawn in: its free ends tiled like its faces, by the area
            // that tiles it (owner, 2026-10-15: they showed bare grey). Stone
            // on an end is drawn just in front of this.
            if w.planned, let a = areas.first(where: { a in a.pieces.contains { $0.wallID == w.id } }) {
                for atStart in [true, false] where room.isFreeEnd(of: w, start: atStart) {
                    let plane = SCNPlane(width: t, height: w.heightFt)
                    plane.firstMaterial = tileMaterial(a.wallTiles[w.id] ?? a.tile, widthFt: t, heightFt: w.heightFt, x0: 0, y0: 0)
                    let n = SCNNode(geometry: plane)
                    n.position = SCNVector3(atStart ? -0.004 : w.lengthFt + 0.004, w.heightFt / 2, 0)
                    n.eulerAngles.y = atStart ? -.pi / 2 : .pi / 2
                    node.addChildNode(n)
                }
            }
            // A half wall's cap.
            if room.isKneeWall(w) {
                let cap = SCNBox(width: w.lengthFt, height: 0.06, length: t + 0.04, chamferRadius: 0)
                cap.firstMaterial = c.stoneParts.contains("cap:\(w.id)") ? stoneMaterial() : tileMaterial(c.tile, widthFt: w.lengthFt, heightFt: t, x0: 0, y0: 0)
                let n = SCNNode(geometry: cap)
                n.position = SCNVector3(w.lengthFt / 2, w.heightFt + 0.03, 0)
                node.addChildNode(n)
            }
            root.addChildNode(node)
        }

        // Benches, niches and corner pieces, of every area.
        for src in sources {
        for item in src.t.items {
            guard let w = room.wall(item.wallID) else { continue }
            let node = wallFrame(w)
            node.name = "item|\(item.id.uuidString)"
            let t = thickness(w)
            let side = Double(faceSign(w, face: item.face, room: room,
                                       toward: floorMid(src.t)))
            switch item.kind {
            case .framedBench, .floatingBench:
                let depth = item.depthIn / 12
                let top = item.heightIn / 12
                let slab = item.kind == .floatingBench ? 3.0 / 12 : top
                let box = SCNBox(width: item.widthFt, height: slab, length: depth, chamferRadius: 0)
                let stoneTop = src.stone.contains("benchTop:\(item.id)")
                let material = tileMaterial(src.tile, widthFt: item.widthFt, heightFt: slab, x0: item.fromFt, y0: 0)
                box.materials = [material, material, material, material,
                                 stoneTop ? stoneMaterial() : tileMaterial(src.tile, widthFt: item.widthFt, heightFt: depth, x0: item.fromFt, y0: 0),
                                 plain(.darkGray)]
                if src.stone.contains("benchFront:\(item.id)") { box.materials[0] = stoneMaterial() }
                // Its back is against the wall: never tiled (owner, 2026-10-14).
                box.materials[2] = plain(UIColor(white: 0.62, alpha: 1))
                // Its outside end, showing at the entry where the curb stops at it
                // (the other end is against a wall, out of sight).
                if src.stone.contains("benchSide:\(item.id)") { box.materials[1] = stoneMaterial(); box.materials[3] = stoneMaterial() }
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
                let nicheTile = item.tile ?? src.tile
                func surface(_ width: Double, _ height: Double, stone: Bool, gx: Double, gy: Double) -> SCNPlane {
                    let p = SCNPlane(width: width, height: height)
                    // Seen from inside the recess only, so it doesn't show
                    // behind the wall from outside the room.
                    p.firstMaterial = stone ? stoneMaterial() : tileMaterial(nicheTile, widthFt: width, heightFt: height, x0: gx, y0: gy)
                    return p
                }
                let backStone = src.t.partStone(item, "back")
                let sides = src.t.partStone(item, "jambs"), top = src.t.partStone(item, "header"),
                    sill = src.t.partStone(item, "shelf"), dividerStone = src.t.partStone(item, "dividers")
                // Stone parts are ¾″ slabs, so their edges show as a frame
                // straight on (owner, 2026-10-14: only the divider showed); the
                // sill sticks out ½″ past the face. Tile parts stay surfaces.
                let st = 0.75 / 12, lip = 0.5 / 12
                let mid = (face + inner) / 2
                func slab(_ w: Double, _ hh: Double, _ l: Double, at p: SCNVector3) {
                    let box = SCNBox(width: w, height: hh, length: l, chamferRadius: 0)
                    box.firstMaterial = stoneMaterial()
                    let n = SCNNode(geometry: box)
                    n.position = p
                    node.addChildNode(n)
                }
                // The back.
                if backStone {
                    slab(w0, h, st, at: SCNVector3(x0 + w0 / 2, y0 + h / 2, inner + side * st / 2))
                } else {
                    let back = SCNNode(geometry: surface(w0, h, stone: false, gx: x0, gy: y0))
                    back.position = SCNVector3(x0 + w0 / 2, y0 + h / 2, inner)
                    if side < 0 { back.eulerAngles.y = .pi }
                    node.addChildNode(back)
                }
                // The sill (base shelf): a slab with a lip past the face.
                if sill {
                    slab(w0, st, d + lip, at: SCNVector3(x0 + w0 / 2, y0 + st / 2, mid + side * lip / 2))
                } else {
                    let n = SCNNode(geometry: surface(w0, d, stone: false, gx: x0, gy: 0))
                    n.position = SCNVector3(x0 + w0 / 2, y0, mid)
                    n.eulerAngles.x = -Float.pi / 2
                    node.addChildNode(n)
                }
                // The header (top).
                if top {
                    slab(w0, st, d, at: SCNVector3(x0 + w0 / 2, y0 + h - st / 2, mid))
                } else {
                    let n = SCNNode(geometry: surface(w0, d, stone: false, gx: x0, gy: 0))
                    n.position = SCNVector3(x0 + w0 / 2, y0 + h, mid)
                    n.eulerAngles.x = Float.pi / 2
                    node.addChildNode(n)
                }
                // Left and right sides (jambs), between the sill and the header.
                for (x, turn, inward) in [(x0, Float.pi / 2, 1.0), (x0 + w0, -Float.pi / 2, -1.0)] {
                    if sides {
                        let lo = y0 + (sill ? st : 0), hi = y0 + h - (top ? st : 0)
                        slab(st, hi - lo, d, at: SCNVector3(x + inward * st / 2, (lo + hi) / 2, mid))
                    } else {
                        let n = SCNNode(geometry: surface(d, h, stone: false, gx: 0, gy: y0))
                        n.position = SCNVector3(x, y0 + h / 2, mid)
                        n.eulerAngles.y = turn
                        node.addChildNode(n)
                    }
                }
                // Dividers: ¾″ shelves.
                if item.dividers > 0 {
                    for k in 1...item.dividers {
                        let y = y0 + h * Double(k) / Double(item.dividers + 1)
                        let shelf = SCNBox(width: w0, height: st, length: d, chamferRadius: 0)
                        shelf.firstMaterial = !dividerStone ? tileMaterial(nicheTile, widthFt: w0, heightFt: d, x0: x0, y0: 0) : stoneMaterial()
                        let n = SCNNode(geometry: shelf)
                        n.position = SCNVector3(x0 + w0 / 2, y, mid)
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
                shape.firstMaterial = stoneMaterial()
                let n = SCNNode(geometry: shape)
                n.eulerAngles.x = -.pi / 2
                n.position = SCNVector3(0, item.bottomIn / 12 - 0.75 / 12, side * t / 2)
                node.addChildNode(n)
            case .window:
                break
            }
            if src.mine, item.id == c.selectedItem, item.kind == .niche {
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
            } else if src.mine, item.id == c.selectedItem {
                node.enumerateHierarchy { n, _ in
                    n.geometry?.materials.forEach { $0.emission.contents = UIColor(red: 0.1, green: 0.45, blue: 0.35, alpha: 1) }
                }
            }
            root.addChildNode(node)
        }
        }

        // Every shower's curb, this area's or another's (owner, 2026-10-12:
        // the curb showed only from the shower itself). Just outside the
        // floor: its inside face on the floor's edge, corners overlapped
        // (`curbRuns`). Its top, inside face and outside face are each tile
        // or stone.
        var curbSets: [(runs: [(a: ScannedRoom.Point, b: ScannedRoom.Point, key: String)], mid: ScannedRoom.Point?,
                        heightIn: Double, stone: Set<String>, tile: TileChoice?)] = []
        if c.area == .shower {
            curbSets.append((c.takeoff.curbRuns(in: room, widthFt: c.curbWidthFt), c.takeoff.floorRect?.center,
                             c.curbHeightIn, c.stoneParts, c.tile))
        }
        for o in c.others where !o.curbs.isEmpty {
            curbSets.append((o.curbs.map { ($0.a, $0.b, $0.key) }, o.floor?.center, o.curbHeightIn, o.stoneParts, o.tile))
        }
        for set in curbSets {
            let mid = set.mid
            for (a, b, key) in set.runs {
                let len = hypot(b.x - a.x, b.y - a.y)
                let h = set.heightIn / 12, w = c.curbWidthFt
                var nx = -(b.y - a.y) / max(len, 1e-9), ny = (b.x - a.x) / max(len, 1e-9)
                var flipped = false
                if let m = mid, ((a.x + b.x) / 2 - m.x) * nx + ((a.y + b.y) / 2 - m.y) * ny < 0 { nx = -nx; ny = -ny; flipped = true }
                let box = SCNBox(width: len, height: h, length: w, chamferRadius: 0.01)
                func face(_ k: String, _ width: Double) -> SCNMaterial {
                    set.stone.contains(k) ? stoneMaterial() : tileMaterial(set.tile, widthFt: width, heightFt: h, x0: 0, y0: 0)
                }
                let top = face(key, len), inside = face(key + ":inside", len), outside = face(key + ":outside", len)
                // The box's front (+z) is the side its left hand faces: outside unless turned.
                box.materials = [flipped ? inside : outside, outside, flipped ? outside : inside, outside, top, top]
                let n = SCNNode(geometry: box)
                n.position = SCNVector3((a.x + b.x) / 2 + nx * w / 2, h / 2, (a.y + b.y) / 2 + ny * w / 2)
                n.eulerAngles.y = Float(-atan2(b.y - a.y, b.x - a.x))
                root.addChildNode(n)
            }
        }
        // Stone jambs: the strip of wall above each end of the curb, as wide
        // as the curb (owner, 2026-10-13: stone jambs didn't show).
        var jambSets: [(faces: [AreaTakeoff.JambFace], stone: Set<String>)] = []
        var headerSets: [(strips: [AreaTakeoff.HeaderStrip], stone: Set<String>)] = []
        // Doors, windows and openings with stone in any area; the entry's
        // jambs in a shower.
        do {
            let doors = c.takeoff.doorAndHeaderFaces(in: room, curbHeightIn: c.curbHeightIn, curbWidthFt: c.curbWidthFt)
            let entry = c.area == .shower ? c.takeoff.jambFaces(in: room, curbHeightIn: c.curbHeightIn, curbWidthFt: c.curbWidthFt) : []
            jambSets.append((entry + doors.jambs, c.stoneParts))
            headerSets.append((doors.headers, c.stoneParts))
        }
        for o in c.others where !o.headers.isEmpty { headerSets.append((o.headers, o.stoneParts)) }
        // Headers dropped from the ceiling (soffits): tile faces and ends, the
        // underside tile or stone (owner, 2026-10-13).
        var soffitSets: [(boxes: [AreaTakeoff.SoffitBox], stone: Set<String>, tile: TileChoice?)] = []
        if c.area == .shower { soffitSets.append((c.takeoff.soffitBoxes(in: room, curbWidthFt: c.curbWidthFt), c.stoneParts, c.tile)) }
        for o in c.others where !o.soffits.isEmpty { soffitSets.append((o.soffits, o.stoneParts, o.tile)) }
        for set in soffitSets {
            for b in set.boxes {
                let len = hypot(b.b.x - b.a.x, b.b.y - b.a.y), h = b.topFt - b.bottomFt
                guard len > 0.01, h > 0.01 else { continue }
                let box = SCNBox(width: len, height: h, length: b.widthFt, chamferRadius: 0)
                let face = tileMaterial(set.tile, widthFt: len, heightFt: h, x0: 0, y0: 0)
                let end = tileMaterial(set.tile, widthFt: b.widthFt, heightFt: h, x0: 0, y0: 0)
                let under = set.stone.contains(b.key) ? stoneMaterial() : tileMaterial(set.tile, widthFt: len, heightFt: b.widthFt, x0: 0, y0: 0)
                box.materials = [face, end, face, end, plain(UIColor(white: 0.9, alpha: 1)), under]
                let n = SCNNode(geometry: box)
                n.position = SCNVector3((b.a.x + b.b.x) / 2, (b.topFt + b.bottomFt) / 2, (b.a.y + b.b.y) / 2)
                n.eulerAngles.y = Float(-atan2(b.b.y - b.a.y, b.b.x - b.a.x))
                root.addChildNode(n)
            }
        }
        // Headers: a door's underside, and the ceiling headers, facing down.
        for set in headerSets {
            for h in set.strips where set.stone.contains(h.key) {
                let len = hypot(h.b.x - h.a.x, h.b.y - h.a.y)
                guard len > 0.01 else { continue }
                let plane = SCNPlane(width: len, height: h.widthFt)
                plane.firstMaterial = stoneMaterial()
                let n = SCNNode(geometry: plane)
                n.position = SCNVector3((h.a.x + h.b.x) / 2, h.heightFt + (h.up ? 0.008 : -0.008), (h.a.y + h.b.y) / 2)
                n.eulerAngles = SCNVector3(h.up ? -Float.pi / 2 : Float.pi / 2, Float(-atan2(h.b.y - h.a.y, h.b.x - h.a.x)), 0)
                root.addChildNode(n)
            }
        }
        for o in c.others where !o.jambs.isEmpty { jambSets.append((o.jambs, o.stoneParts)) }
        for set in jambSets {
            for f in set.faces where set.stone.contains(f.key) {
                let plane = SCNPlane(width: f.widthFt, height: f.topFt - f.bottomFt)
                // One-sided, like the walls: seen from behind its wall, it's gone too.
                plane.firstMaterial = stoneMaterial()
                let n = SCNNode(geometry: plane)
                n.position = SCNVector3(f.center.x + f.facing.x * 0.008, (f.bottomFt + f.topFt) / 2,
                                        f.center.y + f.facing.y * 0.008)
                n.eulerAngles.y = Float(atan2(f.facing.x, f.facing.y))
                root.addChildNode(n)
            }
        }
        for src in sources where src.mine ? c.area == .shower : src.t.floor == .drawn {
            // The drain: a dark grate on the floor.
            if src.t.floor == .drawn, let d = src.t.drainShown() {
                let k = src.t.drainOutline(d)
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
        if preset == .room, let v = wholeRoomView(c) {
            target = v.target
            eye = v.eye
        }
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

    /// The whole room as a doll's house (owner, 2026-10-15: it looked down
    /// steeply from a fixed side, with walls in the way): from above the
    /// corner farthest from this area, square to the room's walls, looking
    /// across it at about 40° down, far enough back that the whole room fits.
    /// The two walls nearest the camera are seen from outside, so they don't
    /// show and the room is open to view.
    private static func wholeRoomView(_ c: Room3DContent) -> (eye: SCNVector3, target: SCNVector3)? {
        let room = c.room
        let pts = room.floorOutline.isEmpty ? room.walls.flatMap { [$0.start, $0.end] } : room.floorOutline
        guard pts.count > 2 else { return nil }
        // The room's own square directions.
        let t = room.squaringAngle
        let ux = ScannedRoom.Point(x: cos(t), y: sin(t)), uy = ScannedRoom.Point(x: -sin(t), y: cos(t))
        func along(_ p: ScannedRoom.Point, _ u: ScannedRoom.Point) -> Double { p.x * u.x + p.y * u.y }
        let xs = pts.map { along($0, ux) }, ys = pts.map { along($0, uy) }
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
        let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
        func plan(_ a: Double, _ b: Double) -> ScannedRoom.Point { .init(x: ux.x * a + uy.x * b, y: ux.y * a + uy.y * b) }
        // The corner farthest from this area, so the area is in view.
        let focus = focusPoint(c)?.center
        let fx = focus.map { along($0, ux) } ?? cx, fy = focus.map { along($0, uy) } ?? cy
        let sx: Double = fx > cx ? -1 : 1, sy: Double = fy > cy ? -1 : 1
        var d = ScannedRoom.Point(x: ux.x * sx * (x1 - x0) + uy.x * sy * (y1 - y0), y: ux.y * sx * (x1 - x0) + uy.y * sy * (y1 - y0))
        let dl = max(hypot(d.x, d.y), 0.01)
        d = .init(x: d.x / dl, y: d.y / dl)
        let ceiling = room.ceilingFt
        let middle = plan(cx, cy)
        let targetY = ceiling * 0.38
        // Far enough back for the room's half-diagonal and height to fit the
        // 60° view, with a margin.
        let radius = hypot(x1 - x0, y1 - y0) / 2
        let reach = (radius + ceiling * 0.12) / sin(Double.pi / 6)
        let down = 40.0 * Double.pi / 180
        let eye = SCNVector3(middle.x + d.x * reach * cos(down), targetY + reach * sin(down), middle.y + d.y * reach * cos(down))
        return (eye, SCNVector3(middle.x, targetY, middle.y))
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

    /// How far a wall's face on `side` stops short of its line's end at an
    /// inside corner: half the thickness of a wall across that end that runs
    /// off into this side (0 at an outside corner or a free end).
    private static func insideCornerInset(_ w: ScannedRoom.Wall, side: Float, atStart: Bool, room: ScannedRoom) -> Double {
        guard w.lengthFt > 0 else { return 0 }
        let p = atStart ? w.start : w.end
        let ux = (w.end.x - w.start.x) / w.lengthFt, uy = (w.end.y - w.start.y) / w.lengthFt
        let nx = -uy * Double(side), ny = ux * Double(side)
        var inset = 0.0
        for o in room.walls where o.id != w.id && o.lengthFt > 0 {
            let dot = abs(((o.end.x - o.start.x) * ux + (o.end.y - o.start.y) * uy) / o.lengthFt)
            guard dot < 0.5, room.distanceToWall(p, o) < 0.1 else { continue }
            let a: Double = (o.start.x - p.x) * nx + (o.start.y - p.y) * ny
            let b: Double = (o.end.x - p.x) * nx + (o.end.y - p.y) * ny
            let into = max(a, b)
            if into > 0.1 { inset = max(inset, thickness(o) / 2) }
        }
        return inset
    }

    private static func thickness(_ w: ScannedRoom.Wall) -> Double {
        AreaTakeoff.drawnThicknessFt(w)
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
    private static func flatShape(_ outline: [ScannedRoom.Point], holes: [[ScannedRoom.Point]] = [],
                                  color: UIColor, lift: Double = 0) -> SCNNode {
        let path = UIBezierPath()
        // Holes wound the other way from the outline, so they're cut out
        // whichever fill rule the shape is built with.
        func signedArea(_ r: [ScannedRoom.Point]) -> Double {
            r.indices.reduce(0.0) { s, i in let a = r[i], b = r[(i + 1) % r.count]; return s + a.x * b.y - b.x * a.y }
        }
        let outer = signedArea(outline) >= 0
        for (k, ring) in ([outline] + holes.filter({ $0.count > 2 })).enumerated() {
            let ccw = signedArea(ring) >= 0
            let pts = (k == 0 || ccw != outer) ? ring : Array(ring.reversed())
            path.move(to: CGPoint(x: pts[0].x, y: -pts[0].y))
            for p in pts.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: -p.y)) }
            path.close()
        }
        path.usesEvenOddFillRule = true
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
    static let stoneColor = StoneLook.uiColor

    /// Stone as white marble: the colour with faint grey veins (owner,
    /// 2026-10-14), so it reads apart from plain light tile.
    private static let stoneMaterialImage: UIImage = {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            StoneLook.uiColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let g = ctx.cgContext
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
            for k in 0..<7 {
                let path = UIBezierPath()
                var p = CGPoint(x: rnd() * size.width, y: -10)
                path.move(to: p)
                while p.y < size.height + 10 {
                    let q = CGPoint(x: p.x + (rnd() - 0.5) * 60, y: p.y + 20 + rnd() * 30)
                    path.addQuadCurve(to: q, controlPoint: CGPoint(x: (p.x + q.x) / 2 + (rnd() - 0.5) * 30, y: (p.y + q.y) / 2))
                    p = q
                }
                g.setStrokeColor(UIColor(white: 0.55, alpha: k % 3 == 0 ? 0.35 : 0.18).cgColor)
                g.setLineWidth(k % 3 == 0 ? 1.6 : 0.8)
                g.addPath(path.cgPath)
                g.strokePath()
            }
        }
    }()

    private static func stoneMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = stoneMaterialImage
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(0.6, 0.6, 1)
        m.lightingModel = .lambert
        return m
    }

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
        // Laid from the floor (and the wall's start), so courses run at the
        // same heights on every wall, whatever its height (owner, 2026-10-14:
        // a half wall's grout lines didn't meet the shower walls'). A plane's
        // texture runs down from its top, so its top edge sets the start.
        let tx = x0 * 12 / pattern.periodIn.width, ty = -(y0 + heightFt) * 12 / pattern.periodIn.height
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


extension EstimateSection {
    /// Walls given a tile of their own, by the scanned wall they're named for.
    func wallTiles(in room: ScannedRoom) -> [UUID: TileChoice] {
        guard !walls.isEmpty else { return [:] }
        var out: [UUID: TileChoice] = [:]
        for w in room.walls {
            let name = room.name(of: w)
            if let tw = walls.first(where: { $0.name == name }) { out[w.id] = tw.tile }
        }
        return out
    }
}


/// How stone looks on the plan, the wall views and in 3-D: white marble for
/// now (owner, 2026-10-14; a colour picker in Admin to talk about later).
enum StoneLook {
    static let uiColor = UIColor(red: 0.914, green: 0.902, blue: 0.878, alpha: 1)   // #E9E6E0
    static let color = Color(uiColor: uiColor)
}
