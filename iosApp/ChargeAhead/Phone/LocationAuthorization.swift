import CoreLocation
import SwiftUI
import UIKit

/// The when-in-use grant as SwiftUI sees it; the shared pipeline only runs once it is there.
final class LocationAuthorization: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var access: LocationAccess = .unknown

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        access = Self.access(of: manager.authorizationStatus)
    }

    /// Asks once; after a refusal only the Settings app can grant it.
    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if let settings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settings)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        access = Self.access(of: manager.authorizationStatus)
    }

    private static func access(of status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .denied, .restricted: return .denied
        default: return .unknown
        }
    }
}
