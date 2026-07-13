import SwiftUI
import GhostRaceKit

/// Record an effort; on save it becomes a segment + your first effort on it —
/// the thing you challenge friends with.
struct RecordView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recorder: LocationRecorder

    @State private var activityType: ActivityType = .run
    @State private var startedAt: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var distanceM: Double = 0
    @State private var segmentName = ""
    @State private var saving = false
    @State private var saveError: String?
    @State private var showingSave = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.grAsphalt.ignoresSafeArea()
                VStack(spacing: 32) {
                    if startedAt == nil {
                        Picker("Activity", selection: $activityType) {
                            Text("🏃 Run").tag(ActivityType.run)
                            Text("🚴 Ride").tag(ActivityType.ride)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    Spacer()
                    VStack(spacing: 10) {
                        Text(RaceCueScheduler.formatDuration(elapsed))
                            .font(GRFont.instrument(64, weight: .heavy))
                            .foregroundStyle(Color.grChalk)
                        Text("\(Int(distanceM)) m")
                            .font(GRFont.instrument(20, weight: .medium))
                            .foregroundStyle(Color.grMuted)
                        gpsChip
                            .padding(.top, 4)
                    }
                    Spacer()

                    if startedAt == nil {
                        Button {
                            recorder.activityType = activityType
                            recorder.requestPermission()
                            recorder.start()
                            startedAt = Date()
                        } label: {
                            Text("Start")
                        }
                        .buttonStyle(BlazeButtonStyle())
                        .padding(.horizontal)
                    } else {
                        Button {
                            recorder.stop()
                            showingSave = true
                        } label: {
                            Text("Finish")
                        }
                        .buttonStyle(StopButtonStyle())
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if startedAt == nil {
                        Text("Record").grLabel(size: 11, tracking: 3, color: .grChalk)
                    } else {
                        HStack(spacing: 7) {
                            Circle().fill(Color.grBlaze).frame(width: 8, height: 8)
                            Text("Rec").grLabel(size: 11, tracking: 3, color: .grBlaze)
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.stop()
                        dismiss()
                    }
                }
            }
            .toolbarBackground(Color.grAsphalt, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onReceive(timer) { _ in
                guard let startedAt else { return }
                elapsed = Date().timeIntervalSince(startedAt)
                let (_, distance) = recorder.makePolyline()
                distanceM = distance
            }
            .alert("Save segment", isPresented: $showingSave) {
                TextField("Segment name", text: $segmentName)
                Button("Save") { Task { await save() } }
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("Name this segment so your rivals know what they're up against.")
            }
            .alert("Couldn't save", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .interactiveDismissDisabled(startedAt != nil)
        }
        .tint(.grBlaze)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var gpsChip: some View {
        if let fix = recorder.latestFix {
            let good = fix.horizontalAccuracyM <= 10
            HStack(spacing: 6) {
                Circle().fill(good ? Color.grOK : Color.grWarn).frame(width: 6, height: 6)
                Text("GPS ±\(Int(fix.horizontalAccuracyM)) M").grLabel(size: 10, tracking: 1.5, color: good ? .grOK : .grWarn)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(Capsule().stroke((good ? Color.grOK : Color.grWarn).opacity(0.4), lineWidth: 1))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "location.slash").font(.system(size: 10))
                Text("Acquiring GPS…").grLabel(size: 10, tracking: 1.5, color: .grMuted)
            }
            .foregroundStyle(Color.grMuted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(Capsule().stroke(Color.grLine, lineWidth: 1))
        }
    }

    private func save() async {
        guard let startedAt else { return }
        saving = true
        defer { saving = false }
        do {
            let (polyline, distance) = recorder.makePolyline()
            guard polyline.count >= 2, distance > 50 else {
                saveError = "Not enough movement recorded to make a raceable segment (need at least 50 m)."
                return
            }
            let name = segmentName.isEmpty
                ? "\(activityType == .run ? "Run" : "Ride") \(Date().formatted(date: .abbreviated, time: .shortened))"
                : segmentName
            let segment = try await model.api.createSegment(
                name: name,
                activityType: activityType,
                polyline: polyline,
                distanceM: distance
            )
            let track = SegmentTrack(
                id: segment.id,
                name: segment.name,
                activityType: segment.activityType,
                polyline: segment.polyline,
                gateRadiusM: segment.gateRadiusM
            )
            let points = recorder.makeEffortPoints(for: track, startedAt: startedAt)
            let duration = points.last?.t ?? elapsed
            _ = try await model.api.createEffort(
                segmentId: segment.id,
                startedAt: startedAt,
                durationS: duration,
                points: points
            )
            await model.refresh()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
