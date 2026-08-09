import SwiftUI

/// Lightweight setup help for anything that needs a watch — recovery, resting
/// heart rate, HRV, sleep. Reached from a watch-dependent card when the store
/// holds no readings of that kind, so the answer to "why is this empty" is one
/// tap away rather than buried in Settings.
///
/// The framing is deliberate: SuperFit never pairs with a watch. It reads
/// everything from Apple Health, so both routes below end at the same place —
/// getting the watch's data *into* Apple Health, then letting SuperFit read it.
struct WatchSetupHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FeatureBackground()
                ScrollView {
                    LazyVStack(spacing: 14) {
                        intro
                        appleWatchCard
                        garminCard
                        footer
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Connect a watch")
            .themedChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                    .withoutGlassBackground()
            }
        }
    }

    private var intro: some View {
        Text("Recovery, resting heart rate and sleep come from Apple Health — SuperFit reads them from there rather than pairing with a watch itself. If these are blank, Apple Health isn't receiving the data yet.")
            .font(Theme.font(14))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appleWatchCard: some View {
        card(icon: "applewatch",
             title: "Apple Watch",
             steps: [
                "Wear it, including overnight — sleep and HRV are only measured while you sleep.",
                "Let SuperFit read your data: iPhone Settings → Health → Data Access & Devices → SuperFit, and turn everything on.",
                "Resting heart rate is worked out once a day and can take until the afternoon to appear.",
             ])
    }

    private var garminCard: some View {
        card(icon: "arrow.triangle.2.circlepath",
             title: "Garmin",
             steps: [
                "Make sure the watch has synced — open the Garmin Connect app and check today's data is there.",
                "Turn on Apple Health sharing: in Garmin Connect tap More → Settings → Apple Health, switch it on, and allow everything when iOS asks.",
                "Let SuperFit read the data: iPhone Settings → Health → Data Access & Devices → SuperFit.",
             ],
             note: "Garmin doesn't share HRV or detailed sleep stages with Apple Health, so recovery may stay limited. Pulling those in needs the optional Garmin server (see docs/GARMIN.md).")
    }

    private var footer: some View {
        Text("After changing any of these, pull down on the Today screen to sync. New readings can take a few minutes to arrive.")
            .font(Theme.font(13))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One provider block: an icon-and-title header over numbered steps and an
    /// optional caveat. Same hairline-outlined card as the rest of the app.
    private func card(icon: String, title: String,
                      steps: [String], note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.gold)
                Text(title)
                    .font(Theme.font(17, .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(Theme.font(13, .bold))
                            .foregroundStyle(Theme.gold)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.wash))
                        Text(step)
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if let note {
                Text(note)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .featurePanel()
    }
}

/// The "how to connect a watch" affordance itself — a question mark and a line
/// of gold. A label rather than a button so it can be dropped inside a card
/// that is already one tap target; wrap it in `WatchHelpLink` where it needs to
/// present the sheet on its own.
struct WatchHelpLabel: View {
    var text = "How to connect a watch"

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "questionmark.circle")
            Text(text)
        }
        .font(Theme.text(13, .medium))
        .foregroundStyle(Theme.gold)
    }
}

/// Self-contained help link that owns its own presentation, for screens where
/// the affordance stands alone rather than inside another button.
struct WatchHelpLink: View {
    var text = "How to connect a watch"
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { WatchHelpLabel(text: text) }
            .buttonStyle(.plain)
            .sheet(isPresented: $showing) { WatchSetupHelpView() }
            .accessibilityHint("Opens instructions for connecting an Apple Watch or Garmin")
    }
}
