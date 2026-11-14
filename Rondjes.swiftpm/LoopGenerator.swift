import Foundation
import CoreLocation

/// Builds a loop from home of (almost) exactly the requested length, as green as possible.
///
/// 1. Read the landscape around home and rank 16 directions by how green a loop there would be.
/// 2. Route the 4 best directions with the nature profile and keep the greenest real route.
/// 3. Tune the size of the loop until the length is within 100 m.
enum LoopGenerator {
    static let tolerance = 100.0

    static func score(_ r: RouteResult) -> Double { (r.green ?? 0) - 1.5 * (r.urban ?? 0) }

    private static func angleDiff(_ a: Double, _ b: Double) -> Double {
        abs(((a - b).truncatingRemainder(dividingBy: 360) + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    /// - Returns: the route and an updated road factor (how much longer roads are than the ideal circle).
    static func make(home: CLLocationCoordinate2D,
                     target: Double,
                     baseBearing: Double,
                     avoidBearing: Double?,
                     factor startFactor: Double,
                     progress: @escaping @MainActor (String) -> Void) async throws -> (RouteResult, Double) {
        var factor = startFactor
        let radius = target / (2 * .pi * factor)
        func learn(_ r: RouteResult, _ rad: Double) {
            factor = min(2.2, max(1, 0.75 * factor + 0.25 * (r.meters / (2 * .pi * rad))))
        }

        // 0) landscape around home
        await progress("Natuur rond je huis bekijken…")
        let landCover = await LandCover.shared.ensure(around: home, radius: radius * 2.6 + 1500)
        var order: [Double] = []
        if landCover {
            var ranked: [(Double, Double)] = []
            for k in 0..<16 {
                let brg = (baseBearing + Double(k) * 22.5).truncatingRemainder(dividingBy: 360)
                if let avoid = avoidBearing, angleDiff(brg, avoid) <= 30 { continue }
                ranked.append((brg, await LandCover.shared.circleScore(home: home, radius: radius, bearing: brg)))
            }
            for (brg, _) in ranked.sorted(by: { $0.1 > $1.1 }) where order.allSatisfy({ angleDiff($0, brg) >= 45 }) {
                order.append(brg)
            }
        } else {
            order = [0, 90, 180, 270, 45, 135, 225, 315].map { (baseBearing + $0).truncatingRemainder(dividingBy: 360) }
            if let avoid = avoidBearing { order = order.filter { angleDiff($0, avoid) > 30 } }
        }

        func rate(_ r: inout RouteResult) async {
            if landCover {
                let c = await LandCover.shared.along(r.coords)
                r.green = c.green; r.urban = c.urban
            }
        }

        // 1) route the most promising directions
        var routed: [RouteResult] = []
        for pass in 0..<2 where routed.isEmpty {
            let plain = pass == 1        // nature planner unavailable: plain walking routes
            for brg in order {
                if routed.count >= 4 { break }
                try Task.checkCancellation()
                await progress(plain ? "Gewone looproute zoeken…" : "Groenste richting zoeken (\(routed.count + 1)/4)…")
                do {
                    var r = try await Router.shared.route([home] + Geo.circlePoints(home: home, radius: radius, bearing: brg) + [home], plain: plain)
                    await rate(&r)
                    r.bearing = brg; r.radius = radius; r.plain = plain
                    learn(r, radius)
                    routed.append(r)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    continue
                }
                if plain { break }
            }
        }
        guard !routed.isEmpty else { throw RoutingError.unroutable("geen begaanbare paden rond je huis gevonden") }

        // prefer the greenest; among nearly-as-green options rotate per distance for some variety
        routed.sort { score($0) > score($1) }
        let good = routed.filter { score($0) >= score(routed[0]) - 0.06 }
        let chosen = good[Int((target / 500).rounded()) % good.count]

        // 2) tune the length: interpolate between the closest too-short and too-long attempt,
        //    nudging the direction a little because routes jump between path variants
        var best = chosen, current = chosen
        var low: RouteResult? = chosen.meters < target ? chosen : nil
        var high: RouteResult? = chosen.meters >= target ? chosen : nil
        let jitter: [Double] = [0, 0, 7, -7, 14, -14, 21, -21, 28, -28]
        for i in 0..<jitter.count where abs(best.meters - target) > tolerance {
            try Task.checkCancellation()
            await progress("Afstand afstemmen (nu \(Fmt.km(Int(best.meters))) km)…")
            var rad: Double
            if let lo = low, let hi = high, hi.radius != lo.radius, hi.meters != lo.meters {
                rad = lo.radius + (target - lo.meters) * (hi.radius - lo.radius) / (hi.meters - lo.meters)
            } else {
                rad = current.radius * pow(target / max(current.meters, 1), 0.9)
            }
            if !rad.isFinite || rad <= 0 { rad = current.radius * pow(target / max(current.meters, 1), 0.9) }
            if current.failed { rad *= 1.06 }
            let brg = (chosen.bearing + jitter[i] + 360).truncatingRemainder(dividingBy: 360)
            do {
                var r = try await Router.shared.route([home] + Geo.circlePoints(home: home, radius: rad, bearing: brg) + [home], plain: chosen.plain)
                await rate(&r)
                r.bearing = brg; r.radius = rad; r.plain = chosen.plain
                current = r
                learn(r, rad)
                if r.meters < target { if low == nil || r.meters > low!.meters { low = r } }
                else if high == nil || r.meters < high!.meters { high = r }
                if abs(r.meters - target) < abs(best.meters - target) { best = r }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                current.radius = rad
                current.failed = true
            }
        }
        return (best, factor)
    }

    /// 80 elevation samples along the route, for the profile chart.
    static func sampleElevations(_ r: RouteResult) -> [Double]? {
        guard let ele = r.elevations, ele.count == r.coords.count, r.coords.count > 1 else { return nil }
        var cum = [0.0]
        for i in 1..<r.coords.count { cum.append(cum[i - 1] + Geo.distance(r.coords[i - 1], r.coords[i])) }
        let total = max(cum.last ?? 1, 1)
        var out: [Double] = []
        var j = 0
        for s in 0..<80 {
            let d = total * Double(s) / 79
            while j < cum.count - 2 && cum[j + 1] < d { j += 1 }
            out.append((ele[j] * 10).rounded() / 10)
        }
        return out
    }
}
