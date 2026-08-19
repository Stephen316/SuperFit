// The wire shapes SuperFit's `GarminProvider` decodes. These must match the
// Swift DTOs exactly — same key spelling (no snake_case), same optionality.
//
// Two Swift-side traps encoded here:
//  1. `SleepDTO`'s minute fields are non-optional `Int` in Swift, so when a
//     `sleep` object is present every one of them must be an integer. When there
//     is no sleep, omit the whole `sleep` key rather than sending a partial one.
//  2. Every `Date` (`bedtime`, `wakeTime`, `startTime`) is decoded with the
//     `.iso8601` strategy, which rejects fractional seconds. Always format them
//     through `toGarminISO` — see lib/http.ts.

export interface SleepDTO {
  inBedMinutes: number;
  asleepMinutes: number;
  deepMinutes: number;
  remMinutes: number;
  lightMinutes: number;
  bedtime?: string; // ISO8601, no milliseconds
  wakeTime?: string; // ISO8601, no milliseconds
}

export interface RecoveryDTO {
  date: string; // yyyy-MM-dd (local calendar day)
  hrvSDNN?: number; // ms
  restingHeartRate?: number; // bpm
  bodyBattery?: number; // integer 0…100
  sleep?: SleepDTO;
}

export interface WorkoutDTO {
  id: string;
  startTime: string; // ISO8601, no milliseconds
  durationSeconds: number;
  activityType: string; // Garmin's key, lower-cased; the app maps unknowns to `other`
  activeKilocalories?: number;
  distanceMeters?: number;
  averageHeartRate?: number;
  maxHeartRate?: number;
  elevationGainMeters?: number;
  averageCadence?: number;
  averagePowerWatts?: number;
  aerobicTrainingEffect?: number;
  anaerobicTrainingEffect?: number;
}
