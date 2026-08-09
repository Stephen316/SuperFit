import Foundation
import SwiftData

/// One mutable counter per calendar day. Hydration is an accumulated daily
/// total rather than a list of identical glasses, keeping multi-year history
/// small while still supporting corrections with the minus button.
@Model
final class HydrationLog {
    var date: Date = Date()
    var millilitres: Double = 0

    init(date: Date, millilitres: Double = 0) {
        self.date = date
        self.millilitres = millilitres
    }
}

/// A synced singleton rather than a device preference: the user's daily goal
/// follows their hydration history across devices and through backups.
@Model
final class HydrationSettings {
    var id: UUID = UUID()
    var dailyGoalMl: Double = 2_500

    init(dailyGoalMl: Double = 2_500) {
        self.dailyGoalMl = dailyGoalMl
    }
}
