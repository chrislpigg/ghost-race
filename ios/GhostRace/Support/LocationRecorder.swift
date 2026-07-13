import CoreLocation
import Foundation
import GhostRaceKit

/// CoreLocation wrapper that keeps recording with the screen off.
/// Requires `UIBackgroundModes: location` and the always/when-in-use usage
/// strings (both set in project.yml).
@Observable
@MainActor
final class LocationRecorder: NSObject, CLLocationManagerDelegate {
    struct Fix: Sendable {
        let coordinate: Coordinate
        let timestamp: Date
        let horizontalAccuracyM: Double
    }

    private let manager = CLLocationManager()
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var latestFix: Fix?
    private(set) var track: [Fix] = []
    private(set) var isRecording = false

    /// Set before starting; affects GPS filtering.
    var activityType: ActivityType = .run

    /// Fires on every accepted fix while recording.
    var onFix: ((Fix) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        track = []
        isRecording = true
        manager.activityType = activityType == .ride ? .otherNavigation : .fitness
        // Riders move faster; a coarser distance filter saves battery without
        // hurting the ~1 Hz cadence the race engine wants.
        manager.distanceFilter = activityType == .ride ? 5 : 2
        manager.startUpdatingLocation()
    }

    func stop() {
        isRecording = false
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.compactMap { location -> Fix? in
            // Reject junk fixes; 30m is generous enough for urban canyons
            // while keeping the race delta meaningful.
            guard location.horizontalAccuracy > 0, location.horizontalAccuracy <= 30 else { return nil }
            return Fix(
                coordinate: Coordinate(
                    lat: location.coordinate.latitude,
                    lon: location.coordinate.longitude
                ),
                timestamp: location.timestamp,
                horizontalAccuracyM: location.horizontalAccuracy
            )
        }
        guard !fixes.isEmpty else { return }
        Task { @MainActor in
            for fix in fixes {
                self.latestFix = fix
                if self.isRecording {
                    self.track.append(fix)
                    self.onFix?(fix)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS errors are routine outdoors; recording simply resumes
        // with the next good fix.
    }

    // MARK: - Deriving race data from a recorded track

    /// Convert the recorded track into a segment polyline (thinned so the
    /// server payload stays small) plus its measured length.
    func makePolyline(minSpacingM: Double = 10) -> (polyline: [Coordinate], distanceM: Double) {
        var polyline: [Coordinate] = []
        for fix in track {
            if let last = polyline.last, Geo.distanceM(last, fix.coordinate) < minSpacingM {
                continue
            }
            polyline.append(fix.coordinate)
        }
        // Always keep the true finish point.
        if let finalFix = track.last, polyline.last != finalFix.coordinate {
            polyline.append(finalFix.coordinate)
        }
        let distance = Geo.cumulativeDistances(polyline).last ?? 0
        return (polyline, distance)
    }

    /// Convert the recorded track into effort points (t, distance-along) for
    /// a given segment geometry.
    func makeEffortPoints(for segment: SegmentTrack, startedAt: Date) -> [EffortPoint] {
        track.compactMap { fix in
            let t = fix.timestamp.timeIntervalSince(startedAt)
            guard t >= 0 else { return nil }
            let projection = Geo.project(fix.coordinate, onto: segment.polyline, cumulative: segment.cumulative)
            return EffortPoint(t: t, d: projection.distanceAlongM)
        }
    }
}
