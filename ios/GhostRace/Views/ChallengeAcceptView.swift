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
            ZStack {
                Color.grAsphalt.ignoresSafeArea()
                Group {
                    if let details {
                        challengeCard(details)
                    } else if let loadError {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.grWarn)
                            Text(loadError)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.grMuted)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else {
                        VStack(spacing: 14) {
                            ProgressView().tint(.grIce)
                            Text("Loading challenge…").grLabel(size: 11, tracking: 2)
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Challenge").grLabel(size: 11, tracking: 3, color: .grChalk)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }.foregroundStyle(Color.grMuted)
                }
            }
            .toolbarBackground(Color.grAsphalt, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(.grBlaze)
        .preferredColorScheme(.dark)
        .task { await load() }
        .fullScreenCover(item: $activeRace, onDismiss: { dismiss() }) { race in
            RaceView(viewModel: race)
        }
    }

    private func challengeCard(_ details: APIClient.ChallengeDetails) -> some View {
        VStack(spacing: 22) {
            Spacer()
            (Text("\(details.challengerName) ").foregroundStyle(Color.grBlaze)
                + Text("called you out").foregroundStyle(Color.grChalk))
                .font(GRFont.display(30))
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)

            VStack(spacing: 10) {
                RouteSilhouette(polyline: details.segment.polyline, stroke: .grIce, lineWidth: 2.5)
                    .frame(width: 130, height: 48)
                Text(details.segment.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.grChalk)
                Text("\(details.segment.activityType == .run ? "RUN" : "RIDE") · \(Int(details.segment.distanceM)) M")
                    .grLabel(size: 10, tracking: 1.5)
                Text("Time to beat").grLabel(size: 10, tracking: 2.5).padding(.top, 6)
                Text(RaceCueScheduler.formatDuration(details.ghost.durationS))
                    .font(GRFont.instrument(36, weight: .heavy))
                    .foregroundStyle(Color.grChalk)
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(Color.grPanel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.grLine, lineWidth: 1))

            Text("You'll race \(details.challengerName)'s ghost — live audio tells you exactly where they were.")
                .font(.system(size: 13))
                .foregroundStyle(Color.grIceDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Spacer()
            Button {
                Task { await accept(details) }
            } label: {
                Text("Accept & race")
            }
            .buttonStyle(BlazeButtonStyle())
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
