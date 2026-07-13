import Foundation
import Testing
@testable import GhostRaceKit

/// Pins the Swift geo/race math to the JS twin in `ghost-race/tools/geo.mjs`
/// via the generated `crosscheck.json`. If these fail after a change to
/// either implementation, the two have drifted apart — fix the code, or
/// regenerate the fixture with `node tools/build-fixtures.mjs` if the change
/// was intentional on both sides.
@Suite("Cross-implementation check")
struct CrossCheckTests {
    struct Fixture: Decodable {
        struct Course: Decodable {
            let polyline: [Coordinate]
            let cumulative: [Double]
            let lengthM: Double
        }
        struct ProjectionCase: Decodable {
            struct Expected: Decodable {
                let distanceAlongM: Double
                let offsetM: Double
            }
            let point: Coordinate
            let expected: Expected
        }
        struct InterpolationCase: Decodable {
            let t: Double
            let expected: Double
        }
        struct EffortFixture: Decodable {
            let durationS: Double
            let points: [EffortPoint]
        }
        struct Race: Decodable {
            let winner: String
            let liveDurationS: Double
            let ghostDurationS: Double
            let leadTakenAtS: Double
        }
        let toleranceM: Double
        let course: Course
        let projectionCases: [ProjectionCase]
        let interpolationCases: [InterpolationCase]
        let ghostEffort: EffortFixture
        let liveEffort: EffortFixture
        let race: Race
    }

    static func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "crosscheck", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func courseLengthMatches() throws {
        let fixture = try Self.loadFixture()
        let cums = Geo.cumulativeDistances(fixture.course.polyline)
        #expect(abs((cums.last ?? 0) - fixture.course.lengthM) < fixture.toleranceM)
        for (mine, theirs) in zip(cums, fixture.course.cumulative) {
            #expect(abs(mine - theirs) < fixture.toleranceM)
        }
    }

    @Test func projectionMatchesJsTwin() throws {
        let fixture = try Self.loadFixture()
        for c in fixture.projectionCases {
            let p = Geo.project(c.point, onto: fixture.course.polyline)
            #expect(abs(p.distanceAlongM - c.expected.distanceAlongM) < fixture.toleranceM)
            #expect(abs(p.offsetM - c.expected.offsetM) < fixture.toleranceM)
        }
    }

    @Test func interpolationMatchesJsTwin() throws {
        let fixture = try Self.loadFixture()
        for c in fixture.interpolationCases {
            let d = GhostEngine.interpolatedDistance(at: c.t, points: fixture.ghostEffort.points)
            #expect(abs(d - c.expected) < fixture.toleranceM)
        }
    }

    /// Replay the full fixture race through GhostEngine and confirm the same
    /// story the JS simulation recorded: the live racer trails, takes the
    /// lead at the expected moment, and wins.
    @Test func fullGhostRaceReplayAgreesOnOutcome() throws {
        let fixture = try Self.loadFixture()
        var engine = GhostEngine(
            courseDistanceM: fixture.course.lengthM,
            opponentPoints: fixture.ghostEffort.points,
            opponentDurationS: fixture.ghostEffort.durationS
        )

        var tookLeadAt: Double?
        var finishedWon: Bool?
        var finishTime: Double?
        var t = 0.0
        while t <= fixture.liveEffort.durationS {
            let mine = GhostEngine.interpolatedDistance(at: t, points: fixture.liveEffort.points)
            let (_, events) = engine.tick(elapsedS: t, myDistanceM: mine)
            for event in events {
                switch event {
                case .tookLead where tookLeadAt == nil:
                    tookLeadAt = t
                case .finished(let won, let myTimeS):
                    finishedWon = won
                    finishTime = myTimeS
                default:
                    break
                }
            }
            t += 1
        }

        #expect(fixture.race.winner == "live")
        #expect(finishedWon == true, "the live racer must beat the ghost")
        let lead = try #require(tookLeadAt)
        #expect(abs(lead - fixture.race.leadTakenAtS) <= 1, "lead change moment agrees with JS twin")
        let finish = try #require(finishTime)
        #expect(abs(finish - fixture.race.liveDurationS) <= 1)
    }
}
