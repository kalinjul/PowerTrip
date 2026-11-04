package org.julakali.powertrip.shared.domain.usecases

import kotlinx.coroutines.flow.first
import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.VehicleCatalogRepository
import org.julakali.powertrip.shared.domain.VehicleRepository
import org.julakali.powertrip.shared.domain.followingCatalog

/** Fetches the catalog and brings the garage's catalog cars up to date with it. */
class RefreshVehicleCatalogInteractor(
    private val repository: VehicleCatalogRepository,
    private val vehicles: VehicleRepository,
) : Interactor<Unit, Unit>() {

    override suspend fun doWork(params: Unit) {
        repository.refresh()
        val presets = repository.presets.first()
        vehicles.updateVehicles { it.followingCatalog(presets) }
    }
}
