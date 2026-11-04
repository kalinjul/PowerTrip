package org.julakali.powertrip.shared.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import org.julakali.powertrip.shared.db.ChargeSiteDatabase
import org.julakali.powertrip.shared.db.VehicleModelEntity
import org.julakali.powertrip.shared.domain.ConnectorType
import org.julakali.powertrip.shared.domain.VehicleCatalogRepository
import org.julakali.powertrip.shared.domain.VehicleCatalogSource
import org.julakali.powertrip.shared.domain.VehiclePreset

class RoomVehicleCatalogRepository(
    private val source: VehicleCatalogSource,
    database: ChargeSiteDatabase,
) : VehicleCatalogRepository {

    private val dao = database.vehicleModels()

    override val presets: Flow<List<VehiclePreset>> = dao.observeAll().map { entities ->
        entities.map { it.toPreset() }
    }

    override suspend fun refresh() {
        val listed = source.presets()
        // An empty catalog is more likely a backend fault than intent; the old one stays usable.
        if (listed.isEmpty()) return
        dao.replaceAll(listed.mapIndexed { index, preset -> preset.toEntity(index) })
    }

    private fun VehiclePreset.toEntity(position: Int) = VehicleModelEntity(
        id = id,
        name = name,
        usableBatteryKwh = usableBatteryKwh,
        consumptionKwhPer100Km = consumptionKwhPer100Km,
        dcPeakPowerKw = dcPeakPowerKw,
        connectors = connectors.mapTo(LinkedHashSet()) { it.name },
        position = position,
        roadLoad = roadLoad,
    )

    private fun VehicleModelEntity.toPreset() = VehiclePreset(
        id = id,
        name = name,
        usableBatteryKwh = usableBatteryKwh,
        consumptionKwhPer100Km = consumptionKwhPer100Km,
        dcPeakPowerKw = dcPeakPowerKw,
        connectors = connectors.mapNotNullTo(LinkedHashSet()) { stored ->
            ConnectorType.entries.firstOrNull { it.name == stored }
        },
        roadLoad = roadLoad,
    )
}
