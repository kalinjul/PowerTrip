import Shared
@testable import ChargeAhead

/// Fixed data for the goldens; nothing here talks to a backend.
enum Fixtures {

    static func site(
        _ name: String,
        operator operatorName: String? = nil,
        powerKw: Double = 150
    ) -> ChargeSite {
        ChargeSite(
            id: "test:\(name)",
            name: name,
            operator: operatorName,
            operatorId: nil,
            position: LatLon(lat: 53.55, lon: 9.99),
            connectors: [Connector(type: .ccs2, maxPowerKw: powerKw, count: 4)],
            address: nil,
            sources: [],
            liveStatusId: nil,
            networkKey: nil
        )
    }

    static func charger(
        _ name: String,
        operator operatorName: String? = nil,
        powerKw: Double,
        availability: SiteAvailability? = nil
    ) -> MapCharger {
        MapCharger(site: site(name, operator: operatorName, powerKw: powerKw), maxPowerKw: powerKw, availability: availability)
    }

    static func live(_ free: Int32, of total: Int32) -> SiteAvailability {
        SiteAvailabilityLive(free: free, total: total)
    }

    static let outOfOrder: SiteAvailability = SiteAvailabilityOutOfOrder.shared
}

extension Fixtures {

    static func preset(_ name: String, batteryKwh: Double, consumption: Double, dcKw: Double) -> VehiclePreset {
        VehiclePreset(
            id: "test:\(name)",
            name: name,
            usableBatteryKwh: batteryKwh,
            consumptionKwhPer100Km: consumption,
            dcPeakPowerKw: dcKw,
            connectors: [.ccs2, .type2],
            roadLoad: nil
        )
    }

    static let model3 = preset("Tesla Model 3 Long Range", batteryKwh: 75, consumption: 15.5, dcKw: 250)
    static let id3 = preset("VW ID.3 Pro S", batteryKwh: 77, consumption: 16.9, dcKw: 175)
    static let zoe = preset("Renault Zoe R135", batteryKwh: 52, consumption: 17.2, dcKw: 50)

    static func garage(
        _ presets: [VehiclePreset] = [model3, id3],
        selected: Int? = 0,
        socPercent: Double = 80,
        arrivalSocPercent: Double = 15
    ) -> GarageUiState {
        let vehicles = presets.map { $0.toProfile() }
        var ranges: [String: KotlinDouble] = [:]
        for vehicle in vehicles {
            ranges[vehicle.id] = KotlinDouble(value: vehicle.usableBatteryKwh / vehicle.consumptionKwhPer100Km * 100)
        }
        return GarageUiState(
            loading: false,
            vehicles: vehicles,
            selected: selected.map { vehicles[$0] },
            arrivalSocPercent: arrivalSocPercent,
            arrivalSheet: nil,
            socPercent: socPercent,
            socSheet: nil,
            fullRangeKm: ranges
        )
    }
}
