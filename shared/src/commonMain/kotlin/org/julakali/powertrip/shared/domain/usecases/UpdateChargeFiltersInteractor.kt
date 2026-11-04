package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.ChargeFilters
import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.PreferencesRepository

class UpdateChargeFiltersInteractor(
    private val preferences: PreferencesRepository,
) : Interactor<UpdateChargeFiltersInteractor.Params, Unit>() {

    data class Params(val filters: ChargeFilters)

    override suspend fun doWork(params: Params) {
        preferences.setChargeFilters(params.filters)
    }
}
