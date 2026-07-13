import CoreHaptics
import Foundation
import GhostRaceKit

/// Distinct physical signatures for the two moments that matter most:
/// overtaking (rising double-tap) and being overtaken (heavy low rumble).
@MainActor
final class HapticEngine {
    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    func play(_ pattern: HapticPattern) {
        guard let engine else { return }
        let events: [CHHapticEvent]
        switch pattern {
        case .overtake:
            events = [
                tap(at: 0, intensity: 0.6, sharpness: 0.7),
                tap(at: 0.12, intensity: 1.0, sharpness: 0.9),
            ]
        case .overtaken:
            events = [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
                    ],
                    relativeTime: 0,
                    duration: 0.5
                )
            ]
        }
        if let hapticPattern = try? CHHapticPattern(events: events, parameters: []),
           let player = try? engine.makePlayer(with: hapticPattern) {
            try? player.start(atTime: 0)
        }
    }

    private func tap(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }
}
