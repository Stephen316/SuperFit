import Foundation

/// One supplement taken on a given day, with how it got there.
struct TakenSupplement: Sendable, Identifiable {
    let id: UUID
    let supplementID: UUID
    let name: String
    let servingLabel: String
    let servings: Double
    let profile: NutrientProfile
    /// True when it comes from a standing daily entry rather than a one-off.
    let isDaily: Bool

    var total: NutrientProfile {
        NutrientProfile(kcal: profile.kcal * servings,
                        proteinG: profile.proteinG * servings,
                        carbsG: profile.carbsG * servings,
                        fatG: profile.fatG * servings,
                        fibreG: profile.fibreG * servings,
                        micros: profile.micros.mapValues { $0 * servings })
    }
}

/// Resolves supplement entries into what was actually taken on a day.
///
/// Daily entries are evaluated rather than materialised: a year of creatine is
/// one row, not 365 identical ones, and a skip is the exception layered on top.
enum SupplementIntake {

    static func taken(on day: Date,
                      entries: [SupplementEntry],
                      supplements: [Supplement],
                      calendar: Calendar = .current) -> [TakenSupplement] {
        let byID = Dictionary(supplements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return taken(on: day, entries: entries, supplementsByID: byID, calendar: calendar)
    }

    private static func taken(on day: Date,
                              entries: [SupplementEntry],
                              supplementsByID byID: [UUID: Supplement],
                              calendar: Calendar) -> [TakenSupplement] {
        let target = calendar.startOfDay(for: day)
        let bounds = DayBounds(target, calendar: calendar)

        let skipped = Set(entries.compactMap { entry -> UUID? in
            guard entry.kind == .skipped, let d = entry.date,
                  bounds.contains(d) else { return nil }
            return entry.supplementID
        })

        var out: [TakenSupplement] = []
        var seenDaily: Set<UUID> = []

        for entry in entries {
            guard let supplementID = entry.supplementID,
                  let supplement = byID[supplementID] else { continue }

            switch entry.kind {
            case .daily:
                guard entry.covers(target, calendar: calendar),
                      !skipped.contains(supplementID),
                      // A supplement stopped and restarted leaves two rows; only
                      // count it once per day.
                      seenDaily.insert(supplementID).inserted
                else { continue }
            case .once:
                guard let d = entry.date, bounds.contains(d) else { continue }
            case .skipped:
                continue
            }

            out.append(TakenSupplement(id: entry.id,
                                       supplementID: supplementID,
                                       name: supplement.name,
                                       servingLabel: supplement.servingLabel,
                                       servings: entry.servings,
                                       profile: supplement.perServing,
                                       isDaily: entry.kind == .daily))
        }
        return out.sorted { $0.name < $1.name }
    }

    /// Combined contribution for a day — what gets added to food totals.
    static func total(on day: Date,
                      entries: [SupplementEntry],
                      supplements: [Supplement],
                      calendar: Calendar = .current) -> NutrientProfile {
        let byID = Dictionary(supplements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return total(on: day, entries: entries, supplementsByID: byID, calendar: calendar)
    }

    private static func total(on day: Date,
                              entries: [SupplementEntry],
                              supplementsByID: [UUID: Supplement],
                              calendar: Calendar) -> NutrientProfile {
        taken(on: day, entries: entries, supplementsByID: supplementsByID, calendar: calendar)
            .reduce(into: NutrientProfile()) { sum, item in
                let t = item.total
                sum.kcal += t.kcal
                sum.proteinG += t.proteinG
                sum.carbsG += t.carbsG
                sum.fatG += t.fatG
                sum.fibreG += t.fibreG
                for (key, value) in t.micros { sum.micros[key, default: 0] += value }
            }
    }

    /// Whether `name` is already taken as a supplement on `day`.
    ///
    /// Food-like supplements — bars, shakes, gainers — appear in both the food
    /// diary and the supplements list, so the same product can be entered twice
    /// and counted twice. Matching is on the exact name because that's the case
    /// this catches: the same catalog item reached from two screens. A loose
    /// match would fire on unrelated foods that merely share a word.
    static func isTakenAsSupplement(name: String, on day: Date,
                                    entries: [SupplementEntry],
                                    supplements: [Supplement],
                                    calendar: Calendar = .current) -> Bool {
        taken(on: day, entries: entries, supplements: supplements, calendar: calendar)
            .contains { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    /// Whether `name` was already logged as food on `day`.
    static func isLoggedAsFood(name: String, on day: Date,
                               logs: [NutritionLog],
                               calendar: Calendar = .current) -> Bool {
        logs.contains { log in
            guard calendar.isDate(log.date, inSameDayAs: day),
                  let logged = log.foodName else { return false }
            return logged.compare(name, options: .caseInsensitive) == .orderedSame
        }
    }

    /// Daily-supplement calories per day across a date range, keyed by day.
    /// Feeds the metabolism engine so shakes don't vanish from energy balance.
    static func dailyKcal(entries: [SupplementEntry],
                          supplements: [Supplement],
                          from start: Date,
                          to end: Date,
                          calendar: Calendar = .current) -> [Date: Double] {
        let byID = Dictionary(supplements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Date: Double] = [:]
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            let kcal = total(on: day, entries: entries, supplementsByID: byID,
                             calendar: calendar).kcal
            if kcal > 0 { out[day] = kcal }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? last.addingTimeInterval(1)
        }
        return out
    }

    /// Totals for a known set of days while building the supplement lookup once.
    /// History and seven-day nutrition views used to rebuild the same UUID map
    /// for every date they displayed.
    static func totals(on days: some Sequence<Date>,
                       entries: [SupplementEntry],
                       supplements: [Supplement],
                       calendar: Calendar = .current) -> [Date: NutrientProfile] {
        let byID = Dictionary(supplements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Date: NutrientProfile] = [:]
        for date in days {
            let day = calendar.startOfDay(for: date)
            out[day] = total(on: day, entries: entries,
                             supplementsByID: byID, calendar: calendar)
        }
        return out
    }
}
