package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.VehicleRepository
import org.julakali.powertrip.shared.domain.VehicleProfile

/** Selects a vehicle, adding it to the garage; `null` clears the selection. */
class SelectVehicleInteractor(
    private val vehicles: VehicleRepository,
) : Interactor<SelectVehicleInteractor.Params, Unit>() {

    data class Params(val profile: VehicleProfile?)

    override suspend fun doWork(params: Params) {
        vehicles.setVehicle(params.profile)
    }
}
