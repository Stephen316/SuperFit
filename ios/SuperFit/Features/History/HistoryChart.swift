import SwiftUI
import Charts

/// Time span a history screen is showing.
enum HistoryRange: Int, CaseIterable, Identifiable {
    case month = 30, quarter = 90, halfYear = 180, year = 365

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .month: return "30d"
        case .quarter: return "90d"
        case .halfYear: return "6m"
        case .year: return "1y"
        }
    }

    var start: Date { Date.now.addingTimeInterval(-Double(rawValue) * 86_400) }

    /// Daily points get unreadable past a few weeks, so longer ranges lean on
    /// the rolling line and drop the raw dots.
    var showsDailyPoints: Bool { self == .month }
}

/// One titled chart with a headline value and change, styled to the app.
///
/// Every history chart shares this so they read as one screen rather than a pile
/// of differently-shaped graphs — and so the "no data yet" case is handled once
/// instead of five times.
struct HistoryChartCard<Content: ChartContent>: View {
    let title: String
    var headline: String?
    var change: String?
    var changeIsGood: Bool?
    var height: CGFloat = 170
    var yLabel: (Double) -> String = { "\(Int($0))" }
    @ChartContentBuilder var content: Content
    var isEmpty: Bool = false
    var emptyMessage: String = "Not enough data yet."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let change {
                    Text(change)
                        .font(Theme.font(13))
                        .monospacedDigit()
                        .foregroundStyle(changeTint)
                }
            }
            if let headline {
                Text(headline)
                    .font(Theme.font(26))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }

            if isEmpty {
                Text(emptyMessage)
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: height * 0.6, alignment: .leading)
            } else {
                Chart { content }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine().foregroundStyle(Theme.divider.opacity(0.4))
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(yLabel(v))
                                        .font(Theme.font(11))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisValueLabel {
                                if let d = value.as(Date.self) {
                                    Text(d, format: .dateTime.month(.abbreviated).day())
                                        .font(Theme.font(11))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .frame(height: height)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var changeTint: Color {
        guard let changeIsGood else { return Theme.textSecondary }
        return changeIsGood ? .green : .orange
    }
}
