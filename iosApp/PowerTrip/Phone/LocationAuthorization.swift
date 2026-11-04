import CoreLocation
import SwiftUI
import UIKit
import Shared

/// The iOS half of the location handshake: runs what `PhoneAppViewModel` asks for and reports the grant back.
final class LocationAuthorization: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let phoneApp: PhoneAppViewModel
    private let onSettled: () -> Void
    private var asked = false

    init(phoneApp: PhoneAppViewModel, onSettled: @escaping () -> Void) {
        self.phoneApp = phoneApp
        self.onSettled = onSettled
        super.init()
        manager.delegate = self
    }

    /// Called whenever the delegate learns the status, launch included: an undecided grant is asked for at once.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined:
            phoneApp.onLocationPermissionRequested()
        case let status:
            let granted = status == .authorizedWhenInUse || status == .authorizedAlways
            if asked {
                asked = false
                phoneApp.onLocationPermissionResult(granted: granted)
            } else {
                phoneApp.onLocationPermissionChecked(granted: granted)
            }
        }
    }

    func handle(_ event: PhoneAppEvent) {
        switch onEnum(of: event) {
        case .requestLocationPermission:
            if manager.authorizationStatus == .notDetermined {
                asked = true
                manager.requestWhenInUseAuthorization()
            } else {
                // After a refusal only the Settings app can grant it.
                openSettings()
            }
        case .checkLocationSettings:
            Task.detached { [onSettled] in
                let enabled = CLLocationManager.locationServicesEnabled()
                await MainActor.run {
                    if enabled { onSettled() } else { Self.openSettings() }
                }
            }
        }
        phoneApp.onEventHandled()
    }

    private func openSettings() { Self.openSettings() }

    private static func openSettings() {
        if let settings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settings)
        }
    }
}
