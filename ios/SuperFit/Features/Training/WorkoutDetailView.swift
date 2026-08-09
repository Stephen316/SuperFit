import SwiftUI
import SwiftData

/// Everything recorded for one workout.
///
/// Rows appear only when the workout actually has the value. A missing metric is
/// omitted rather than shown as a dash or a zero — the same rule the recovery and
/// sleep views follow, because "0 m elevation" and "no elevation recorded" mean
/// very different things and only one of them is true for a treadmill run.
struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    let workout: WorkoutRecord

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
    private var metrics: WorkoutActivity.Metrics { workout.activity.metrics }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                effortSection
                if !detailRows.isEmpty {
                    Section("Detail") {
                        ForEach(detailRows, id: \.label) { row in
                            LabeledContent(row.label, value: row.value)
                        }
                    }
                }
                if !workout.laps.isEmpty { lapSection }
                sourceSection
            }
            .navigationTitle(workout.activity.displayName)
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .featureList()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                .withoutGlassBackground()
            }
        }
    }

    private var effortSection: some View {
        Section {
            Picker("Session effort", selection: Binding(
                get: { workout.sessionRPE ?? 0 },
                set: { value in
                    workout.sessionRPE = value == 0 ? nil : value
                    try? context.save()
                })) {
                Text("Not rated").tag(0)
                ForEach(1...10, id: \.self) { value in
                    Text("\(value) / 10").tag(value)
                }
            }
        } footer: {
            Text("Rate how hard the whole session felt. This fills strain when heart-rate data is unavailable.")
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent("When", value: workout.startedAt
                .formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
            LabeledContent("Duration", value: durationString)
            LabeledContent("Active energy", value: "\(Int(workout.activeEnergyKcal)) kcal")
        } footer: {
            // The app's whole thesis is that expenditure is measured from intake
            // against the weight trend, so this number is history, not a budget.
            Text("Workout calories are shown for reference. They are never added "
                 + "back to your daily target.")
        }
    }

    private struct Row { let label: String; let value: String }

    private var detailRows: [Row] {
        var rows: [Row] = []

        if metrics.contains(.distance), let metres = workout.distanceMetres, metres > 0 {
            rows.append(Row(label: "Distance", value: distanceString(metres)))
        }
        if metrics.contains(.pace), let speed = workout.averageSpeed {
            rows.append(Row(label: "Average pace", value: paceString(speed)))
        }
        if let avg = workout.avgHeartRate {
            rows.append(Row(label: "Average heart rate", value: "\(Int(avg)) bpm"))
        }
        if let max = workout.maxHeartRate {
            rows.append(Row(label: "Max heart rate", value: "\(Int(max)) bpm"))
        }
        if let min = workout.minHeartRate {
            rows.append(Row(label: "Min heart rate", value: "\(Int(min)) bpm"))
        }
        if metrics.contains(.elevation), let gain = workout.elevationGainMetres, gain > 0 {
            rows.append(Row(label: "Elevation gain", value: elevationString(gain)))
        }
        if metrics.contains(.cadence), let cadence = workout.avgCadence, cadence > 0 {
            rows.append(Row(label: "Average cadence",
                            value: String(format: "%.0f spm", cadence)))
        }
        if metrics.contains(.power), let power = workout.avgPowerWatts, power > 0 {
            rows.append(Row(label: "Average power", value: String(format: "%.0f W", power)))
        }
        if metrics.contains(.strokes), let strokes = workout.swimStrokeCount, strokes > 0 {
            rows.append(Row(label: "Strokes", value: String(format: "%.0f", strokes)))
        }
        if let style = workout.swimStrokeStyle {
            rows.append(Row(label: "Stroke", value: style))
        }
        if let total = workout.totalEnergyKcal {
            rows.append(Row(label: "Total energy", value: "\(Int(total)) kcal"))
        }
        return rows
    }

    private var lapSection: some View {
        Section(metrics.contains(.laps) ? "Laps" : "Segments") {
            ForEach(workout.laps, id: \.index) { lap in
                HStack {
                    Text("\(lap.index)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                    Text(lapDuration(lap.durationSeconds))
                        .monospacedDigit()
                    Spacer()
                    if let metres = lap.distanceMetres {
                        Text(distanceString(metres))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let hr = lap.avgHeartRate {
                        Text("\(Int(hr)) bpm")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sourceSection: some View {
        Section("Source") {
            LabeledContent("Recorded by", value: workout.sourceName ?? workout.source.displayName)
            if let notes = workout.notes {
                LabeledContent("Training effect", value: notes)
            }
        }
    }

    private var durationString: String {
        let total = Int(workout.durationSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%dh %02dm", hours, minutes)
            : String(format: "%dm %02ds", minutes, seconds)
    }

    private func lapDuration(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func distanceString(_ metres: Double) -> String {
        units == .metric
            ? String(format: "%.2f km", metres / 1000)
            : String(format: "%.2f mi", metres / 1609.344)
    }

    private func elevationString(_ metres: Double) -> String {
        units == .metric
            ? String(format: "%.0f m", metres)
            : String(format: "%.0f ft", metres * 3.28084)
    }

    private func paceString(_ metresPerSecond: Double) -> String {
        guard metresPerSecond > 0 else { return "—" }
        let perUnit = units == .metric ? 1000.0 : 1609.344
        let secondsPerUnit = perUnit / metresPerSecond
        return String(format: "%d:%02d /%@",
                      Int(secondsPerUnit) / 60, Int(secondsPerUnit) % 60,
                      units == .metric ? "km" : "mi")
    }
}
