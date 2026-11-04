package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.SearchArea
import org.julakali.powertrip.shared.domain.PreferencesRepository
import org.julakali.powertrip.shared.domain.SiteRepository
import kotlinx.coroutines.flow.first

/**
 * Discards the stock and refills [Params.area] from the network.
 * [ChargeStopsObserver] picks the new sites up from the store's flow.
 */
class RefreshChargeStopsInteractor(
    private val repository: SiteRepository,
    private val preferences: PreferencesRepository,
) : Interactor<RefreshChargeStopsInteractor.Params, Unit>() {

    data class Params(val area: SearchArea)

    override suspend fun doWork(params: Params) {
        repository.invalidate()
        repository.load(params.area, preferences.networks.first().selectedKeys())
    }
}
