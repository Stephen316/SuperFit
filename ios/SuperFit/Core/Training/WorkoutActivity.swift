import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Every activity the app can record or import, and what kind of data each one
/// carries.
///
/// The kind matters more than the label: a run has distance and pace, a swim has
/// distance and strokes, a lift has sets and reps, and yoga has none of those.
/// Driving the UI from `metrics` rather than from a `switch` on the case means a
/// new activity needs one row here and nothing else.
enum WorkoutActivity: String, Codable, CaseIterable, Sendable, Identifiable {
    // Strength
    case strengthTraining, functionalTraining, coreTraining

    // Run / walk
    case running, trailRunning, treadmillRunning, walking, hiking

    // Ride
    case cycling, indoorCycling, mountainBiking

    // Water
    case poolSwimming, openWaterSwimming, rowing, indoorRowing, paddling

    // Machines & conditioning
    case elliptical, stairClimbing, hiit, jumpRope, circuitTraining

    // Mind & body
    case yoga, pilates, stretching, mobility

    // Sport
    case boxing, martialArts, climbing, tennis, badminton, squash
    case football, basketball, golf, skiing, snowboarding, skating
    case dance, surfing, other

    var id: String { rawValue }

    /// What a workout of this kind can meaningfully report. Anything not listed
    /// is hidden rather than shown as a zero — a swim has no elevation gain, and
    /// "0 m climbed" reads as a measurement when it is an absence.
    struct Metrics: OptionSet, Sendable {
        let rawValue: Int
        static let distance    = Metrics(rawValue: 1 << 0)
        static let pace        = Metrics(rawValue: 1 << 1)
        static let elevation   = Metrics(rawValue: 1 << 2)
        static let cadence     = Metrics(rawValue: 1 << 3)
        static let power       = Metrics(rawValue: 1 << 4)
        static let strokes     = Metrics(rawValue: 1 << 5)
        static let laps        = Metrics(rawValue: 1 << 6)
        static let sets        = Metrics(rawValue: 1 << 7)
    }

    var metrics: Metrics {
        switch self {
        case .strengthTraining, .functionalTraining, .coreTraining, .circuitTraining:
            return [.sets]
        case .running, .trailRunning:
            return [.distance, .pace, .elevation, .cadence, .power]
        case .treadmillRunning:
            return [.distance, .pace, .cadence]
        case .walking, .hiking:
            return [.distance, .pace, .elevation, .cadence]
        case .cycling, .mountainBiking:
            return [.distance, .pace, .elevation, .cadence, .power]
        case .indoorCycling:
            return [.distance, .pace, .cadence, .power]
        case .poolSwimming:
            return [.distance, .pace, .strokes, .laps]
        case .openWaterSwimming:
            return [.distance, .pace, .strokes]
        case .rowing, .indoorRowing, .paddling:
            return [.distance, .pace, .cadence, .power]
        case .elliptical, .stairClimbing:
            return [.distance, .cadence]
        case .skiing, .snowboarding:
            return [.distance, .pace, .elevation]
        case .skating, .surfing:
            return [.distance, .pace]
        case .climbing:
            return [.elevation]
        case .hiit, .jumpRope, .boxing, .martialArts, .dance:
            return []
        case .yoga, .pilates, .stretching, .mobility:
            return []
        case .tennis, .badminton, .squash, .football, .basketball, .golf:
            return [.distance]
        case .other:
            return []
        }
    }

    /// Strength work is logged as sets against the exercise catalog; everything
    /// else is a duration-and-distance activity.
    var isStrength: Bool { metrics.contains(.sets) }

    /// Whether a live in-app session should ask for location. Indoor activities
    /// would only burn battery on a GPS fix that never moves.
    var usesLocation: Bool {
        switch self {
        case .running, .trailRunning, .walking, .hiking, .cycling, .mountainBiking,
             .openWaterSwimming, .paddling, .skiing, .snowboarding, .skating, .surfing:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .strengthTraining: return "Strength training"
        case .functionalTraining: return "Functional training"
        case .coreTraining: return "Core training"
        case .running: return "Running"
        case .trailRunning: return "Trail running"
        case .treadmillRunning: return "Treadmill"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .cycling: return "Cycling"
        case .indoorCycling: return "Indoor cycling"
        case .mountainBiking: return "Mountain biking"
        case .poolSwimming: return "Pool swimming"
        case .openWaterSwimming: return "Open water swimming"
        case .rowing: return "Rowing"
        case .indoorRowing: return "Indoor rowing"
        case .paddling: return "Paddling"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair climbing"
        case .hiit: return "HIIT"
        case .jumpRope: return "Jump rope"
        case .circuitTraining: return "Circuit training"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .stretching: return "Stretching"
        case .mobility: return "Mobility"
        case .boxing: return "Boxing"
        case .martialArts: return "Martial arts"
        case .climbing: return "Climbing"
        case .tennis: return "Tennis"
        case .badminton: return "Badminton"
        case .squash: return "Squash"
        case .football: return "Football"
        case .basketball: return "Basketball"
        case .golf: return "Golf"
        case .skiing: return "Skiing"
        case .snowboarding: return "Snowboarding"
        case .skating: return "Skating"
        case .dance: return "Dance"
        case .surfing: return "Surfing"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .strengthTraining, .functionalTraining: return "dumbbell.fill"
        case .coreTraining, .circuitTraining: return "figure.core.training"
        case .running, .treadmillRunning: return "figure.run"
        case .trailRunning: return "figure.hiking"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .cycling, .mountainBiking: return "figure.outdoor.cycle"
        case .indoorCycling: return "figure.indoor.cycle"
        case .poolSwimming, .openWaterSwimming: return "figure.pool.swim"
        case .rowing, .indoorRowing: return "figure.rower"
        case .paddling: return "figure.outdoor.rowing"
        case .elliptical: return "figure.elliptical"
        case .stairClimbing: return "figure.stair.stepper"
        case .hiit: return "figure.highintensity.intervaltraining"
        case .jumpRope: return "figure.jumprope"
        case .yoga: return "figure.yoga"
        case .pilates: return "figure.pilates"
        case .stretching, .mobility: return "figure.flexibility"
        case .boxing: return "figure.boxing"
        case .martialArts: return "figure.martial.arts"
        case .climbing: return "figure.climbing"
        case .tennis: return "figure.tennis"
        case .badminton: return "figure.badminton"
        case .squash: return "figure.squash"
        case .football: return "figure.soccer"
        case .basketball: return "figure.basketball"
        case .golf: return "figure.golf"
        case .skiing: return "figure.skiing.downhill"
        case .snowboarding: return "figure.snowboarding"
        case .skating: return "figure.skating"
        case .dance: return "figure.dance"
        case .surfing: return "figure.surfing"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// Grouping for the picker, so 40 activities stay scannable.
    enum Group: String, CaseIterable, Sendable, Identifiable {
        case strength = "Strength"
        case runWalk = "Run & walk"
        case ride = "Ride"
        case water = "Water"
        case conditioning = "Conditioning"
        case mindBody = "Mind & body"
        case sport = "Sport"
        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .strengthTraining, .functionalTraining, .coreTraining: return .strength
        case .running, .trailRunning, .treadmillRunning, .walking, .hiking: return .runWalk
        case .cycling, .indoorCycling, .mountainBiking: return .ride
        case .poolSwimming, .openWaterSwimming, .rowing, .indoorRowing, .paddling: return .water
        case .elliptical, .stairClimbing, .hiit, .jumpRope, .circuitTraining: return .conditioning
        case .yoga, .pilates, .stretching, .mobility: return .mindBody
        default: return .sport
        }
    }

    static func inGroup(_ group: Group) -> [WorkoutActivity] {
        allCases.filter { $0.group == group }
    }
}
