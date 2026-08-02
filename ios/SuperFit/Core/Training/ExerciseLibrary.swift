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
        Entry("Barbell Bench Press", .barbell, [.chest: 5, .frontDelts: 3, .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2,
                                        .upperChest: 2],
              alias: ["bench press", "flat bench", "bb bench", "flat barbell press"]),
        Entry("Incline Barbell Press", .barbell, [.upperChest: 5, .chest: 3, .frontDelts: 3,
                                          .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2],
              alias: ["incline bench", "incline bench press"]),
        Entry("Decline Barbell Press", .barbell, [.chest: 5, .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2, .frontDelts: 2],
              alias: ["decline bench", "decline bench press"]),
        Entry("Close-Grip Bench Press", .barbell, [.tricepsLateral: 4, .tricepsLong: 4, .tricepsMedial: 3, .chest: 3, .frontDelts: 2],
              alias: ["cgbp", "close grip bench", "narrow grip bench"]),
        Entry("Flat Dumbbell Press", .dumbbell, [.chest: 5, .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2, .frontDelts: 2,
                                         .upperChest: 2],
              alias: ["dumbbell bench press", "db bench", "db press"]),
        Entry("Incline Dumbbell Press", .dumbbell, [.upperChest: 5, .chest: 3, .frontDelts: 3,
                                            .tricepsLateral: 2, .tricepsLong: 2, .tricepsMedial: 1],
              alias: ["incline db press", "incline dumbbell bench"]),
        Entry("Decline Dumbbell Press", .dumbbell, [.chest: 5, .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2],
              alias: ["decline db press"]),
        Entry("Machine Chest Press", .machine, [.chest: 5, .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2, .frontDelts: 2],
              alias: ["seated chest press", "hammer strength press",
                      "plate loaded chest press"]),
        Entry("Smith Machine Bench Press", .machine, [.chest: 5, .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2, .frontDelts: 2],
              alias: ["smith bench", "smith machine press"]),
        Entry("Cable Fly", .cable, [.chest: 5, .upperChest: 2, .frontDelts: 1],
              alias: ["cable crossover", "crossover", "standing fly"]),
        Entry("Low-to-High Cable Fly", .cable, [.upperChest: 5, .chest: 2, .frontDelts: 1],
              alias: ["incline cable fly", "low cable fly", "upper chest fly"]),
        Entry("Dumbbell Fly", .dumbbell, [.chest: 5, .frontDelts: 1],
              alias: ["flat fly", "chest fly", "db fly"]),
        Entry("Pec Deck", .machine, [.chest: 5, .upperChest: 1],
              alias: ["machine fly", "butterfly", "pec fly"]),
        Entry("Dip", .bodyweight, [.chest: 4, .tricepsLateral: 4, .tricepsLong: 4, .tricepsMedial: 3, .frontDelts: 2],
              bodyweight: 1.0, alias: ["chest dip", "parallel bar dip", "bar dip"]),
        Entry("Push-Up", .bodyweight, [.chest: 4, .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2, .upperAbs: 2, .lowerAbs: 2, .frontDelts: 2],
              bodyweight: 0.65, alias: ["press up", "pushup", "press-up"]),
        Entry("Landmine Press", .barbell, [.frontDelts: 4, .upperChest: 3, .upperAbs: 2, .lowerAbs: 2, .tricepsLateral: 2, .tricepsLong: 2, .tricepsMedial: 1],
              alias: ["landmine shoulder press", "half kneeling landmine press"]),

        // MARK: Shoulders
        Entry("Overhead Press", .barbell, [.frontDelts: 5, .sideDelts: 3, .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2, .upperAbs: 2, .lowerAbs: 2],
              alias: ["ohp", "military press", "standing press", "strict press",
                      "shoulder press", "barbell shoulder press"]),
        Entry("Push Press", .barbell, [.frontDelts: 5, .sideDelts: 3, .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2, .vastusLateralis: 2, .vastusMedialis: 2, .rectusFemoris: 2],
              alias: ["barbell push press"]),
        Entry("Seated Dumbbell Press", .dumbbell, [.frontDelts: 5, .sideDelts: 3, .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2],
              alias: ["db shoulder press", "dumbbell shoulder press", "seated db press"]),
        Entry("Arnold Press", .dumbbell, [.frontDelts: 5, .sideDelts: 3, .tricepsLateral: 2, .tricepsLong: 2, .tricepsMedial: 1],
              alias: ["arnolds", "rotating shoulder press"]),
        Entry("Machine Shoulder Press", .machine, [.frontDelts: 5, .sideDelts: 3, .tricepsLateral: 3, .tricepsLong: 3, .tricepsMedial: 2],
              alias: ["seated machine press", "plate loaded shoulder press"]),
        Entry("Lateral Raise", .dumbbell, [.sideDelts: 5, .frontDelts: 1],
              alias: ["side raise", "lat raise", "side lateral raise", "db lateral"]),
        Entry("Cable Lateral Raise", .cable, [.sideDelts: 5],
              alias: ["cable side raise", "single arm cable lateral"]),
        Entry("Machine Lateral Raise", .machine, [.sideDelts: 5],
              alias: ["lateral raise machine"]),
        Entry("Rear Delt Fly", .dumbbell, [.rearDelts: 5, .rhomboids: 2, .middleTraps: 2],
              alias: ["reverse fly", "rear delt raise", "bent over lateral raise",
                      "rear lateral raise"]),
        Entry("Cable Rear Delt Fly", .cable, [.rearDelts: 5, .rhomboids: 2, .middleTraps: 2],
              alias: ["reverse cable fly", "cable reverse fly", "rear delt cable"]),
        Entry("Reverse Pec Deck", .machine, [.rearDelts: 5, .rhomboids: 2, .middleTraps: 2],
              alias: ["rear delt machine", "reverse machine fly"]),
        Entry("Face Pull", .cable, [.rearDelts: 4, .rhomboids: 3, .middleTraps: 3, .upperTraps: 2, .lowerTraps: 1],
              alias: ["cable face pull", "rope face pull"]),
        Entry("Front Raise", .dumbbell, [.frontDelts: 4],
              alias: ["front delt raise", "db front raise"]),
        Entry("Upright Row", .barbell, [.sideDelts: 4, .upperTraps: 4, .middleTraps: 3, .lowerTraps: 3, .biceps: 2],
              alias: ["barbell upright row", "cable upright row"]),

        // MARK: Back
        Entry("Deadlift", .barbell,
              [.erectorSpinae: 5, .gluteusMaximus: 4, .gluteusMedius: 2, .bicepsFemoris: 4, .semitendinosus: 4, .upperTraps: 3, .middleTraps: 2, .lowerTraps: 2, .upperAbs: 2, .lowerAbs: 2, .wristFlexors: 2, .brachioradialis: 1,
               .lats: 2],
              alias: ["conventional deadlift", "dl", "barbell deadlift"]),
        Entry("Sumo Deadlift", .barbell,
              [.gluteusMaximus: 5, .gluteusMedius: 3, .adductorLongus: 4, .adductorMagnus: 4, .pectineus: 3, .erectorSpinae: 4, .vastusLateralis: 4, .vastusMedialis: 4, .rectusFemoris: 4, .bicepsFemoris: 3, .semitendinosus: 3,
               .upperTraps: 3, .middleTraps: 2, .lowerTraps: 2, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["sumo dl", "wide stance deadlift"]),
        Entry("Trap Bar Deadlift", .barbell,
              [.gluteusMaximus: 4, .gluteusMedius: 2, .erectorSpinae: 4, .vastusLateralis: 4, .vastusMedialis: 4, .rectusFemoris: 4, .bicepsFemoris: 3, .semitendinosus: 3, .upperTraps: 3, .middleTraps: 2, .lowerTraps: 2, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["hex bar deadlift", "trap bar dl", "hexbar deadlift"]),
        Entry("Deficit Deadlift", .barbell,
              [.erectorSpinae: 5, .gluteusMaximus: 4, .gluteusMedius: 2, .bicepsFemoris: 4, .semitendinosus: 4, .upperTraps: 3, .middleTraps: 2, .lowerTraps: 2, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["deficit dl"]),
        Entry("Rack Pull", .barbell, [.erectorSpinae: 4, .upperTraps: 4, .middleTraps: 3, .lowerTraps: 3, .wristFlexors: 3, .brachioradialis: 2, .lats: 2],
              alias: ["block pull", "partial deadlift"]),
        Entry("Power Clean", .barbell,
              [.upperTraps: 5, .middleTraps: 4, .lowerTraps: 4, .gluteusMaximus: 4, .gluteusMedius: 2, .erectorSpinae: 4, .vastusLateralis: 4, .vastusMedialis: 4, .rectusFemoris: 4, .rhomboids: 3, .frontDelts: 2],
              alias: ["clean", "hang clean"]),
        Entry("Barbell Row", .barbell, [.rhomboids: 5, .middleTraps: 5, .lats: 4, .biceps: 3, .wristFlexors: 2, .brachioradialis: 1,
                                .erectorSpinae: 2, .rearDelts: 2],
              alias: ["bent over row", "bor", "bent-over barbell row",
                      "barbell bent over row"]),
        Entry("Pendlay Row", .barbell, [.rhomboids: 5, .middleTraps: 5, .lats: 4, .biceps: 3, .erectorSpinae: 2, .upperTraps: 2, .lowerTraps: 1],
              alias: ["dead stop row", "strict barbell row"]),
        Entry("Dumbbell Row", .dumbbell, [.lats: 5, .rhomboids: 4, .middleTraps: 4, .biceps: 3, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["one arm row", "single arm dumbbell row", "db row", "kroc row"]),
        Entry("Chest-Supported Row", .machine, [.rhomboids: 5, .middleTraps: 5, .lats: 4, .biceps: 3, .rearDelts: 3],
              alias: ["seal row", "incline bench row", "prone row"]),
        Entry("Meadows Row", .barbell, [.lats: 5, .rhomboids: 4, .middleTraps: 4, .biceps: 3, .upperTraps: 2, .lowerTraps: 1],
              alias: ["landmine row", "single arm landmine row"]),
        Entry("Machine Row", .machine, [.rhomboids: 5, .middleTraps: 5, .lats: 4, .biceps: 3],
              alias: ["hammer strength row", "plate loaded row", "iso row"]),
        Entry("Inverted Row", .bodyweight, [.rhomboids: 4, .middleTraps: 4, .biceps: 3, .lats: 3, .upperAbs: 2, .lowerAbs: 2],
              bodyweight: 0.7,
              alias: ["body row", "australian pull up", "bodyweight row", "ring row"]),
        Entry("Pull-Up", .bodyweight, [.lats: 5, .biceps: 3, .rhomboids: 3, .middleTraps: 3, .wristFlexors: 2, .brachioradialis: 1, .upperAbs: 1, .lowerAbs: 1],
              bodyweight: 1.0, alias: ["pullup", "wide grip pull up", "pull ups"]),
        Entry("Chin-Up", .bodyweight, [.biceps: 4, .lats: 4, .rhomboids: 3, .middleTraps: 3, .wristFlexors: 2, .brachioradialis: 1],
              bodyweight: 1.0, alias: ["chinup", "underhand pull up", "supinated pull up"]),
        Entry("Neutral-Grip Pull-Up", .bodyweight, [.lats: 5, .biceps: 3, .rhomboids: 3, .middleTraps: 3,
                                            .wristFlexors: 2, .brachioradialis: 1],
              bodyweight: 1.0, alias: ["hammer grip pull up", "parallel grip pull up"]),
        Entry("Lat Pulldown", .cable, [.lats: 5, .biceps: 3, .rhomboids: 2, .middleTraps: 2],
              alias: ["pulldown", "front pulldown", "wide grip pulldown"]),
        Entry("Reverse-Grip Pulldown", .cable, [.lats: 5, .biceps: 4, .rhomboids: 2, .middleTraps: 2],
              alias: ["underhand pulldown", "supinated pulldown"]),
        Entry("Single-Arm Lat Pulldown", .cable, [.lats: 5, .biceps: 3],
              alias: ["one arm pulldown", "unilateral pulldown"]),
        Entry("Seated Cable Row", .cable, [.rhomboids: 5, .middleTraps: 5, .lats: 4, .biceps: 3, .upperTraps: 2, .lowerTraps: 1],
              alias: ["cable row", "low row", "seated row"]),
        Entry("T-Bar Row", .machine, [.rhomboids: 5, .middleTraps: 5, .lats: 4, .biceps: 3, .erectorSpinae: 2],
              alias: ["tbar row", "t bar row"]),
        Entry("Straight-Arm Pulldown", .cable, [.lats: 4, .tricepsLateral: 1, .tricepsLong: 1, .tricepsMedial: 1],
              alias: ["lat pullover cable", "stiff arm pulldown", "lat prayer"]),
        Entry("Dumbbell Pullover", .dumbbell, [.lats: 4, .serratus: 4, .chest: 3, .tricepsLateral: 2, .tricepsLong: 2, .tricepsMedial: 1],
              alias: ["db pullover", "pullover"]),
        Entry("Barbell Shrug", .barbell, [.upperTraps: 5, .middleTraps: 4, .lowerTraps: 4, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["shrug", "bb shrug"]),
        Entry("Dumbbell Shrug", .dumbbell, [.upperTraps: 5, .middleTraps: 4, .lowerTraps: 4, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["db shrug"]),
        Entry("Back Extension", .bodyweight, [.erectorSpinae: 4, .gluteusMaximus: 3, .gluteusMedius: 1, .bicepsFemoris: 3, .semitendinosus: 3],
              bodyweight: 0.45,
              alias: ["hyperextension", "45 degree back extension", "roman chair"]),
        Entry("Reverse Hyperextension", .machine,
              [.gluteusMaximus: 4, .gluteusMedius: 2, .erectorSpinae: 4, .bicepsFemoris: 3, .semitendinosus: 3],
              alias: ["reverse hyper"]),

        // MARK: Biceps
        Entry("Barbell Curl", .barbell, [.biceps: 5, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["bb curl", "straight bar curl"]),
        Entry("EZ Bar Curl", .barbell, [.biceps: 5, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["ez curl", "cambered bar curl"]),
        Entry("Dumbbell Curl", .dumbbell, [.biceps: 5, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["db curl", "bicep curl", "alternating curl"]),
        Entry("Hammer Curl", .dumbbell, [.biceps: 4, .wristFlexors: 3, .brachioradialis: 2],
              alias: ["neutral grip curl", "db hammer curl"]),
        Entry("Preacher Curl", .machine, [.biceps: 5],
              alias: ["scott curl", "preacher bench curl"]),
        Entry("Incline Dumbbell Curl", .dumbbell, [.biceps: 5],
              alias: ["incline curl", "seated incline curl"]),
        Entry("Concentration Curl", .dumbbell, [.biceps: 5],
              alias: ["seated concentration curl"]),
        Entry("Spider Curl", .dumbbell, [.biceps: 5],
              alias: ["prone incline curl"]),
        Entry("Cable Curl", .cable, [.biceps: 5, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["cable bicep curl", "low pulley curl"]),
        Entry("Cable Hammer Curl", .cable, [.biceps: 4, .wristFlexors: 3, .brachioradialis: 2],
              alias: ["rope hammer curl", "rope curl"]),
        Entry("Reverse Curl", .barbell, [.wristFlexors: 4, .brachioradialis: 3, .biceps: 3],
              alias: ["pronated curl", "reverse grip curl"]),

        // MARK: Triceps
        Entry("Triceps Pushdown", .cable, [.tricepsLateral: 5, .tricepsLong: 5, .tricepsMedial: 4],
              alias: ["tricep pushdown", "cable pushdown", "bar pushdown",
                      "tricep extension"]),
        Entry("Rope Triceps Pushdown", .cable, [.tricepsLateral: 5, .tricepsLong: 5, .tricepsMedial: 4],
              alias: ["rope pushdown", "rope tricep extension"]),
        Entry("Overhead Triceps Extension", .cable, [.tricepsLateral: 5, .tricepsLong: 5, .tricepsMedial: 4],
              alias: ["overhead extension", "cable overhead tricep", "french press"]),
        Entry("Dumbbell Overhead Extension", .dumbbell, [.tricepsLateral: 5, .tricepsLong: 5, .tricepsMedial: 4],
              alias: ["single dumbbell overhead extension", "db overhead tricep"]),
        Entry("Skull Crusher", .barbell, [.tricepsLateral: 5, .tricepsLong: 5, .tricepsMedial: 4],
              alias: ["lying triceps extension", "skullcrusher", "ez bar skull crusher"]),
        Entry("Triceps Kickback", .dumbbell, [.tricepsLateral: 4, .tricepsLong: 4, .tricepsMedial: 3],
              alias: ["kickback", "tricep kickback"]),
        Entry("Bench Dip", .bodyweight, [.tricepsLateral: 4, .tricepsLong: 4, .tricepsMedial: 3, .chest: 2, .frontDelts: 2],
              bodyweight: 0.6, alias: ["tricep dip", "chair dip"]),
        Entry("Diamond Push-Up", .bodyweight, [.tricepsLateral: 4, .tricepsLong: 4, .tricepsMedial: 3, .chest: 3, .frontDelts: 2],
              bodyweight: 0.65, alias: ["close grip push up", "triangle push up"]),

        // MARK: Quads
        Entry("Barbell Squat", .barbell, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5, .gluteusMaximus: 4, .gluteusMedius: 2, .adductorLongus: 3, .adductorMagnus: 3, .pectineus: 2, .upperAbs: 2, .lowerAbs: 2,
                                  .erectorSpinae: 2],
              alias: ["back squat", "squat", "high bar squat", "low bar squat"]),
        Entry("Front Squat", .barbell, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5, .upperAbs: 3, .lowerAbs: 3, .gluteusMaximus: 3, .gluteusMedius: 1, .rhomboids: 2, .middleTraps: 2],
              alias: ["fs", "barbell front squat"]),
        Entry("Smith Machine Squat", .machine, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5, .gluteusMaximus: 3, .gluteusMedius: 1, .adductorLongus: 2, .adductorMagnus: 2, .pectineus: 1],
              alias: ["smith squat"]),
        Entry("Box Squat", .barbell, [.gluteusMaximus: 5, .gluteusMedius: 3, .vastusLateralis: 4, .vastusMedialis: 4, .rectusFemoris: 4, .erectorSpinae: 2],
              alias: ["squat to box"]),
        Entry("Leg Press", .machine, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5, .gluteusMaximus: 3, .gluteusMedius: 1, .adductorLongus: 2, .adductorMagnus: 2, .pectineus: 1],
              alias: ["45 degree leg press", "horizontal leg press", "seated leg press"]),
        Entry("Single-Leg Press", .machine, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5, .gluteusMaximus: 4, .gluteusMedius: 2],
              alias: ["one leg press", "unilateral leg press"]),
        Entry("Hack Squat", .machine, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5, .gluteusMaximus: 3, .gluteusMedius: 1],
              alias: ["machine hack squat"]),
        Entry("Pendulum Squat", .machine, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5, .gluteusMaximus: 3, .gluteusMedius: 1],
              alias: ["pendulum"]),
        Entry("Belt Squat", .machine, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5, .gluteusMaximus: 3, .gluteusMedius: 1],
              alias: ["hip belt squat"]),
        Entry("Leg Extension", .machine, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5],
              alias: ["quad extension", "knee extension"]),
        Entry("Bulgarian Split Squat", .dumbbell, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5, .gluteusMaximus: 4, .gluteusMedius: 2, .adductorLongus: 2, .adductorMagnus: 2, .pectineus: 1, .upperAbs: 1, .lowerAbs: 1],
              bodyweight: 0.85,
              alias: ["rfess", "rear foot elevated split squat", "bulgarians"]),
        Entry("Split Squat", .dumbbell, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5, .gluteusMaximus: 4, .gluteusMedius: 2],
              bodyweight: 0.85, alias: ["static lunge", "stationary lunge"]),
        Entry("Walking Lunge", .dumbbell,
              [.gluteusMaximus: 4, .gluteusMedius: 2, .vastusLateralis: 4, .vastusMedialis: 4, .rectusFemoris: 4, .adductorLongus: 2, .adductorMagnus: 2, .pectineus: 1, .bicepsFemoris: 2, .semitendinosus: 2],
              bodyweight: 0.85, alias: ["lunge", "db walking lunge"]),
        Entry("Reverse Lunge", .dumbbell, [.gluteusMaximus: 4, .gluteusMedius: 2, .vastusLateralis: 4, .vastusMedialis: 4, .rectusFemoris: 4, .bicepsFemoris: 2, .semitendinosus: 2],
              bodyweight: 0.85, alias: ["backward lunge", "step back lunge"]),
        Entry("Step-Up", .dumbbell, [.gluteusMaximus: 4, .gluteusMedius: 2, .vastusLateralis: 4, .vastusMedialis: 4, .rectusFemoris: 4],
              bodyweight: 0.85, alias: ["box step up", "db step up"]),
        Entry("Goblet Squat", .dumbbell, [.vastusLateralis: 4, .vastusMedialis: 4, .rectusFemoris: 4, .gluteusMaximus: 3, .gluteusMedius: 1, .upperAbs: 2, .lowerAbs: 2],
              alias: ["kettlebell goblet squat", "db goblet squat"]),
        Entry("Sissy Squat", .bodyweight, [.vastusLateralis: 5, .vastusMedialis: 5, .rectusFemoris: 5],
              bodyweight: 0.7, alias: ["sissy"]),

        // MARK: Hamstrings and glutes
        Entry("Romanian Deadlift", .barbell,
              [.bicepsFemoris: 5, .semitendinosus: 5, .gluteusMaximus: 4, .gluteusMedius: 2, .erectorSpinae: 3, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["rdl", "romanian dl", "barbell rdl"]),
        Entry("Stiff-Leg Deadlift", .barbell,
              [.bicepsFemoris: 5, .semitendinosus: 5, .erectorSpinae: 4, .gluteusMaximus: 3, .gluteusMedius: 1, .wristFlexors: 2, .brachioradialis: 1],
              alias: ["sldl", "straight leg deadlift"]),
        Entry("Single-Leg Romanian Deadlift", .dumbbell,
              [.bicepsFemoris: 5, .semitendinosus: 5, .gluteusMaximus: 4, .gluteusMedius: 2, .upperAbs: 2, .lowerAbs: 2, .erectorSpinae: 2],
              alias: ["single leg rdl", "sl rdl", "one leg rdl"]),
        Entry("Lying Leg Curl", .machine, [.bicepsFemoris: 5, .semitendinosus: 5, .gastrocnemius: 1, .soleus: 1],
              alias: ["leg curl", "prone leg curl", "hamstring curl"]),
        Entry("Seated Leg Curl", .machine, [.bicepsFemoris: 5, .semitendinosus: 5],
              alias: ["seated hamstring curl"]),
        Entry("Standing Leg Curl", .machine, [.bicepsFemoris: 5, .semitendinosus: 5],
              alias: ["single leg curl standing"]),
        Entry("Nordic Curl", .bodyweight, [.bicepsFemoris: 5, .semitendinosus: 5, .upperAbs: 2, .lowerAbs: 2],
              bodyweight: 0.6,
              alias: ["nordic hamstring curl", "nordics", "natural glute ham raise"]),
        Entry("Glute Ham Raise", .bodyweight,
              [.bicepsFemoris: 5, .semitendinosus: 5, .gluteusMaximus: 3, .gluteusMedius: 1, .erectorSpinae: 2],
              bodyweight: 0.7, alias: ["ghr", "glute-ham raise"]),
        Entry("Hip Thrust", .barbell, [.gluteusMaximus: 5, .gluteusMedius: 3, .bicepsFemoris: 3, .semitendinosus: 3, .vastusLateralis: 1, .vastusMedialis: 1, .rectusFemoris: 1],
              alias: ["barbell hip thrust", "bench hip thrust"]),
        Entry("Machine Hip Thrust", .machine, [.gluteusMaximus: 5, .gluteusMedius: 3, .bicepsFemoris: 3, .semitendinosus: 3],
              alias: ["glute drive", "hip thrust machine"]),
        Entry("Glute Bridge", .bodyweight, [.gluteusMaximus: 4, .gluteusMedius: 2, .bicepsFemoris: 2, .semitendinosus: 2],
              bodyweight: 0.35, alias: ["floor bridge"]),
        Entry("Cable Pull-Through", .cable, [.gluteusMaximus: 5, .gluteusMedius: 3, .bicepsFemoris: 4, .semitendinosus: 4, .erectorSpinae: 2],
              alias: ["pull through", "rope pull through"]),
        Entry("Good Morning", .barbell, [.bicepsFemoris: 4, .semitendinosus: 4, .erectorSpinae: 4, .gluteusMaximus: 3, .gluteusMedius: 1],
              alias: ["gm", "barbell good morning"]),
        Entry("Cable Kickback", .cable, [.gluteusMaximus: 4, .gluteusMedius: 2],
              alias: ["glute kickback", "cable glute kickback"]),
        Entry("Hip Abduction", .machine, [.gluteusMedius: 5, .gluteusMaximus: 3],
              alias: ["abductor machine", "abduction machine", "outer thigh machine"]),
        Entry("Hip Adduction", .machine, [.adductorLongus: 5, .adductorMagnus: 5, .pectineus: 4],
              alias: ["adductor machine", "inner thigh machine"]),

        // MARK: Calves
        Entry("Standing Calf Raise", .machine, [.gastrocnemius: 5, .soleus: 4],
              alias: ["calf raise", "standing calves"]),
        Entry("Seated Calf Raise", .machine, [.soleus: 5, .gastrocnemius: 2],
              alias: ["seated calves", "soleus raise"]),
        Entry("Leg Press Calf Raise", .machine, [.gastrocnemius: 5, .soleus: 4],
              alias: ["calf press", "leg press calves"]),
        Entry("Single-Leg Calf Raise", .bodyweight, [.gastrocnemius: 5, .soleus: 4],
              bodyweight: 0.9, alias: ["one leg calf raise", "unilateral calf raise"]),

        // MARK: Forearms and grip
        Entry("Tibialis Raise", .bodyweight, [.tibialisAnterior: 5, .peroneals: 2],
              bodyweight: 0.3,
              alias: ["tib raise", "toe raise", "anterior tibialis raise"]),
        Entry("Push-Up Plus", .bodyweight, [.serratus: 5, .chest: 3, .frontDelts: 2],
              bodyweight: 0.65,
              alias: ["scapular push-up", "protraction push up", "serratus push up"]),
        Entry("Wrist Curl", .dumbbell, [.wristFlexors: 5, .brachioradialis: 4],
              alias: ["barbell wrist curl", "seated wrist curl"]),
        Entry("Reverse Wrist Curl", .dumbbell, [.wristExtensors: 5, .brachioradialis: 3],
              alias: ["wrist extension"]),
        Entry("Farmer's Walk", .dumbbell, [.wristFlexors: 5, .brachioradialis: 4, .upperTraps: 4, .middleTraps: 3, .lowerTraps: 3, .upperAbs: 3, .lowerAbs: 3],
              alias: ["farmers carry", "farmer carry", "loaded carry"]),
        Entry("Dead Hang", .bodyweight, [.wristFlexors: 5, .brachioradialis: 4, .lats: 2],
              bodyweight: 1.0, alias: ["bar hang", "hanging"]),

        // MARK: Core
        Entry("Plank", .bodyweight, [.upperAbs: 4, .lowerAbs: 4, .obliques: 2], bodyweight: 0.0,
              alias: ["front plank", "forearm plank"]),
        Entry("Side Plank", .bodyweight, [.obliques: 5, .upperAbs: 2, .lowerAbs: 2], bodyweight: 0.0,
              alias: ["lateral plank"]),
        Entry("Cable Crunch", .cable, [.upperAbs: 5, .lowerAbs: 5, .obliques: 2],
              alias: ["kneeling cable crunch", "rope crunch"]),
        Entry("Crunch", .bodyweight, [.upperAbs: 4, .lowerAbs: 4], bodyweight: 0.3,
              alias: ["floor crunch", "ab crunch"]),
        Entry("Sit-Up", .bodyweight, [.upperAbs: 4, .lowerAbs: 4, .obliques: 2], bodyweight: 0.4,
              alias: ["situp", "decline sit up", "full sit up"]),
        Entry("Hanging Leg Raise", .bodyweight, [.upperAbs: 5, .lowerAbs: 5, .obliques: 2, .wristFlexors: 1, .brachioradialis: 1],
              bodyweight: 0.45,
              alias: ["hanging knee raise", "leg raise", "captains chair leg raise"]),
        Entry("Ab Wheel Rollout", .bodyweight, [.upperAbs: 5, .lowerAbs: 5, .lats: 2, .frontDelts: 1],
              bodyweight: 0.45, alias: ["ab roller", "wheel rollout"]),
        Entry("Russian Twist", .bodyweight, [.obliques: 5, .upperAbs: 3, .lowerAbs: 3], bodyweight: 0.3,
              alias: ["seated twist", "oblique twist"]),
        Entry("Pallof Press", .cable, [.obliques: 4, .upperAbs: 3, .lowerAbs: 3],
              alias: ["anti rotation press", "cable pallof"]),
        Entry("Cable Woodchop", .cable, [.obliques: 5, .upperAbs: 3, .lowerAbs: 3],
              alias: ["woodchopper", "wood chop", "cable chop"]),
        Entry("Dead Bug", .bodyweight, [.upperAbs: 4, .lowerAbs: 4], bodyweight: 0.2,
              alias: ["deadbug"]),
        Entry("Mountain Climber", .bodyweight, [.upperAbs: 3, .lowerAbs: 3, .frontDelts: 2, .vastusLateralis: 2, .vastusMedialis: 2, .rectusFemoris: 2],
              bodyweight: 0.5, alias: ["mountain climbers"]),
        Entry("Hollow Hold", .bodyweight, [.upperAbs: 5, .lowerAbs: 5], bodyweight: 0.0,
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
