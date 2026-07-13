import Foundation

/// A point-in-time comparison between me and my opponent.
public struct RaceSnapshot: Equatable, Sendable {
    public var elapsedS: Double
    public var myDistanceM: Double
    public var opponentDistanceM: Double
    /// Positive when I'm ahead, negative when I'm behind.
    public var gapM: Double
    /// The gap expressed in seconds at my current speed; nil until the engine
    /// has seen enough ticks to estimate speed.
    public var gapS: Double?
    public var mySpeedMps: Double?
    public var courseDistanceM: Double

    public var remainingM: Double { max(0, courseDistanceM - myDistanceM) }
    public var iAmAhead: Bool { gapM >= 0 }
}

public enum RaceEvent: Equatable, Sendable {
    case tookLead
    case lostLead
    case finalStretch
    case finished(won: Bool, myTimeS: Double)
}

/// The core race comparator. Feed it my position once a second and it tells
/// me where I stand against the opponent and what just happened.
///
/// The opponent is *always* a ghost: in ghost mode its points are loaded
/// up-front from a stored effort; in live mode they arrive one at a time via
/// `updateOpponent(_:)` from the WebSocket relay. Everything downstream
/// (audio, haptics, HUD) is identical in both modes.
public struct GhostEngine: Sendable {
    private enum Leader: Equatable { case tied, me, opponent }

    public let courseDistanceM: Double
    /// A lead change only registers when the gap swings past this magnitude,
    /// so GPS jitter around a dead heat doesn't cause announcement flapping.
    public let leadHysteresisM: Double
    /// "Final stretch" fires when this much course (or less) remains.
    public let finalStretchM: Double

    private(set) public var opponentPoints: [EffortPoint]
    private let opponentDurationS: Double?

    private var leader: Leader = .tied
    private var announcedFinalStretch = false
    private var finished = false
    private var recentTicks: [(t: Double, d: Double)] = []

    public init(
        courseDistanceM: Double,
        opponentPoints: [EffortPoint],
        opponentDurationS: Double? = nil,
        leadHysteresisM: Double = 3,
        finalStretchM: Double = 100
    ) {
        self.courseDistanceM = courseDistanceM
        self.opponentPoints = opponentPoints.sorted { $0.t < $1.t }
        self.opponentDurationS = opponentDurationS
        self.leadHysteresisM = leadHysteresisM
        self.finalStretchM = finalStretchM
    }

    /// Convenience for ghost mode: race a stored effort.
    public init(courseDistanceM: Double, ghost: GhostEffort) {
        self.init(
            courseDistanceM: courseDistanceM,
            opponentPoints: ghost.points,
            opponentDurationS: ghost.durationS
        )
    }

    /// Live mode: a fresh opponent position arrived over the wire.
    public mutating func updateOpponent(_ point: EffortPoint) {
        if let last = opponentPoints.last, point.t <= last.t { return } // drop stale/out-of-order
        opponentPoints.append(point)
    }

    /// Linear interpolation of distance-along-course at elapsed time `t`.
    /// Clamps to the first/last known points (a finished ghost stays parked
    /// at the finish line; a live opponent holds their last known position).
    public static func interpolatedDistance(at t: Double, points: [EffortPoint]) -> Double {
        guard let first = points.first else { return 0 }
        if t <= first.t { return first.d }
        guard let last = points.last else { return 0 }
        if t >= last.t { return last.d }

        // Binary search for the surrounding pair.
        var lo = 0
        var hi = points.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if points[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = points[lo]
        let b = points[hi]
        guard b.t > a.t else { return a.d }
        let f = (t - a.t) / (b.t - a.t)
        return a.d + f * (b.d - a.d)
    }

    public mutating func tick(elapsedS: Double, myDistanceM: Double) -> (snapshot: RaceSnapshot, events: [RaceEvent]) {
        let opponentD = Self.interpolatedDistance(at: elapsedS, points: opponentPoints)
        let gapM = myDistanceM - opponentD

        recentTicks.append((t: elapsedS, d: myDistanceM))
        if recentTicks.count > 6 { recentTicks.removeFirst() }
        var speed: Double?
        if let first = recentTicks.first, let last = recentTicks.last, last.t - first.t >= 2 {
            speed = (last.d - first.d) / (last.t - first.t)
        }
        var gapS: Double?
        if let s = speed, s > 0.5 { gapS = gapM / s }

        let snapshot = RaceSnapshot(
            elapsedS: elapsedS,
            myDistanceM: myDistanceM,
            opponentDistanceM: opponentD,
            gapM: gapM,
            gapS: gapS,
            mySpeedMps: speed,
            courseDistanceM: courseDistanceM
        )

        var events: [RaceEvent] = []
        if finished { return (snapshot, events) }

        // Lead changes, with hysteresis against jitter.
        switch leader {
        case .tied:
            if gapM > leadHysteresisM {
                leader = .me
                events.append(.tookLead)
            } else if gapM < -leadHysteresisM {
                leader = .opponent
                events.append(.lostLead)
            }
        case .me:
            if gapM < -leadHysteresisM {
                leader = .opponent
                events.append(.lostLead)
            }
        case .opponent:
            if gapM > leadHysteresisM {
                leader = .me
                events.append(.tookLead)
            }
        }

        if !announcedFinalStretch, snapshot.remainingM > 0, snapshot.remainingM <= finalStretchM {
            announcedFinalStretch = true
            events.append(.finalStretch)
        }

        if myDistanceM >= courseDistanceM {
            finished = true
            let won: Bool
            if let duration = opponentDurationS {
                won = elapsedS < duration
            } else {
                won = opponentD < courseDistanceM
            }
            events.append(.finished(won: won, myTimeS: elapsedS))
        }

        return (snapshot, events)
    }
}
