import Foundation
import SwiftData

/// The pull-to-refresh action behind the four data-entry tabs.
///
/// Refresh means the same thing on every one of them: take whatever Health has
/// that the store does not, then recompute the estimates built on it. Doing only
/// the first half would leave the screen showing new samples against a TDEE and a
/// calorie target derived from the old ones, which is worse than not refreshing —
/// the numbers would disagree with each other rather than merely being stale.
///
/// Screens reload their own local state afterwards; this covers the shared part.
@MainActor
enum FeatureRefresh {

    /// A year, not the coordinator's default 90 days. A manual pull is the
    /// gesture people reach for after wearing a watch on holiday or restoring a
    /// backup, and a 90-day window silently drops the rest.
    static let days = 365

    /// Returns a message when the store could not be written, so the caller can
    /// surface it instead of a refresh that appears to succeed and changes
    /// nothing.
    @discardableResult
    static func syncAndAggregate(context: ModelContext) async -> String? {
        let changes = await SyncCoordinator(context: context).syncAll(days: days)
        AggregationService(context: context)
            .runAll(refreshWeightTrend: changes.weightTrendNeedsRefresh)
        return changes.failureMessage
    }
}
