import SwiftUI
import GhostRaceKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var recorder = LocationRecorder()
    @State private var showingRecord = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.grAsphalt.ignoresSafeArea()
                content
            }
            .navigationDestination(for: String.self) { segmentId in
                if let segment = model.segments.first(where: { $0.id == segmentId }) {
                    SegmentDetailView(segment: segment, recorder: recorder)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { GhostWordmark(size: 19) }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(Color.grMuted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingRecord = true } label: {
                        Image(systemName: "record.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.grBlaze)
                    }
                }
            }
            .toolbarBackground(Color.grAsphalt, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .refreshable { await model.refresh() }
            .fullScreenCover(isPresented: $showingRecord) {
                RecordView(recorder: recorder)
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: challengeTokenBinding) { token in
                ChallengeAcceptView(token: token.value, recorder: recorder)
            }
            .sheet(item: raceIdBinding) { raceId in
                JoinRaceView(raceId: raceId.value, recorder: recorder)
            }
            .overlay {
                if !model.isOnboarded { OnboardingView() }
            }
        }
        .tint(.grBlaze)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let error = model.registrationError {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.grWarn)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.grWarn.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.grWarn.opacity(0.3), lineWidth: 1))
                        .padding(.bottom, 6)
                }

                if !model.rivals.isEmpty {
                    Text("Rivalries").grLabel(size: 11, tracking: 3).padding(.top, 4)
                    ForEach(model.rivals) { rival in
                        RivalRow(rival: rival)
                    }
                }

                Text("My segments").grLabel(size: 11, tracking: 3).padding(.top, 12)
                if model.segments.isEmpty {
                    emptySegments
                }
                ForEach(model.segments) { segment in
                    NavigationLink(value: segment.id) {
                        SegmentRow(segment: segment)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }

    private var emptySegments: some View {
        VStack(alignment: .leading, spacing: 12) {
            GhostMark(size: 54, stroke: .grIceDim, lineWidth: 1.4).opacity(0.7)
            Text("Record a run or ride to create your first segment — then challenge a friend to beat it.")
                .font(.system(size: 15))
                .foregroundStyle(Color.grMuted)
            Button {
                showingRecord = true
            } label: {
                Label("Record a segment", systemImage: "record.circle")
            }
            .buttonStyle(BlazeButtonStyle())
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.grPanelDeep, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.grLine, lineWidth: 1))
    }

    private var challengeTokenBinding: Binding<TokenBox?> {
        Binding(
            get: { model.pendingChallengeToken.map(TokenBox.init) },
            set: { model.pendingChallengeToken = $0?.value }
        )
    }

    private var raceIdBinding: Binding<TokenBox?> {
        Binding(
            get: { model.pendingRaceId.map(TokenBox.init) },
            set: { model.pendingRaceId = $0?.value }
        )
    }
}

struct RivalRow: View {
    let rival: APIClient.RivalRecord

    private var leading: Bool { rival.wins >= rival.losses }

    var body: some View {
        PanelCard(accent: leading ? .grBlaze : .grLoss) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rival.rivalName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.grChalk)
                    Text(seriesText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.grMuted)
                }
                Spacer()
                Text("\(rival.wins)–\(rival.losses)")
                    .font(GRFont.instrument(22, weight: .heavy))
                    .foregroundStyle(leading ? Color.grOK : Color.grLoss)
            }
        }
    }

    private var seriesText: String {
        if rival.wins > rival.losses { return "You lead the series" }
        if rival.wins < rival.losses { return "\(rival.rivalName) leads the series" }
        return "Series tied"
    }
}

struct SegmentRow: View {
    let segment: APIClient.Segment

    var body: some View {
        HStack(spacing: 12) {
            RouteSilhouette(polyline: segment.polyline, stroke: .grIce, lineWidth: 2.5)
                .frame(width: 52, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(segment.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.grChalk)
                Text("\(segment.activityType == .run ? "RUN" : "RIDE") · \(Int(segment.distanceM)) M")
                    .grLabel(size: 10, tracking: 1.5)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.grLine)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.grPanelDeep, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.grLine, lineWidth: 1))
    }
}

/// Join a live duel someone invited you to: pick which of your segments
/// you'll race on (same segment = a fair head-to-head; different segments =
/// a distance duel), then enter the room.
struct JoinRaceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let raceId: String
    let recorder: LocationRecorder

    @State private var selectedSegmentId: String?
    @State private var activeRace: RaceViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.grAsphalt.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Race ID").grLabel(size: 10, tracking: 2)
                        Spacer()
                        Text(raceId).font(GRFont.instrument(13, weight: .medium)).foregroundStyle(Color.grIce)
                    }
                    .padding(14)
                    .background(Color.grPanel, in: RoundedRectangle(cornerRadius: 12))

                    Text("Race on which segment?").grLabel(size: 11, tracking: 2)
                    if model.segments.isEmpty {
                        Text("You need a recorded segment first — record one, then rejoin with this link.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.grMuted)
                    }
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.segments) { segment in
                                Button { selectedSegmentId = segment.id } label: {
                                    HStack(spacing: 12) {
                                        RouteSilhouette(polyline: segment.polyline, stroke: .grIce, lineWidth: 2.5)
                                            .frame(width: 44, height: 34)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(segment.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.grChalk)
                                            Text("\(Int(segment.distanceM)) M").grLabel(size: 10, tracking: 1.5)
                                        }
                                        Spacer()
                                        if selectedSegmentId == segment.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.grBlaze)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.grPanelDeep, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedSegmentId == segment.id ? Color.grBlaze : Color.grLine, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("Pick the same segment as your rival for a fair duel; any segment works for a distance race.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.grMuted)

                    Button("Race") { join() }
                        .buttonStyle(BlazeButtonStyle())
                        .disabled(selectedSegmentId == nil)
                        .opacity(selectedSegmentId == nil ? 0.5 : 1)
                }
                .padding(20)
            }
            .navigationTitle("Join live duel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { selectedSegmentId = model.segments.first?.id }
            .fullScreenCover(item: $activeRace, onDismiss: { dismiss() }) { race in
                RaceView(viewModel: race)
            }
        }
        .tint(.grBlaze)
        .preferredColorScheme(.dark)
    }

    private func join() {
        guard let segment = model.segments.first(where: { $0.id == selectedSegmentId }) else { return }
        activeRace = RaceViewModel(
            mode: .live(raceId: raceId),
            segment: .init(segment),
            opponentName: "your rival",
            api: model.api,
            recorder: recorder,
            audio: AudioCueEngine(),
            haptics: HapticEngine()
        )
    }
}

/// Identifiable wrapper so a plain token string can drive `.sheet(item:)`.
struct TokenBox: Identifiable {
    let value: String
    var id: String { value }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    var body: some View {
        ZStack {
            Color.grAsphalt.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                GhostMark(size: 96, stroke: .grIce, lineWidth: 1.8, checkerHem: true)
                GhostWordmark(size: 40)
                Text("Race your friends in the real world.\nGhosts, live duels, and bragging rights.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.grMuted)
                TextField("", text: $name, prompt: Text("Your name").foregroundColor(.grMuted))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.grChalk)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(Color.grPanel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.grLine, lineWidth: 1))
                    .padding(.horizontal, 40)
                    .padding(.top, 4)
                Button("Let's race") {
                    model.displayName = name.trimmingCharacters(in: .whitespaces)
                    Task { await model.bootstrap() }
                }
                .buttonStyle(BlazeButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                .padding(.horizontal, 40)
                Spacer()
                CheckerStrip(square: 12).frame(height: 14)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ZStack {
                Color.grAsphalt.ignoresSafeArea()
                Form {
                    Section {
                        TextField("Name", text: $model.displayName)
                    } header: {
                        Text("Profile").grLabel(size: 10, tracking: 2)
                    }
                    .listRowBackground(Color.grPanel)

                    Section {
                        TextField("Server URL", text: $model.serverURL)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    } header: {
                        Text("Server").grLabel(size: 10, tracking: 2)
                    } footer: {
                        Text("For local testing: your Mac's address running `npm run dev`, e.g. http://192.168.1.20:8787")
                            .foregroundStyle(Color.grMuted)
                    }
                    .listRowBackground(Color.grPanel)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task { await model.bootstrap() }
                        dismiss()
                    }
                }
            }
        }
        .tint(.grBlaze)
        .preferredColorScheme(.dark)
    }
}
