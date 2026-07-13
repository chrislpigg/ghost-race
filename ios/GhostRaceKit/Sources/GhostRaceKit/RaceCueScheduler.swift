import Foundation

public enum Tone: String, Equatable, Sendable {
    case startBeep
    case leadJingle
    case behindWarning
    case finalStretch
    case winFanfare
    case loseTrombone
}

public enum HapticPattern: String, Equatable, Sendable {
    case overtake
    case overtaken
}

/// A concrete instruction for the device: speak, play a tone, or buzz.
public enum Cue: Equatable, Sendable {
    case say(String)
    case play(Tone)
    case haptic(HapticPattern)
}

/// Turns raw race snapshots and events into a paced stream of cues.
///
/// Design goals: lead changes and the finish always cue immediately; routine
/// gap updates are rate-limited so the athlete isn't nagged every second; the
/// cadence tightens in the final stretch to build Mario Kart-style tension.
public struct RaceCueScheduler: Sendable {
    public let opponentName: String
    public let announceIntervalS: Double
    public let finalStretchIntervalS: Double
    public let minQuietS: Double

    private var lastCueAtS: Double = -.greatestFiniteMagnitude
    private var lastGapAnnounceAtS: Double = -.greatestFiniteMagnitude
    private var inFinalStretch = false
    private var raceOver = false

    public init(
        opponentName: String,
        announceIntervalS: Double = 30,
        finalStretchIntervalS: Double = 15,
        minQuietS: Double = 8
    ) {
        self.opponentName = opponentName
        self.announceIntervalS = announceIntervalS
        self.finalStretchIntervalS = finalStretchIntervalS
        self.minQuietS = minQuietS
    }

    public mutating func cues(for snapshot: RaceSnapshot, events: [RaceEvent]) -> [Cue] {
        guard !raceOver else { return [] }
        var out: [Cue] = []

        for event in events {
            switch event {
            case .tookLead:
                out.append(.play(.leadJingle))
                out.append(.haptic(.overtake))
                out.append(.say("You took the lead from \(opponentName)!"))
            case .lostLead:
                out.append(.play(.behindWarning))
                out.append(.haptic(.overtaken))
                out.append(.say("\(opponentName) just passed you!"))
            case .finalStretch:
                inFinalStretch = true
                out.append(.play(.finalStretch))
                out.append(.say("Final stretch! \(Self.roundedMeters(snapshot.remainingM)) meters to go."))
            case .finished(let won, let myTimeS):
                raceOver = true
                out.append(.play(won ? .winFanfare : .loseTrombone))
                let time = Self.formatDuration(myTimeS)
                out.append(.say(won
                    ? "Finished in \(time). You beat \(opponentName)!"
                    : "Finished in \(time). \(opponentName) takes this one."))
            }
        }

        if !out.isEmpty {
            lastCueAtS = snapshot.elapsedS
            lastGapAnnounceAtS = snapshot.elapsedS
            return out
        }

        // Routine gap update, rate-limited.
        let interval = inFinalStretch ? finalStretchIntervalS : announceIntervalS
        guard snapshot.elapsedS - lastGapAnnounceAtS >= interval,
              snapshot.elapsedS - lastCueAtS >= minQuietS
        else { return [] }

        lastCueAtS = snapshot.elapsedS
        lastGapAnnounceAtS = snapshot.elapsedS
        return [.say(Self.gapPhrase(snapshot: snapshot, opponentName: opponentName))]
    }

    // MARK: - Phrasing

    static func gapPhrase(snapshot: RaceSnapshot, opponentName: String) -> String {
        let ahead = snapshot.iAmAhead
        if let gapS = snapshot.gapS, abs(gapS) >= 2 {
            let seconds = Int(abs(gapS).rounded())
            return ahead
                ? "You're \(seconds) seconds ahead of \(opponentName)."
                : "You're \(seconds) seconds behind \(opponentName)."
        }
        let meters = Self.roundedMeters(abs(snapshot.gapM))
        if meters == 0 { return "Neck and neck with \(opponentName)!" }
        return ahead
            ? "You're \(meters) meters ahead of \(opponentName)."
            : "You're \(meters) meters behind \(opponentName)."
    }

    /// Round to something a human wants read aloud: nearest 5 under 100m,
    /// nearest 10 beyond.
    static func roundedMeters(_ meters: Double) -> Int {
        let m = abs(meters)
        let step = m < 100 ? 5.0 : 10.0
        return Int((m / step).rounded() * step)
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
