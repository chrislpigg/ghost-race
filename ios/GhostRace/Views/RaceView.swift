import SwiftUI
import GhostRaceKit

/// The in-race screen. Designed for glances (handlebar mount, mid-stride):
/// one huge delta number, a track bar with both racers, and color that tells
/// the story before you can read anything.
struct RaceView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: RaceViewModel

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            switch viewModel.phase {
            case .idle, .waitingForOpponent, .headingToStart:
                preRace
            case .countdown(let startAt):
                CountdownView(startAt: startAt)
            case .racing:
                hud
            case .finished(let won, _, let summary):
                ResultView(won: won, summary: summary, opponentName: viewModel.opponentName) {
                    dismiss()
                }
            case .aborted(let reason):
                VStack(spacing: 16) {
                    Image(systemName: "flag.slash").font(.system(size: 48))
                    Text(reason).multilineTextAlignment(.center)
                    Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .onAppear { viewModel.begin() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Quit") {
                    viewModel.cancel()
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var background: Color {
        guard case .racing = viewModel.phase, let snapshot = viewModel.snapshot else {
            return Color(.systemBackground)
        }
        // Ahead: deep green. Behind: dark red. Instantly readable at a glance.
        return snapshot.iAmAhead
            ? Color(red: 0.02, green: 0.25, blue: 0.1)
            : Color(red: 0.3, green: 0.05, blue: 0.05)
    }

    private var preRace: some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large)
            Text(statusText).font(.title3).multilineTextAlignment(.center)
            if case .waitingForOpponent = viewModel.phase, let raceId = viewModel.liveRaceId {
                VStack(spacing: 8) {
                    Text("Race ID").font(.caption.bold()).tracking(2).foregroundStyle(.secondary)
                    Text(raceId)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    if let link = URL(string: "ghostrace://race/\(raceId)") {
                        ShareLink(
                            item: link,
                            message: Text("Race me right now on GhostRace! 🏁")
                        ) {
                            Label("Invite your rival", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }

    private var statusText: String {
        switch viewModel.phase {
        case .headingToStart: return "Head to the start line.\nThe race begins the moment you cross it."
        case .waitingForOpponent: return viewModel.statusLine
        default: return viewModel.statusLine
        }
    }

    private var hud: some View {
        VStack(spacing: 24) {
            Spacer()

            if let snapshot = viewModel.snapshot {
                // The big number: gap in seconds when known, meters otherwise.
                VStack(spacing: 4) {
                    Text(gapHeadline(snapshot))
                        .font(.system(size: 88, weight: .black, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(snapshot.iAmAhead ? "AHEAD" : "BEHIND")
                        .font(.title3.bold())
                        .tracking(4)
                        .opacity(0.8)
                }
                .foregroundStyle(.white)

                TrackBar(snapshot: snapshot, opponentName: viewModel.opponentName)
                    .padding(.horizontal)

                HStack(spacing: 40) {
                    stat("TIME", RaceCueScheduler.formatDuration(snapshot.elapsedS))
                    stat("PACE", paceText(snapshot))
                    stat("TO GO", "\(Int(snapshot.remainingM)) m")
                }
                .foregroundStyle(.white.opacity(0.9))
            } else {
                ProgressView().tint(.white)
            }

            Spacer()
            if !viewModel.statusLine.isEmpty {
                Text(viewModel.statusLine)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding()
    }

    private func gapHeadline(_ snapshot: RaceSnapshot) -> String {
        if let gapS = snapshot.gapS {
            return String(format: "%+.0fs", gapS)
        }
        return String(format: "%+.0fm", snapshot.gapM)
    }

    private func paceText(_ snapshot: RaceSnapshot) -> String {
        guard let speed = snapshot.mySpeedMps, speed > 0.3 else { return "—" }
        if viewModel.segment.activityType == .ride {
            return String(format: "%.1f km/h", speed * 3.6)
        }
        let secondsPerKm = 1000 / speed
        return "\(RaceCueScheduler.formatDuration(secondsPerKm)) /km"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2.bold()).tracking(2).opacity(0.6)
            Text(value).font(.title3.monospacedDigit().bold())
        }
    }
}

/// The Mario Kart strip: both racers as dots progressing along the course.
struct TrackBar: View {
    let snapshot: RaceSnapshot
    let opponentName: String

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: 6)
                // Finish flag.
                Text("🏁")
                    .offset(x: width - 24, y: -22)

                racerDot("🟠", name: opponentName, fraction: fraction(snapshot.opponentDistanceM), width: width, above: false)
                racerDot("🔵", name: "You", fraction: fraction(snapshot.myDistanceM), width: width, above: true)
            }
        }
        .frame(height: 72)
    }

    private func fraction(_ d: Double) -> Double {
        snapshot.courseDistanceM > 0 ? min(1, max(0, d / snapshot.courseDistanceM)) : 0
    }

    private func racerDot(_ emoji: String, name: String, fraction: Double, width: CGFloat, above: Bool) -> some View {
        VStack(spacing: 2) {
            if above {
                Text(name).font(.caption2.bold()).foregroundStyle(.white)
                Text(emoji).font(.title3)
            } else {
                Text(emoji).font(.title3)
                Text(name).font(.caption2.bold()).foregroundStyle(.white.opacity(0.8))
            }
        }
        .position(x: max(16, min(width - 16, width * fraction)), y: above ? 8 : 56)
        .animation(.easeInOut(duration: 0.8), value: fraction)
    }
}

struct CountdownView: View {
    let startAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = startAt.timeIntervalSince(context.date)
            VStack(spacing: 12) {
                if remaining > 0 {
                    Text("\(Int(remaining.rounded(.up)))")
                        .font(.system(size: 140, weight: .black, design: .rounded))
                        .contentTransition(.numericText(countsDown: true))
                    Text("GET READY").font(.title3.bold()).tracking(6).opacity(0.7)
                } else {
                    Text("GO!")
                        .font(.system(size: 120, weight: .black, design: .rounded))
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

struct ResultView: View {
    let won: Bool
    let summary: String
    let opponentName: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(won ? "🏆" : "😤").font(.system(size: 96))
            Text(won ? "Victory!" : "Defeat")
                .font(.largeTitle.black())
            Text(summary)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if !won {
                Text("Rematch and take it back.")
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }
            Button(won ? "Rub it in later" : "Done") { onDone() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}
