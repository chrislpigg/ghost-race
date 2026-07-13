import SwiftUI
import GhostRaceKit

/// Opened from a ghostrace://challenge/<token> link: shows who challenged you
/// on what, then launches the ghost race. This screen is the whole viral
/// loop — keep it fast and taunting.
struct ChallengeAcceptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let token: String
    let recorder: LocationRecorder

    @State private var details: APIClient.ChallengeDetails?
    @State private var loadError: String?
    @State private var activeRace: RaceViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let details {
                    challengeCard(details)
                } else if let loadError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(loadError).multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ProgressView("Loading challenge…")
                }
            }
            .navigationTitle("Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $activeRace, onDismiss: { dismiss() }) { race in
            RaceView(viewModel: race)
        }
    }

    private func challengeCard(_ details: APIClient.ChallengeDetails) -> some View {
        VStack(spacing: 24) {
            Text("⚔️").font(.system(size: 72))
            Text("\(details.challengerName) challenged you!")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                Text(details.segment.name).font(.headline)
                Text("\(details.segment.activityType == .run ? "🏃" : "🚴") \(Int(details.segment.distanceM)) m")
                    .foregroundStyle(.secondary)
                Text("Time to beat: \(RaceCueScheduler.formatDuration(details.ghost.durationS))")
                    .font(.title3.monospacedDigit().bold())
                    .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))

            Text("You'll race \(details.challengerName)'s ghost — live audio tells you exactly where they were.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await accept(details) }
            } label: {
                Text("Accept & race")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private func load() async {
        do {
            details = try await model.api.challengeDetails(token: token)
        } catch {
            loadError = "Couldn't load this challenge. It may have expired, or the server is unreachable.\n(\(error.localizedDescription))"
        }
    }

    private func accept(_ details: APIClient.ChallengeDetails) async {
        do {
            _ = try await model.api.acceptChallenge(token: token)
        } catch {
            // Accept is idempotent server-side for the same invitee; racing
            // can proceed even if this errored because it was already accepted.
        }
        let ghost = GhostEffort(
            id: details.ghost.id,
            athleteName: details.challengerName,
            durationS: details.ghost.durationS,
            points: details.ghost.points
        )
        activeRace = RaceViewModel(
            mode: .ghost(ghost, challengeToken: token),
            segment: .init(details.segment),
            opponentName: details.challengerName,
            api: model.api,
            recorder: recorder,
            audio: AudioCueEngine(),
            haptics: HapticEngine()
        )
    }
}
