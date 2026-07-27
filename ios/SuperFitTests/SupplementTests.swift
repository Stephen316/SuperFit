import Testing
import Foundation
@testable import SuperFit

private let cal = Calendar(identifier: .gregorian)
private let today = cal.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

private func makeSupplement(_ name: String, kcal: Double = 0, protein: Double = 0,
                            micros: [Micronutrient: Double] = [:]) -> Supplement {
    Supplement(name: name, category: .performance, servingLabel: "serving",
               profile: NutrientProfile(kcal: kcal, proteinG: protein,
                                        micros: Dictionary(uniqueKeysWithValues:
                                            micros.map { ($0.key.rawValue, $0.value) })))
}

struct SupplementTests {

    // MARK: Daily entries carry forward

    @Test func dailyEntryAppliesToEverySubsequentDay() {
        let creatine = makeSupplement("Creatine")
        let entry = SupplementEntry(supplementID: creatine.id, kind: .daily)
        entry.startedOn = day(0)

        for offset in [0, 1, 7, 60] {
            let taken = SupplementIntake.taken(on: day(offset), entries: [entry],
                                               supplements: [creatine], calendar: cal)
            #expect(taken.count == 1, "missing on day \(offset)")
        }
    }

    @Test func dailyEntryDoesNotApplyBeforeItStarted() {
        let s = makeSupplement("Creatine")
        let entry = SupplementEntry(supplementID: s.id, kind: .daily)
        entry.startedOn = day(0)
        let taken = SupplementIntake.taken(on: day(-1), entries: [entry],
                                           supplements: [s], calendar: cal)
        #expect(taken.isEmpty)
    }

    @Test func stoppingADailyEntryEndsItWithoutErasingHistory() {
        let s = makeSupplement("Creatine")
        let entry = SupplementEntry(supplementID: s.id, kind: .daily)
        entry.startedOn = day(0)
        entry.stoppedOn = day(10)

        func count(_ offset: Int) -> Int {
            SupplementIntake.taken(on: day(offset), entries: [entry],
                                   supplements: [s], calendar: cal).count
        }
        #expect(count(5) == 1)      // still running
        #expect(count(10) == 1)     // inclusive of the stop day
        #expect(count(11) == 0)     // stopped
    }

    @Test func skippingOneDayLeavesTheRoutineIntact() {
        let s = makeSupplement("Creatine")
        let daily = SupplementEntry(supplementID: s.id, kind: .daily)
        daily.startedOn = day(0)
        let skip = SupplementEntry(supplementID: s.id, kind: .skipped)
        skip.date = day(3)

        func count(_ offset: Int) -> Int {
            SupplementIntake.taken(on: day(offset), entries: [daily, skip],
                                   supplements: [s], calendar: cal).count
        }
        #expect(count(2) == 1)
        #expect(count(3) == 0)      // skipped
        #expect(count(4) == 1)      // back tomorrow
    }

    @Test func oneOffEntryAppliesToItsDayOnly() {
        let s = makeSupplement("Caffeine")
        let entry = SupplementEntry(supplementID: s.id, kind: .once)
        entry.date = day(0)

        #expect(SupplementIntake.taken(on: day(0), entries: [entry],
                                       supplements: [s], calendar: cal).count == 1)
        #expect(SupplementIntake.taken(on: day(1), entries: [entry],
                                       supplements: [s], calendar: cal).isEmpty)
    }

    /// Stopping and restarting leaves two daily rows; the day they overlap must
    /// not double-count.
    @Test func overlappingDailyEntriesCountOnce() {
        let s = makeSupplement("Creatine", kcal: 10)
        let first = SupplementEntry(supplementID: s.id, kind: .daily)
        first.startedOn = day(0)
        let second = SupplementEntry(supplementID: s.id, kind: .daily)
        second.startedOn = day(5)

        let taken = SupplementIntake.taken(on: day(10), entries: [first, second],
                                           supplements: [s], calendar: cal)
        #expect(taken.count == 1)
    }

    // MARK: Nutrient contribution

    @Test func servingsScaleTheContribution() {
        let whey = makeSupplement("Whey", kcal: 113, protein: 25,
                                  micros: [.calcium: 120])
        let entry = SupplementEntry(supplementID: whey.id, kind: .once, servings: 2)
        entry.date = day(0)

        let total = SupplementIntake.total(on: day(0), entries: [entry],
                                           supplements: [whey], calendar: cal)
        #expect(total.kcal == 226)
        #expect(total.proteinG == 50)
        #expect(total.micros[Micronutrient.calcium.rawValue] == 240)
    }

    @Test func totalsCombineAcrossSupplements() {
        let whey = makeSupplement("Whey", kcal: 113, protein: 25, micros: [.calcium: 120])
        let multi = makeSupplement("Multivitamin", micros: [.calcium: 80, .zinc: 10])
        let a = SupplementEntry(supplementID: whey.id, kind: .once)
        a.date = day(0)
        let b = SupplementEntry(supplementID: multi.id, kind: .once)
        b.date = day(0)

        let total = SupplementIntake.total(on: day(0), entries: [a, b],
                                           supplements: [whey, multi], calendar: cal)
        #expect(total.kcal == 113)
        #expect(total.micros[Micronutrient.calcium.rawValue] == 200)
        #expect(total.micros[Micronutrient.zinc.rawValue] == 10)
    }

    // MARK: Feeding the metabolism engine

    /// Protein shakes are real calories: leaving them out of energy balance
    /// would inflate measured TDEE by the same amount.
    @Test func supplementCaloriesReachTheIntakeRecord() {
        let logs = [NutritionLog(date: day(-1), meal: .lunch)]
        logs[0].kcal = 2000
        let metrics = [BodyMetrics(date: day(-1), weightKg: 80)]

        let without = MetabolicRecordAssembler.dailyRecords(
            logs: logs, metrics: metrics, asOf: today)
        let with = MetabolicRecordAssembler.dailyRecords(
            logs: logs, metrics: metrics,
            supplementKcal: [day(-1): 340], asOf: today)

        #expect(without.first?.intakeKcal == 2000)
        #expect(with.first?.intakeKcal == 2340)
    }

    /// A day whose only record is a standing creatine entry was not a logged
    /// day; counting it would drag the intake average toward zero.
    @Test func supplementsAloneDoNotCreateALoggedDay() {
        let metrics = [BodyMetrics(date: day(-1), weightKg: 80)]
        let records = MetabolicRecordAssembler.dailyRecords(
            logs: [], metrics: metrics, supplementKcal: [day(-1): 340], asOf: today)
        #expect(records.allSatisfy { $0.intakeKcal == nil })
    }

    // MARK: Catalog integrity

    @Test func catalogEntriesAreDistinctAndLabelled() {
        let names = SupplementCatalog.items.map(\.name)
        #expect(Set(names).count == names.count, "duplicate supplement names")
        #expect(SupplementCatalog.items.allSatisfy { !$0.serving.isEmpty })
        #expect(SupplementCatalog.items.count >= 40)
    }

    @Test func everyCategoryHasEntries() {
        for category in SupplementCategory.allCases {
            #expect(SupplementCatalog.items.contains { $0.category == category },
                    "\(category) has no supplements")
        }
    }

    /// Creatine, beta-alanine and caffeine aren't oxidised for energy — a small
    /// invented calorie figure would be worse than zero.
    @Test func nonCaloricPerformanceSupplementsAreZeroKcal() {
        for name in ["Creatine Monohydrate", "Beta-Alanine", "Caffeine 200 mg"] {
            let item = SupplementCatalog.items.first { $0.name == name }
            #expect(item?.kcal == 0, "\(name) should carry no calories")
        }
    }

    /// Protein powders must not be zero-calorie — that's the error that would
    /// corrupt TDEE.
    @Test func proteinSupplementsCarryCalories() {
        for item in SupplementCatalog.items where item.category == .protein {
            #expect(item.kcal > 0, "\(item.name) has no calories")
            #expect(item.protein > 0, "\(item.name) has no protein")
        }
    }

    // MARK: Food-like supplements are also foods

    /// Anything you'd call a snack or a meal must be findable from the food
    /// diary, not only the supplements list.
    @Test func snackAndMealSupplementsAreFoodLike() {
        let expected = ["Protein Bar", "Protein Shake (ready to drink)",
                        "Meal Replacement Shake", "Protein Cookie", "Protein Yoghurt",
                        "Mass Gainer", "Whey Protein Isolate", "Casein Protein",
                        "Plant Protein Blend", "Collagen Peptides"]
        for name in expected {
            let item = SupplementCatalog.items.first { $0.name == name }
            #expect(item?.isFoodLike == true, "\(name) should be loggable as food")
        }
    }

    /// Pills and zero-calorie powders must not clutter food search.
    @Test func pillsAndZeroCaloriePowdersAreNotFoodLike() {
        for name in ["Multivitamin", "Vitamin D3 2000 IU", "Magnesium Glycinate",
                     "Creatine Monohydrate", "Beta-Alanine", "Probiotic"] {
            let item = SupplementCatalog.items.first { $0.name == name }
            #expect(item?.isFoodLike == false, "\(name) should stay out of food search")
        }
    }

    /// Supplements are per serving, foods are per 100 g. The conversion has to
    /// round-trip or a logged scoop would carry the wrong macros.
    @Test func perServingConvertsToPer100gAndBack() {
        let whey = Supplement(name: "Whey", category: .protein, servingLabel: "30 g scoop",
                              servingGrams: 30,
                              profile: NutrientProfile(kcal: 113, proteinG: 25, carbsG: 2,
                                                       fatG: 0.5,
                                                       micros: [Micronutrient.calcium.rawValue: 120]))
        let food = try? #require(whey.asFood)
        guard let food else { return }

        #expect(food.servingGrams == 30)
        #expect(food.source == .supplement)
        // Per 100 g is the per-serving figure scaled by 100/30.
        #expect(abs(food.per100g.proteinG - 25 * 100 / 30) < 0.001)
        // Scaling one serving back must return the original label figures.
        let oneServing = food.scaled(grams: 30)
        #expect(abs(oneServing.kcal - 113) < 0.001)
        #expect(abs(oneServing.proteinG - 25) < 0.001)
        #expect(abs((oneServing.micros[Micronutrient.calcium.rawValue] ?? 0) - 120) < 0.001)
    }

    @Test func supplementsWithoutAServingWeightAreNotFoods() {
        let pill = Supplement(name: "Vitamin D3", category: .vitamins, servingLabel: "capsule",
                              profile: NutrientProfile(micros: [Micronutrient.vitaminD.rawValue: 50]))
        #expect(pill.asFood == nil)
    }

    @Test func everyFoodLikeCatalogItemHasAServingWeight() {
        for item in SupplementCatalog.items where item.isFoodLike {
            #expect((item.servingGrams ?? 0) > 0, "\(item.name) is food-like with no weight")
        }
    }

    // MARK: Double-entry detection

    @Test func detectsAProductTakenAsBothFoodAndSupplement() {
        let bar = makeSupplement("Protein Bar", kcal: 220, protein: 20)
        let entry = SupplementEntry(supplementID: bar.id, kind: .once)
        entry.date = day(0)

        #expect(SupplementIntake.isTakenAsSupplement(
            name: "Protein Bar", on: day(0), entries: [entry],
            supplements: [bar], calendar: cal))
        // Different day, no clash.
        #expect(!SupplementIntake.isTakenAsSupplement(
            name: "Protein Bar", on: day(1), entries: [entry],
            supplements: [bar], calendar: cal))
    }

    @Test func supplementNameMatchIgnoresCase() {
        let bar = makeSupplement("Protein Bar", kcal: 220)
        let entry = SupplementEntry(supplementID: bar.id, kind: .once)
        entry.date = day(0)
        #expect(SupplementIntake.isTakenAsSupplement(
            name: "protein bar", on: day(0), entries: [entry],
            supplements: [bar], calendar: cal))
    }

    /// A skipped daily supplement isn't taken, so logging the food is not a
    /// double entry and must not warn.
    @Test func skippedSupplementDoesNotCountAsDoubleEntry() {
        let bar = makeSupplement("Protein Bar", kcal: 220)
        let daily = SupplementEntry(supplementID: bar.id, kind: .daily)
        daily.startedOn = day(0)
        let skip = SupplementEntry(supplementID: bar.id, kind: .skipped)
        skip.date = day(0)

        #expect(!SupplementIntake.isTakenAsSupplement(
            name: "Protein Bar", on: day(0), entries: [daily, skip],
            supplements: [bar], calendar: cal))
    }

    @Test func detectsAProductAlreadyInTheFoodDiary() {
        let log = NutritionLog(date: day(0), meal: .snack)
        log.foodName = "Protein Bar"

        #expect(SupplementIntake.isLoggedAsFood(
            name: "Protein Bar", on: day(0), logs: [log], calendar: cal))
        #expect(!SupplementIntake.isLoggedAsFood(
            name: "Protein Bar", on: day(1), logs: [log], calendar: cal))
    }

    /// Matching is exact so an unrelated food sharing a word doesn't warn.
    @Test func partialNameOverlapIsNotADoubleEntry() {
        let log = NutritionLog(date: day(0), meal: .lunch)
        log.foodName = "Protein Bar Chocolate Peanut"

        #expect(!SupplementIntake.isLoggedAsFood(
            name: "Protein Bar", on: day(0), logs: [log], calendar: cal))
    }

    /// Macro grams must be consistent with the stated calories (4/4/9).
    @Test func catalogMacrosAgreeWithStatedCalories() {
        for item in SupplementCatalog.items where item.kcal > 0 {
            let fromMacros = 4 * item.protein + 4 * item.carbs + 9 * item.fat
            // Fibre is partially fermented and labels round; allow slack.
            #expect(abs(fromMacros - item.kcal) <= max(15, item.kcal * 0.15),
                    "\(item.name): \(fromMacros) kcal from macros vs \(item.kcal) stated")
        }
    }
}
