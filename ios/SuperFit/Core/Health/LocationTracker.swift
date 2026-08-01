import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

/// Distance accumulated from GPS during a live outdoor session.
///
/// Only used for activities whose `usesLocation` is true — asking for a fix
/// during an indoor rower would drain the battery on a position that never moves.
/// The watch does this better when you have one; this exists for the case where
/// the phone is the only device you're carrying.
@MainActor
@Observable
final class LocationTracker: NSObject {

    private(set) var distanceMetres: Double = 0
    private(set) var isAuthorized = false
    /// True when a fix has been received. Until then distance is genuinely
    /// unknown rather than zero, and the UI says so.
    private(set) var hasFix = false

    #if canImport(CoreLocation)
    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        // 5 m between callbacks: below that, GPS jitter while standing still
        // accumulates as phantom distance over a long session.
        manager.distanceFilter = 5
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func reset() {
        distanceMetres = 0
        lastLocation = nil
        hasFix = false
    }
    #else
    func start() {}
    func stop() {}
    func reset() {}
    #endif
}

#if canImport(CoreLocation)
extension LocationTracker: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let fixes = locations
        Task { @MainActor in
            for location in fixes {
                // Discard low-confidence fixes: a 100 m-accuracy reading between
                // two good ones adds a 100 m "sprint" that never happened.
                guard location.horizontalAccuracy >= 0,
                      location.horizontalAccuracy < 50 else { continue }
                if let last = self.lastLocation {
                    let step = location.distance(from: last)
                    if step.isFinite, step > 0 { self.distanceMetres += step }
                }
                self.lastLocation = location
                self.hasFix = true
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // A failed fix is not a failed workout: duration and heart rate still
        // record, so the session continues with distance unavailable.
    }
}
#endif
