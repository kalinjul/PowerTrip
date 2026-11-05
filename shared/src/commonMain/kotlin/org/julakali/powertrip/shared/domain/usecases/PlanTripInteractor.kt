package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.AppCoroutineDispatchers
import org.julakali.powertrip.shared.domain.Destination
import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.LatLon
import org.julakali.powertrip.shared.domain.DestinationHistory
import org.julakali.powertrip.shared.domain.PreferencesRepository
import org.julakali.powertrip.shared.domain.ReverseGeocoder
import org.julakali.powertrip.shared.domain.StartChoice
import org.julakali.powertrip.shared.domain.VehicleCatalogRepository
import org.julakali.powertrip.shared.domain.VehicleRepository
import org.julakali.powertrip.shared.domain.TripPlanResult
import org.julakali.powertrip.shared.domain.TripPlanning
import org.julakali.powertrip.shared.domain.TripRepository
import org.julakali.powertrip.shared.domain.cancellableRunCatching
import org.julakali.powertrip.shared.domain.unreachable
import org.julakali.powertrip.shared.domain.planWithSettings
import org.julakali.powertrip.shared.domain.startFor

/**
 * Plans to [Params.destination] with the selected vehicle and makes it the
 * planned trip and the app-wide destination. A failed plan still sets the
 * destination. `null` when there is neither a start nor a position to plan from.
 */
class PlanTripInteractor(
    private val planner: TripPlanning,
    private val vehicles: VehicleRepository,
    private val catalog: VehicleCatalogRepository,
    private val preferences: PreferencesRepository,
    private val addresses: ReverseGeocoder,
    private val history: DestinationHistory,
    private val trips: TripRepository,
    private val dispatchers: AppCoroutineDispatchers,
) : Interactor<PlanTripInteractor.Params, TripPlanResult?>() {

    /**
     * [from] is the current position, `null` without a fix. [startSocPercent]
     * plans with a charge level that isn't persisted; `null` takes the stored one.
     */
    data class Params(
        val from: LatLon?,
        val destination: Destination,
        val startSocPercent: Double? = null,
        val start: StartChoice = StartChoice.Keep,
    )

    override suspend fun doWork(params: Params): TripPlanResult? {
        val start = trips.state.value.startFor(params.destination, params.start)
        val from = start?.place?.position ?: params.from ?: return null
        val result = cancellableRunCatching {
            planner.planWithSettings(
                vehicles, catalog, preferences, addresses, from, params.destination, params.startSocPercent, dispatchers.computation,
                knownStartAddress = start?.place?.let { it.address ?: it.name },
            )
        }.getOrDefault(TripPlanResult.NoConnection)
        val why = result.unreachable()
        trips.update { state ->
            when {
                result is TripPlanResult.Planned -> state.planned(params.destination, result.plan, start)
                why != null -> state.unreachable(params.destination, why, start)
                else -> state.planDismissed()
            }
        }
        history.addRecentDestination(params.destination)
        return result
    }
}
