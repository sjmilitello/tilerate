import Testing
import Foundation
import UIKit
@testable import TileRate_Installation_Estimator

/// How stone looks (owner, 2026-10-17): the area's stone, a piece's own,
/// My Stones, and the patterns drawn the same every time.
struct StoneLookTests {
    @Test func takeoffSavedBeforeReadsWithTheStandardStone() throws {
        // A takeoff saved before stone looks: none of the new keys.
        let old = #"{"pieces":[],"items":[],"trim":[{"key":"curb","stone":true}],"floor":"drawn"}"#
        let t = try JSONDecoder().decode(AreaTakeoff.self, from: Data(old.utf8))
        #expect(t.stoneLook == nil && t.stoneLooks.isEmpty)
        #expect(t.areaStone == .standard)
        #expect(t.trim.first?.stone == true && t.floor == .drawn)
    }

    @Test func stoneLooksSaveAndReadBack() throws {
        var t = AreaTakeoff()
        var taj = StoneAppearance(pattern: .quartziteLinear, base: "#E9E4DB", markings: "#A88157", second: "#A4ACB3")
        taj.name = "Taj Mahal"
        t.stoneLook = taj
        t.stoneLooks["curb"] = StoneAppearance(pattern: .graniteFine, base: "#1F1F1F", markings: "#898989", honed: true)
        let back = try JSONDecoder().decode(AreaTakeoff.self, from: JSONEncoder().encode(t))
        #expect(back.stoneLook == taj)
        #expect(back.stoneLooks == t.stoneLooks)
    }

    @Test func aPatternThisVersionDoesntKnowReadsAsTheStandardOne() throws {
        let json = ##"{"pattern":"lapisLazuli","base":"#335C7A","honed":true}"##
        let l = try JSONDecoder().decode(StoneAppearance.self, from: Data(json.utf8))
        #expect(l.pattern == .softVeins && l.base == "#335C7A" && l.honed)
        #expect(l.markings == StoneAppearance.standard.markings)
    }

    @Test func aPieceFollowsTheAreaUnlessItHasItsOwn() {
        var t = AreaTakeoff()
        let black = StoneAppearance(pattern: .graniteFine, base: "#1F1F1F", markings: "#898989")
        let white = StoneAppearance(pattern: .solid, base: "#F7F7F7")
        t.stoneLook = black
        t.stoneLooks["corner:x"] = white
        #expect(t.stone(for: "curb") == black)
        #expect(t.stone(for: "corner:x") == white)
        let keys = StoneKeys(keys: ["curb", "corner:x"], area: t.areaStone, looks: t.stoneLooks)
        #expect(keys.look("curb") == black && keys.look("corner:x") == white)
    }

    @Test func mergedAreasKeepTheirOwnStone() {
        let a = StoneKeys(keys: ["wallEnd:A:end"], area: .usual(.soapstone))
        let b = StoneKeys(keys: ["kneeEnd:B:start"], area: .usual(.onyx))
        let m = StoneKeys.merged([a, b])
        #expect(m.contains("wallEnd:A:end") && m.contains("kneeEnd:B:start"))
        #expect(m.look("wallEnd:A:end") == .usual(.soapstone))
        #expect(m.look("kneeEnd:B:start") == .usual(.onyx))
    }

    /// Every pattern draws from its photo's map (in the app), at the size
    /// asked, with markings (not one flat colour), and the same pixels each time.
    @Test func everyPatternDrawsTheSameEachTime() throws {
        for p in StoneAppearance.Pattern.allCases {
            #expect(StoneMaps.map(p, n: 16) != nil, "no map for \(p)")
            let look = StoneAppearance.usual(p)
            let a = try #require(StonePatterns.patternImage(look, pixels: 64).cgImage)
            #expect(a.width == 64 && a.height == 64, "\(p)")
            let fresh = try #require(StonePatterns.draw(look, pixels: 63).cgImage)
            let again = try #require(StonePatterns.draw(look, pixels: 63).cgImage)
            #expect(pixels(fresh) == pixels(again), "\(p)")
            let px = pixels(a)
            let distinct = Set(stride(from: 0, to: px.count, by: 4).map { i in px[i] }).count
            #expect(distinct > (p == .solid ? 2 : 8), "\(p) looks flat: \(distinct)")
        }
    }

    @Test func drawnInTheChosenColours() throws {
        var look = StoneAppearance(pattern: .solid, base: "#335C7A")
        let img = try #require(StonePatterns.patternImage(look, pixels: 32).cgImage)
        // Solid: the base colour, a little shading either way (on average, the base).
        let px = pixels(img)
        func mean(_ c: Int) -> Int { stride(from: c, to: px.count, by: 4).map { Int(px[$0]) }.reduce(0, +) / (32 * 32) }
        #expect(abs(mean(0) - 0x33) < 12 && abs(mean(1) - 0x5C) < 12 && abs(mean(2) - 0x7A) < 12)
        look.base = "#F7F7F7"
        #expect(StonePatterns.cachedPattern(look, pixels: 32) == nil)
    }

    @Test func myStonesAndRecentlyUsedStayOnThePhone() {
        let suite = "StoneLookTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let lib = StoneLibrary(defaults: defaults)
        lib.save(.usual(.quartziteLinear), name: "Taj Mahal")
        lib.save(.usual(.graniteFine), name: "Absolute black")
        lib.save(.usual(.quartziteCloudy), name: "taj mahal")          // same name: replaced
        #expect(lib.mine.count == 2 && lib.mine[0].pattern == .quartziteCloudy)
        lib.rename(at: 1, to: "Black pearl")
        lib.delete(at: 0)
        for p in StoneAppearance.Pattern.allCases { lib.used(.usual(p)) }
        lib.used(.usual(.onyx))
        let again = StoneLibrary(defaults: defaults)
        #expect(again.mine.map(\.name) == ["Black pearl"])
        #expect(again.recent.count == StoneLibrary.recentLimit)
        #expect(again.recent.first == .usual(.onyx))
        #expect(again.recent.filter { $0.looksLike(.usual(.onyx)) }.count == 1)
    }

    @Test func anUnreadableLibraryIsKeptAside() {
        let suite = "StoneLookTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "stoneLibrary.mine.v1")
        let lib = StoneLibrary(defaults: defaults)
        #expect(lib.mine.isEmpty)
        #expect(defaults.data(forKey: "stoneLibrary.mine.v1.unreadable") == Data("not json".utf8))
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return out
    }
}
