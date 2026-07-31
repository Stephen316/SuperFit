import Foundation
import SwiftData

/// Built-in exercise catalog with muscle-tension scores (1–5: how much tension
/// the muscle experiences in the lift; 5 = prime mover at long length /
/// maximal load, 1 = lightly assisting). Seeded into SwiftData on first launch.
enum ExerciseLibrary {

    typealias T = [MuscleGroup: Int]

    /// One catalogued lift.
    ///
    /// A struct rather than a tuple now that there are five fields: at that width
    /// positional arguments stop being readable, and swapping the tension map for
    /// the bodyweight fraction would fail silently.
    struct Entry {
        let name: String
        let category: ExerciseCategory
        let tension: T
        /// Fraction of bodyweight moved, for the bodyweight entries. Values are
        /// the standard biomechanics estimates: a pull-up/dip moves essentially
        /// all of you, a push-up ~65% (feet bear the rest), a plank is isometric
        /// so it carries no rep-based tonnage.
        let bodyweight: Double
        /// Other names the same lift goes by — abbreviations ("RDL", "OHP"),
        /// regional names, and what people actually type on the gym floor.
        ///
        /// **Searchable, never displayed.** One lift appears under one name so the
        /// list stays scannable and a year of logs stays comparable; the aliases
        /// only widen what finds it. "OHP" and "military press" both land on
        /// Overhead Press, and the row still reads "Overhead Press".
        let aliases: [String]

        init(_ name: String, _ category: ExerciseCategory, _ tension: T,
             bodyweight: Double = 0, alias: [String] = []) {
            self.name = name
            self.category = category
            self.tension = tension
            self.bodyweight = bodyweight
            self.aliases = alias
        }
    }

    static let catalog: [Entry] = [
        // MARK: Chest
        Entry("Barbell Bench Press", .barbell, [.chest: 5, .frontDelts: 3, .triceps: 3,
                                        .upperChest: 2],
              alias: ["bench press", "flat bench", "bb bench", "flat barbell press"]),
        Entry("Incline Barbell Press", .barbell, [.upperChest: 5, .chest: 3, .frontDelts: 3,
                                          .triceps: 3],
              alias: ["incline bench", "incline bench press"]),
        Entry("Decline Barbell Press", .barbell, [.chest: 5, .triceps: 3, .frontDelts: 2],
              alias: ["decline bench", "decline bench press"]),
        Entry("Close-Grip Bench Press", .barbell, [.triceps: 4, .chest: 3, .frontDelts: 2],
              alias: ["cgbp", "close grip bench", "narrow grip bench"]),
        Entry("Flat Dumbbell Press", .dumbbell, [.chest: 5, .triceps: 3, .frontDelts: 2,
                                         .upperChest: 2],
              alias: ["dumbbell bench press", "db bench", "db press"]),
        Entry("Incline Dumbbell Press", .dumbbell, [.upperChest: 5, .chest: 3, .frontDelts: 3,
                                            .triceps: 2],
              alias: ["incline db press", "incline dumbbell bench"]),
        Entry("Decline Dumbbell Press", .dumbbell, [.chest: 5, .triceps: 3],
              alias: ["decline db press"]),
        Entry("Machine Chest Press", .machine, [.chest: 5, .triceps: 3, .frontDelts: 2],
              alias: ["seated chest press", "hammer strength press",
                      "plate loaded chest press"]),
        Entry("Smith Machine Bench Press", .machine, [.chest: 5, .triceps: 3, .frontDelts: 2],
              alias: ["smith bench", "smith machine press"]),
        Entry("Cable Fly", .cable, [.chest: 5, .upperChest: 2, .frontDelts: 1],
              alias: ["cable crossover", "crossover", "standing fly"]),
        Entry("Low-to-High Cable Fly", .cable, [.upperChest: 5, .chest: 2, .frontDelts: 1],
              alias: ["incline cable fly", "low cable fly", "upper chest fly"]),
        Entry("Dumbbell Fly", .dumbbell, [.chest: 5, .frontDelts: 1],
              alias: ["flat fly", "chest fly", "db fly"]),
        Entry("Pec Deck", .machine, [.chest: 5, .upperChest: 1],
              alias: ["machine fly", "butterfly", "pec fly"]),
        Entry("Dip", .bodyweight, [.chest: 4, .triceps: 4, .frontDelts: 2],
              bodyweight: 1.0, alias: ["chest dip", "parallel bar dip", "bar dip"]),
        Entry("Push-Up", .bodyweight, [.chest: 4, .triceps: 3, .abs: 2, .frontDelts: 2],
              bodyweight: 0.65, alias: ["press up", "pushup", "press-up"]),
        Entry("Landmine Press", .barbell, [.frontDelts: 4, .upperChest: 3, .abs: 2, .triceps: 2],
              alias: ["landmine shoulder press", "half kneeling landmine press"]),

        // MARK: Shoulders
        Entry("Overhead Press", .barbell, [.frontDelts: 5, .sideDelts: 3, .triceps: 3, .abs: 2],
              alias: ["ohp", "military press", "standing press", "strict press",
                      "shoulder press", "barbell shoulder press"]),
        Entry("Push Press", .barbell, [.frontDelts: 5, .sideDelts: 3, .triceps: 3, .quads: 2],
              alias: ["barbell push press"]),
        Entry("Seated Dumbbell Press", .dumbbell, [.frontDelts: 5, .sideDelts: 3, .triceps: 3],
              alias: ["db shoulder press", "dumbbell shoulder press", "seated db press"]),
        Entry("Arnold Press", .dumbbell, [.frontDelts: 5, .sideDelts: 3, .triceps: 2],
              alias: ["arnolds", "rotating shoulder press"]),
        Entry("Machine Shoulder Press", .machine, [.frontDelts: 5, .sideDelts: 3, .triceps: 3],
              alias: ["seated machine press", "plate loaded shoulder press"]),
        Entry("Lateral Raise", .dumbbell, [.sideDelts: 5, .frontDelts: 1],
              alias: ["side raise", "lat raise", "side lateral raise", "db lateral"]),
        Entry("Cable Lateral Raise", .cable, [.sideDelts: 5],
              alias: ["cable side raise", "single arm cable lateral"]),
        Entry("Machine Lateral Raise", .machine, [.sideDelts: 5],
              alias: ["lateral raise machine"]),
        Entry("Rear Delt Fly", .dumbbell, [.rearDelts: 5, .upperBack: 2],
              alias: ["reverse fly", "rear delt raise", "bent over lateral raise",
                      "rear lateral raise"]),
        Entry("Cable Rear Delt Fly", .cable, [.rearDelts: 5, .upperBack: 2],
              alias: ["reverse cable fly", "cable reverse fly", "rear delt cable"]),
        Entry("Reverse Pec Deck", .machine, [.rearDelts: 5, .upperBack: 2],
              alias: ["rear delt machine", "reverse machine fly"]),
        Entry("Face Pull", .cable, [.rearDelts: 4, .upperBack: 3, .traps: 2],
              alias: ["cable face pull", "rope face pull"]),
        Entry("Front Raise", .dumbbell, [.frontDelts: 4],
              alias: ["front delt raise", "db front raise"]),
        Entry("Upright Row", .barbell, [.sideDelts: 4, .traps: 4, .biceps: 2],
              alias: ["barbell upright row", "cable upright row"]),

        // MARK: Back
        Entry("Deadlift", .barbell,
              [.lowerBack: 5, .glutes: 4, .hamstrings: 4, .traps: 3, .abs: 2, .forearms: 2,
               .lats: 2],
              alias: ["conventional deadlift", "dl", "barbell deadlift"]),
        Entry("Sumo Deadlift", .barbell,
              [.glutes: 5, .adductors: 4, .lowerBack: 4, .quads: 4, .hamstrings: 3,
               .traps: 3, .forearms: 2],
              alias: ["sumo dl", "wide stance deadlift"]),
        Entry("Trap Bar Deadlift", .barbell,
              [.glutes: 4, .lowerBack: 4, .quads: 4, .hamstrings: 3, .traps: 3, .forearms: 2],
              alias: ["hex bar deadlift", "trap bar dl", "hexbar deadlift"]),
        Entry("Deficit Deadlift", .barbell,
              [.lowerBack: 5, .glutes: 4, .hamstrings: 4, .traps: 3, .forearms: 2],
              alias: ["deficit dl"]),
        Entry("Rack Pull", .barbell, [.lowerBack: 4, .traps: 4, .forearms: 3, .lats: 2],
              alias: ["block pull", "partial deadlift"]),
        Entry("Power Clean", .barbell,
              [.traps: 5, .glutes: 4, .lowerBack: 4, .quads: 4, .upperBack: 3,
               .frontDelts: 2],
              alias: ["clean", "hang clean"]),
        Entry("Barbell Row", .barbell, [.upperBack: 5, .lats: 4, .biceps: 3, .forearms: 2,
                                .lowerBack: 2, .rearDelts: 2],
              alias: ["bent over row", "bor", "bent-over barbell row",
                      "barbell bent over row"]),
        Entry("Pendlay Row", .barbell, [.upperBack: 5, .lats: 4, .biceps: 3, .lowerBack: 2,
                                .traps: 2],
              alias: ["dead stop row", "strict barbell row"]),
        Entry("Dumbbell Row", .dumbbell, [.lats: 5, .upperBack: 4, .biceps: 3, .forearms: 2],
              alias: ["one arm row", "single arm dumbbell row", "db row", "kroc row"]),
        Entry("Chest-Supported Row", .machine, [.upperBack: 5, .lats: 4, .biceps: 3, .rearDelts: 3],
              alias: ["seal row", "incline bench row", "prone row"]),
        Entry("Meadows Row", .barbell, [.lats: 5, .upperBack: 4, .biceps: 3, .traps: 2],
              alias: ["landmine row", "single arm landmine row"]),
        Entry("Machine Row", .machine, [.upperBack: 5, .lats: 4, .biceps: 3],
              alias: ["hammer strength row", "plate loaded row", "iso row"]),
        Entry("Inverted Row", .bodyweight, [.upperBack: 4, .biceps: 3, .lats: 3, .abs: 2],
              bodyweight: 0.7,
              alias: ["body row", "australian pull up", "bodyweight row", "ring row"]),
        Entry("Pull-Up", .bodyweight, [.lats: 5, .biceps: 3, .upperBack: 3, .forearms: 2, .abs: 1],
              bodyweight: 1.0, alias: ["pullup", "wide grip pull up", "pull ups"]),
        Entry("Chin-Up", .bodyweight, [.biceps: 4, .lats: 4, .upperBack: 3, .forearms: 2],
              bodyweight: 1.0, alias: ["chinup", "underhand pull up", "supinated pull up"]),
        Entry("Neutral-Grip Pull-Up", .bodyweight, [.lats: 5, .biceps: 3, .upperBack: 3,
                                            .forearms: 2],
              bodyweight: 1.0, alias: ["hammer grip pull up", "parallel grip pull up"]),
        Entry("Lat Pulldown", .cable, [.lats: 5, .biceps: 3, .upperBack: 2],
              alias: ["pulldown", "front pulldown", "wide grip pulldown"]),
        Entry("Reverse-Grip Pulldown", .cable, [.lats: 5, .biceps: 4, .upperBack: 2],
              alias: ["underhand pulldown", "supinated pulldown"]),
        Entry("Single-Arm Lat Pulldown", .cable, [.lats: 5, .biceps: 3],
              alias: ["one arm pulldown", "unilateral pulldown"]),
        Entry("Seated Cable Row", .cable, [.upperBack: 5, .lats: 4, .biceps: 3, .traps: 2],
              alias: ["cable row", "low row", "seated row"]),
        Entry("T-Bar Row", .machine, [.upperBack: 5, .lats: 4, .biceps: 3, .lowerBack: 2],
              alias: ["tbar row", "t bar row"]),
        Entry("Straight-Arm Pulldown", .cable, [.lats: 4, .triceps: 1],
              alias: ["lat pullover cable", "stiff arm pulldown", "lat prayer"]),
        Entry("Dumbbell Pullover", .dumbbell, [.lats: 4, .chest: 3, .triceps: 2],
              alias: ["db pullover", "pullover"]),
        Entry("Barbell Shrug", .barbell, [.traps: 5, .forearms: 2],
              alias: ["shrug", "bb shrug"]),
        Entry("Dumbbell Shrug", .dumbbell, [.traps: 5, .forearms: 2],
              alias: ["db shrug"]),
        Entry("Back Extension", .bodyweight, [.lowerBack: 4, .glutes: 3, .hamstrings: 3],
              bodyweight: 0.45,
              alias: ["hyperextension", "45 degree back extension", "roman chair"]),
        Entry("Reverse Hyperextension", .machine,
              [.glutes: 4, .lowerBack: 4, .hamstrings: 3],
              alias: ["reverse hyper"]),

        // MARK: Biceps
        Entry("Barbell Curl", .barbell, [.biceps: 5, .forearms: 2],
              alias: ["bb curl", "straight bar curl"]),
        Entry("EZ Bar Curl", .barbell, [.biceps: 5, .forearms: 2],
              alias: ["ez curl", "cambered bar curl"]),
        Entry("Dumbbell Curl", .dumbbell, [.biceps: 5, .forearms: 2],
              alias: ["db curl", "bicep curl", "alternating curl"]),
        Entry("Hammer Curl", .dumbbell, [.biceps: 4, .forearms: 3],
              alias: ["neutral grip curl", "db hammer curl"]),
        Entry("Preacher Curl", .machine, [.biceps: 5],
              alias: ["scott curl", "preacher bench curl"]),
        Entry("Incline Dumbbell Curl", .dumbbell, [.biceps: 5],
              alias: ["incline curl", "seated incline curl"]),
        Entry("Concentration Curl", .dumbbell, [.biceps: 5],
              alias: ["seated concentration curl"]),
        Entry("Spider Curl", .dumbbell, [.biceps: 5],
              alias: ["prone incline curl"]),
        Entry("Cable Curl", .cable, [.biceps: 5, .forearms: 2],
              alias: ["cable bicep curl", "low pulley curl"]),
        Entry("Cable Hammer Curl", .cable, [.biceps: 4, .forearms: 3],
              alias: ["rope hammer curl", "rope curl"]),
        Entry("Reverse Curl", .barbell, [.forearms: 4, .biceps: 3],
              alias: ["pronated curl", "reverse grip curl"]),

        // MARK: Triceps
        Entry("Triceps Pushdown", .cable, [.triceps: 5],
              alias: ["tricep pushdown", "cable pushdown", "bar pushdown",
                      "tricep extension"]),
        Entry("Rope Triceps Pushdown", .cable, [.triceps: 5],
              alias: ["rope pushdown", "rope tricep extension"]),
        Entry("Overhead Triceps Extension", .cable, [.triceps: 5],
              alias: ["overhead extension", "cable overhead tricep", "french press"]),
        Entry("Dumbbell Overhead Extension", .dumbbell, [.triceps: 5],
              alias: ["single dumbbell overhead extension", "db overhead tricep"]),
        Entry("Skull Crusher", .barbell, [.triceps: 5],
              alias: ["lying triceps extension", "skullcrusher", "ez bar skull crusher"]),
        Entry("Triceps Kickback", .dumbbell, [.triceps: 4],
              alias: ["kickback", "tricep kickback"]),
        Entry("Bench Dip", .bodyweight, [.triceps: 4, .chest: 2, .frontDelts: 2],
              bodyweight: 0.6, alias: ["tricep dip", "chair dip"]),
        Entry("Diamond Push-Up", .bodyweight, [.triceps: 4, .chest: 3, .frontDelts: 2],
              bodyweight: 0.65, alias: ["close grip push up", "triangle push up"]),

        // MARK: Quads
        Entry("Barbell Squat", .barbell, [.quads: 5, .glutes: 4, .adductors: 3, .abs: 2,
                                  .lowerBack: 2],
              alias: ["back squat", "squat", "high bar squat", "low bar squat"]),
        Entry("Front Squat", .barbell, [.quads: 5, .abs: 3, .glutes: 3, .upperBack: 2],
              alias: ["fs", "barbell front squat"]),
        Entry("Smith Machine Squat", .machine, [.quads: 5, .glutes: 3, .adductors: 2],
              alias: ["smith squat"]),
        Entry("Box Squat", .barbell, [.glutes: 5, .quads: 4, .lowerBack: 2],
              alias: ["squat to box"]),
        Entry("Leg Press", .machine, [.quads: 5, .glutes: 3, .adductors: 2],
              alias: ["45 degree leg press", "horizontal leg press", "seated leg press"]),
        Entry("Single-Leg Press", .machine, [.quads: 5, .glutes: 4],
              alias: ["one leg press", "unilateral leg press"]),
        Entry("Hack Squat", .machine, [.quads: 5, .glutes: 3],
              alias: ["machine hack squat"]),
        Entry("Pendulum Squat", .machine, [.quads: 5, .glutes: 3],
              alias: ["pendulum"]),
        Entry("Belt Squat", .machine, [.quads: 5, .glutes: 3],
              alias: ["hip belt squat"]),
        Entry("Leg Extension", .machine, [.quads: 5],
              alias: ["quad extension", "knee extension"]),
        Entry("Bulgarian Split Squat", .dumbbell, [.quads: 5, .glutes: 4, .adductors: 2, .abs: 1],
              bodyweight: 0.85,
              alias: ["rfess", "rear foot elevated split squat", "bulgarians"]),
        Entry("Split Squat", .dumbbell, [.quads: 5, .glutes: 4],
              bodyweight: 0.85, alias: ["static lunge", "stationary lunge"]),
        Entry("Walking Lunge", .dumbbell,
              [.glutes: 4, .quads: 4, .adductors: 2, .hamstrings: 2],
              bodyweight: 0.85, alias: ["lunge", "db walking lunge"]),
        Entry("Reverse Lunge", .dumbbell, [.glutes: 4, .quads: 4, .hamstrings: 2],
              bodyweight: 0.85, alias: ["backward lunge", "step back lunge"]),
        Entry("Step-Up", .dumbbell, [.glutes: 4, .quads: 4],
              bodyweight: 0.85, alias: ["box step up", "db step up"]),
        Entry("Goblet Squat", .dumbbell, [.quads: 4, .glutes: 3, .abs: 2],
              alias: ["kettlebell goblet squat", "db goblet squat"]),
        Entry("Sissy Squat", .bodyweight, [.quads: 5],
              bodyweight: 0.7, alias: ["sissy"]),

        // MARK: Hamstrings and glutes
        Entry("Romanian Deadlift", .barbell,
              [.hamstrings: 5, .glutes: 4, .lowerBack: 3, .forearms: 2],
              alias: ["rdl", "romanian dl", "barbell rdl"]),
        Entry("Stiff-Leg Deadlift", .barbell,
              [.hamstrings: 5, .lowerBack: 4, .glutes: 3, .forearms: 2],
              alias: ["sldl", "straight leg deadlift"]),
        Entry("Single-Leg Romanian Deadlift", .dumbbell,
              [.hamstrings: 5, .glutes: 4, .abs: 2, .lowerBack: 2],
              alias: ["single leg rdl", "sl rdl", "one leg rdl"]),
        Entry("Lying Leg Curl", .machine, [.hamstrings: 5, .calves: 1],
              alias: ["leg curl", "prone leg curl", "hamstring curl"]),
        Entry("Seated Leg Curl", .machine, [.hamstrings: 5],
              alias: ["seated hamstring curl"]),
        Entry("Standing Leg Curl", .machine, [.hamstrings: 5],
              alias: ["single leg curl standing"]),
        Entry("Nordic Curl", .bodyweight, [.hamstrings: 5, .abs: 2],
              bodyweight: 0.6,
              alias: ["nordic hamstring curl", "nordics", "natural glute ham raise"]),
        Entry("Glute Ham Raise", .bodyweight,
              [.hamstrings: 5, .glutes: 3, .lowerBack: 2],
              bodyweight: 0.7, alias: ["ghr", "glute-ham raise"]),
        Entry("Hip Thrust", .barbell, [.glutes: 5, .hamstrings: 3, .quads: 1],
              alias: ["barbell hip thrust", "bench hip thrust"]),
        Entry("Machine Hip Thrust", .machine, [.glutes: 5, .hamstrings: 3],
              alias: ["glute drive", "hip thrust machine"]),
        Entry("Glute Bridge", .bodyweight, [.glutes: 4, .hamstrings: 2],
              bodyweight: 0.35, alias: ["floor bridge"]),
        Entry("Cable Pull-Through", .cable, [.glutes: 5, .hamstrings: 4, .lowerBack: 2],
              alias: ["pull through", "rope pull through"]),
        Entry("Good Morning", .barbell, [.hamstrings: 4, .lowerBack: 4, .glutes: 3],
              alias: ["gm", "barbell good morning"]),
        Entry("Cable Kickback", .cable, [.glutes: 4],
              alias: ["glute kickback", "cable glute kickback"]),
        Entry("Hip Abduction", .machine, [.abductors: 5, .glutes: 3],
              alias: ["abductor machine", "abduction machine", "outer thigh machine"]),
        Entry("Hip Adduction", .machine, [.adductors: 5],
              alias: ["adductor machine", "inner thigh machine"]),

        // MARK: Calves
        Entry("Standing Calf Raise", .machine, [.calves: 5],
              alias: ["calf raise", "standing calves"]),
        Entry("Seated Calf Raise", .machine, [.calves: 5],
              alias: ["seated calves", "soleus raise"]),
        Entry("Leg Press Calf Raise", .machine, [.calves: 5],
              alias: ["calf press", "leg press calves"]),
        Entry("Single-Leg Calf Raise", .bodyweight, [.calves: 5],
              bodyweight: 0.9, alias: ["one leg calf raise", "unilateral calf raise"]),

        // MARK: Forearms and grip
        Entry("Wrist Curl", .dumbbell, [.forearms: 5],
              alias: ["barbell wrist curl", "seated wrist curl"]),
        Entry("Reverse Wrist Curl", .dumbbell, [.forearms: 5],
              alias: ["wrist extension"]),
        Entry("Farmer's Walk", .dumbbell, [.forearms: 5, .traps: 4, .abs: 3],
              alias: ["farmers carry", "farmer carry", "loaded carry"]),
        Entry("Dead Hang", .bodyweight, [.forearms: 5, .lats: 2],
              bodyweight: 1.0, alias: ["bar hang", "hanging"]),

        // MARK: Core
        Entry("Plank", .bodyweight, [.abs: 4, .obliques: 2], bodyweight: 0.0,
              alias: ["front plank", "forearm plank"]),
        Entry("Side Plank", .bodyweight, [.obliques: 5, .abs: 2], bodyweight: 0.0,
              alias: ["lateral plank"]),
        Entry("Cable Crunch", .cable, [.abs: 5, .obliques: 2],
              alias: ["kneeling cable crunch", "rope crunch"]),
        Entry("Crunch", .bodyweight, [.abs: 4], bodyweight: 0.3,
              alias: ["floor crunch", "ab crunch"]),
        Entry("Sit-Up", .bodyweight, [.abs: 4, .obliques: 2], bodyweight: 0.4,
              alias: ["situp", "decline sit up", "full sit up"]),
        Entry("Hanging Leg Raise", .bodyweight, [.abs: 5, .obliques: 2, .forearms: 1],
              bodyweight: 0.45,
              alias: ["hanging knee raise", "leg raise", "captains chair leg raise"]),
        Entry("Ab Wheel Rollout", .bodyweight, [.abs: 5, .lats: 2, .frontDelts: 1],
              bodyweight: 0.45, alias: ["ab roller", "wheel rollout"]),
        Entry("Russian Twist", .bodyweight, [.obliques: 5, .abs: 3], bodyweight: 0.3,
              alias: ["seated twist", "oblique twist"]),
        Entry("Pallof Press", .cable, [.obliques: 4, .abs: 3],
              alias: ["anti rotation press", "cable pallof"]),
        Entry("Cable Woodchop", .cable, [.obliques: 5, .abs: 3],
              alias: ["woodchopper", "wood chop", "cable chop"]),
        Entry("Dead Bug", .bodyweight, [.abs: 4], bodyweight: 0.2,
              alias: ["deadbug"]),
        Entry("Mountain Climber", .bodyweight, [.abs: 3, .frontDelts: 2, .quads: 2],
              bodyweight: 0.5, alias: ["mountain climbers"]),
        Entry("Hollow Hold", .bodyweight, [.abs: 5], bodyweight: 0.0,
              alias: ["hollow body hold"]),
    ]

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        if existing.isEmpty {
            for e in catalog {
                context.insert(Exercise(name: e.name, category: e.category,
                                        tension: e.tension,
                                        bodyweightFraction: e.bodyweight,
                                        aliases: e.aliases))
            }
            try? context.save()
            return
        }
        // Migrate rows written before tension / bodyweight-fraction / aliases
        // existed, and add newly-catalogued exercises by name.
        let byName = Dictionary(grouping: existing, by: \.name)
        var changed = false
        for e in catalog {
            if let row = byName[e.name]?.first {
                // Re-synced every launch, not only when empty. Tension is
                // catalogue data and never user-edited for a built-in, so the
                // current scores must win — otherwise splitting "shoulders" into
                // front/side/rear delts would only reach a fresh install, and
                // everyone else would keep scoring against muscles that no longer
                // exist. Custom exercises are not in the catalogue and untouched.
                if row.tension != e.tension {
                    row.tension = e.tension
                    changed = true
                }
                if row.bodyweightFraction != e.bodyweight {
                    row.bodyweightFraction = e.bodyweight
                    changed = true
                }
                // Aliases are catalogue data and never user-edited, so an existing
                // row takes the current list rather than keeping an older one.
                // That's how a newly added alias reaches someone who already has
                // the exercise seeded.
                if row.aliases != e.aliases {
                    row.aliases = e.aliases
                    changed = true
                }
            } else {
                context.insert(Exercise(name: e.name, category: e.category,
                                        tension: e.tension,
                                        bodyweightFraction: e.bodyweight,
                                        aliases: e.aliases))
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
