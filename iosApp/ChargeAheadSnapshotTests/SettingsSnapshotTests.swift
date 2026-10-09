import Shared
import SwiftUI
import XCTest
@testable import ChargeAhead

@MainActor
final class SettingsSnapshotTests: XCTestCase {

    private func settings(mode: ChargeMode = .normal, networks: Int32 = 3) -> some View {
        NavigationStack {
            SettingsContent(
                state: DrawerUiState(
                    vehicleName: "VW ID.3",
                    preferredNetworkCount: networks,
                    filters: ChargeFilters(minPowerKw: 150, slowMode: mode == .ac),
                    mode: mode
                ),
                onOpen: { _ in },
                onMinPower: { _ in },
                onMode: { _ in }
            )
        }
    }

    func testModesOff() {
        assertLightAndDark(settings(), named: "settings", frame: .phone)
    }

    func testAcModeOn() {
        assertLightAndDark(settings(mode: .ac), named: "settings", frame: .phone)
    }

    func testBrowseModeOnAllNetworks() {
        assertLightAndDark(settings(mode: .browse, networks: 0), named: "settings", frame: .phone)
    }

    func testNetworks() {
        let networks = [
            Network(key: "ionity", name: "Ionity", operatorIds: [], nameKeywords: [], rank: nil),
            Network(key: "enbw", name: "EnBW", operatorIds: [], nameKeywords: [], rank: nil),
            Network(key: "tesla", name: "Tesla Supercharger", operatorIds: [], nameKeywords: [], rank: nil),
            Network(key: "aral-pulse", name: "Aral pulse", operatorIds: [], nameKeywords: [], rank: nil),
            Network(key: "stadtwerke-musterstadt", name: "Stadtwerke Musterstadt", operatorIds: [], nameKeywords: [], rank: nil),
        ]
        assertLightAndDark(
            NavigationStack {
                NetworksContent(state: NetworksUiState(networks: networks, selected: ["ionity", "enbw"], search: ""), query: .constant("")) { _ in }
            },
            named: "networks",
            frame: .phone
        )
    }

    func testLicenses() {
        let sources = [
            DataSource(id: "ocm", name: "Open Charge Map", url: "https://openchargemap.org", datasets: [
                Dataset(kind: .sites, url: nil, license: License(name: "CC BY 4.0", url: "https://creativecommons.org/licenses/by/4.0/")),
            ]),
            DataSource(id: "osm", name: "OpenStreetMap", url: "https://www.openstreetmap.org", datasets: [
                Dataset(kind: .routing, url: nil, license: License(name: "ODbL", url: nil)),
                Dataset(kind: .places, url: nil, license: License(name: "ODbL", url: nil)),
            ]),
        ]
        assertLightAndDark(
            NavigationStack {
                LicensesContent(state: LicensesUiState(dataSources: DataSourcesStateLoaded(sources: sources)), onRetry: {})
            },
            named: "licenses",
            frame: .phone
        )
    }
}
