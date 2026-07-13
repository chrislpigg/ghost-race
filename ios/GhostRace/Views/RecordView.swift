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
                VStack(spacing: 8) {
                    Text(RaceCueScheduler.formatDuration(elapsed))
                        .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                    Text("\(Int(distanceM)) m")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    if let fix = recorder.latestFix {
                        Label("GPS ±\(Int(fix.horizontalAccuracyM))m", systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(fix.horizontalAccuracyM <= 10 ? .green : .orange)
                    } else {
                        Label("Acquiring GPS…", systemImage: "location.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .padding(.horizontal)
                } else {
                    Button {
                        recorder.stop()
                        showingSave = true
                    } label: {
                        Text("Finish")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.stop()
                        dismiss()
                    }
                }
            }
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
