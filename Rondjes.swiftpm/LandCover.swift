import Foundation
import CoreLocation
import UIKit

/// Reads the landscape around home from OpenStreetMap map tiles (zoom 12):
/// grey / pink / purple areas are built-up, greens and blue are nature, farmland or water.
actor LandCover {
    static let shared = LandCover()

    static let zoom = 12
    static let block = 2                  // 2×2 pixels per cell (≈ 50 m)
    static let cellsPerTile = 256 / block

    enum Cover: UInt8 { case unknown = 0, urban = 1, green = 2 }

    private var tiles: [String: [UInt8]] = [:]
    private var failed: Set<String> = []

    private static let palette: [(Int, Int, Int, Cover)] = [
        (224, 223, 223, .urban), (242, 218, 217, .urban), (255, 214, 209, .urban), (235, 219, 232, .urban),
        (223, 221, 206, .urban), (199, 199, 180, .urban), (217, 208, 201, .urban), (255, 255, 229, .urban),
        (238, 238, 238, .urban), (230, 214, 206, .urban),
        (173, 209, 158, .green), (200, 250, 204, .green), (205, 235, 176, .green), (238, 240, 213, .green),
        (174, 223, 163, .green), (200, 215, 171, .green), (214, 217, 159, .green), (201, 225, 191, .green),
        (170, 203, 175, .green), (222, 246, 192, .green), (223, 252, 226, .green), (170, 211, 223, .green),
        (245, 233, 198, .green), (199, 230, 169, .green), (211, 237, 187, .green), (165, 213, 139, .green),
        (157, 202, 138, .green)
    ]

    private static func classify(_ r: Int, _ g: Int, _ b: Int) -> Cover {
        var best = Cover.unknown, bestDistance = 13 * 13
        for (pr, pg, pb, c) in palette {
            let d = (r - pr) * (r - pr) + (g - pg) * (g - pg) + (b - pb) * (b - pb)
            if d < bestDistance { bestDistance = d; best = c }
        }
        return best
    }

    private static func loadTile(x: Int, y: Int) async throws -> [UInt8] {
        var req = URLRequest(url: URL(string: "https://tile.openstreetmap.org/\(zoom)/\(x)/\(y).png")!)
        req.setValue("Rondjes/2.0 (iOS hardloop-app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data)?.cgImage else { throw URLError(.badServerResponse) }

        var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        pixels.withUnsafeMutableBytes { buffer in
            if let ctx = CGContext(data: buffer.baseAddress, width: 256, height: 256, bitsPerComponent: 8,
                                   bytesPerRow: 256 * 4, space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .none
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
            }
        }

        let n = cellsPerTile
        var cells = [UInt8](repeating: 0, count: n * n)
        for cy in 0..<n {
            for cx in 0..<n {
                var urban = 0, green = 0
                for dy in 0..<block {
                    for dx in 0..<block {
                        let i = ((cy * block + dy) * 256 + cx * block + dx) * 4
                        switch classify(Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])) {
                        case .urban: urban += 1
                        case .green: green += 1
                        case .unknown: break
                        }
                    }
                }
                cells[cy * n + cx] = urban > green ? Cover.urban.rawValue : green > urban ? Cover.green.rawValue : 0
            }
        }
        return cells
    }

    /// Loads the tiles around a point. Returns false when the land cover is not available.
    func ensure(around center: CLLocationCoordinate2D, radius: Double) async -> Bool {
        let metersPerPixel = 156_543.03 * cos(center.latitude * .pi / 180) / pow(2, Double(Self.zoom))
        let p = Geo.worldPixel(center, zoom: Self.zoom)
        let r = radius / metersPerPixel
        let x0 = Int(floor((p.x - r) / 256)), x1 = Int(floor((p.x + r) / 256))
        let y0 = Int(floor((p.y - r) / 256)), y1 = Int(floor((p.y + r) / 256))
        guard (x1 - x0 + 1) * (y1 - y0 + 1) <= 36 else { return false }

        var keys: [(String, Int, Int)] = []
        for x in x0...x1 { for y in y0...y1 { keys.append(("\(x)/\(y)", x, y)) } }
        let missing = keys.filter { tiles[$0.0] == nil && !failed.contains($0.0) }

        await withTaskGroup(of: (String, [UInt8]?).self) { group in
            for (key, x, y) in missing {
                group.addTask { (key, try? await LandCover.loadTile(x: x, y: y)) }
            }
            for await (key, cells) in group {
                if let cells { tiles[key] = cells } else { failed.insert(key) }
            }
        }
        let loaded = keys.filter { tiles[$0.0] != nil }.count
        return Double(loaded) >= Double(keys.count) * 0.7
    }

    private func cell(_ gx: Int, _ gy: Int) -> Int {
        let n = Self.cellsPerTile
        let tx = Int(floor(Double(gx) / Double(n))), ty = Int(floor(Double(gy) / Double(n)))
        guard let t = tiles["\(tx)/\(ty)"] else { return -1 }
        return Int(t[(gy - ty * n) * n + (gx - tx * n)])
    }

    /// Majority cover of the 5×5 cells (≈ 250 m) around a point, ignoring roads and labels.
    func cover(at c: CLLocationCoordinate2D) -> Cover? {
        let p = Geo.worldPixel(c, zoom: Self.zoom)
        let gx = Int(floor(p.x / Double(Self.block))), gy = Int(floor(p.y / Double(Self.block)))
        var urban = 0, green = 0, known = false
        for dy in -2...2 {
            for dx in -2...2 {
                let v = cell(gx + dx, gy + dy)
                if v >= 0 { known = true }
                if v == Int(Cover.urban.rawValue) { urban += 1 } else if v == Int(Cover.green.rawValue) { green += 1 }
            }
        }
        guard known else { return nil }
        return urban > green ? .urban : green > urban ? .green : .unknown
    }

    /// Share of green and built-up along a line, sampled every ~60 m.
    func along(_ pts: [CLLocationCoordinate2D]) -> (green: Double?, urban: Double?) {
        var urban = 0, green = 0, n = 0
        var acc = 60.0
        for i in 1..<max(pts.count, 1) {
            acc += Geo.distance(pts[i - 1], pts[i])
            guard acc >= 60 else { continue }
            acc = 0
            guard let c = cover(at: pts[i]) else { continue }
            n += 1
            if c == .urban { urban += 1 } else if c == .green { green += 1 }
        }
        guard n > 0 else { return (nil, nil) }
        return (Double(green) / Double(n), Double(urban) / Double(n))
    }

    /// How green a circle of the given size in the given direction would be.
    func circleScore(home: CLLocationCoordinate2D, radius: Double, bearing: Double) -> Double {
        let center = Geo.destination(from: home, distance: radius, bearing: bearing)
        let pts = (0...48).map { Geo.destination(from: center, distance: radius, bearing: bearing + 180 + Double($0) * 7.5) }
        let c = along(pts)
        return (c.green ?? 0) - 1.5 * (c.urban ?? 0)
    }
}
