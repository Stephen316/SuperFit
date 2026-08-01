import Foundation
#if canImport(HealthKit)
import HealthKit

/// Translation between the app's activity taxonomy and HealthKit's.
///
/// The mapping is deliberately lossy in one direction only. HealthKit has ~80
/// activity types and the app has 40, so several collapse onto `.other` on the
/// way in; nothing collapses on the way out. Anything unrecognised imports as
/// `.other` with its metrics intact rather than being dropped — an unknown
/// activity is still a workout that happened.
extension WorkoutActivity {

    var healthKitType: HKWorkoutActivityType {
        switch self {
        case .strengthTraining: return .traditionalStrengthTraining
        case .functionalTraining: return .functionalStrengthTraining
        case .coreTraining: return .coreTraining
        case .circuitTraining: return .mixedCardio
        case .running, .trailRunning, .treadmillRunning: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        case .cycling, .mountainBiking, .indoorCycling: return .cycling
        case .poolSwimming, .openWaterSwimming: return .swimming
        case .rowing, .indoorRowing: return .rowing
        case .paddling: return .paddleSports
        case .elliptical: return .elliptical
        case .stairClimbing: return .stairClimbing
        case .hiit: return .highIntensityIntervalTraining
        case .jumpRope: return .jumpRope
        case .yoga: return .yoga
        case .pilates: return .pilates
        case .stretching, .mobility: return .flexibility
        case .boxing: return .boxing
        case .martialArts: return .martialArts
        case .climbing: return .climbing
        case .tennis: return .tennis
        case .badminton: return .badminton
        case .squash: return .squash
        case .football: return .soccer
        case .basketball: return .basketball
        case .golf: return .golf
        case .skiing: return .downhillSkiing
        case .snowboarding: return .snowboarding
        case .skating: return .skatingSports
        case .dance: return .cardioDance
        case .surfing: return .surfingSports
        case .other: return .other
        }
    }

    /// Indoor/outdoor and pool/open-water are HealthKit *metadata*, not distinct
    /// activity types, so they're resolved here rather than by the raw type.
    init(healthKit type: HKWorkoutActivityType, isIndoor: Bool? = nil,
         swimsInPool: Bool? = nil) {
        switch type {
        case .traditionalStrengthTraining: self = .strengthTraining
        case .functionalStrengthTraining: self = .functionalTraining
        case .coreTraining: self = .coreTraining
        case .running: self = (isIndoor == true) ? .treadmillRunning : .running
        case .walking: self = .walking
        case .hiking: self = .hiking
        case .cycling: self = (isIndoor == true) ? .indoorCycling : .cycling
        case .swimming: self = (swimsInPool == false) ? .openWaterSwimming : .poolSwimming
        case .rowing: self = (isIndoor == true) ? .indoorRowing : .rowing
        case .paddleSports: self = .paddling
        case .elliptical: self = .elliptical
        case .stairClimbing, .stairs, .stepTraining: self = .stairClimbing
        case .highIntensityIntervalTraining: self = .hiit
        case .jumpRope: self = .jumpRope
        case .mixedCardio: self = .circuitTraining
        case .yoga: self = .yoga
        case .pilates: self = .pilates
        case .flexibility, .preparationAndRecovery: self = .stretching
        case .boxing, .kickboxing: self = .boxing
        case .martialArts: self = .martialArts
        case .climbing: self = .climbing
        case .tennis: self = .tennis
        case .badminton: self = .badminton
        case .squash, .racquetball: self = .squash
        case .soccer: self = .football
        case .basketball: self = .basketball
        case .golf: self = .golf
        case .downhillSkiing, .crossCountrySkiing, .snowSports: self = .skiing
        case .snowboarding: self = .snowboarding
        case .skatingSports: self = .skating
        case .cardioDance, .socialDance, .barre: self = .dance
        case .surfingSports: self = .surfing
        default: self = .other
        }
    }
}

#endif
