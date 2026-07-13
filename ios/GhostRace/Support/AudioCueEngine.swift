import AVFoundation
import Foundation
import GhostRaceKit

/// Speaks announcements and plays synthesized tone cues over the athlete's
/// own music (ducking, never interrupting). Tones are generated in code —
/// no bundled audio assets needed for the MVP.
@MainActor
final class AudioCueEngine {
    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let tonePlayer = AVAudioPlayerNode()
    private var configured = false

    /// Note sequences per tone: (frequencyHz, durationS) pairs.
    private static let toneScores: [Tone: [(Double, Double)]] = [
        .startBeep: [(880, 0.15)],
        .leadJingle: [(523, 0.12), (659, 0.12), (784, 0.12), (1047, 0.25)], // C E G C — triumphant
        .behindWarning: [(330, 0.2), (0, 0.08), (330, 0.2)],                // low double-buzz
        .finalStretch: [(660, 0.1), (0, 0.06), (660, 0.1), (0, 0.06), (880, 0.18)],
        .winFanfare: [(523, 0.15), (659, 0.15), (784, 0.15), (1047, 0.4), (784, 0.12), (1047, 0.5)],
        .loseTrombone: [(392, 0.25), (370, 0.25), (349, 0.25), (330, 0.6)], // descending womp
    ]

    func activate() {
        guard !configured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // duckOthers: the athlete's music dips while we speak, then
            // recovers. mixWithOthers alone would bury speech under music.
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)

            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            engine.attach(tonePlayer)
            engine.connect(tonePlayer, to: engine.mainMixerNode, format: format)
            try engine.start()
            configured = true
        } catch {
            // Audio failing must never take the race down; cues just go silent.
        }
    }

    func deactivate() {
        synthesizer.stopSpeaking(at: .immediate)
        tonePlayer.stop()
        engine.stop()
        configured = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func perform(_ cues: [Cue], haptics: HapticEngine?) {
        activate()
        for cue in cues {
            switch cue {
            case .say(let text):
                speak(text)
            case .play(let tone):
                play(tone)
            case .haptic(let pattern):
                haptics?.play(pattern)
            }
        }
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)
    }

    private func play(_ tone: Tone) {
        guard configured, let score = Self.toneScores[tone] else { return }
        let sampleRate = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let totalFrames = AVAudioFrameCount(score.reduce(0) { $0 + $1.1 } * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
              let samples = buffer.floatChannelData?[0]
        else { return }

        var frame = 0
        for (frequency, duration) in score {
            let frames = Int(duration * sampleRate)
            for i in 0..<frames {
                if frequency == 0 {
                    samples[frame] = 0 // rest
                } else {
                    let t = Double(i) / sampleRate
                    // Quick fade in/out per note to avoid clicks.
                    let envelope = min(1, min(Double(i), Double(frames - i)) / (0.01 * sampleRate))
                    samples[frame] = Float(sin(2 * .pi * frequency * t) * 0.4 * envelope)
                }
                frame += 1
            }
        }
        buffer.frameLength = AVAudioFrameCount(frame)
        if !tonePlayer.isPlaying { tonePlayer.play() }
        tonePlayer.scheduleBuffer(buffer)
    }
}
