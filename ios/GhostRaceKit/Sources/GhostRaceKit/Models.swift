import Foundation

public enum ActivityType: String, Codable, Sendable {
    case run
    case ride
}

/// One sample of an effort: seconds since the effort started, meters along
/// the segment. This is the wire format shared with the server and the shape
/// a live opponent's positions arrive in — identical to a stored ghost's.
public struct EffortPoint: Codable, Equatable, Sendable {
    public var t: Double
    public var d: Double

    public init(t: Double, d: Double) {
        self.t = t
        self.d = d
    }
}

/// A raceable segment: the course geometry plus derived measurements.
public struct SegmentTrack: Codable, Sendable {
    public var id: String
    public var name: String
    public var activityType: ActivityType
    public var polyline: [Coordinate]
    public var gateRadiusM: Double
    /// Cumulative meters at each polyline vertex; last entry is total length.
    public var cumulative: [Double]

    public var distanceM: Double { cumulative.last ?? 0 }
    public var start: Coordinate { polyline.first! }
    public var finish: Coordinate { polyline.last! }

    public init(
        id: String,
        name: String,
        activityType: ActivityType,
        polyline: [Coordinate],
        gateRadiusM: Double = 25
    ) {
        precondition(polyline.count >= 2, "a segment needs at least 2 points")
        self.id = id
        self.name = name
        self.activityType = activityType
        self.polyline = polyline
        self.gateRadiusM = gateRadiusM
        self.cumulative = Geo.cumulativeDistances(polyline)
    }
}

/// A completed, stored effort — the thing you race as a ghost.
public struct GhostEffort: Codable, Sendable {
    public var id: String
    public var athleteName: String
    public var durationS: Double
    public var points: [EffortPoint]

    public init(id: String, athleteName: String, durationS: Double, points: [EffortPoint]) {
        self.id = id
        self.athleteName = athleteName
        self.durationS = durationS
        self.points = points
    }
}
