import SwiftUI

/// A compact horizontal battery that fills to a fraction of its width, in the
/// classic ~2:1 battery proportion with a terminal nub. Empty (outline only) when
/// there is no reading, so "no data" reads as an empty cell, not a drained one.
struct BatteryView: View {
    /// 0…1. Clamped; values outside the range pin to the ends.
    var fraction: Double
    var hasData: Bool
    /// The fill colour — the energy box drives this from the charge level.
    var tint: Color
    var width: CGFloat = 156
    var height: CGFloat = 66

    private var inset: CGFloat { max(3, height * 0.1) }

    var body: some View {
        HStack(spacing: 3) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 3)
                if hasData {
                    RoundedRectangle(cornerRadius: (height - inset * 2) * 0.32, style: .continuous)
                        .fill(tint)
                        .frame(width: max(0, (width - inset * 2) * clamped),
                               height: height - inset * 2)
                        .padding(.leading, inset)
                }
            }
            .frame(width: width, height: height)
            // Terminal nub.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.hairline)
                .frame(width: 5, height: height * 0.42)
        }
        .accessibilityElement()
        .accessibilityLabel("Energy")
        .accessibilityValue(hasData ? "\(Int(clamped * 100)) percent" : "No data")
    }

    private var clamped: Double { min(max(fraction, 0), 1) }
}
