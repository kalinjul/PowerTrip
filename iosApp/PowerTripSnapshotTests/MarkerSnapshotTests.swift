import Shared
import SwiftUI
import XCTest
@testable import PowerTrip

@MainActor
final class MarkerSnapshotTests: XCTestCase {

    func testPillsBySpeedAndAvailability() {
        assertLightAndDark(
            OverMap {
                ChargerPill(charger: Fixtures.charger("Ionity Holmmoor", operator: "IONITY", powerKw: 350, availability: Fixtures.live(5, of: 6)))
                ChargerPill(charger: Fixtures.charger("EnBW Rastplatz", operator: "EnBW", powerKw: 150, availability: Fixtures.live(1, of: 4)))
                ChargerPill(charger: Fixtures.charger("Shell Recharge", operator: "Shell", powerKw: 50, availability: Fixtures.live(0, of: 2)))
                ChargerPill(charger: Fixtures.charger("Stadtwerke", powerKw: 22))
                ChargerPill(charger: Fixtures.charger("Tesla Supercharger", operator: "Tesla", powerKw: 250, availability: Fixtures.outOfOrder))
            },
            named: "pills"
        )
    }

    func testChargeNowCallout() {
        let candidate = Fixtures.candidate(Fixtures.ionity, km: 3.4)
        assertLightAndDark(
            OverMap {
                ChargeNowCallout(rank: 1, color: Brand.operatorColor(candidate.site), title: "Ionity", meta: chargeNowMeta(candidate))
                ChargeNowCallout(rank: 2, color: Brand.operatorColor(Fixtures.enbw), title: "EnBW mobility+ Ladepark Kassel Niestetal", meta: chargeNowMeta(Fixtures.candidate(Fixtures.enbw, km: 7.9)))
            },
            named: "callout"
        )
    }

    func testDotsBySpeedAndAvailability() {
        assertLightAndDark(
            OverMap {
                ChargerDot(charger: Fixtures.charger("a", powerKw: 350, availability: Fixtures.live(5, of: 6)))
                ChargerDot(charger: Fixtures.charger("b", powerKw: 150, availability: Fixtures.live(1, of: 4)))
                ChargerDot(charger: Fixtures.charger("c", powerKw: 50, availability: Fixtures.live(0, of: 2)))
                ChargerDot(charger: Fixtures.charger("d", powerKw: 22))
                ChargerDot(charger: Fixtures.charger("e", powerKw: 250, availability: Fixtures.outOfOrder))
            },
            named: "dots"
        )
    }
}

/// Markers stacked on a map-like backdrop, so their edges show.
private struct OverMap<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(16)
            .background(Color(.systemGray5))
    }
}
