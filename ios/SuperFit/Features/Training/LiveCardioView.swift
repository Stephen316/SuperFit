import SwiftUI
import SwiftData

/// A live cardio session tracked on the phone.
///
/// Deliberately modest: elapsed time always, GPS distance for outdoor
/// activities, and nothing invented. There's no heart rate here because the
/// phone has no sensor for it — a watch does, and a watch-recorded session
/// imports with heart rate intact through the picker instead.
struct LiveCardioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    let activity: WorkoutActivity

    @State private var location = LocationTracker()
    @State private var startedAt = Date.now
    @State private var elapsed: TimeInterval = 0
    @State private var isPaused = false
    @State private var pausedTotal: TimeInterval = 0
    @State private var pauseStartedAt: Date?
    @State private var showingDiscard = false
    @State private var showingRPE = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
    private var tracksDistance: Bool { activity.usesLocation }

    var body: some View {
        ZStack {
            FeatureBackground()
            VStack(spacing: 24) {
                header
                Spacer()
                elapsedDisplay
                if tracksDistance { distanceDisplay }
                Spacer()
                controls
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .onAppear {
            if tracksDistance { location.start() }
            CardioActivityController.start(activityName: activity.displayName,
                                           effectiveStart: startedAt)
        }
        .onDisappear { location.stop() }
        .onReceive(tick) { _ in
            guard !isPaused else { return }
            elapsed = Date.now.timeIntervalSince(startedAt) - pausedTotal
        }
        .confirmationDialog("Discard this workout?", isPresented: $showingDiscard) {
            Button("Discard", role: .destructive) {
                location.stop()
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Nothing will be saved.")
        }
        .sheet(isPresented: $showingRPE) {
            SessionRPEPrompt { rating in
                saveFinishedWorkout(rpe: rating)
            }
            .presentationDetents([.height(410)])
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: activity.symbolName)
            Text(activity.displayName)
                .font(Theme.font(18, .medium))
            Spacer()
            if tracksDistance {
                Image(systemName: location.hasFix ? "location.fill" : "location.slash")
                    .foregroundStyle(location.hasFix ? Theme.gold : Theme.textSecondary)
            }
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var elapsedDisplay: some View {
        VStack(spacing: 4) {
            Text(timeString(elapsed))
                .font(Theme.font(64, .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text("Elapsed")
                .font(Theme.font(13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var distanceDisplay: some View {
        // Before the first fix, distance is unknown rather than zero. Showing
        // "0.00 km" while the GPS is still searching reads as a measurement.
        if location.hasFix {
            HStack(spacing: 40) {
                stat(distanceString, "Distance")
                stat(paceString, "Pace")
            }
        } else {
            Text("Waiting for GPS…")
                .font(Theme.font(14))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.font(28, .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.font(12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                showingDiscard = true
            } label: {
                Text("Discard")
                    .font(Theme.font(16, .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
            }
            .foregroundStyle(Theme.textSecondary)

            Button {
                togglePause()
            } label: {
                Text(isPaused ? "Resume" : "Pause")
                    .font(Theme.font(16, .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
            }
            .foregroundStyle(Theme.textPrimary)

            Button {
                finish()
            } label: {
                Text("Finish")
                    .font(Theme.font(16, .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.gold)
                    )
            }
            .foregroundStyle(.black)
        }
    }

    private func togglePause() {
        if isPaused {
            if let pauseStartedAt {
                pausedTotal += Date.now.timeIntervalSince(pauseStartedAt)
            }
            pauseStartedAt = nil
            isPaused = false
            if tracksDistance { location.start() }
        } else {
            pauseStartedAt = .now
            isPaused = true
            location.stop()
        }
        syncLiveActivity()
    }

    /// The lock-screen clock is derived from a start date shifted by the paused
    /// total, so it resumes where it stopped without per-second updates.
    private func syncLiveActivity() {
        CardioActivityController.update(
            effectiveStart: startedAt.addingTimeInterval(pausedTotal),
            pausedElapsed: isPaused ? elapsed : nil)
    }

    private func finish() {
        CardioActivityController.end()
        location.stop()
        if isPaused, let pauseStartedAt {
            pausedTotal += Date.now.timeIntervalSince(pauseStartedAt)
        }
        elapsed = max(Date.now.timeIntervalSince(startedAt) - pausedTotal, 0)
        isPaused = true
        showingRPE = true
    }

    private func saveFinishedWorkout(rpe: Int?) {
        let record = WorkoutRecord(startedAt: startedAt,
                                   endedAt: startedAt.addingTimeInterval(max(elapsed, 0)),
                                   activity: activity,
                                   source: .liveSession)
        record.sourceName = "iPhone"
        record.sessionRPE = rpe
        // Only record distance when a fix actually arrived. No fix means the
        // distance is unknown, and storing 0 would make it look measured.
        if tracksDistance, location.hasFix, location.distanceMetres > 0 {
            record.distanceMetres = location.distanceMetres
        }
        context.insert(record)
        try? context.save()

        // Mirror the session into HealthKit so it appears in Apple Health and
        // Fitness. Best-effort: an unauthorised or unavailable store just means
        // the workout stays in SuperFit only. The importer skips our own
        // authored copy on the next sync, so this never doubles the record.
        let write = WorkoutWrite(start: record.startedAt, end: record.endedAt,
                                 activity: record.activity,
                                 activeEnergyKcal: record.activeEnergyKcal > 0
                                     ? record.activeEnergyKcal : nil,
                                 distanceMetres: record.distanceMetres)
        Task { try? await HealthKitManager().saveWorkout(write) }

        showingRPE = false
        dismiss()
    }

    private var distanceString: String {
        let metres = location.distanceMetres
        if units == .metric {
            return String(format: "%.2f km", metres / 1000)
        }
        return String(format: "%.2f mi", metres / 1609.344)
    }

    /// Minutes per kilometre or mile, the way a runner reads pace.
    private var paceString: String {
        let metres = location.distanceMetres
        guard metres > 50, elapsed > 0 else { return "—" }
        let perUnit = units == .metric ? 1000.0 : 1609.344
        let secondsPerUnit = elapsed / (metres / perUnit)
        let minutes = Int(secondsPerUnit) / 60
        let seconds = Int(secondsPerUnit) % 60
        return String(format: "%d:%02d /%@", minutes, seconds, units == .metric ? "km" : "mi")
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(max(interval, 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
