package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.AppCoroutineDispatchers
import org.julakali.powertrip.shared.domain.ChargeFilters
import org.julakali.powertrip.shared.domain.ChargeNowRanker
import org.julakali.powertrip.shared.domain.ChargeNowResult
import org.julakali.powertrip.shared.domain.ChargePointStatus
import org.julakali.powertrip.shared.domain.ChargePointStatusRepository
import org.julakali.powertrip.shared.domain.ChargeSite
import org.julakali.powertrip.shared.domain.LatLon
import org.julakali.powertrip.shared.domain.PreferencesRepository
import org.julakali.powertrip.shared.domain.SiteAvailability
import org.julakali.powertrip.shared.domain.SiteRepository
import org.julakali.powertrip.shared.domain.SubjectInteractor
import org.julakali.powertrip.shared.domain.chargeNowSlice
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn

/**
 * The best fast chargers around a position among the stored sites, ranked
 * against the driver's filters — and if need be relaxing them.
 *
 * Never fetches: [RefreshChargeNowInteractor] refills the store.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ChargeNowObserver(
    private val repository: SiteRepository,
    private val statusRepository: ChargePointStatusRepository,
    private val preferences: PreferencesRepository,
    private val dispatchers: AppCoroutineDispatchers,
) : SubjectInteractor<ChargeNowObserver.Params, ChargeNowResult?>() {

    /** [position] `null` means: no location yet, and no result. */
    data class Params(val position: LatLon?)

    override fun createObservable(params: Params): Flow<ChargeNowResult?> {
        val position = params.position ?: return flowOf(null)
        return combine(preferences.chargeFilters, preferences.networks, ::Pair)
            .distinctUntilChanged()
            .flatMapLatest { (filters, networks) ->
                combine(repository.chargeNowSlice(position, filters, networks), statusRepository.statuses) { sites, statuses ->
                    ChargeNowRanker.rank(
                        // A full or broken site is no recommendation; one without live data can't be ruled out.
                        sites = sites.filter { it.isWorthSuggesting(statuses, filters) },
                        position = position,
                        filters = filters,
                        networks = networks,
                    )
                }
            }
            // Upstream too: the store maps and merges every row per emission, and it emits per tile
            // the refill writes, all while the sheet is animating on main.
            .flowOn(dispatchers.computation)
    }

    private fun ChargeSite.isWorthSuggesting(statuses: Map<String, List<ChargePointStatus>>, filters: ChargeFilters): Boolean {
        val points = liveStatusId?.let(statuses::get) ?: return true
        return when (val availability = SiteAvailability.of(points, filters.slowMode, filters.minPowerKw)) {
            null -> true
            SiteAvailability.OutOfOrder -> false
            is SiteAvailability.Live -> availability.free > 0
        }
    }
}
