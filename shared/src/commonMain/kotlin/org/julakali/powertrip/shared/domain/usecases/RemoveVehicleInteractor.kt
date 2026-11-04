package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.VehicleRepository

class RemoveVehicleInteractor(
    private val vehicles: VehicleRepository,
) : Interactor<RemoveVehicleInteractor.Params, Unit>() {

    data class Params(val id: String)

    override suspend fun doWork(params: Params) {
        vehicles.removeVehicle(params.id)
    }
}
