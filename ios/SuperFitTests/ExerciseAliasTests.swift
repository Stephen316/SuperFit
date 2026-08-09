import Testing
import Foundation
@testable import SuperFit

/// Exercises answer to more names than they display.
///
/// One lift shows under one name — a list carrying "Overhead Press / OHP /
/// Military Press / Strict Press" on every row is unreadable, and logging the
/// same lift under three names would split its history into three progressions
/// that each look stalled. The aliases only widen what *finds* it.
struct ExerciseAliasTests {

    private func entry(_ name: String) -> ExerciseLibrary.Entry {
        ExerciseLibrary.catalog.first { $0.name == name }!
    }

    private func exercise(_ name: String) -> Exercise {
        let e = entry(name)
        return Exercise(name: e.name, category: e.category, tension: e.tension,
                        bodyweightFraction: e.bodyweight, aliases: e.aliases)
    }

    // MARK: Searching

    @Test func anAbbreviationFindsTheLift() {
        #expect(exercise("Overhead Press").matches("OHP"))
        #expect(exercise("Romanian Deadlift").matches("rdl"))
        #expect(exercise("Bulgarian Split Squat").matches("RFESS"))
        #expect(exercise("Glute Ham Raise").matches("ghr"))
    }

    @Test func anotherCommonNameFindsTheLift() {
        #expect(exercise("Overhead Press").matches("military press"))
        #expect(exercise("Barbell Row").matches("bent over row"))
        #expect(exercise("Pec Deck").matches("butterfly"))
        #expect(exercise("Back Extension").matches("hyperextension"))
        #expect(exercise("Skull Crusher").matches("lying triceps extension"))
    }

    @Test func matchingIsCaseInsensitiveAndPartial() {
        #expect(exercise("Overhead Press").matches("MILITARY"))
        #expect(exercise("Romanian Deadlift").matches("Romanian"))
    }

    @Test func anEmptyQueryMatchesEverything() {
        #expect(exercise("Deadlift").matches(""))
        #expect(exercise("Deadlift").matches("   "))
    }

    @Test func anUnrelatedTermDoesNotMatch() {
        #expect(!exercise("Deadlift").matches("bicep"))
        #expect(!exercise("Lateral Raise").matches("squat"))
    }

    /// A lift with no aliases still searches by its own name.
    @Test func aCustomExerciseWithNoAliasesStillMatches() {
        let custom = Exercise(name: "My Machine Thing", category: .machine,
                              tension: [.chest: 4], isCustom: true)
        #expect(custom.matches("machine"))
        #expect(!custom.matches("ohp"))
    }

    // MARK: Catalogue integrity

    @Test func theCatalogueHasNoDuplicateNames() {
        let names = ExerciseLibrary.catalog.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func theCatalogueIncludesExpandedMachineFamilies() {
        let names = Set(ExerciseLibrary.catalog.map(\.name))
        let expected = [
            "Incline Machine Chest Press", "Neutral-Grip Machine Chest Press",
            "Machine High Row", "Machine Low Row", "Neutral-Grip Machine Row",
            "Plate-Loaded Pulldown", "V-Squat Machine", "Reverse Hack Squat",
            "Kneeling Leg Curl", "Machine Glute Kickback", "Machine Crunch",
        ]
        for name in expected { #expect(names.contains(name), "missing \(name)") }

        #expect(exercise("Incline Machine Chest Press")
            .matches("incline chest press machine"))
        #expect(exercise("Neutral-Grip Machine Chest Press")
            .matches("neutral grip chest press machine"))
    }

    /// Machine names are not cosmetic duplicates when the movement path changes.
    /// The incline path biases clavicular pec, a neutral press remains chest-led
    /// with more elbow-extension demand, and an elbows-out row shifts credit from
    /// lats toward scapular retractors and rear delts.
    @Test func expandedMachineTensionMapsReflectMovementPath() {
        let incline = entry("Incline Machine Chest Press").tension
        #expect(incline[.upperChest] == 5)
        #expect(incline[.chest] == 3)

        let neutralPress = entry("Neutral-Grip Machine Chest Press").tension
        #expect(neutralPress[.chest] == 5)
        #expect(neutralPress[.tricepsLong] == 4)

        let neutralRow = entry("Neutral-Grip Machine Row").tension
        let wideRow = entry("Wide-Grip Machine Row").tension
        #expect(neutralRow[.lats] == 5)
        #expect(wideRow[.rhomboids] == 5)
        #expect(wideRow[.rearDelts] == 4)
    }

    /// An alias pointing at two different lifts would make one of them
    /// unreachable by that term, which is worse than having no alias.
    @Test func noAliasIsSharedByTwoExercises() {
        var owner: [String: String] = [:]
        for entry in ExerciseLibrary.catalog {
            for alias in entry.aliases {
                let key = alias.lowercased()
                #expect(owner[key] == nil,
                        "\"\(alias)\" is on both \(owner[key] ?? "") and \(entry.name)")
                owner[key] = entry.name
            }
        }
    }

    /// An alias identical to another lift's display name would shadow it.
    @Test func noAliasCollidesWithAnotherExercisesName() {
        let names = Set(ExerciseLibrary.catalog.map { $0.name.lowercased() })
        for entry in ExerciseLibrary.catalog {
            for alias in entry.aliases where alias.lowercased() != entry.name.lowercased() {
                #expect(!names.contains(alias.lowercased()),
                        "\"\(alias)\" on \(entry.name) is another exercise's name")
            }
        }
    }

    /// Every lift trains something, and every score is on the 1–5 scale.
    ///
    /// Deliberately not requiring a 4 or 5 on every exercise: some accessories
    /// genuinely top out at 3 — a face pull, an adductor machine, a mountain
    /// climber — and inflating them to satisfy a rule would overstate the volume
    /// they contribute.
    @Test func everyExerciseScoresAtLeastOneMuscleInRange() {
        for entry in ExerciseLibrary.catalog {
            #expect(!entry.tension.isEmpty, "\(entry.name) scores no muscle")
            #expect(entry.tension.values.allSatisfy { (1...5).contains($0) },
                    "\(entry.name) has a tension score outside 1–5")
        }
    }

    // MARK: The 13 → 20 split

    /// Sets logged before the split must still decode. Only custom exercises can
    /// carry the old names — built-ins are re-synced from the catalogue — but a
    /// custom lift silently losing its muscles would corrupt volume history.
    @Test func preSplitMuscleNamesStillDecode() {
        #expect(MuscleGroup(stored: "shoulders") == .sideDelts)
        #expect(MuscleGroup(stored: "back") == .lats)
        #expect(MuscleGroup(stored: "core") == .upperAbs)
        // Current names keep working, and nonsense still fails.
        #expect(MuscleGroup(stored: "rearDelts") == .rearDelts)
        #expect(MuscleGroup(stored: "elbow") == nil)
    }

    /// End to end: a row written with the old vocabulary reads back as the new.
    @Test func anExerciseStoredWithOldNamesReadsBackSplit() {
        let old = Exercise(name: "Legacy Press", category: .barbell, tension: [:])
        old.tensionRaw = ["shoulders:5", "core:2"]
        #expect(old.tension[.sideDelts] == 5)
        #expect(old.tension[.upperAbs] == 2)
    }

    /// The split is only worth having if the catalogue actually uses it — a
    /// pressing movement must not credit rear delts, and a row must not credit
    /// front delts.
    @Test func theSplitIsActuallyExpressedInTheCatalogue() {
        let press = entry("Overhead Press").tension
        #expect(press[.frontDelts] == 5)
        #expect(press[.rearDelts] == nil)

        let fly = entry("Rear Delt Fly").tension
        #expect(fly[.rearDelts] == 5)
        #expect(fly[.frontDelts] == nil)

        // Incline loads the clavicular head; flat does not, beyond a little.
        #expect(entry("Incline Barbell Press").tension[.upperChest] == 5)
        #expect((entry("Barbell Bench Press").tension[.upperChest] ?? 0) <= 2)

        // A vertical pull is lats; a horizontal one is rhomboids and mid-traps.
        #expect(entry("Lat Pulldown").tension[.lats] == 5)
        #expect(entry("Seated Cable Row").tension[.rhomboids] == 5)
    }

    @Test func theCatalogueCoversEveryMuscleGroup() {
        var covered = Set<MuscleGroup>()
        for entry in ExerciseLibrary.catalog {
            for (muscle, score) in entry.tension where score >= 4 { covered.insert(muscle) }
        }
        // Two muscles are drawn but have no lift that trains them directly.
        // They are on the figure because they are visible and because a
        // compound movement still loads them, not because anyone programmes a
        // set for them. Exempting them beats inventing exercises nobody does.
        let noDirectLift: Set<MuscleGroup> = [.sartorius, .pectineus, .peroneals]
        for muscle in MuscleGroup.allCases where !noDirectLift.contains(muscle) {
            #expect(covered.contains(muscle),
                    "no exercise trains \(muscle.displayName) as a prime mover")
        }
    }
}
