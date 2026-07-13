import Foundation

/// Detects crossing a start or finish gate from noisy GPS fixes.
///
/// The classic failure modes this guards against:
/// - GPS jitter making a stationary athlete "cross" the gate repeatedly:
///   after a detection the detector must see the athlete leave a hysteresis
///   band (`radiusM + hysteresisM`) before it can arm again.
/// - A wandering fix near the finish triggering a premature finish: the
///   detector refuses to fire until the athlete has actually travelled
///   `minTravelM` since arming (0 for start gates).
public struct GateDetector: Sendable {
    public enum State: Sendable {
        /// Outside the gate, eligible to detect a crossing.
        case armed
        /// Inside the gate radius after a detection; waiting for exit.
        case inside
    }

    public let gate: Coordinate
    public let radiusM: Double
    public let hysteresisM: Double
    public let minTravelM: Double

    private(set) public var state: State
    private var travelledM: Double = 0
    private var lastPosition: Coordinate?

    public init(
        gate: Coordinate,
        radiusM: Double = 25,
        hysteresisM: Double = 10,
        minTravelM: Double = 0,
        startsInsideGate: Bool = false
    ) {
        self.gate = gate
        self.radiusM = radiusM
        self.hysteresisM = hysteresisM
        self.minTravelM = minTravelM
        self.state = startsInsideGate ? .inside : .armed
    }

    /// Feed the next GPS fix. Returns `true` exactly once per genuine crossing.
    public mutating func update(position: Coordinate) -> Bool {
        if let last = lastPosition {
            travelledM += Geo.distanceM(last, position)
        }
        lastPosition = position

        let distanceToGate = Geo.distanceM(position, gate)
        switch state {
        case .armed:
            guard distanceToGate <= radiusM else { return false }
            guard travelledM >= minTravelM else { return false }
            state = .inside
            return true
        case .inside:
            if distanceToGate > radiusM + hysteresisM {
                state = .armed
                travelledM = 0
            }
            return false
        }
    }
}
