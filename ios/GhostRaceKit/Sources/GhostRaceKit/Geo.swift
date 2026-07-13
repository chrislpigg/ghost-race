import Foundation

/// A latitude/longitude pair. GhostRaceKit deliberately avoids CoreLocation so
/// the domain logic stays pure, portable, and testable anywhere.
public struct Coordinate: Codable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// Result of projecting a GPS fix onto a segment's polyline.
public struct PolylineProjection: Equatable, Sendable {
    /// Meters along the polyline from its start to the closest point.
    public var distanceAlongM: Double
    /// Perpendicular distance from the fix to the polyline, in meters.
    /// Large values mean the athlete is off-course (or GPS is drifting).
    public var offsetM: Double
}

public enum Geo {
    public static let earthRadiusM = 6_371_000.0

    /// Great-circle distance between two coordinates, in meters.
    public static func distanceM(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusM * asin(min(1, sqrt(h)))
    }

    /// Cumulative distance in meters at each vertex of `polyline`.
    /// First entry is always 0; last entry is the polyline's total length.
    public static func cumulativeDistances(_ polyline: [Coordinate]) -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(polyline.count)
        var total = 0.0
        for (i, point) in polyline.enumerated() {
            if i > 0 { total += distanceM(polyline[i - 1], point) }
            out.append(total)
        }
        return out
    }

    /// Project `point` onto `polyline`, returning how far along the line the
    /// closest point is and how far off the line the fix sits.
    ///
    /// Uses a local equirectangular projection per polyline edge — accurate to
    /// well under GPS noise at segment scale (a few km), and cheap enough to
    /// run every second while racing. Must stay in lockstep with the JS twin
    /// in `ghost-race/tools/geo.mjs`; the shared `crosscheck.json` fixture
    /// pins both to the same expected values.
    public static func project(
        _ point: Coordinate,
        onto polyline: [Coordinate],
        cumulative: [Double]? = nil
    ) -> PolylineProjection {
        precondition(polyline.count >= 2, "polyline needs at least 2 points")
        let cums = cumulative ?? cumulativeDistances(polyline)

        var best = PolylineProjection(distanceAlongM: 0, offsetM: .greatestFiniteMagnitude)
        for i in 0..<(polyline.count - 1) {
            let a = polyline[i]
            let b = polyline[i + 1]
            let meanLat = (a.lat + b.lat) / 2 * .pi / 180
            let mPerDegLat = .pi / 180 * earthRadiusM
            let mPerDegLon = mPerDegLat * cos(meanLat)

            // Local planar coordinates in meters, origin at `a`.
            let bx = (b.lon - a.lon) * mPerDegLon
            let by = (b.lat - a.lat) * mPerDegLat
            let px = (point.lon - a.lon) * mPerDegLon
            let py = (point.lat - a.lat) * mPerDegLat

            let lenSq = bx * bx + by * by
            let t = lenSq == 0 ? 0 : max(0, min(1, (px * bx + py * by) / lenSq))
            let cx = t * bx
            let cy = t * by
            let offset = ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot()
            if offset < best.offsetM {
                let edgeLen = (cums[i + 1] - cums[i])
                best = PolylineProjection(distanceAlongM: cums[i] + t * edgeLen, offsetM: offset)
            }
        }
        return best
    }
}
