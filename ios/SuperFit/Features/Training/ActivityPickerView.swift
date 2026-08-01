import SwiftUI
import SwiftData

/// The first screen behind "Start workout".
///
/// Strength keeps the existing flow — pick a template or an empty session, then
/// log sets. Everything else is a duration activity, and for those the useful
/// question isn't which exercise but *where the data comes from*: track it live
/// on the phone, or pull in what the watch already recorded.
struct ActivityPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let savedTemplates: [WorkoutTemplate]
    let recentWatchWorkouts: [WorkoutSample]
    /// Strength: nil template means an empty session.
    let onStartStrength: (String?) -> Void
    let onStartLive: (WorkoutActivity) -> Void
    let onImport: (WorkoutSample) -> Void

    @State private var search = ""

    private var groups: [WorkoutActivity.Group] {
        WorkoutActivity.Group.allCases.filter { !activities(in: $0).isEmpty }
    }

    private func activities(in group: WorkoutActivity.Group) -> [WorkoutActivity] {
        let all = WorkoutActivity.inGroup(group)
        guard !search.isEmpty else { return all }
        return all.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    if !recentWatchWorkouts.isEmpty { recentSection }
                    strengthSection
                }

                ForEach(groups) { group in
                    if group != .strength || !search.isEmpty {
                        Section(group.rawValue) {
                            ForEach(activities(in: group)) { activity in
                                row(for: activity)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Find an activity")
            .navigationTitle("New workout")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .themedList()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                .withoutGlassBackground()
            }
        }
    }

    /// Watch workouts not yet in the app, offered for one-tap import. This is the
    /// common case: the watch tracked it properly, the phone just needs to know.
    private var recentSection: some View {
        Section("From your watch") {
            ForEach(recentWatchWorkouts, id: \.externalID) { sample in
                Button {
                    onImport(sample)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: sample.activity.symbolName)
                            .foregroundStyle(Theme.gold)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.activity.displayName)
                            Text(sample.start, format: .dateTime.weekday().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(sample.durationSeconds / 60)) min")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Image(systemName: "square.and.arrow.down")
                            .font(.caption).foregroundStyle(Theme.gold)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var strengthSection: some View {
        Section("Strength") {
            ForEach(savedTemplates) { template in
                Button {
                    onStartStrength(template.name)
                    dismiss()
                } label: {
                    Label(template.name, systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.plain)
            }
            Button {
                onStartStrength(nil)
                dismiss()
            } label: {
                Label("Empty gym workout", systemImage: "dumbbell.fill")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func row(for activity: WorkoutActivity) -> some View {
        if activity.isStrength {
            Button {
                onStartStrength(nil)
                dismiss()
            } label: {
                activityLabel(activity)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ActivityStartOptionsView(
                    activity: activity,
                    recent: recentWatchWorkouts.filter { $0.activity == activity },
                    onStartLive: { onStartLive(activity); dismiss() },
                    onImport: { onImport($0); dismiss() })
            } label: {
                activityLabel(activity)
            }
        }
    }

    private func activityLabel(_ activity: WorkoutActivity) -> some View {
        HStack {
            Image(systemName: activity.symbolName)
                .foregroundStyle(Theme.gold)
                .frame(width: 28)
            Text(activity.displayName)
        }
    }
}

/// Live or from history, for one chosen activity.
struct ActivityStartOptionsView: View {
    let activity: WorkoutActivity
    let recent: [WorkoutSample]
    let onStartLive: () -> Void
    let onImport: (WorkoutSample) -> Void

    var body: some View {
        List {
            Section {
                Button(action: onStartLive) {
                    HStack {
                        Image(systemName: "record.circle")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start live").font(.headline)
                            Text(activity.usesLocation
                                 ? "Times the session and follows distance by GPS."
                                 : "Times the session on this phone.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            } footer: {
                if activity.usesLocation {
                    Text("A watch records heart rate and route more accurately. "
                         + "Use this when the phone is all you have with you.")
                }
            }

            Section("Recent \(activity.displayName.lowercased()) from your watch") {
                if recent.isEmpty {
                    Text("Nothing recorded yet.").foregroundStyle(.secondary)
                }
                ForEach(recent, id: \.externalID) { sample in
                    Button { onImport(sample) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.start, format: .dateTime.weekday().day().month().hour().minute())
                                if let distance = sample.distanceMetres {
                                    Text(String(format: "%.2f km", distance / 1000))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(Int(sample.durationSeconds / 60)) min")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(activity.displayName)
        .themedChrome()
        .navigationBarTitleDisplayMode(.inline)
        .themedList()
    }
}
