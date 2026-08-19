import SwiftUI

struct WorkoutRow: View {
    let workout: WorkoutRecord
    let units: UnitSystem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.activity.symbolName)
                .foregroundStyle(Theme.gold)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(workout.activity.displayName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(workout.startedAt, format: .dateTime.month().day())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(summary)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        var parts = ["\(Int(workout.durationSeconds / 60)) min"]
        if workout.activity.metrics.contains(.distance),
           let metres = workout.distanceMetres, metres > 0 {
            parts.append(units == .metric
                         ? String(format: "%.2f km", metres / 1000)
                         : String(format: "%.2f mi", metres / 1609.344))
        }
        if workout.activeEnergyKcal > 0 {
            parts.append("\(Int(workout.activeEnergyKcal)) kcal")
        }
        if let hr = workout.avgHeartRate { parts.append("\(Int(hr)) bpm") }
        return parts.joined(separator: " · ")
    }
}

struct SessionRow: View {
    let session: TrainingSession
    let exercises: [Exercise]
    /// Off where a date header already covers the row, in which case the row
    /// shows the time instead.
    var showsDate = true

    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
    private var workingSets: [SetEntry] {
        (session.sets ?? []).filter { !$0.isWarmup && $0.completedAt != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(session.templateName ?? "Workout").font(.subheadline.weight(.medium))
                Spacer()
                Text(session.startedAt, format: showsDate
                     ? .dateTime.month().day()
                     : .dateTime.hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(summary)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        let tonnage = workingSets.reduce(0) { $0 + $1.volumeKg }
        let names = Set(workingSets.compactMap { set in
            exercises.first { $0.id == set.exerciseID }?.name
        })
        let list = names.prefix(3).joined(separator: ", ")
        return "\(workingSets.count) sets · \(Int(units.displayWeight(tonnage))) \(units.weightUnit) total"
            + (list.isEmpty ? "" : " · \(list)")
    }
}
