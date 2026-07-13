import Testing
@testable import GhostRaceKit

@Suite("Geo")
struct GeoTests {
    // One degree of longitude at the equator is ~111.19 km for R=6371 km.
    @Test func haversineKnownDistance() {
        let a = Coordinate(lat: 0, lon: 0)
        let b = Coordinate(lat: 0, lon: 1)
        let d = Geo.distanceM(a, b)
        #expect(abs(d - 111_195) < 50)
    }

    @Test func haversineIsSymmetricAndZeroOnIdentity() {
        let a = Coordinate(lat: 37.77, lon: -122.45)
        let b = Coordinate(lat: 37.78, lon: -122.44)
        #expect(Geo.distanceM(a, a) == 0)
        #expect(abs(Geo.distanceM(a, b) - Geo.distanceM(b, a)) < 1e-9)
    }

    @Test func cumulativeDistancesStartAtZeroAndIncrease() {
        let line = [
            Coordinate(lat: 37.77, lon: -122.45),
            Coordinate(lat: 37.771, lon: -122.45),
            Coordinate(lat: 37.772, lon: -122.449),
        ]
        let cums = Geo.cumulativeDistances(line)
        #expect(cums.count == 3)
        #expect(cums[0] == 0)
        #expect(cums[1] > 0)
        #expect(cums[2] > cums[1])
    }

    @Test func projectionOntoStraightLine() {
        // A ~1113m line straight north; project a point alongside its midpoint.
        let line = [Coordinate(lat: 0, lon: 0), Coordinate(lat: 0.01, lon: 0)]
        let total = Geo.cumulativeDistances(line)[1]
        let midOffEast = Coordinate(lat: 0.005, lon: 0.0001) // ~11m east of midpoint
        let p = Geo.project(midOffEast, onto: line)
        #expect(abs(p.distanceAlongM - total / 2) < 1)
        #expect(abs(p.offsetM - 11.1) < 0.5)
    }

    @Test func projectionClampsBeforeStartAndAfterFinish() {
        let line = [Coordinate(lat: 0, lon: 0), Coordinate(lat: 0.01, lon: 0)]
        let total = Geo.cumulativeDistances(line)[1]
        let before = Geo.project(Coordinate(lat: -0.001, lon: 0), onto: line)
        #expect(before.distanceAlongM == 0)
        #expect(abs(before.offsetM - 111.2) < 1)
        let after = Geo.project(Coordinate(lat: 0.011, lon: 0), onto: line)
        #expect(abs(after.distanceAlongM - total) < 0.001)
    }

    @Test func projectionPicksTheNearestEdgeOnAnLShapedCourse() {
        // North then east. A point close to the eastbound leg must map there,
        // not onto the northbound leg.
        let line = [
            Coordinate(lat: 0, lon: 0),
            Coordinate(lat: 0.01, lon: 0),
            Coordinate(lat: 0.01, lon: 0.01),
        ]
        let cums = Geo.cumulativeDistances(line)
        let nearSecondLeg = Coordinate(lat: 0.0101, lon: 0.005)
        let p = Geo.project(nearSecondLeg, onto: line, cumulative: cums)
        #expect(p.distanceAlongM > cums[1], "must land on the second leg")
        #expect(p.offsetM < 15)
    }
}
