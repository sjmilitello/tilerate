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

    // MARK: Direction, names on the estimate and cutlist (owner, 2026-10-18)

    @Test func veinsRunAcrossOnlyWhereThePatternHasADirection() throws {
        var l = StoneAppearance.usual(.quartziteLinear)
        #expect(!l.runsAcross)
        l.across = true
        #expect(l.runsAcross)
        let back = try JSONDecoder().decode(StoneAppearance.self, from: JSONEncoder().encode(l))
        #expect(back.across && back.looksLike(l))
        #expect(!l.looksLike(.usual(.quartziteLinear)))
        var g = StoneAppearance.usual(.graniteFine)
        g.across = true
        #expect(!g.runsAcross)                      // flecks have no direction
    }

    func cornerShower() -> (ScannedRoom, AreaTakeoff) {
        let room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        _ = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        t.trim = [.init(key: "curb", stone: true), .init(key: "curb:inside", stone: true)]
        return (room, t)
    }

    func curbLine(_ t: AreaTakeoff, _ room: ScannedRoom, into s: inout EstimateSection) -> String? {
        t.apply(room, to: &s)
        return s.additionsLabor.first { $0.id == AreaTakeoff.stoneLineID(s.id, StoneGroup.curb) }?.activity
    }

    @Test func theEstimateNamesTheStoneOnceOneIsChosen() {
        var (room, t) = cornerShower()
        var s = EstimateSection()
        s.area = .shower
        // Never chosen: the line reads as it always has.
        #expect(curbLine(t, room, into: &s) == "Stone curb")
        var taj = StoneAppearance.usual(.quartziteLinear)
        taj.name = "Taj Mahal"
        t.stoneLook = taj
        #expect(curbLine(t, room, into: &s) == "Stone curb – Taj Mahal, polished")
        // A piece in an unnamed stone of its own: its kind and finish, both listed.
        var black = StoneAppearance.usual(.graniteFine)
        black.honed = true
        t.stoneLooks["curb:inside"] = black
        #expect(curbLine(t, room, into: &s) == "Stone curb – Taj Mahal, polished & granite, honed")
        // Words typed over on the estimate stay.
        if let i = s.additionsLabor.firstIndex(where: { $0.id == AreaTakeoff.stoneLineID(s.id, StoneGroup.curb) }) {
            s.additionsLabor[i].activity = "Curb in customer's own slab"
        }
        #expect(curbLine(t, room, into: &s) == "Curb in customer's own slab")
    }

    @Test func theCutlistCarriesTheStoneAndKeepsDifferentStonesApart() throws {
        var (room, t) = cornerShower()
        #expect(t.cutlist(in: room, area: .shower, curbHeightIn: 4, prices: StonePrices()).allSatisfy { $0.material == nil && $0.finish == nil })
        var taj = StoneAppearance.usual(.quartziteLinear)
        taj.name = "Taj Mahal"
        t.stoneLook = taj
        t.stoneLooks["curb:inside"] = .usual(.soapstone)
        let list = t.cutlist(in: room, area: .shower, curbHeightIn: 4, prices: StonePrices())
        let tops = list.filter { $0.type == "curbTop" }
        #expect(!tops.isEmpty && tops.allSatisfy { $0.material == "Taj Mahal" && $0.finish == "polished" })
        let inside = list.filter { $0.type == "curbInside" }
        #expect(!inside.isEmpty && inside.allSatisfy { $0.material == "soapstone" })
        let json = StoneCutlistExport.json(pieces: list, customer: PartyInfo(name: "Smith", address: "", address2: "", cityStateZip: "", phone: "", email: ""),
                                           estimateID: UUID(), estimateNumber: 1, title: "Smith")
        let body = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        let rows = try #require(body["pieces"] as? [[String: Any]])
        #expect(rows.contains { $0["material"] as? String == "Taj Mahal" && $0["finish"] as? String == "polished" })
    }

    @Test func everyPatternHasASurfaceAndARealSize() {
        for p in StoneAppearance.Pattern.allCases {
            #expect(StoneMaps.surface(p) != nil, "no surface for \(p)")
            #expect(StoneMaps.spanFt(p) >= 1.5 && StoneMaps.spanFt(p) <= 6)
        }
        #expect(StoneMaps.spanFt(.boldVeins) > StoneMaps.spanFt(.graniteFine))
    }
}
