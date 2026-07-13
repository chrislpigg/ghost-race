import SwiftUI
import GhostRaceKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var recorder = LocationRecorder()
    @State private var showingRecord = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                if let error = model.registrationError {
                    Section {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                }

                if !model.rivals.isEmpty {
                    Section("Rivals") {
                        ForEach(model.rivals) { rival in
                            RivalRow(rival: rival)
                        }
                    }
                }

                Section("My segments") {
                    if model.segments.isEmpty {
                        Text("Record a run or ride to create your first segment — then challenge a friend to beat it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.segments) { segment in
                        NavigationLink(value: segment.id) {
                            VStack(alignment: .leading) {
                                Text(segment.name).font(.headline)
                                Text("\(segment.activityType == .run ? "🏃" : "🚴") \(Int(segment.distanceM)) m")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("GhostRace")
            .navigationDestination(for: String.self) { segmentId in
                if let segment = model.segments.first(where: { $0.id == segmentId }) {
                    SegmentDetailView(segment: segment, recorder: recorder)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingRecord = true
                    } label: {
                        Label("Record", systemImage: "record.circle")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .refreshable { await model.refresh() }
            .fullScreenCover(isPresented: $showingRecord) {
                RecordView(recorder: recorder)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
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
            Form {
                Section {
                    LabeledContent("Race ID") {
                        Text(raceId).font(.footnote.monospaced())
                    }
                }
                Section("Race on which segment?") {
                    if model.segments.isEmpty {
                        Text("You need a recorded segment first — record one, then rejoin with this link.")
                            .foregroundStyle(.secondary)
                    }
                    Picker("Segment", selection: $selectedSegmentId) {
                        ForEach(model.segments) { segment in
                            Text("\(segment.name) (\(Int(segment.distanceM)) m)")
                                .tag(Optional(segment.id))
                        }
                    }
                    .pickerStyle(.inline)
                } footer: {
                    Text("Pick the same segment as your rival for a fair duel; any segment works for a distance race.")
                }
            }
            .navigationTitle("Join live duel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Race") { join() }
                        .disabled(selectedSegmentId == nil)
                }
            }
            .onAppear { selectedSegmentId = model.segments.first?.id }
            .fullScreenCover(item: $activeRace, onDismiss: { dismiss() }) { race in
                RaceView(viewModel: race)
            }
        }
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

struct RivalRow: View {
    let rival: APIClient.RivalRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(rival.rivalName).font(.headline)
                Text(seriesText).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(rival.wins)–\(rival.losses)")
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(rival.wins >= rival.losses ? .green : .red)
        }
    }

    private var seriesText: String {
        if rival.wins > rival.losses { return "You lead the series" }
        if rival.wins < rival.losses { return "\(rival.rivalName) leads the series" }
        return "Series tied"
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("🏁").font(.system(size: 64))
                Text("GhostRace").font(.largeTitle.bold())
                Text("Race your friends in the real world.\nGhosts, live duels, and bragging rights.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 40)
                Button("Let's race") {
                    model.displayName = name.trimmingCharacters(in: .whitespaces)
                    Task { await model.bootstrap() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $model.displayName)
                }
                Section {
                    TextField("Server URL", text: $model.serverURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                } header: {
                    Text("Server")
                } footer: {
                    Text("For local testing: your Mac's address running `npm run dev`, e.g. http://192.168.1.20:8787")
                }
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
    }
}
