import CoreGraphics
import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// The plan's dimensions (`PlanDimensions`, `PlanDimensionPlacer`, adapted
/// from FabSpecPro's dimensioning): every one is drawn, inside stretches add
/// up to their wall, and the layout keeps the drafting rules.
struct PlanDimensionTests {
    /// 11′ × 8′ with an L of partition walls off two of its walls — the
    /// shape of the owner's shower and closet scan.
    private func partitionedRoom() -> ScannedRoom {
        var r = ScannedRoom()
        func wall(_ l: String, _ a: (Double, Double), _ b: (Double, Double)) -> ScannedRoom.Wall {
            ScannedRoom.Wall(label: l, lengthFt: hypot(b.0 - a.0, b.1 - a.1), heightFt: 8,
                             start: .init(x: a.0, y: a.1), end: .init(x: b.0, y: b.1))
        }
        r.walls = [wall("A", (0, 0), (11, 0)), wall("B", (11, 0), (11, 8)), wall("C", (11, 8), (0, 8)),
                   wall("D", (0, 8), (0, 0)), wall("E", (4, 4), (4, 8)), wall("F", (4, 4), (0, 4))]
        return r
    }

    private func layout(_ room: ScannedRoom, floor: AreaTakeoff.FloorRect? = nil,
                        curb: [(ScannedRoom.Point, ScannedRoom.Point)] = [])
        -> (dims: [PlanDimension], placed: [PlanDimensionPlacer.Placed]) {
        let dims = PlanDimensions.build(room: room, floor: floor, curbEdges: curb, items: [],
                                        inward: { w, _ in
                                            let u = PlanDimensions.unit(w.start, w.end)
                                            return .init(x: -u.y, y: u.x)
                                        })
        let scale: CGFloat = 30
        func at(_ p: ScannedRoom.Point) -> CGPoint { CGPoint(x: 40 + p.x * scale, y: 40 + p.y * scale) }
        var placer = PlanDimensionPlacer()
        for w in room.walls {
            placer.claim(from: at(w.start), to: at(w.end))
            placer.edges.append((at(w.start), at(w.end)))
        }
        let placed = placer.layout(dims, at: at, measure: { CGSize(width: CGFloat($0.count) * 6.5, height: 13) })
        return (dims, placed)
    }

    @Test func aWallMetPartwayIsDimensionedInItsStretches() {
        let room = partitionedRoom()
        let a = room.walls[0], d = room.walls[3], c = room.walls[2]
        // A meets nothing partway; D is met by F at 4′; C by E at 7′ along it.
        #expect(PlanDimensions.stretches(of: a, in: room).isEmpty)
        let dStretch = PlanDimensions.stretches(of: d, in: room)
        #expect(dStretch.count == 1)
        #expect(dStretch[0].at.map { ($0 * 100).rounded() / 100 } == [0, 4, 8])
        let cStretch = PlanDimensions.stretches(of: c, in: room)
        #expect(cStretch[0].at.map { ($0 * 100).rounded() / 100 } == [0, 7, 11])
        // Into the room, where the partition is.
        #expect(dStretch[0].side.x > 0.9)
        #expect(cStretch[0].side.y < -0.9)
    }

    @Test func everyDimensionIsDrawnAndNoNumbersOverlap() {
        let (dims, placed) = layout(partitionedRoom())
        #expect(placed.count == dims.count)
        // Six overalls (two partitions as walls of their own) and four stretches.
        #expect(dims.filter { $0.kind == .chain }.count == 4)
        for i in placed.indices {
            for j in placed.indices where j > i {
                #expect(!placed[i].box.intersects(placed[j].box),
                        "\(placed[i].dimension.text) and \(placed[j].dimension.text) overlap")
            }
        }
    }

    @Test func aPartitionIsDimensionedOnWhicheverSideIsClear() {
        let (_, placed) = layout(partitionedRoom())
        #expect(placed.filter { !$0.clean }.map(\.dimension.text) == [])
    }

    @Test func dimensionLinesDoNotCrossOneAnother() {
        let (_, placed) = layout(partitionedRoom())
        for i in placed.indices {
            for j in placed.indices where j != i {
                let a = placed[i].line, b = placed[j].line
                #expect(!PlanDimensionPlacer.crossesCleanly(a.0, a.1, b.0, b.1))
                for w in placed[i].witnesses {
                    #expect(!PlanDimensionPlacer.crossesCleanly(w.0, w.1, b.0, b.1),
                            "an extension line of \(placed[i].dimension.text) crosses \(placed[j].dimension.text)")
                }
            }
        }
    }

    @Test func aShowerFloorAndCurbAreDimensionedWithoutCrowding() {
        var room = partitionedRoom()
        room.walls.removeLast(2)
        let floor = AreaTakeoff.FloorRect(origin: .init(x: 11, y: 8), u: .init(x: -1, y: 0), v: .init(x: 0, y: -1),
                                          widthFt: 5, depthFt: 3)
        let c = floor.corners
        // An alcove: the curb across the front, the width.
        let (dims, placed) = layout(room, floor: floor, curb: [(c[2], c[3])])
        #expect(placed.count == dims.count)
        #expect(placed.filter { !$0.clean }.map(\.dimension.text) == [])
        // The curb gives the width; the depth goes along the wall, inside the floor.
        #expect(dims.contains { $0.text == "Curb 60″" })
        #expect(!dims.contains { $0.id == "floor-width" })
        let depth = dims.first { $0.id == "floor-depth" }
        #expect(depth.map { abs($0.a.x - 11) < 1e-9 && abs($0.b.x - 11) < 1e-9 } == true)
        for i in placed.indices {
            for j in placed.indices where j > i { #expect(!placed[i].box.intersects(placed[j].box)) }
        }
    }

    // MARK: The face-on wall (`WallDimensions`)

    /// An 8′ 1″ × 8′ wall with a 2′ 6″ × 3′ window 3′ 6″ up and a niche low down.
    private func wallLayout(chosen: WallDimensions.Span? = nil)
        -> (dims: [PlanDimension], placed: [PlanDimensionPlacer.Placed]) {
        let window = WallDimensions.Span(from: 3.75, to: 6.25, bottom: 3.5, top: 6.5)
        let niche = WallDimensions.Span(from: 0.5, to: 1.5, bottom: 1, top: 3)
        let dims = WallDimensions.build(lengthFt: 97.0 / 12, heightFt: 8, spans: [window, niche],
                                        tileTops: [8], chosen: chosen)
        let scale: CGFloat = 30
        func at(_ p: ScannedRoom.Point) -> CGPoint { CGPoint(x: 30 + p.x * scale, y: 30 + (8 - p.y) * scale) }
        var placer = PlanDimensionPlacer()
        let wall = CGRect(x: 30, y: 30, width: 97.0 / 12 * scale, height: 8 * scale)
        let c = [CGPoint(x: wall.minX, y: wall.minY), CGPoint(x: wall.maxX, y: wall.minY),
                 CGPoint(x: wall.maxX, y: wall.maxY), CGPoint(x: wall.minX, y: wall.maxY)]
        for i in 0..<4 { placer.claim(from: c[i], to: c[(i + 1) % 4]) }
        let placed = placer.layout(dims, at: at, measure: { CGSize(width: CGFloat($0.count) * 5.6, height: 11) })
        return (dims, placed)
    }

    @Test func aWallsRowAndColumnAddUpToItsLengthAndHeight() {
        let (dims, _) = wallLayout()
        let along = dims.filter { $0.id.hasPrefix("along-") }.map(\.value).reduce(0, +)
        let up = dims.filter { $0.id.hasPrefix("up-") }.map(\.value).reduce(0, +)
        #expect(abs(along - 97.0 / 12) < 1e-9)
        #expect(abs(up - 8) < 1e-9)
        // Corner, niche, gap, window, end: five stretches; floor, niche, gap, window, above: five heights.
        #expect(dims.filter { $0.id.hasPrefix("along-") }.count == 5)
        #expect(dims.filter { $0.id.hasPrefix("up-") }.map(\.text) == ["12″", "24″", "6″", "36″", "18″"])
    }

    @Test func aChosenWindowIsDimensionedOnItselfAndNothingOverlaps() {
        let window = WallDimensions.Span(from: 3.75, to: 6.25, bottom: 3.5, top: 6.5)
        let (dims, placed) = wallLayout(chosen: window)
        #expect(dims.first { $0.id == "chosen-width" }?.text == "30″")
        #expect(dims.first { $0.id == "chosen-height" }?.text == "36″")
        #expect(placed.count == dims.count)
        for i in placed.indices {
            for j in placed.indices where j > i {
                #expect(!placed[i].box.intersects(placed[j].box),
                        "\(placed[i].dimension.text) and \(placed[j].dimension.text) overlap")
                let a = placed[i].line, b = placed[j].line
                #expect(!PlanDimensionPlacer.crossesCleanly(a.0, a.1, b.0, b.1))
            }
        }
        // The length beyond the row, the height beyond the column.
        let length = placed.first { $0.dimension.id == "length" }!, row = placed.first { $0.dimension.id == "along-1" }!
        #expect(length.line.0.y > row.line.0.y)
        let height = placed.first { $0.dimension.id == "height" }!, column = placed.first { $0.dimension.id == "up-1" }!
        #expect(height.line.0.x > column.line.0.x)
    }

    @Test func theCatchTestSumsUpTheMissNineteenTriesInTwentyStayWithin() {
        let misses = (1...20).map(Double.init)          // 1 … 20 points
        #expect(CatchTestView.percentile(misses, 0.95) == 19)
        #expect(CatchTestView.percentile(misses, 0.5) == 10)
        #expect(CatchTestView.percentile([4], 0.95) == 4)
        #expect(CatchTestView.percentile([], 0.95) == nil)
    }
}
