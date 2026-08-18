import SwiftUI

/// The whole watch UI: start a lift, run it, and rest by heart rate between sets.
struct WatchRootView: View {
    @State private var manager = WatchWorkoutManager()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch manager.phase {
            case .idle: idle
            case .working: working
            case .resting: resting
            case .ended: ended
            }
        }
        .onReceive(tick) { _ in manager.tick() }
    }

    private var idle: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell.fill").font(.title2).foregroundStyle(.yellow)
            Text("SuperFit").font(.headline)
            Button {
                Task { await manager.requestAuthorization(); await manager.startWorkout() }
            } label: {
                Label("Start Lift", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .tint(.yellow)
        }
        .padding(.horizontal, 4)
    }

    private var working: some View {
        VStack(spacing: 8) {
            hrRow
            Text(timeString(manager.elapsed))
                .font(.system(.title3, design: .rounded)).monospacedDigit()
                .foregroundStyle(.secondary)
            Button { manager.doneSet() } label: {
                Label("Done Set", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .tint(.yellow)
            endButton
        }
        .padding(.horizontal, 4)
    }

    private var resting: some View {
        let ready = manager.readiness == .ready
        return VStack(spacing: 6) {
            hrRow
            Text(ready ? "Ready" : "Resting")
                .font(.headline)
                .foregroundStyle(ready ? .green : .orange)
            Text(ready
                 ? "HR recovered — go"
                 : "HR \(Int(manager.currentHR)) → target \(Int(manager.targetHR))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(timeString(manager.restElapsed))
                .font(.system(.body, design: .rounded)).monospacedDigit()
            Button { manager.startNextSet() } label: {
                Label("Start Set", systemImage: "arrow.right").frame(maxWidth: .infinity)
            }
            .tint(ready ? .green : .gray)
            endButton
        }
        .padding(.horizontal, 4)
    }

    private var ended: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
            Text("Workout saved").font(.headline)
            Button("Done") { manager.reset() }.tint(.yellow)
        }
    }

    private var hrRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill").foregroundStyle(.red)
            Text(manager.currentHR > 0 ? "\(Int(manager.currentHR))" : "--")
                .font(.system(.title2, design: .rounded)).monospacedDigit()
            Text("bpm").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var endButton: some View {
        Button(role: .destructive) {
            Task { await manager.endWorkout() }
        } label: {
            Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity)
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(max(t, 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
