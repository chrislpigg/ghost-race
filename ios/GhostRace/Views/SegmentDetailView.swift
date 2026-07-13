import SwiftUI
import GhostRaceKit

/// A segment's home: race your own ghost, challenge a friend with your best
/// effort, or start a live duel.
struct SegmentDetailView: View {
    @Environment(AppModel.self) private var model
    let segment: APIClient.Segment
    let recorder: LocationRecorder

    @State private var myBestEffort: APIClient.Effort?
    @State private var challengeURL: URL?
    @State private var activeRace: RaceViewModel?
    @State private var creatingLiveRace = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Distance", value: "\(Int(segment.distanceM)) m")
                LabeledContent("Type", value: segment.activityType == .run ? "Run" : "Ride")
                if let effort = myBestEffort {
                    LabeledContent("Your best", value: RaceCueScheduler.formatDuration(effort.durationS))
                }
            }

            Section("Race") {
                if let effort = myBestEffort {
                    Button {
                        startGhostRace(against: effort, name: "your ghost", challengeToken: nil)
                    } label: {
                        Label("Race your ghost", systemImage: "figure.run.circle")
                    }

                    Button {
                        Task { await createChallenge(effortId: effort.id) }
                    } label: {
                        Label("Challenge a friend", systemImage: "person.2.fill")
                    }
                }

                Button {
                    Task { await createLiveRace() }
                } label: {
                    Label(
                        creatingLiveRace ? "Creating race…" : "Start a live duel",
                        systemImage: "bolt.fill"
                    )
                }
                .disabled(creatingLiveRace)
            }
        }
        .navigationTitle(segment.name)
        .task { await loadBestEffort() }
        .sheet(item: $challengeURL) { url in
            ShareChallengeSheet(url: url, segmentName: segment.name)
        }
        .fullScreenCover(item: $activeRace) { race in
            RaceView(viewModel: race)
        }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadBestEffort() async {
        myBestEffort = try? await model.api.listMyEfforts(segmentId: segment.id).first
    }

    private func startGhostRace(against effort: APIClient.Effort, name: String, challengeToken: String?) {
        let ghost = GhostEffort(
            id: effort.id,
            athleteName: name,
            durationS: effort.durationS,
            points: effort.points
        )
        activeRace = RaceViewModel(
            mode: .ghost(ghost, challengeToken: challengeToken),
            segment: .init(segment),
            opponentName: name,
            api: model.api,
            recorder: recorder,
            audio: AudioCueEngine(),
            haptics: HapticEngine()
        )
    }

    private func createChallenge(effortId: String) async {
        do {
            let challenge = try await model.api.createChallenge(effortId: effortId)
            if let urlString = challenge.url, let url = URL(string: urlString) {
                challengeURL = url
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createLiveRace() async {
        creatingLiveRace = true
        defer { creatingLiveRace = false }
        do {
            let room = try await model.api.createRace(segmentId: segment.id)
            activeRace = RaceViewModel(
                mode: .live(raceId: room.raceId),
                segment: .init(segment),
                opponentName: "your rival",
                api: model.api,
                recorder: recorder,
                audio: AudioCueEngine(),
                haptics: HapticEngine()
            )
            // The waiting screen shows the race id with a share button;
            // a proper invite flow rides on push notifications in v2.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

extension RaceViewModel: Identifiable {}

struct ShareChallengeSheet: View {
    let url: URL
    let segmentName: String

    var body: some View {
        VStack(spacing: 20) {
            Text("Throw down the gauntlet")
                .font(.title2.bold())
            Text("Send this link. When they open it in GhostRace, they race your ghost on \(segmentName) — and you'll both see who really owns it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            ShareLink(
                item: url,
                message: Text("I just set a time on \(segmentName). Beat it if you can. 🏁")
            ) {
                Label("Share challenge", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
