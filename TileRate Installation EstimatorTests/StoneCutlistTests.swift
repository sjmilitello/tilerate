import Testing
import Foundation
@testable import TileRate_Installation_Estimator

/// The stone cutlist (owner, 2026-10-16): pieces sized to order, named
/// without sizes, lettered by the order added when there's more than one.
struct StoneCutlistTests {
    /// A 120″ × 120″ room with a 48″ × 48″ corner shower: two curb runs.
    func cornerShower() -> (ScannedRoom, AreaTakeoff) {
        let room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        _ = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        return (room, t)
    }

    @Test func cornerCurbsRunThroughTheCornerToTheOtherTopsEdge() {
        var (room, t) = cornerShower()
        t.trim = [.init(key: "curb", stone: true), .init(key: "curb:outside", stone: true), .init(key: "curb:inside", stone: true)]
        var prices = StonePrices()
        prices.parts[.curbTop] = StoneRate(widthIn: 7)            // 7″ on a 4½″ curb: 1¼″ each side
        prices.parts[.curbOutside] = StoneRate(widthIn: 4)
        let list = t.cutlist(in: room, area: .shower, curbHeightIn: 4, prices: prices)
        let byName = Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0) })
        // Each run is 48″ along the floor; through the other curb (4½″) and past its overhang (1¼″).
        #expect(byName["Curb A Top"]?.lengthIn == 53.75 && byName["Curb A Top"]?.widthIn == 7)
        #expect(byName["Curb B Top"]?.lengthIn == 53.75)
        // The outside face past the other outside face's 3 cm: 48 + 4½ + 1 3/16 (to the sixteenth).
        #expect(byName["Curb A Outside Face"]?.lengthIn == 53.6875 && byName["Curb A Outside Face"]?.widthIn == 4)
        // Inside faces: the curb's length; height the curb's when no width is set.
        #expect(byName["Curb A Inside Face"]?.lengthIn == 48 && byName["Curb A Inside Face"]?.widthIn == 4)
        #expect(list.allSatisfy { $0.thickness == .threeCm && $0.edges == "All Edges Polished" })
        // Prices follow the same sizes.
        let curb = t.trimPieces(in: room, area: .shower, curbHeightIn: 4, prices: prices).first { $0.key == "curb" }!
        #expect(abs(curb.lengthFt - 2 * 53.75 / 12) < 1e-9)
        _ = room
    }

    @Test func nichePiecesFullWidthAndHeightLessAStoneBack() {
        var (room, t) = cornerShower()
        let wall = room.walls.first { w in t.pieces.contains { $0.wallID == w.id } }!
        t.items = [.init(kind: .niche, wallID: wall.id, fromFt: 1, toFt: 1 + 13.0 / 12, bottomIn: 48, heightIn: 24, dividers: 1)]
        let n = t.items[0]
        for part in ["back", "shelf", "jambs", "header", "dividers"] { t.setPartStone(n, part, true) }
        let list = t.cutlist(in: room, area: .shower, curbHeightIn: 4, prices: StonePrices())
        let byName = Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0) })
        let depth = ((3.5 - 2 / 2.54) * 16).rounded() / 16             // 3½″ less the 2 cm back
        #expect(byName["Niche Back"].map { $0.lengthIn == 13 && $0.widthIn == 24 && $0.thickness == .twoCm } == true)
        #expect(byName["Niche Base Shelf"].map { $0.lengthIn == 13 && $0.widthIn == depth } == true)
        #expect(byName["Niche Jambs"].map { $0.lengthIn == 24 && $0.quantity == 2 && $0.widthIn == depth } == true)
        #expect(byName["Niche Header"]?.lengthIn == 13)
        #expect(byName["Niche Divider Shelf"]?.quantity == 1)
        // A second niche: lettered by the order added.
        t.items.append(.init(kind: .niche, wallID: wall.id, fromFt: 3, toFt: 4, bottomIn: 48, heightIn: 12))
        t.setPartStone(t.items[1], "jambs", true)
        let two = t.cutlist(in: room, area: .shower, curbHeightIn: 4, prices: StonePrices()).map(\.name)
        #expect(two.contains("Niche A Jambs") && two.contains("Niche B Jambs") && two.contains("Niche A Back"))
        _ = room
    }

    @Test func entryJambsAreOneRowWhenTheyMatch() {
        var (room, t) = cornerShower()
        let jambs = t.trimPieces(in: room, area: .shower, curbHeightIn: 4).filter { $0.key.hasPrefix("jamb:") }
        t.trim = jambs.map { .init(key: $0.key, stone: true) }
        let list = t.cutlist(in: room, area: .shower, curbHeightIn: 4, prices: StonePrices())
        #expect(list.first { $0.name == "Entry Jambs" }?.quantity == 2)
        // Different lengths: each its own.
        t.trim[0].lengthFt = 5
        let apart = t.cutlist(in: room, area: .shower, curbHeightIn: 4, prices: StonePrices()).map(\.name)
        #expect(apart.contains("Entry Left Jamb") && apart.contains("Entry Right Jamb"))
        _ = room
    }

    @Test func halfWallCapRunsPastItsFreeEnd() {
        var room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        let w = room.addPlannedWall(from: .init(x: 0, y: 5), to: .init(x: 4, y: 5), heightIn: 42, thicknessIn: 4.5)
        var t = AreaTakeoff()
        t.pieces = [.init(wallID: w.id, fromFt: 0, toFt: 4, heightIn: 42)]
        t.trim = [.init(key: "cap:\(w.id)", stone: true)]
        let list = t.cutlist(in: room, area: .wall, curbHeightIn: 4, prices: StonePrices())
        #expect(list.first?.name == "Half Wall Cap" && list.first?.lengthIn == 48.75 && list.first?.widthIn == 4.5)
    }

    @Test func identicalCornerShelvesAreOneRow() {
        var (room, t) = cornerShower()
        let wall = room.walls.first { w in t.pieces.contains { $0.wallID == w.id } }!
        t.items = [.init(kind: .cornerShelf, wallID: wall.id, bottomIn: 48, sizeIn: 9),
                   .init(kind: .cornerShelf, wallID: wall.id, bottomIn: 60, sizeIn: 9)]
        let list = t.cutlist(in: room, area: .shower, curbHeightIn: 4, prices: StonePrices())
        #expect(list.count == 1 && list[0].name == "Corner Shelves" && list[0].quantity == 2 && list[0].shape == .rightTriangle)
        _ = room
    }

    @Test func jsonAndSpreadsheetCarryEveryPiece() throws {
        var (room, t) = cornerShower()
        t.trim = [.init(key: "curb", stone: true)]
        var doc = EstimateDocument()
        var r = EstimateRoom(name: "Bath")
        r.scan = room
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .rectangle, .straightStacked))
        s.scanTakeoff = t
        r.sections = [s]
        doc.rooms = [r]
        let pieces = StoneCutlistExport.pieces(document: doc, rates: Rates())
        #expect(pieces.map(\.name) == ["Curb A Top", "Curb B Top"])
        let cust = PartyInfo(name: "Smith", address: "1 Main St", phone: "555", email: "a@b.c")
        let data = StoneCutlistExport.json(pieces: pieces, customer: cust, estimateID: doc.id, estimateNumber: 1450, title: "Smith")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["estimate"] as? [String: Any])?["id"] as? String == doc.id.uuidString)
        #expect(json["format"] as? String == "stone-cutlist" && json["formatVersion"] as? Int == 1)
        let customer = try #require(json["customer"] as? [String: Any])
        #expect(customer["name"] as? String == "Smith" && customer["phone"] == nil)          // no phone or email
        let first = try #require((json["pieces"] as? [[String: Any]])?.first)
        #expect(first["name"] as? String == "Curb A Top" && (first["thickness"] as? [String: Any])?["unit"] as? String == "cm")
        #expect(first["edges"] as? String == "Polished")                                    // FabSpecPro's own name
        // The link: compact, zlib-compressed, base64url without padding, z=1.
        let link = try #require(StoneCutlistExport.link(json: StoneCutlistExport.json(pieces: pieces, customer: cust, estimateID: doc.id,
                                                                                      estimateNumber: 1450, title: "Smith", compact: true)))
        let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(link.scheme == "fabspecpro" && link.host == "import" && items.first { $0.name == "z" }?.value == "1")
        var b64 = (items.first { $0.name == "cutlist" }?.value ?? "").replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        #expect(!b64.contains("="))
        while b64.count % 4 != 0 { b64 += "=" }
        let unzipped = try (Data(base64Encoded: b64)! as NSData).decompressed(using: .zlib) as Data
        #expect((try JSONSerialization.jsonObject(with: unzipped) as? [String: Any])?["format"] as? String == "stone-cutlist")
        let csv = StoneCutlistExport.csv(pieces: pieces).split(separator: "\n")
        #expect(csv[0] == "Piece,Group,Type,Shape,Length (in),Width (in),Thickness,Edges,Qty,Notes")
        #expect(csv[1].hasPrefix("Curb A Top,Curb,curbTop,Rectangle,52.5,4.5,3 cm,All Edges Polished,1"))
        _ = room
    }
}

/// An estimate keeps one id for good (owner, 2026-10-17): saved, read, and
/// for estimates saved before ids, the same on every read.
struct EstimateIDTests {
    @Test func anEstimateKeepsItsID() throws {
        var doc = EstimateDocument()
        doc.rooms = [EstimateRoom(name: "Bath")]
        let again = try JSONDecoder().decode(EstimateDocument.self, from: JSONEncoder().encode(doc))
        #expect(again.id == doc.id)
        // Saved before: no id. The same each time it's read — its first room's.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        json["id"] = nil
        let old = try JSONSerialization.data(withJSONObject: json)
        let a = try JSONDecoder().decode(EstimateDocument.self, from: old)
        let b = try JSONDecoder().decode(EstimateDocument.self, from: old)
        #expect(a.id == b.id && a.id == doc.rooms[0].id)
    }
}
