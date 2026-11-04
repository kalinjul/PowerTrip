package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.NetworkPreferences
import org.julakali.powertrip.shared.domain.PreferencesRepository
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

class UpdateNetworksInteractor(
    private val preferences: PreferencesRepository,
) : Interactor<UpdateNetworksInteractor.Params, Unit>() {

    data class Params(val preferences: NetworkPreferences)

    override suspend fun doWork(params: Params) {
        // Once begun, finish: leaving the screen mid-save must not lose the change.
        withContext(NonCancellable) { preferences.setNetworks(params.preferences) }
    }
}
