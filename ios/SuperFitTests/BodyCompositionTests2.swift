import Testing
import Foundation
@testable import SuperFit

/// Lean mass has to survive a day the user typed by hand, or the protein target
/// and the basal formula swing on no new evidence.
struct RecentLeanMassTests {

    private let cal = Calendar(identifier: .gregorian)

    private func row(daysAgo: Int, weight: Double, lean: Double?) -> BodyMetrics {
        let m = BodyMetrics(date: cal.date(byAdding: .day, value: -daysAgo, to: .now)!,
                            weightKg: weight)
        m.leanMassKg = lean
        return m
    }

    /// The reported shape: smart scale on Monday, typed by hand on Tuesday.
    @Test func aManualWeighInDoesNotDiscardYesterdaysComposition() {
        let metrics = [row(daysAgo: 0, weight: 80, lean: nil),
                       row(daysAgo: 1, weight: 80.2, lean: 65)]
        #expect(BodyComposition.recentLeanMassKg(metrics) == 65)
    }

    @Test func theNewestReadingWinsWhenThereAreSeveral() {
        let metrics = [row(daysAgo: 0, weight: 80, lean: 66),
                       row(daysAgo: 5, weight: 81, lean: 64)]
        #expect(BodyComposition.recentLeanMassKg(metrics) == 66)
    }

    /// It expires. A figure from last spring describes somebody else, and
    /// carrying it forever would be worse than falling back to Mifflin.
    @Test func aStaleReadingIsNotUsed() {
        let fresh = [row(daysAgo: 29, weight: 80, lean: 65)]
        let stale = [row(daysAgo: 31, weight: 80, lean: 65)]
        #expect(BodyComposition.recentLeanMassKg(fresh) == 65)
        #expect(BodyComposition.recentLeanMassKg(stale) == nil)
    }

    /// Nonsense is not a measurement: a lean mass at or above bodyweight would
    /// push the Katch-McArdle basal above anything real.
    @Test func implausibleReadingsAreRejected() {
        #expect(BodyComposition.recentLeanMassKg([row(daysAgo: 0, weight: 80, lean: 0)]) == nil)
        #expect(BodyComposition.recentLeanMassKg([row(daysAgo: 0, weight: 80, lean: -5)]) == nil)
        #expect(BodyComposition.recentLeanMassKg([row(daysAgo: 0, weight: 80, lean: 95)]) == nil)
        // Falls through to the older valid one rather than giving up.
        let mixed = [row(daysAgo: 0, weight: 80, lean: 95), row(daysAgo: 2, weight: 80, lean: 65)]
        #expect(BodyComposition.recentLeanMassKg(mixed) == 65)
    }

    /// The boundary itself. Lean mass equal to bodyweight is 0% body fat — not a
    /// person, and reachable only through a hand-edited archive, since every
    /// writer in the app clamps body fat to 3–70%. All three guards on this
    /// invariant are strict; they used to disagree.
    @Test func leanMassEqualToBodyweightIsRejected() {
        #expect(BodyComposition.recentLeanMassKg([row(daysAgo: 0, weight: 80, lean: 80)]) == nil)
        #expect(BodyComposition.recentLeanMassKg([row(daysAgo: 0, weight: 80, lean: 79.9)]) == 79.9)
    }

    /// And the basal estimate declines it too, rather than taking a figure
    /// `BodyComposition` would have refused to hand it.
    @Test func katchMcArdleDeclinesAZeroBodyFatReading() {
        let engine = MetabolismEngine()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func basal(lean: Double?) -> Double {
            let records = (0..<20).map { d in
                DailyRecord(date: cal.date(byAdding: .day, value: d, to: start)!,
                            intakeKcal: 2500, weightKg: 80)
            }
            return engine.estimate(
                records: records, windowDays: 30,
                prior: .init(sex: .male, ageYears: 30, heightCm: 180,
                             activity: .moderate, leanMassKg: lean),
                asOf: cal.date(byAdding: .day, value: 20, to: start)!).basalKcal
        }
        // 0% body fat falls back to Mifflin, which is what a refusal looks like.
        #expect(basal(lean: 80) == basal(lean: nil))
        // A real reading still switches to Katch-McArdle.
        #expect(basal(lean: 65) != basal(lean: nil))
    }

    @Test func noCompositionAtAllIsNil() {
        #expect(BodyComposition.recentLeanMassKg([row(daysAgo: 0, weight: 80, lean: nil)]) == nil)
        #expect(BodyComposition.recentLeanMassKg([]) == nil)
    }

    /// What the flip actually cost, measured rather than assumed.
    ///
    /// For an average build the two bases nearly agree — `defaultProtein`
    /// carries higher per-kg figures for lean mass (2.4 against 2.0) precisely
    /// so they do, and 80 kg at 65 kg LBM comes out 156 g against 160 g. The
    /// calibration is working, and the flip is nearly free.
    ///
    /// It is the people furthest from average who paid, which is exactly who the
    /// lean-mass basis exists for: at 100 kg and 65 kg LBM the same day reads
    /// 156 g or 200 g depending on whether the last row happened to carry a
    /// composition reading.
    @Test func theFlipCostsMostForBodiesFurthestFromAverage() {
        let calc = MacroCalculator()

        func gap(bodyweight: Double, lean: Double) -> Double {
            let onLean = calc.targets(kcal: 2400, goal: .recomposition,
                                      bodyweightKg: bodyweight, leanMassKg: lean)
            let onBodyweight = calc.targets(kcal: 2400, goal: .recomposition,
                                            bodyweightKg: bodyweight, leanMassKg: nil)
            return abs(onLean.proteinG - onBodyweight.proteinG)
        }

        #expect(gap(bodyweight: 80, lean: 65) < 10, "average build: the bases agree")
        #expect(gap(bodyweight: 100, lean: 65) > 35, "higher body fat: they do not")
    }
}

/// The archive has to round-trip what the user can create.
@MainActor
struct ArchiveAliasTests {

    @Test func aliasesSurviveTheRoundTrip() throws {
        var archive = DataArchive()
        archive.exercises = [
            .init(id: UUID(), name: "Romanian Deadlift", category: "barbell",
                  tension: ["bicepsFemoris:5"], bodyweightFraction: 0, isCustom: true,
                  aliases: ["RDL", "stiff leg deadlift"])
        ]
        let decoded = try DataArchiveService.decode(DataArchiveService.encode(archive))
        #expect(decoded.exercises.first?.aliases == ["RDL", "stiff leg deadlift"])
    }

    /// An archive written before the field existed must still open. Swift's
    /// synthesised decoding ignores property defaults, so this only works
    /// because the field is optional — worth pinning.
    @Test func anArchiveWithoutAliasesStillDecodes() throws {
        let json = """
        {
          "version": 1,
          "exportedAt": "2026-01-01T00:00:00Z",
          "bodyMetrics": [], "foods": [], "nutritionLogs": [],
          "exercises": [{
            "id": "\(UUID().uuidString)", "name": "Bench", "category": "barbell",
            "tension": ["chest:5"], "bodyweightFraction": 0, "isCustom": true
          }],
          "sessions": [], "templates": [], "supplements": [],
          "supplementEntries": [], "sleep": [], "vitals": [], "energy": []
        }
        """
        let decoded = try DataArchiveService.decode(Data(json.utf8))
        #expect(decoded.exercises.count == 1)
        #expect(decoded.exercises.first?.aliases == nil)
    }
}
