import SwiftUI
import GhostRaceKit

/// The in-race screen. Designed for glances (handlebar mount, mid-stride):
/// one huge delta number, a track bar with both racers, and color that tells
/// the story before you can read anything. Arcade energy is spent on exactly
/// three beats — countdown, lead change, finish — and nowhere else.
struct RaceView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: RaceViewModel

    @State private var leadBanner: String?

    private var iAmAhead: Bool { viewModel.snapshot?.iAmAhead ?? true }

    var body: some View {
        ZStack {
            backgroundLayer

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
                abort(reason)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: iAmAhead)
        .onAppear { viewModel.begin() }
        .onChange(of: viewModel.snapshot?.iAmAhead) { old, new in
            guard let old, let new, old != new else { return }
            showLeadBanner(new ? "You took the lead" : "\(viewModel.opponentName) took the lead")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Quit") {
                    viewModel.cancel()
                    dismiss()
                }
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Background

    @ViewBuilder
    private var backgroundLayer: some View {
        switch viewModel.phase {
        case .racing:
            ZStack {
                Color.grAsphalt
                Rectangle().fill(RaceField.ahead).opacity(iAmAhead ? 1 : 0)
                Rectangle().fill(RaceField.behind).opacity(iAmAhead ? 0 : 1)
            }
            .ignoresSafeArea()
        case .finished(let won, _, _):
            Rectangle().fill(won ? RaceField.victory : RaceField.defeat).ignoresSafeArea()
        default:
            Color.grAsphalt.ignoresSafeArea()
        }
    }

    // MARK: Pre-race / waiting

    private var preRace: some View {
        VStack(spacing: 22) {
            GhostMark(size: 84, stroke: .grIce, lineWidth: 1.6)
                .opacity(0.85)
            ProgressView().controlSize(.regular).tint(.grIce)
            Text(statusText)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.grChalk)
                .multilineTextAlignment(.center)

            if case .waitingForOpponent = viewModel.phase, let raceId = viewModel.liveRaceId {
                VStack(spacing: 10) {
                    Text("Race ID").grLabel(size: 10, tracking: 3, color: .grMuted)
                    Text(raceId)
                        .font(GRFont.instrument(13, weight: .medium))
                        .foregroundStyle(Color.grIce)
                        .textSelection(.enabled)
                    if let link = URL(string: "ghostrace://race/\(raceId)") {
                        ShareLink(item: link, message: Text("Race me right now on GhostRace! 🏁")) {
                            Label("Invite your rival", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .buttonStyle(IceButtonStyle())
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(18)
                .background(Color.grPanel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.grLine, lineWidth: 1))
            }
        }
        .padding(28)
    }

    private var statusText: String {
        switch viewModel.phase {
        case .headingToStart:
            return "Head to the start line.\nThe race begins the moment you cross it."
        default:
            return viewModel.statusLine
        }
    }

    // MARK: Racing HUD

    private var hud: some View {
        VStack(spacing: 22) {
            Spacer()

            if let snapshot = viewModel.snapshot {
                VStack(spacing: 6) {
                    if let banner = leadBanner {
                        Text(banner)
                            .font(GRFont.label(12).weight(.heavy))
                            .tracking(2)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.grInk)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.grChalk)
                            .rotationEffect(.degrees(-2))
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                            .padding(.bottom, 6)
                    }
                    Text(gapHeadline(snapshot))
                        .font(GRFont.instrument(80, weight: .heavy))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(snapshot.iAmAhead ? "Ahead" : "Behind")
                        .font(GRFont.display(20))
                        .textCase(.uppercase)
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.85))
                }

                TrackBar(snapshot: snapshot, opponentName: viewModel.opponentName)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                HStack {
                    StatBlock(key: "Time", value: RaceCueScheduler.formatDuration(snapshot.elapsedS), valueColor: .white)
                    Spacer()
                    StatBlock(key: "Pace", value: paceText(snapshot), alignment: .center, valueColor: .white)
                    Spacer()
                    StatBlock(key: "To go", value: "\(Int(snapshot.remainingM)) m", alignment: .trailing, valueColor: .white)
                }
                .padding(.horizontal, 2)
            } else {
                ProgressView().tint(.white)
            }

            Spacer()
            if !viewModel.statusLine.isEmpty {
                Text(viewModel.statusLine)
                    .font(GRFont.label(11))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
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
        return "\(RaceCueScheduler.formatDuration(secondsPerKm))/km"
    }

    private func abort(_ reason: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.slash").font(.system(size: 46)).foregroundStyle(Color.grMuted)
            Text(reason)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.grChalk)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(GhostlineButtonStyle())
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(32)
    }

    private func showLeadBanner(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { leadBanner = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if leadBanner == text {
                withAnimation(.easeOut(duration: 0.4)) { leadBanner = nil }
            }
        }
    }
}

/// The Mario Kart strip: you are a blaze chevron, the opponent is the ghost
/// glyph riding below the line with a dashed trail behind it.
struct TrackBar: View {
    let snapshot: RaceSnapshot
    let opponentName: String

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let youX = clampedX(fraction(snapshot.myDistanceM), width: width)
            let oppX = clampedX(fraction(snapshot.opponentDistanceM), width: width)

            ZStack(alignment: .topLeading) {
                Capsule().fill(.white.opacity(0.22)).frame(height: 5)
                    .position(x: width / 2, y: 40)
                // Start tick + finish checker.
                Rectangle().fill(.white.opacity(0.45)).frame(width: 2, height: 16)
                    .position(x: 1, y: 40)
                CheckerStrip(square: 6).frame(width: 14, height: 22)
                    .position(x: width - 7, y: 34)

                // Opponent ghost, below the line, with a dashed trail.
                Capsule()
                    .stroke(Color.grIce.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                    .frame(width: max(0, oppX - 8), height: 1)
                    .position(x: oppX / 2, y: 42)
                racer(above: false, x: oppX, name: opponentName) {
                    GhostMark(size: 16, stroke: .grIce, lineWidth: 2)
                }
                // You, above the line, blaze chevron.
                racer(above: true, x: youX, name: "You") {
                    RacerChevron().fill(Color.grBlazeHot)
                        .frame(width: 16, height: 18)
                        .shadow(color: .grBlaze.opacity(0.7), radius: 5)
                }
            }
        }
        .frame(height: 76)
    }

    private func fraction(_ d: Double) -> Double {
        snapshot.courseDistanceM > 0 ? min(1, max(0, d / snapshot.courseDistanceM)) : 0
    }

    private func clampedX(_ f: Double, width: CGFloat) -> CGFloat {
        max(16, min(width - 16, width * f))
    }

    private func racer<Glyph: View>(above: Bool, x: CGFloat, name: String, @ViewBuilder glyph: () -> Glyph) -> some View {
        VStack(spacing: 3) {
            if above {
                Text(name).grLabel(size: 9, tracking: 1.5, color: .grBlazeHot)
                glyph()
            } else {
                glyph()
                Text(name).grLabel(size: 9, tracking: 1.5, color: .grIce)
            }
        }
        .position(x: x, y: above ? 12 : 60)
        .animation(.easeInOut(duration: 0.8), value: x)
    }
}

/// Server-synced countdown. A blaze ring drains around the numeral; the whole
/// thing is one of the three arcade moments in the app.
struct CountdownView: View {
    let startAt: Date
    @State private var total: Double = 3

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let remaining = startAt.timeIntervalSince(context.date)
            let fraction = total > 0 ? max(0, min(1, remaining / total)) : 0

            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.grLine, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.grBlaze, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if remaining > 0 {
                        Text("\(Int(remaining.rounded(.up)))")
                            .font(GRFont.instrument(120, weight: .heavy))
                            .foregroundStyle(Color.grChalk)
                            .contentTransition(.numericText(countsDown: true))
                    } else {
                        Text("GO!")
                            .font(GRFont.display(96))
                            .foregroundStyle(Color.grOK)
                    }
                }
                .frame(width: 190, height: 190)

                if remaining > 0 {
                    Text("Get ready")
                        .font(GRFont.display(18))
                        .textCase(.uppercase)
                        .tracking(8)
                        .foregroundStyle(Color.grMuted)
                }
            }
        }
        .onAppear { total = max(0.5, startAt.timeIntervalSinceNow) }
    }
}

struct ResultView: View {
    let won: Bool
    let summary: String
    let opponentName: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            if won {
                CheckerStrip(square: 10)
                    .frame(width: 130, height: 10)
                    .transition(.move(edge: .top))
            } else {
                GhostMark(size: 64, stroke: .grIce, lineWidth: 1.6, smug: true)
            }

            Text(won ? "Victory" : "Defeat")
                .font(GRFont.display(46))
                .textCase(.uppercase)
                .foregroundStyle(Color.grChalk)

            Text(summary)
                .font(.system(size: 15))
                .foregroundStyle(Color.grMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if !won {
                Text("Rematch and take it back.")
                    .font(.system(size: 15, weight: .semibold))
                    .italic()
                    .foregroundStyle(Color.grBlazeHot)
            }

            Spacer()
            Button(won ? "Rub it in later" : "Done") { onDone() }
                .buttonStyle(won ? AnyButtonStyle(BlazeButtonStyle()) : AnyButtonStyle(GhostlineButtonStyle()))
        }
        .padding(32)
    }
}

/// Type-erases a ButtonStyle so a view can pick one at runtime.
struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { config in AnyView(style.makeBody(configuration: config)) }
    }
    func makeBody(configuration: Configuration) -> some View { _makeBody(configuration) }
}
