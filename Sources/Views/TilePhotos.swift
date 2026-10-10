import UIKit

/// Photos of real tiles (owner, 2026-10-09: "photo of the real tile"),
/// kept as files in Documents/Tile Photos and named by id; a `TileChoice`
/// holds only the id (`photoID`), so estimates stay small. A photo that's
/// gone (another phone, a deleted file) draws as the tile's colour.
enum TilePhotos {
    private static var cache: [String: UIImage] = [:]

    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Tile Photos", isDirectory: true)
    }

    static func url(_ id: String) -> URL { folder.appendingPathComponent(id + ".jpg") }

    /// Saves a photo (shrunk to 1024 pixels on its long side), returning its id.
    static func save(_ image: UIImage) -> String? {
        let longSide = max(image.size.width, image.size.height)
        let scale = min(1, 1024 / max(longSide, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = small.jpegData(compressionQuality: 0.85) else { return nil }
        let id = UUID().uuidString
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url(id), options: .atomic)
        } catch { return nil }
        cache[id] = small
        return id
    }

    static func image(_ id: String?) -> UIImage? {
        guard let id, !id.isEmpty else { return nil }
        if let i = cache[id] { return i }
        guard let i = UIImage(contentsOfFile: url(id).path) else { return nil }
        cache[id] = i
        return i
    }
}
