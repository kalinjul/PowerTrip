package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.NavigationApp
import org.julakali.powertrip.shared.domain.PreferencesRepository

class SetNavigationAppInteractor(
    private val preferences: PreferencesRepository,
) : Interactor<SetNavigationAppInteractor.Params, Unit>() {

    data class Params(val app: NavigationApp)

    override suspend fun doWork(params: Params) {
        preferences.setNavigationApp(params.app)
    }
}
