package org.julakali.powertrip.shared.domain.usecases

import kotlinx.coroutines.flow.first
import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.PreferencesRepository
import org.julakali.powertrip.shared.domain.SiteCache
import org.julakali.powertrip.shared.domain.TripRepository
import org.julakali.powertrip.shared.domain.invoke

/**
 * What a process does once when it comes up, whoever brings it up: the phone,
 * a car session, the iOS app. Each step fails on its own; none stops the next.
 */
class StartAppInteractor(
    private val preferences: PreferencesRepository,
    private val siteCache: SiteCache,
    private val trips: TripRepository,
    private val refreshTripSites: RefreshTripSitesInteractor,
    private val refreshNetworks: RefreshNetworksInteractor,
    private val refreshVehicleCatalog: RefreshVehicleCatalogInteractor,
) : Interactor<Unit, Unit>() {

    override suspend fun doWork(params: Unit) {
        runCatching { siteCache.prune(preferences.networks.first().preferredOperators) }
        runCatching { trips.restore() }
        refreshTripSites()
        refreshNetworks()
        refreshVehicleCatalog()
    }
}
