import Testing
@testable import GhostRaceKit

@Suite("RaceCueScheduler")
struct RaceCueSchedulerTests {
    func snapshot(
        elapsedS: Double,
        gapM: Double,
        gapS: Double? = nil,
        remainingFrom courseM: Double = 1000,
        myDistanceM: Double = 500
    ) -> RaceSnapshot {
        RaceSnapshot(
            elapsedS: elapsedS,
            myDistanceM: myDistanceM,
            opponentDistanceM: myDistanceM - gapM,
            gapM: gapM,
            gapS: gapS,
            mySpeedMps: nil,
            courseDistanceM: courseM
        )
    }

    @Test func leadChangeCuesImmediatelyWithJingleHapticAndSpeech() {
        var scheduler = RaceCueScheduler(opponentName: "Alex")
        let cues = scheduler.cues(for: snapshot(elapsedS: 12, gapM: 5), events: [.tookLead])
        #expect(cues.contains(.play(.leadJingle)))
        #expect(cues.contains(.haptic(.overtake)))
        #expect(cues.contains(.say("You took the lead from Alex!")))
    }

    @Test func routineGapAnnouncementsAreRateLimited() {
        var scheduler = RaceCueScheduler(opponentName: "Alex", announceIntervalS: 30)
        // t=0..29: silence (interval not reached since t=-inf... first announce allowed immediately)
        let first = scheduler.cues(for: snapshot(elapsedS: 5, gapM: -20), events: [])
        #expect(first.count == 1, "first gap update speaks")
        // A second later: silence.
        #expect(scheduler.cues(for: snapshot(elapsedS: 6, gapM: -21), events: []).isEmpty)
        #expect(scheduler.cues(for: snapshot(elapsedS: 34, gapM: -25), events: []).isEmpty)
        // Interval elapsed: speaks again.
        #expect(scheduler.cues(for: snapshot(elapsedS: 35, gapM: -25), events: []).count == 1)
    }

    @Test func eventCuesResetTheGapAnnouncementClock() {
        var scheduler = RaceCueScheduler(opponentName: "Alex", announceIntervalS: 30, minQuietS: 8)
        _ = scheduler.cues(for: snapshot(elapsedS: 5, gapM: -20), events: [])
        _ = scheduler.cues(for: snapshot(elapsedS: 20, gapM: 4), events: [.tookLead])
        // 30s after the *event*, not after the earlier announcement.
        #expect(scheduler.cues(for: snapshot(elapsedS: 36, gapM: 6), events: []).isEmpty)
        #expect(scheduler.cues(for: snapshot(elapsedS: 51, gapM: 6), events: []).count == 1)
    }

    @Test func finalStretchTightensTheCadence() {
        var scheduler = RaceCueScheduler(
            opponentName: "Alex",
            announceIntervalS: 30,
            finalStretchIntervalS: 15,
            minQuietS: 8
        )
        _ = scheduler.cues(
            for: snapshot(elapsedS: 100, gapM: -10, remainingFrom: 1000, myDistanceM: 910),
            events: [.finalStretch]
        )
        // 15s cadence now, not 30.
        #expect(scheduler.cues(for: snapshot(elapsedS: 110, gapM: -8), events: []).isEmpty)
        #expect(scheduler.cues(for: snapshot(elapsedS: 116, gapM: -8), events: []).count == 1)
    }

    @Test func finishCuesAndThenGoesSilentForever() {
        var scheduler = RaceCueScheduler(opponentName: "Alex")
        let cues = scheduler.cues(
            for: snapshot(elapsedS: 292, gapM: 12, myDistanceM: 1000),
            events: [.finished(won: true, myTimeS: 292)]
        )
        #expect(cues.contains(.play(.winFanfare)))
        #expect(cues.contains(.say("Finished in 4:52. You beat Alex!")))
        #expect(scheduler.cues(for: snapshot(elapsedS: 400, gapM: 12), events: []).isEmpty)
    }

    @Test func prefersSecondsWhenAvailableAndMetersOtherwise() {
        #expect(
            RaceCueScheduler.gapPhrase(
                snapshot: snapshot(elapsedS: 10, gapM: -33, gapS: -8.2),
                opponentName: "Alex"
            ) == "You're 8 seconds behind Alex."
        )
        #expect(
            RaceCueScheduler.gapPhrase(
                snapshot: snapshot(elapsedS: 10, gapM: 17),
                opponentName: "Alex"
            ) == "You're 15 meters ahead of Alex."
        )
        #expect(
            RaceCueScheduler.gapPhrase(
                snapshot: snapshot(elapsedS: 10, gapM: 1),
                opponentName: "Alex"
            ) == "Neck and neck with Alex!"
        )
    }

    @Test func metersRounding() {
        #expect(RaceCueScheduler.roundedMeters(17) == 15)
        #expect(RaceCueScheduler.roundedMeters(98) == 100)
        #expect(RaceCueScheduler.roundedMeters(112) == 110)
        #expect(RaceCueScheduler.roundedMeters(2) == 0)
    }

    @Test func durationFormatting() {
        #expect(RaceCueScheduler.formatDuration(292) == "4:52")
        #expect(RaceCueScheduler.formatDuration(59.6) == "1:00")
        #expect(RaceCueScheduler.formatDuration(3601) == "60:01")
    }
}
