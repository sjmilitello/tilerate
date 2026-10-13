import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// "Make every wall this height" (owner, 2026-10-12).
struct WallHeightTests {
    @Test func everyWallToTheCeilingTakesTheHeightHalfWallsKeepTheirs() {
        var room = ScannedRoom.sample
        let tall = 99.5 / 12
        room.walls[0].heightFt = tall
        var half = room.walls[1]
        half.id = UUID()
        half.planned = true
        half.heightFt = 3.5
        room.walls.append(half)
        #expect(room.wallsDiffer(from: tall))

        room.setEveryWallHeight(tall)

        #expect(!room.wallsDiffer(from: tall))
        #expect(room.walls.filter { $0.id != half.id }.allSatisfy { abs($0.heightFt - tall) < 1e-9 })
        #expect(room.wall(half.id)?.heightFt == 3.5)
        #expect(abs(room.ceilingFt - tall) < 1e-9)
    }

    @Test func openingsStayInsideALowerWall() {
        var room = ScannedRoom.sample
        guard let i = room.openings.indices.first else { return }
        room.setEveryWallHeight(5)
        let o = room.openings[i]
        #expect(o.bottomFt + o.heightFt <= 5 + 1e-9)
    }
}
