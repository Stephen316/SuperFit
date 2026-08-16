import SwiftUI

/// A curated how-to video, played through YouTube's own embed player.
///
/// The official player rather than a extracted stream: it is the supported way to
/// show someone else's video, it keeps the view count and attribution with the
/// uploader, and it does not break when YouTube changes anything.
/// What one exercise is, and what you have done with it.
///
/// Reached from the "i" beside a lift when adding it, so the decision to include
/// something can be made against both how it is performed and your own history —
/// which is why the two live behind one control rather than in separate screens.
struct ExerciseInfoView: View {
    let exercise: Exercise

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private enum Tab: Hashable { case howTo, history }
    @State private var tab = Tab.howTo
    /// Newline-separated exercise names whose video has been reported.
    @AppStorage("flaggedExerciseVideos") private var flaggedRaw = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FeatureTabControl(options: [(Tab.howTo, "How to"), (Tab.history, "History")],
                                  selection: $tab)
                switch tab {
                case .howTo:  howTo
                case .history: ExerciseProgressView(exercise: exercise)
                }
            }
            .background(FeatureBackground())
            .navigationTitle(exercise.name)
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                .withoutGlassBackground()
            }
        }
    }

    @ViewBuilder
    private var howTo: some View {
        if let id = ExerciseVideos.id(for: exercise.name) {
            VStack(spacing: 16) {
                Button { ExerciseVideos.watchURL(id: id).map(openURL.callAsFunction) } label: {
                    ZStack {
                        AsyncImage(url: ExerciseVideos.thumbnailURL(id: id)) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Theme.wash
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipped()
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.white.opacity(0.92))
                            .shadow(radius: 8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadiusCompact))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(exercise.name) demonstration on YouTube")

                Text("Opens in YouTube")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.textSecondary)

                flagControl
                Spacer(minLength: 0)
            }
            .padding(20)
        } else {
            missingVideo
        }
    }

    /// Temporary: lets a wrong or poor-quality pick be reported from the screen
    /// where it is noticed, rather than remembered and lost. Flags are stored
    /// locally and copied to the clipboard so they can be pasted back.
    private var flagControl: some View {
        Button {
            var flagged = Set(flaggedRaw.split(separator: "\n").map(String.init))
            if flagged.contains(exercise.name) {
                flagged.remove(exercise.name)
            } else {
                flagged.insert(exercise.name)
                UIPasteboard.general.string =
                    "Wrong/poor video: \(exercise.name) — \(ExerciseVideos.id(for: exercise.name) ?? "")"
            }
            flaggedRaw = flagged.sorted().joined(separator: "\n")
        } label: {
            Label(isFlagged ? "Flagged — copied to clipboard" : "Report this video",
                  systemImage: isFlagged ? "flag.fill" : "flag")
                .font(Theme.text(13))
                .foregroundStyle(isFlagged ? Theme.gold : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var isFlagged: Bool {
        flaggedRaw.split(separator: "\n").contains { $0 == exercise.name }
    }

    @ViewBuilder
    private var missingVideo: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "play.rectangle")
                .font(.system(size: 34))
                .foregroundStyle(Theme.textSecondary)
            Text("No how-to video yet")
                .font(Theme.text(17, .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("No demonstration has been picked for this lift yet. Check the form suits you before following it.")
                .font(Theme.text(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if let search = ExerciseVideos.searchURL(for: exercise.name) {
                Button("Search YouTube") { openURL(search) }
                    .font(Theme.text(15, .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .background { Capsule().fill(Theme.gold) }
                    .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}
