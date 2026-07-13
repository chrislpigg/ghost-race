import Foundation
import Observation
import GhostRaceKit

/// Orchestrates a race from GPS fix to audio cue. One code path for both
/// modes: in ghost mode the opponent's points are preloaded; in live mode
/// they stream in from the WebSocket and everything else is identical.
@Observable
@MainActor
final class RaceViewModel {
    enum Mode {
        /// Race a stored effort. `challengeToken` set when this ghost came
        /// from a challenge link, so the result gets reported back.
        case ghost(GhostEffort, challengeToken: String?)
        /// Race a live rival through a server room.
        case live(raceId: String)
    }

    enum Phase: Equatable {
        case idle
        case waitingForOpponent      // live: waiting for the rival to join/ready
        case headingToStart          // ghost: walk into the start gate to begin
        case countdown(startAt: Date)
        case racing
        case finished(won: Bool, myTimeS: Double, summary: String)
        case aborted(String)
    }

    let mode: Mode
    let segment: SegmentTrack
    let opponentName: String

    private(set) var phase: Phase = .idle
    private(set) var snapshot: RaceSnapshot?
    private(set) var statusLine: String = ""

    /// The room id to share with your rival while waiting (live mode only).
    var liveRaceId: String? {
        if case .live(let raceId) = mode { return raceId }
        return nil
    }

    private let api: APIClient
    private let recorder: LocationRecorder
    private let audio: AudioCueEngine
    private let haptics: HapticEngine

    private var engine: GhostEngine
    private var scheduler: RaceCueScheduler
    private var startGate: GateDetector
    private var raceStartedAt: Date?
    private var startedAtWallClock: Date?
    private var liveClient: LiveRaceClient?
    private var myUserId: String?
    private var uploadedPoints: [EffortPoint] = []
    private var finishedLocally = false

    init(
        mode: Mode,
        segment: TrackInput,
        opponentName: String,
        api: APIClient,
        recorder: LocationRecorder,
        audio: AudioCueEngine,
        haptics: HapticEngine
    ) {
        self.mode = mode
        self.segment = segment.track
        self.opponentName = opponentName
        self.api = api
        self.recorder = recorder
        self.audio = audio
        self.haptics = haptics

        switch mode {
        case .ghost(let ghost, _):
            self.engine = GhostEngine(courseDistanceM: segment.track.distanceM, ghost: ghost)
        case .live:
            self.engine = GhostEngine(courseDistanceM: segment.track.distanceM, opponentPoints: [])
        }
        self.scheduler = RaceCueScheduler(opponentName: opponentName)
        self.startGate = GateDetector(
            gate: segment.track.start,
            radiusM: segment.track.gateRadiusM,
            startsInsideGate: false
        )
    }

    /// Wraps APIClient.Segment / SegmentTrack construction so views can pass either.
    struct TrackInput {
        let track: SegmentTrack
        init(_ apiSegment: APIClient.Segment) {
            track = SegmentTrack(
                id: apiSegment.id,
                name: apiSegment.name,
                activityType: apiSegment.activityType,
                polyline: apiSegment.polyline,
                gateRadiusM: apiSegment.gateRadiusM
            )
        }
        init(track: SegmentTrack) { self.track = track }
    }

    // MARK: - Lifecycle

    func begin() {
        audio.activate()
        recorder.activityType = segment.activityType
        recorder.onFix = { [weak self] fix in self?.handle(fix: fix) }
        recorder.start()

        switch mode {
        case .ghost:
            phase = .headingToStart
            statusLine = "Head to the start of \(segment.name)"
        case .live(let raceId):
            phase = .waitingForOpponent
            statusLine = "Waiting for \(opponentName)…"
            connectLive(raceId: raceId)
        }
    }

    func cancel() {
        recorder.stop()
        liveClient?.close()
        audio.deactivate()
        if case .finished = phase {} else { phase = .aborted("Race cancelled") }
    }

    // MARK: - GPS fixes drive everything

    private func handle(fix: LocationRecorder.Fix) {
        switch phase {
        case .headingToStart:
            var gate = startGate
            if gate.update(position: fix.coordinate) {
                startRaceClock(at: fix.timestamp)
                audio.perform([.play(.startBeep), .say("Go! Racing \(opponentName).")], haptics: haptics)
            }
            startGate = gate
        case .countdown(let startAt):
            if fix.timestamp >= startAt {
                phase = .racing
                tick(fix: fix)
            }
        case .racing:
            tick(fix: fix)
        default:
            break
        }
    }

    private func startRaceClock(at date: Date) {
        raceStartedAt = date
        startedAtWallClock = Date()
        phase = .racing
    }

    private func tick(fix: LocationRecorder.Fix) {
        guard let startedAt = raceStartedAt, !finishedLocally else { return }
        let elapsed = fix.timestamp.timeIntervalSince(startedAt)
        guard elapsed >= 0 else { return }

        let projection = Geo.project(fix.coordinate, onto: segment.polyline, cumulative: segment.cumulative)
        let myDistance = min(projection.distanceAlongM, segment.distanceM)
        uploadedPoints.append(EffortPoint(t: elapsed, d: myDistance))

        if case .live = mode {
            liveClient?.sendPosition(t: elapsed, d: myDistance)
        }

        let (snapshot, events) = engine.tick(elapsedS: elapsed, myDistanceM: myDistance)
        self.snapshot = snapshot
        let cues = scheduler.cues(for: snapshot, events: events)
        if !cues.isEmpty { audio.perform(cues, haptics: haptics) }

        for event in events {
            if case .finished(let won, let myTimeS) = event {
                finishedLocally = true
                Task { await self.completeRace(won: won, myTimeS: myTimeS) }
            }
        }
    }

    // MARK: - Finishing

    private func completeRace(won: Bool, myTimeS: Double) async {
        recorder.stop()
        let timeText = RaceCueScheduler.formatDuration(myTimeS)

        switch mode {
        case .ghost(let ghost, let challengeToken):
            var summary = won
                ? "You beat \(opponentName) by \(RaceCueScheduler.formatDuration(ghost.durationS - myTimeS))."
                : "\(opponentName) won by \(RaceCueScheduler.formatDuration(myTimeS - ghost.durationS))."
            if let token = challengeToken {
                do {
                    _ = try await api.completeChallenge(
                        token: token,
                        startedAt: startedAtWallClock ?? Date(),
                        durationS: myTimeS,
                        points: uploadedPoints
                    )
                } catch {
                    summary += " (Couldn't report the result — it will not count until you're back online.)"
                }
            }
            phase = .finished(won: won, myTimeS: myTimeS, summary: "Finished in \(timeText). \(summary)")
        case .live:
            liveClient?.finish(durationS: myTimeS)
            // The authoritative result arrives over the socket; show the
            // local verdict meanwhile.
            phase = .finished(won: won, myTimeS: myTimeS, summary: "Finished in \(timeText). Waiting for official result…")
        }
    }

    // MARK: - Live mode plumbing

    private func connectLive(raceId: String) {
        guard let url = try? api.webSocketURL() else {
            phase = .aborted("Bad server URL")
            return
        }
        let client = LiveRaceClient(url: url, raceId: raceId, deviceToken: api.deviceToken)
        liveClient = client
        client.onEvent = { [weak self] event in self?.handleLive(event: event) }
        client.connect()
    }

    private func handleLive(event: LiveRaceClient.Event) {
        switch event {
        case .joined(let you, let peers):
            myUserId = you
            if peers.count == 2 { statusLine = "Both racers in. Get ready!" }
            liveClient?.ready()
        case .peerJoined:
            statusLine = "\(opponentName) is here. Get ready!"
            liveClient?.ready()
        case .countdown(let startAt, let serverNow):
            // Correct for clock skew between phone and server.
            let skew = Date().timeIntervalSince(serverNow)
            let localStart = startAt.addingTimeInterval(skew)
            raceStartedAt = localStart
            startedAtWallClock = localStart
            phase = .countdown(startAt: localStart)
            audio.perform([.play(.startBeep), .say("Race starts in \(Int(max(0, localStart.timeIntervalSinceNow.rounded()))) seconds.")], haptics: nil)
        case .opponentPosition(let point):
            engine.updateOpponent(point)
        case .opponentFinished(let durationS):
            engine.updateOpponent(EffortPoint(t: durationS, d: segment.distanceM))
        case .result(let winnerId, let reason, _):
            let mine = myUserId
            let won = mine != nil ? winnerId == mine : {
                if case .finished(let localWon, _, _) = phase { return localWon }
                return false
            }()
            let note = reason == "dnf" ? " (\(opponentName) dropped out.)" : ""
            if case .finished(_, let myTimeS, _) = phase {
                phase = .finished(won: won, myTimeS: myTimeS, summary: "Official: \(won ? "you win!" : "\(opponentName) wins.")\(note)")
            }
        case .opponentDisconnected(let graceMs):
            statusLine = "\(opponentName) lost connection — \(Int(graceMs / 1000))s grace."
            audio.perform([.say("\(opponentName) lost connection.")], haptics: nil)
        case .opponentReconnected:
            statusLine = "\(opponentName) is back."
        case .error(let message):
            phase = .aborted(message)
        case .socketClosed:
            if case .finished = phase {} else if case .aborted = phase {} else {
                phase = .aborted("Connection to the race server was lost.")
            }
        }
    }
}
