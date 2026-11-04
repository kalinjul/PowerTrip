package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.NetworkRepository

class RefreshNetworksInteractor(
    private val repository: NetworkRepository,
) : Interactor<Unit, Unit>() {

    override suspend fun doWork(params: Unit) = repository.refresh()
}
