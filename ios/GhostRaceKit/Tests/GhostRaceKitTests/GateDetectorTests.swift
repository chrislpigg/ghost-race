import Testing
@testable import GhostRaceKit

@Suite("GateDetector")
struct GateDetectorTests {
    let gate = Coordinate(lat: 0, lon: 0)

    /// ~`meters` north of the gate.
    func north(_ meters: Double) -> Coordinate {
        Coordinate(lat: meters / 111_195, lon: 0)
    }

    @Test func firesExactlyOncePerCrossing() {
        var detector = GateDetector(gate: gate, radiusM: 25, hysteresisM: 10)
        #expect(!detector.update(position: north(100)))
        #expect(!detector.update(position: north(50)))
        #expect(detector.update(position: north(20)), "entering the radius fires")
        #expect(!detector.update(position: north(10)), "staying inside does not re-fire")
        #expect(!detector.update(position: north(0)))
    }

    @Test func jitterAroundTheRadiusDoesNotDoubleFire() {
        var detector = GateDetector(gate: gate, radiusM: 25, hysteresisM: 10)
        #expect(detector.update(position: north(20)))
        // GPS wobbles between 20m and 30m: inside radius, then just outside,
        // but never beyond radius + hysteresis (35m) — must stay quiet.
        #expect(!detector.update(position: north(30)))
        #expect(!detector.update(position: north(20)))
        #expect(!detector.update(position: north(30)))
        #expect(!detector.update(position: north(18)))
    }

    @Test func reArmsAfterLeavingTheHysteresisBand() {
        var detector = GateDetector(gate: gate, radiusM: 25, hysteresisM: 10)
        #expect(detector.update(position: north(20)))
        #expect(!detector.update(position: north(40)), "leaving re-arms silently")
        #expect(detector.update(position: north(20)), "a genuine second lap fires again")
    }

    @Test func minTravelGuardBlocksPrematureFinish() {
        // Finish gate 30m from where the athlete starts: standing at the start
        // (which is within GPS-noise range of a short segment's finish) must
        // not finish the race until real distance has been covered.
        var detector = GateDetector(gate: gate, radiusM: 25, hysteresisM: 10, minTravelM: 200)
        #expect(!detector.update(position: north(24)), "inside radius but no travel yet")
        #expect(!detector.update(position: north(26)))
        // Run away and come back, accumulating > 200m of travel.
        #expect(!detector.update(position: north(150)))
        #expect(detector.update(position: north(20)), "after real travel the crossing fires")
    }

    @Test func startsInsideGateRequiresExitFirst() {
        // Athlete begins standing on the start line: the detector must not
        // count that as a crossing, only the next genuine entry.
        var detector = GateDetector(gate: gate, radiusM: 25, hysteresisM: 10, startsInsideGate: true)
        #expect(!detector.update(position: north(5)))
        #expect(!detector.update(position: north(40)), "walking away re-arms")
        #expect(detector.update(position: north(10)), "coming back is a real crossing")
    }
}
