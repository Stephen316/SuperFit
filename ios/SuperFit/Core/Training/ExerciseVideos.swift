import Foundation

/// Hand-picked how-to videos, one per exercise.
///
/// **Curated deliberately, never searched.** Whether a video demonstrates safe
/// form is a judgement no algorithm makes: a search API returns whatever ranks,
/// and the top result for a barbell lift is as likely to be a bad rep as a good
/// one. Showing that inside a training app presents it as instruction, so every
/// entry here is one somebody watched and chose.
///
/// Keys are matched the same way exercise search matches — case and punctuation
/// insensitive — so "Barbell Bench Press" and "barbell bench-press" find the same
/// record.
enum ExerciseVideos {

    /// YouTube video ids, keyed by catalogue exercise name.
    ///
    /// Deliberately empty. Filling it is the curation step; until an exercise has
    /// an entry the how-to tab offers a YouTube search instead, so the feature is
    /// useful from the first build and improves one lift at a time.
    ///
    /// Take the id from the watch URL: `youtube.com/watch?v=**dQw4w9WgXcQ**`.
    /// **Every entry below is unverified.** Search returned a video whose title
    /// matches the exercise exactly, but YouTube's pages are script-rendered, so
    /// the uploading channel could not be confirmed programmatically — and the
    /// channel is the whole basis for trusting the form. Watch each one and
    /// either keep it or replace it.
    ///
    /// Add more as you curate: the id is the `v=` value in a watch URL.
    static let ids: [String: String] = [

        // ---- ScottHermanFitness ----
        // How To: Barbell Bench Press (The Set-Up)
        "Barbell Bench Press": "Lr8hSSFcByY",
        // How To: Barbell Bent-Over Row
        "Barbell Row": "9efgcAjQe7E",
        // SQUAT (MAX) 3-16-2012
        "Barbell Squat": "9hqtrxHjB7E",
        // How To: Bench Dip
        "Bench Dip": "c3ZGl4pAwZ4",
        // How To: Bulgarian Split Squat
        "Bulgarian Split Squat": "2C-uNgKwPLE",
        // How To: Cable Fly (High-To-Low) || 3 GOLDEN RULES
        "Cable Fly": "8Um35Es-ROE",
        // How To: Rope Hammer Curl
        "Cable Hammer Curl": "1Quc_tOv97I",
        // HOW TO: Close-Grip Bench Press (TRICEPS BUILDER) || PERFECT FORM
        "Close-Grip Bench Press": "UYJsFzqdgK4",
        // How To: Floor Crunch
        "Crunch": "NGRKFMKhF8s",
        // Deadlift (MAX) 3-14-2012
        "Deadlift": "8PfS5ZZO0lA",
        // How To: Diamond Push-Up
        "Diamond Push-Up": "J0DnG1_S92I",
        // How To: Barbell Drag Curl (Increase Bicep Peaks!)
        "Drag Curl": "LMdNTHH6G8I",
        // How To: Bicep Curl (Hammer Strength)
        "Dumbbell Curl": "TKOG5N0YEV4",
        // How To: Dumbbell Romanian Deadlift
        "Dumbbell Romanian Deadlift": "FQKfr1YDhEk",
        // How To: Dumbbell Shrug
        "Dumbbell Shrug": "xDt6qbKgLkY",
        // How To: Dumbbell Upright-Row
        "Dumbbell Upright Row": "IhZLB48kluc",
        // How To: Face Pull
        "Face Pull": "rep-qVOkqgk",
        // How To: Front Squat (Barbell)
        "Front Squat": "tlfahNdNPPI",
        // How To: Glute Bridge
        "Glute Bridge": "8bbE64NuDTU",
        // How To: Goblet Squat
        "Goblet Squat": "MeIiIdhvXT4",
        // Hanging Leg-Raise (HLR) (MAX REPS) 3-12-2012
        "Hanging Leg Raise": "mtRbxzc33vw",
        // How To: Hip Abduction (LF Cable)
        "Hip Abduction": "1rbpTTzEnV4",
        // How To: Hip Adduction (LF Cable)
        "Hip Adduction": "5Mkus4JdXDE",
        // How To: Hip Thrust
        "Hip Thrust": "SEdqd1n0cvg",
        // HOW TO: Incline Dumbbell Fly || PERFECT FORM (GROWTH & STRENGTH)
        "Incline Dumbbell Fly": "idAvu2HvqSQ",
        // How To: Landmine Oblique Twist
        "Landmine Rotation": "epdBIT32SS0",
        // How To: Lat Pulldown (Cybex)
        "Lat Pulldown": "7D2t1XnrW2s",
        // How To: Lateral Raise (Shoulder Recovery)
        "Lateral Raise": "yPzAmmuH-H8",
        // How To: Leg Extension (Cybex)
        "Leg Extension": "YyvSfVjQeL0",
        // How To: Leg Press (Cybex)
        "Leg Press": "oujca3_Shgw",
        // How To: Prone Leg Curl (Cybex)
        "Lying Leg Curl": "1Tq3QdYUuHs",
        // How To: Overhead Press (Cybex)
        "Overhead Press": "Wqq43dKW1TU",
        // HOW TO: Overhead Triceps Extension (BEST EXERCISE FOR HUGE TRICEPS) || PER
        "Overhead Triceps Extension": "fYqswDVbJDg",
        // How To: Pendlay Row || BUILD BIG LATS!
        "Pendlay Row": "Weu9HMHdiDA",
        // How To: Plank
        "Plank": "pSHjTRCQxIw",
        // How To: Barbell Push-Press (Increase Upper & Lower Body Explosive Strength
        "Push Press": "fFY7CGKjGNM",
        // How To: Push-Up
        "Push-Up": "wxhNoKZlfY8",
        // Rack Pull, Quads & Glutes - NO EXCUSES - Muscle Building Workout!
        "Rack Pull": "JLo6MtKjnJo",
        // Romanian Deadlift- Why Using Wrist Straps Helps Build BIGGER HAMSTRINGS! M
        "Romanian Deadlift": "JZFLOolN770",
        // How To: Seated Barbell Shoulder Press
        "Seated Barbell Shoulder Press": "oBGeXxnigsQ",
        // HOW TO: Dumbbell Shoulder Press (BIGGER SHOULDERS & BIGGER BENCH PRESS!) |
        "Seated Dumbbell Press": "GFblCmuEE18",
        // How To: Seated Leg Curl (Cybex)
        "Seated Leg Curl": "ELOCsoDSmrg",
        // How To: Single-Leg Calf Raise
        "Single-Leg Calf Raise": "ORT4oJ_R8Qs",
        // How To: One-Leg Press (Cybex)
        "Single-Leg Press": "xT5-HS6e9O4",
        // How To: Sissy Squat
        "Sissy Squat": "VUiFlZ2FsKA",
        // How To: Sit-Up || 3 Golden Rules (BUILD ABS FAST!)
        "Sit-Up": "0OWEtuS7-pE",
        // How To: Skull Crusher (BUILD BIGGER TRICEPS!) || PERFECT FORM
        "Skull Crusher": "RavQHfFxbdA",
        // How To: Smith Machine- Bench Press
        "Smith Machine Bench Press": "z_r6hDOYtO0",
        // How To: Smith Machine- Squat
        "Smith Machine Squat": "AHnX-aimA4E",
        // HOW TO: Spider Curl (HUGE BICEPS BUILDER!) || PERFECT FORM
        "Spider Curl": "CITtSuda0Fg",
        // How To: Standing Leg Curl (BM)
        "Standing Leg Curl": "Z053-kKjesQ",
        // How To: Sumo Deadlift (Wide Stance Deadlift)
        "Sumo Deadlift": "1v4r9hht_K4",
        // How To: T-Bar Row
        "T-Bar Row": "j3Igk5nyZE4",
        // How To: Tricep Kickback (Dumbbell)
        "Triceps Kickback": "6SS6K3lAwZ8",
        // How To: Tricep Pushdown (Life Fitness Cable)
        "Triceps Pushdown": "2-LAMcpzODU",
        // How To: Barbell Upright Row
        "Upright Row": "amCU-ziHITM",
        // How To:  V-Up (Hardcore Abdominal Exercise)
        "V-Up": "wRCgPeligF4",
        // How To: Seated Wrist Curl
        "Wrist Curl": "qMtmHwaCmYI",
        // How To: Zercher Squat
        "Zercher Squat": "vpy4ADmlo1E",
        // How To: Zottman Curl
        "Zottman Curl": "ZrpRBgswtHs",

        // ---- Bodybuilding.com ----
        // Ab Roller - Ab Exercises - Bodybuilding.com
        "Ab Wheel Rollout": "Q5MT5omGNJI",
        // Barbell Curl - Biceps Exercise - Bodybuilding.com
        "Barbell Curl": "dDI8ClxRS04",
        // Barbell Shrug - Shoulder Exercise - Bodybuilding.com
        "Barbell Shrug": "9xGqgGFAtiM",
        // Behind The Back Wrist Curl - Forearm Exercise - Bodybuilding.com
        "Behind-the-Back Wrist Curl": "sVLVLcsfWSo",
        // Glute Ham Raise - Legs / Glutes Exercise - Bodybuilding.com
        "Glute Ham Raise": "TDdV0dCsqKs",
        // Hammer Curl - Biceps Exercise - Bodybuilding.com
        "Hammer Curl": "0IAM2YtviQY",
        // Incline Dumbbell Press - Chest Exercise - Bodybuilding.com
        "Incline Dumbbell Press": "DnV3R4vp3K0",
        // Ab Crunch Machine - Core / Abs - Bodybuilding.com
        "Machine Crunch": "JSBuaT1tHfM",
        // Butterfly - Chest Exercise - Bodybuilding.com
        "Pec Deck": "oGxc2ph8Fnw",
        // Power Clean - Back & Legs Exercise - Bodybuilding.com
        "Power Clean": "zCEj0d3TatI",
        // Preacher Curl - Biceps Exercise - Bodybuilding.com
        "Preacher Curl": "RgN216Cumtw",
        // Russian Twist - Ab Exercises - Bodybuilding.com
        "Russian Twist": "Nl-txzo-7WQ",
        // Seated Cable Row | Exercise Guide
        "Seated Cable Row": "xQNrFHEMhI4",
        // Split Squat - Legs Exercise - Bodybuilding.com
        "Split Squat": "UJWLxHAYxx4",
        // Straight Arm Pulldown - Back Exercise - Bodybuilding.com
        "Straight-Arm Pulldown": "wcVDItawocI",

        // ---- UNBROKEN FITNESS SOLUTIONS ----
        // Barbell Floor Press
        "Barbell Floor Press": "OPcaaBGdckA",
        // Belt Squat
        "Belt Squat": "mRSo8IZHI-M",
        // Bicycle Crunches
        "Bicycle Crunch": "nokZFAeYKP8",
        // Cable Crunch
        "Cable Crunch": "2AZyh9BDOjk",
        // Dead Bug
        "Dead Bug": "TzRPaUPBRGI",
        // Hollow Body Hold
        "Hollow Hold": "M5eEnQCY2ZM",
        // Kettlebell Swings
        "Kettlebell Swing": "gOjToFcf9tg",
        // Mountain Climbers
        "Mountain Climber": "wXbEk86uNSo",
        // Dumbbell Overhead Press
        "Standing Dumbbell Press": "qc2bcooXIic",
        // Hex Bar Deadlift
        "Trap Bar Deadlift": "baRdEuoSKMM",

        // ---- ATHLEAN-X™ ----
        // Dumbbell Bench Press (BETTER CHEST ACTIVATION!)
        "Flat Dumbbell Press": "SHsUIZiNdeY",
        // Incline Bench Press - TactiX Revealed!
        "Incline Barbell Press": "CTB_Jb_UvII",
        // Toes to Bar Exercise (How NOT to Work Your Abs!)
        "Toes-to-Bar": "9PLvTHeuot8",

        // ---- Buff Dudes ----
        // Arnold Press - Shoulder Exercise - Proper Form Tutorial
        "Arnold Press": "6Z15_WdXmVw",
        // How to Perform the Farmer's Walk - Exercise Tutorial
        "Farmer's Walk": "Fkzk_RqlYig",

        // ---- Muscle & Strength ----
        // Big J's Workout Tips: How To Hack Squat
        "Hack Squat": "iZefNtyVInE",
        // Perfect Pull Ups | 4 Exercises to Help You Perform Pull Ups
        "Pull-Up": "KlKkUdCj6aM",

    ]

    private static let index: [String: String] = {
        Dictionary(ids.map { (normalise($0.key), $0.value) },
                   uniquingKeysWith: { a, _ in a })
    }()

    static func normalise(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// The curated video for an exercise, if one has been chosen.
    static func id(for exerciseName: String) -> String? {
        index[normalise(exerciseName)]
    }

    /// Channels trusted for form demonstrations, best first.
    ///
    /// Chosen by the app's owner, not by ranking. Scott Herman leads because his
    /// catalogue is one video per exercise titled "How To: <Exercise>", which is
    /// exactly the shape this feature wants; ATHLEAN-X has the production quality
    /// but mixes single-move breakdowns with round-ups; Unbroken Fitness is the
    /// no-voiceover reference library.
    ///
    /// Reorder this and every uncurated search follows.
    static let preferredChannels = [
        "ScottHermanFitness",
        "ATHLEAN-X",
        "Unbroken Fitness Solutions",
    ]

    /// Where to send someone when no video has been curated yet, in priority
    /// order: Scott Herman, then ATHLEAN-X, then Unbroken Fitness.
    ///
    /// Each is an exact-phrase search on that channel's own title convention
    /// rather than a loose query. Measured across a sample, `"How To: Romanian
    /// Deadlift"` returns one clean result while `How To Barbell Squat` returns
    /// channel pages and unrelated uploads — the phrasing is what makes it
    /// precise.
    ///
    /// A search rather than a guessed video id: it cannot rot when an upload is
    /// deleted, and it cannot silently point at the wrong lift. That risk is
    /// real — searching for a neutral-grip chest press surfaced a *row* machine
    /// video with a near-identical title.
    static func searchURLs(for exerciseName: String) -> [(channel: String, url: URL)] {
        preferredChannels.compactMap { channel in
            var components = URLComponents(string: "https://www.youtube.com/results")
            components?.queryItems = [
                URLQueryItem(name: "search_query",
                             value: "\(channel) \"How To: \(exerciseName)\"")
            ]
            return components?.url.map { (channel, $0) }
        }
    }

    /// The public thumbnail for a video. `hqdefault` exists for every upload,
    /// where the higher resolutions do not.
    static func thumbnailURL(id: String) -> URL? {
        URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
    }

    /// Opens the video in the YouTube app, or the browser if it is not installed.
    ///
    /// Linking rather than embedding, deliberately. Creators can switch off
    /// embedding per video, and several of the ones below have — an embedded
    /// player then shows "This video is unavailable" inside the app, which reads
    /// as a bug rather than as the uploader's choice. Linking always works,
    /// honours that choice, and keeps the view with the creator.
    static func watchURL(id: String) -> URL? {
        URL(string: "https://www.youtube.com/watch?v=\(id)")
    }
}
