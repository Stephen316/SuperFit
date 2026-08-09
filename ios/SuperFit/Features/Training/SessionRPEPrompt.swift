import SwiftUI

/// Short post-workout check-in for the validated session-RPE method.
struct SessionRPEPrompt: View {
    let onComplete: (Int?) -> Void

    @State private var rating = 7.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Text("How hard did that feel?")
                    .font(Theme.font(22, .semibold))
                Text("Rate the whole session, where 1 is very easy and 10 is maximal.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                Text("\(Int(rating))")
                    .font(Theme.font(54, .semibold))
                    .foregroundStyle(Theme.gold)
                    .monospacedDigit()
                Slider(value: $rating, in: 1...10, step: 1)
                    .tint(Theme.gold)
                    .accessibilityLabel("Session effort")
                    .accessibilityValue("\(Int(rating)) out of 10")
                HStack {
                    Text("Very easy")
                    Spacer()
                    Text("Maximal")
                }
                .font(Theme.font(12))
                .foregroundStyle(Theme.textSecondary)

                Button("Save effort") { onComplete(Int(rating)) }
                    .font(Theme.font(16, .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.gold)
                    )
                    .foregroundStyle(.black)
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { onComplete(nil) }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
