import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// Wall letters go in the order you'd meet the walls going clockwise round
/// the plan from the top wall, each wall running into another lettered
/// straight after it (owner's call, 2026-10-09).
struct WallLetteringTests {
    private func wall(_ label: String, _ a: (Double, Double), _ b: (Double, Double)) -> ScannedRoom.Wall {
        ScannedRoom.Wall(label: label, lengthFt: ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot(),
                         heightFt: 8, start: .init(x: a.0, y: a.1), end: .init(x: b.0, y: b.1))
    }

    /// The owner's bathroom as the phone has it (scan coordinates, turned
    /// about 65° from the screen), lettered the old way by angle: the closet
    /// (A, C, D) mixed in with the outside walls.
    private var ownersRoom: ScannedRoom {
        var r = ScannedRoom()
        r.walls = [
            wall("A", (-3.19, -2.14), (-5.43, -3.19)),
            wall("B", (-8.31, 2.96), (-2.59, -9.25)),
            wall("C", (-4.17, -5.89), (1.38, -3.3)),
            wall("D", (1.38, -3.3), (2.95, -6.65)),
            wall("E", (-2.59, -9.25), (8.67, -3.97)),
            wall("F", (8.67, -3.97), (7.33, -1.1)),
            wall("G", (7.33, -1.1), (8.17, -0.71)),
            wall("H", (8.17, -0.71), (5.02, 6.01)),
            wall("I", (5.02, 6.01), (4.18, 5.62)),
            wall("J", (4.18, 5.62), (2.95, 8.24)),
            wall("K", (2.95, 8.24), (-8.31, 2.96)),
        ]
        r.lettering = 0
        return r
    }

    @Test func theOwnersRoomIsLetteredInTheOrderYouMeetTheWalls() {
        var r = ownersRoom
        let old = Dictionary(uniqueKeysWithValues: r.walls.map { ($0.id, $0.label) })
        r.reletter()
        let now = Dictionary(uniqueKeysWithValues: r.walls.map { (old[$0.id]!, $0.label) })
        // On screen old E is the top wall: it comes first, then the closet
        // that runs into it (its front D, then its side C), then on round the
        // outside, the stub A straight after the wall it stands on (B).
        #expect(now == ["E": "A", "D": "B", "C": "C", "F": "D", "G": "E", "H": "F",
                        "I": "G", "J": "H", "K": "I", "B": "J", "A": "K"])
        #expect(r.lettering == ScannedRoom.letteringVersion)
    }

    @Test func aPlainRoomStartsAtTheTopWallAndGoesClockwise() {
        // On screen y runs down: the top wall is y = 0.
        var r = ScannedRoom()
        r.walls = [wall("", (0, 8), (0, 0)), wall("", (10, 8), (0, 8)), wall("", (0, 0), (10, 0)), wall("", (10, 0), (10, 8))]
        let ids = r.walls.map(\.id)
        r.reletter()
        let byID = Dictionary(uniqueKeysWithValues: r.walls.map { ($0.id, $0.label) })
        #expect(byID[ids[2]] == "A")  // top
        #expect(byID[ids[3]] == "B")  // right
        #expect(byID[ids[1]] == "C")  // bottom
        #expect(byID[ids[0]] == "D")  // left
        // Walls are never turned round.
        #expect(r.walls[2].start == .init(x: 0, y: 0))
    }

    @Test func aWallRunningIntoAnotherIsLetteredRightAfterIt() {
        // A partition off the right wall, and a stub off it.
        var r = ScannedRoom()
        r.walls = [wall("", (0, 0), (10, 0)), wall("", (10, 0), (10, 8)), wall("", (10, 8), (0, 8)), wall("", (0, 8), (0, 0)),
                   wall("", (10, 4), (6, 4)), wall("", (6, 4), (6, 6))]
        let ids = r.walls.map(\.id)
        r.reletter()
        let labels = ids.map { id in r.walls.first { $0.id == id }!.label }
        #expect(labels == ["A", "B", "E", "F", "C", "D"])
    }

    @Test func oldScansAreReletteredAndTheirAreasWallsRenamedWhenRead() throws {
        var room = EstimateRoom()
        room.scan = ownersRoom
        var shower = EstimateSection()
        var glass = TileChoice(); glass.tileWidthIn = 2; glass.tileLengthIn = 2
        shower.walls = [TiledWall(name: "Wall A", sqft: 10, tile: glass), TiledWall(name: "Wall B", sqft: 20),
                        TiledWall(name: "Benches", sqft: 3)]
        room.sections = [shower]
        let read = try JSONDecoder().decode(EstimateRoom.self, from: JSONEncoder().encode(room))
        // On screen old E is the top wall. Old D (the closet's front) meets it
        // partway, so it's two walls now: A (the closet's top) and D (on
        // past the closet). The left wall, old B, is three: K, M and N, cut
        // where the stub (old A, now L) and the closet's side (C) meet it.
        let s = try #require(read.scan)
        let byLength = { (l: String) in s.walls.first { $0.label == l }!.lengthFt }
        #expect(s.walls.count == 14)
        #expect(abs(byLength("A") + byLength("D") - 12.44) < 0.02)
        #expect(abs(byLength("K") + byLength("M") + byLength("N") - 13.48) < 0.02)
        // The stub keeps its glass tile; the left wall's tile goes on each of
        // its sections, the first keeping the square feet till it's measured again.
        let walls = read.sections[0].walls
        #expect(walls.map(\.name) == ["Wall L", "Wall K", "Wall M", "Wall N", "Benches"])
        #expect(walls.map(\.sqft) == [10, 20, 0, 0, 3])
        #expect(walls[0].tile.tileWidthIn == 2)
        #expect(read.scan?.lettering == ScannedRoom.letteringVersion)
        // Read again: nothing changes.
        let again = try JSONDecoder().decode(EstimateRoom.self, from: JSONEncoder().encode(read))
        #expect(again == read)
    }

    // MARK: Sections

    /// A 10′ × 8′ room, top wall y = 0, with a divider from the top wall's
    /// middle down 4′.
    private func roomWithDivider() -> (ScannedRoom, top: UUID, divider: UUID) {
        var r = ScannedRoom()
        r.walls = [wall("", (0, 0), (10, 0)), wall("", (10, 0), (10, 8)), wall("", (10, 8), (0, 8)), wall("", (0, 8), (0, 0)),
                   wall("", (6, 0), (6, 4))]
        r.reletter()
        return (r, r.walls[0].id, r.walls[4].id)
    }

    @Test func aDividerPartwayCutsAWallIntoSectionsEachWithItsOwnLetter() {
        let (r0, top, divider) = roomWithDivider()
        var r = r0
        let changed1 = r.sectionAtDividers()
        #expect(changed1)
        r.reletter()
        #expect(r.walls.count == 6)
        let parts = r.sections(of: top)
        #expect(parts.map(\.lengthFt) == [6, 4])
        // Top-left section A, the divider B right after it, then the top's
        // right-hand section C, and on round.
        #expect(parts.map(\.label) == ["A", "C"])
        #expect(r.wall(divider)?.label == "B")
        // Doing it again changes nothing; the section's id is the same every time.
        let changed2 = r.sectionAtDividers()
        #expect(!changed2)
        var again = r0
        again.sectionAtDividers()
        #expect(Set(again.walls.map(\.id)) == Set(r.walls.map(\.id)))
        // A divider is still a partition (drawn solid in 3-D), a section isn't.
        #expect(PlanDimensions.isPartition(r.wall(divider)!, in: r))
        #expect(!PlanDimensions.isPartition(parts[1], in: r))
    }

    @Test func tileAcrossADividerSplitsAndJoinsAgainWhenTheDividerGoes() {
        let (r0, top, divider) = roomWithDivider()
        var t = AreaTakeoff()
        t.pieces = [.init(wallID: top, fromFt: 4, toFt: 9, heightIn: 96)]
        t.items = [.init(kind: .niche, wallID: top, fromFt: 7, toFt: 8)]
        var r = r0
        r.sectionAtDividers()
        let cut = t.following(old: r0, new: r)
        let second = r.sections(of: top)[1].id
        #expect(cut.pieces.map(\.wallID) == [top, second])
        #expect(cut.pieces.map { [$0.fromFt, $0.toFt] } == [[4, 6], [0, 3]])
        #expect(cut.items.first?.wallID == second)
        #expect(cut.items.first?.fromFt == 1)
        // The divider deleted: one wall again, the tile one piece.
        var gone = r
        gone.walls.removeAll { $0.id == divider }
        let before = gone
        let changed3 = gone.sectionAtDividers()
        #expect(changed3)
        #expect(gone.walls.count == 4)
        #expect(gone.wall(top)?.lengthFt == 10)
        let joined = cut.following(old: before, new: gone)
        #expect(joined.pieces.count == 1)
        #expect(joined.pieces.first.map { [$0.fromFt, $0.toFt] } == [4, 9])
        #expect(joined.items.first?.wallID == top)
        #expect(joined.items.first?.fromFt == 7)
    }

    @Test func movingADividerMovesTheJointAndHalfWallsDontDivide() {
        var (r, top, divider) = roomWithDivider()
        r.sectionAtDividers()
        r.moveWall(divider, by: .init(x: -2, y: 0))
        let changed4 = r.sectionAtDividers()
        #expect(!changed4)
        #expect(r.sections(of: top).map(\.lengthFt) == [4, 6])
        // A half wall drawn in doesn't divide the wall it meets.
        let (h0, _, d0) = roomWithDivider()
        var h = h0
        h.walls.removeAll { $0.id == d0 }
        var half = wall("H", (3, 8), (3, 5))
        half.planned = true
        half.heightFt = 3.5
        h.walls.append(half)
        let changedHalf = h.sectionAtDividers()
        #expect(!changedHalf)
        // A wall split by hand never joins again by itself.
        let (hand0, handTop, d1) = roomWithDivider()
        var hand = hand0
        hand.walls.removeAll { $0.id == d1 }
        hand.splitWall(handTop, atFt: 3)
        let changedHand = hand.sectionAtDividers()
        #expect(!changedHand)
        #expect(hand.walls.count == 5)
    }

    @Test func aDividerCanBeTiledOnEitherSideOrBoth() {
        var (r, top, divider) = roomWithDivider()
        r.sectionAtDividers()
        let d = r.wall(divider)!
        #expect(r.isDivider(d))
        #expect(!r.isDivider(r.wall(top)!))
        // Face 0 is the side toward the area (its floor, here the left of
        // the divider); face 1 the far side.
        let left = ScannedRoom.Point(x: 3, y: 2)
        let own = r.sideNormal(of: d, face: 0, toward: left)
        let far = r.sideNormal(of: d, face: 1, toward: left)
        #expect(own.x < -0.99 && far.x > 0.99)
        #expect(r.faceName(of: d, looking: far) == "Side facing wall \(r.walls.first { $0.start.x == 10 && $0.end.x == 10 }!.label)")
        // Tile on both sides counts both.
        var t = AreaTakeoff()
        t.pieces = [.init(wallID: divider, fromFt: 0, toFt: 4, heightIn: 96, face: 0),
                    .init(wallID: divider, fromFt: 0, toFt: 4, heightIn: 96, face: 1)]
        #expect(t.pieces.reduce(0) { $0 + t.sqft(of: $1, in: r) } == 64)
    }

    @Test func aWallInSectionsIsDimensionedAsOneWithItsStretches() {
        var (r, _, _) = roomWithDivider()
        r.sectionAtDividers()
        let dims = PlanDimensions.build(room: r, floor: nil, curbEdges: [], items: [], inward: { w, _ in
            let n = ScannedRoom.Point(x: -(w.end.y - w.start.y) / w.lengthFt, y: (w.end.x - w.start.x) / w.lengthFt)
            return n
        })
        let values = dims.map { ($0.value * 100).rounded() / 100 }
        #expect(values.contains(10))   // the top wall's overall
        #expect(values.contains(6) && values.contains(4))   // its stretches either side of the divider
    }

    @Test func aNewScanKeepsItsLetters() throws {
        var room = EstimateRoom()
        var s = ownersRoom
        s.lettering = ScannedRoom.letteringVersion
        room.scan = s
        let read = try JSONDecoder().decode(EstimateRoom.self, from: JSONEncoder().encode(room))
        #expect(read.scan?.walls.map(\.label) == s.walls.map(\.label))
    }
}
