import Testing
@testable import GhostRaceKit

@Suite("GhostEngine")
struct GhostEngineTests {
    let ghostPoints = [
        EffortPoint(t: 0, d: 0),
        EffortPoint(t: 10, d: 40),
        EffortPoint(t: 20, d: 80),
        EffortPoint(t: 30, d: 120),
    ]

    @Test func interpolationExactBetweenAndClamped() {
        #expect(GhostEngine.interpolatedDistance(at: 10, points: ghostPoints) == 40)
        #expect(GhostEngine.interpolatedDistance(at: 15, points: ghostPoints) == 60)
        #expect(GhostEngine.interpolatedDistance(at: -5, points: ghostPoints) == 0)
        #expect(GhostEngine.interpolatedDistance(at: 99, points: ghostPoints) == 120,
                "a finished ghost stays parked at the finish")
        #expect(GhostEngine.interpolatedDistance(at: 5, points: []) == 0)
    }

    @Test func gapIsPositiveWhenAhead() {
        var engine = GhostEngine(courseDistanceM: 120, opponentPoints: ghostPoints)
        let (snapshot, _) = engine.tick(elapsedS: 10, myDistanceM: 50)
        #expect(snapshot.opponentDistanceM == 40)
        #expect(snapshot.gapM == 10)
        #expect(snapshot.iAmAhead)
    }

    @Test func leadChangeEventsRespectHysteresis() {
        var engine = GhostEngine(courseDistanceM: 1000, opponentPoints: [
            EffortPoint(t: 0, d: 0), EffortPoint(t: 100, d: 400),
        ], leadHysteresisM: 3)

        // Dead heat within hysteresis: no event.
        var (_, events) = engine.tick(elapsedS: 10, myDistanceM: 41)
        #expect(events.isEmpty)

        // Clearly ahead: tookLead once.
        (_, events) = engine.tick(elapsedS: 20, myDistanceM: 90)
        #expect(events == [.tookLead])

        // Jitter back to a small deficit (within hysteresis): no flapping.
        (_, events) = engine.tick(elapsedS: 30, myDistanceM: 118)
        #expect(events.isEmpty)

        // Genuinely overtaken: lostLead.
        (_, events) = engine.tick(elapsedS: 40, myDistanceM: 150)
        #expect(events == [.lostLead])

        // Still behind: no repeat.
        (_, events) = engine.tick(elapsedS: 50, myDistanceM: 190)
        #expect(events.isEmpty)
    }

    @Test func finalStretchFiresOnce() {
        var engine = GhostEngine(
            courseDistanceM: 500,
            opponentPoints: ghostPoints,
            finalStretchM: 100
        )
        var (_, events) = engine.tick(elapsedS: 1, myDistanceM: 350)
        #expect(!events.contains(.finalStretch))
        (_, events) = engine.tick(elapsedS: 2, myDistanceM: 420)
        #expect(events.contains(.finalStretch))
        (_, events) = engine.tick(elapsedS: 3, myDistanceM: 450)
        #expect(!events.contains(.finalStretch), "final stretch announces only once")
    }

    @Test func finishAgainstAFasterGhostLoses() {
        // Ghost finishes 100m in 20s. I arrive at 25s.
        let ghost = GhostEffort(id: "g", athleteName: "Alex", durationS: 20, points: [
            EffortPoint(t: 0, d: 0), EffortPoint(t: 20, d: 100),
        ])
        var engine = GhostEngine(courseDistanceM: 100, ghost: ghost)
        var (_, events) = engine.tick(elapsedS: 20, myDistanceM: 90)
        #expect(events.isEmpty || !events.contains(.finished(won: true, myTimeS: 20)))
        (_, events) = engine.tick(elapsedS: 25, myDistanceM: 100)
        #expect(events.contains(.finished(won: false, myTimeS: 25)))
        // Ticking after the finish stays silent.
        (_, events) = engine.tick(elapsedS: 26, myDistanceM: 100)
        #expect(events.isEmpty)
    }

    @Test func finishBeforeTheGhostWins() {
        let ghost = GhostEffort(id: "g", athleteName: "Alex", durationS: 20, points: [
            EffortPoint(t: 0, d: 0), EffortPoint(t: 20, d: 100),
        ])
        var engine = GhostEngine(courseDistanceM: 100, ghost: ghost)
        let (_, events) = engine.tick(elapsedS: 18, myDistanceM: 100)
        #expect(events.contains(.finished(won: true, myTimeS: 18)))
    }

    @Test func liveOpponentPointsArriveIncrementally() {
        // A live rival is a ghost whose points stream in: same math.
        var engine = GhostEngine(courseDistanceM: 400, opponentPoints: [])
        engine.updateOpponent(EffortPoint(t: 0, d: 0))
        engine.updateOpponent(EffortPoint(t: 10, d: 55))
        engine.updateOpponent(EffortPoint(t: 8, d: 30)) // out of order: dropped
        let (snapshot, _) = engine.tick(elapsedS: 5, myDistanceM: 20)
        #expect(snapshot.opponentDistanceM == 27.5, "interpolates the streamed points")
        #expect(snapshot.gapM == -7.5)
        // Beyond the last known point the opponent holds position.
        var engine2 = engine
        let (later, _) = engine2.tick(elapsedS: 60, myDistanceM: 200)
        #expect(later.opponentDistanceM == 55)
    }

    @Test func gapSecondsUsesRecentSpeed() throws {
        var engine = GhostEngine(courseDistanceM: 1000, opponentPoints: [
            EffortPoint(t: 0, d: 0), EffortPoint(t: 100, d: 500),
        ])
        // Tick once per second at a steady 4 m/s; ghost moves 5 m/s.
        var lastSnapshot: RaceSnapshot?
        for t in 0...5 {
            let (s, _) = engine.tick(elapsedS: Double(t), myDistanceM: Double(t) * 4)
            lastSnapshot = s
        }
        let snapshot = try #require(lastSnapshot)
        let speed = try #require(snapshot.mySpeedMps)
        #expect(abs(speed - 4) < 0.01)
        let gapS = try #require(snapshot.gapS)
        // 5m behind at 4 m/s = 1.25s behind.
        #expect(abs(gapS - (-1.25)) < 0.01)
    }
}
