import SwiftUI
import UIKit

/// The estimate's stone cutlist, sent to FabSpecPro or saved as a
/// spreadsheet (owner, 2026-10-16). The format is a public contract kept
/// with FabSpecPro (`docs/stone-cutlist-format.md`): version 1 here.
enum StoneCutlistExport {
    static let formatVersion = 1
    /// FabSpecPro's link and file: names chosen to outlast bundle IDs.
    static let scheme = "fabspecpro"
    static let fileExtension = "stonecutlist"

    /// Every stone piece of the estimate, named. When more than one area has
    /// stone, each name starts with its area ("Shower 2 – Niche Jambs").
    static func pieces(document: EstimateDocument, rates: Rates) -> [CutPiece] {
        let prices = StonePrices(rates: rates)
        var perArea: [(label: String, pieces: [CutPiece])] = []
        let multipleRooms = document.rooms.count > 1
        for room in document.rooms {
            var seen: [Area: Int] = [:]
            for s in room.sections {
                let kind = s.area ?? .wall
                seen[kind, default: 0] += 1
                guard let scan = s.roomScan ?? room.scan, let t = s.scanTakeoff, !s.measuredByHand else { continue }
                let pieces = t.cutlist(in: scan, area: s.area, curbHeightIn: t.curbHeightIn ?? rates.curbHeightIn, prices: prices)
                guard !pieces.isEmpty else { continue }
                let areaName = kind.rawValue + (seen[kind]! > 1 ? " \(seen[kind]!)" : "")
                perArea.append((multipleRooms ? "\(room.name) \(areaName)" : areaName, pieces))
            }
        }
        guard perArea.count > 1 else { return perArea.first?.pieces ?? [] }
        return perArea.flatMap { area in
            area.pieces.map { p in
                var p = p
                p.name = "\(area.label) - \(p.name)"
                p.id = "\(area.label)#\(p.id)"
                return p
            }
        }
    }

    /// The cutlist for FabSpecPro (format version 1).
    static func json(pieces: [CutPiece], customer: PartyInfo, estimateID: UUID, estimateNumber: Int, title: String,
                     date: Date = Date(), exportID: UUID = UUID(), compact: Bool = false) -> Data {
        let iso = ISO8601DateFormatter()
        func round(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
        let body: [String: Any] = [
            "format": "stone-cutlist",
            "formatVersion": formatVersion,
            "source": ["app": "TileRate",
                       "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""],
            "exportID": exportID.uuidString,
            "exportedAt": iso.string(from: Date()),
            "units": "inches",
            "estimate": ["id": estimateID.uuidString, "number": estimateNumber, "title": title, "date": iso.string(from: date)],
            "customer": ["name": customer.name, "address": customer.address, "address2": customer.address2,
                         "cityStateZip": customer.cityStateZip],
            "pieces": pieces.map { p -> [String: Any] in
                [
                    "id": p.id, "name": p.name, "group": p.group, "type": p.type, "shape": p.shape.rawValue,
                    "lengthIn": round(p.lengthIn), "widthIn": round(p.widthIn),
                    "thickness": ["value": round(p.thickness.value), "unit": p.thickness.unit.rawValue],
                    // "standard": every edge, the shop's standard finished edge.
                    "edges": p.edges,
                    "quantity": p.quantity, "notes": [String](),
                ]
            },
        ]
        let options: JSONSerialization.WritingOptions = compact ? [.sortedKeys, .withoutEscapingSlashes]
                                                                : [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? JSONSerialization.data(withJSONObject: body, options: options)) ?? Data()
    }

    /// The same pieces as a spreadsheet: decimal inches, one row per piece.
    static func csv(pieces: [CutPiece]) -> String {
        func cell(_ s: String) -> String {
            s.contains(",") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        func number(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...4)).grouping(.never).locale(Locale(identifier: "en_US"))) }
        var rows = ["Piece,Group,Type,Shape,Length (in),Width (in),Thickness,Edges,Qty,Notes"]
        for p in pieces {
            rows.append([p.name, p.group, p.type, p.shape == .rightTriangle ? "Right triangle" : "Rectangle",
                         number(p.lengthIn), number(p.widthIn), p.thickness.text,
                         p.edges == "standard" ? "All Edges Finished" : p.edges, String(p.quantity), ""]
                .map(cell).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// The link that opens FabSpecPro with the cutlist inside it: compact
    /// JSON, zlib-compressed (raw DEFLATE, `z=1`), base64url without padding.
    static func link(json: Data) -> URL? {
        let (bytes, z) = (try? (json as NSData).compressed(using: .zlib) as Data).map { ($0, true) } ?? (json, false)
        let b64 = bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return URL(string: "\(scheme)://import?cutlist=\(b64)" + (z ? "&z=1" : ""))
    }

    /// A file with the given contents, to share.
    static func file(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    static func safeName(_ s: String) -> String {
        let cleaned = s.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Estimate" : cleaned
    }
}

/// "Export stone cutlist" on the review screen: send to FabSpecPro, or the
/// spreadsheet (free). No PDF — a drawing is FabSpecPro's (owner, 2026-10-16).
struct StoneCutlistCard: View {
    let pieces: [CutPiece]
    let customer: PartyInfo
    let estimateID: UUID
    let estimateNumber: Int
    let title: String

    @State private var notInstalled = false

    var body: some View {
        if !pieces.isEmpty {
            NDCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Stone cutlist", systemImage: "square.split.diagonal.2x2").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text("\(pieces.reduce(0) { $0 + $1.quantity }) pieces").font(.system(size: 14)).foregroundStyle(ND.secondary)
                    }
                    Text("Every piece set to stone, sized to order.").font(.system(size: 14)).foregroundStyle(ND.secondary)
                    HStack(spacing: 10) {
                        Button { send() } label: {
                            Label("Send to FabSpecPro", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NDPrimaryButtonStyle())
                        Button { shareCSV() } label: {
                            Label("Spreadsheet", systemImage: "tablecells").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NDSecondaryButtonStyle())
                    }
                }
                .padding(14)
            }
            .alert("FabSpecPro isn't installed", isPresented: $notInstalled) {
                Button("Save cutlist file") { shareFile() }
                Button("Spreadsheet (CSV)") { shareCSV() }
                Button("OK", role: .cancel) {}
            } message: {
                Text("FabSpecPro turns this cutlist into a project with drawings of every piece. Install it on this iPhone, then send again — or save the cutlist file or a spreadsheet for now.")
            }
        }
    }

    private func json(compact: Bool = false) -> Data {
        StoneCutlistExport.json(pieces: pieces, customer: customer, estimateID: estimateID,
                                estimateNumber: estimateNumber, title: title, compact: compact)
    }

    private var baseName: String {
        StoneCutlistExport.safeName("\(customer.name.isEmpty ? "Estimate \(estimateNumber)" : customer.name) stone cutlist")
    }

    private func send() {
        guard let url = StoneCutlistExport.link(json: json(compact: true)) else { notInstalled = true; return }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened { notInstalled = true }
        }
    }

    private func shareCSV() {
        guard let url = StoneCutlistExport.file(Data(StoneCutlistExport.csv(pieces: pieces).utf8), name: "\(baseName).csv") else { return }
        presentPDFShareSheet(url: url)
    }

    private func shareFile() {
        guard let url = StoneCutlistExport.file(json(), name: "\(baseName).\(StoneCutlistExport.fileExtension)") else { return }
        presentPDFShareSheet(url: url)
    }
}
