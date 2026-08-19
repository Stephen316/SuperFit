import Testing
import Foundation
@testable import SuperFit

/// Guards the hand-written catalog against the mistakes the compiler can't catch:
/// a duplicated exercise, a tension score outside 1–5, an entry that names no
/// muscle, or a bodyweight fraction out of range. Seeding matches on name, so a
/// duplicate name would silently shadow one of the pair.
struct ExerciseCatalogTests {

    @Test("Exercise names are unique (case-insensitively)")
    func uniqueNames() {
        let names = ExerciseLibrary.catalog.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count)
    }

    @Test("Every tension score is a whole 1…5")
    func tensionsInRange() {
        for entry in ExerciseLibrary.catalog {
            for (muscle, score) in entry.tension {
                #expect((1...5).contains(score),
                        "\(entry.name) rates \(muscle) at \(score)")
            }
        }
    }

    @Test("Every entry names at least one muscle and has a non-empty name")
    func wellFormed() {
        for entry in ExerciseLibrary.catalog {
            #expect(!entry.name.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!entry.tension.isEmpty, "\(entry.name) targets no muscle")
        }
    }

    @Test("Bodyweight fractions are within 0…1")
    func bodyweightFractionsSane() {
        for entry in ExerciseLibrary.catalog {
            #expect((0...1).contains(entry.bodyweight), "\(entry.name): \(entry.bodyweight)")
        }
    }

    @Test("An alias never collides with a different exercise's display name")
    func aliasesDoNotShadowNames() {
        let names = Set(ExerciseLibrary.catalog.map { $0.name.lowercased() })
        for entry in ExerciseLibrary.catalog {
            for alias in entry.aliases where names.contains(alias.lowercased()) {
                Issue.record("\(entry.name) has alias '\(alias)' that is another exercise's name")
            }
        }
    }
}
