package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.AppCoroutineDispatchers
import org.julakali.powertrip.shared.domain.Destination
import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.LatLon
import org.julakali.powertrip.shared.domain.DestinationHistory
import org.julakali.powertrip.shared.domain.PreferencesRepository
import org.julakali.powertrip.shared.domain.ReverseGeocoder
import org.julakali.powertrip.shared.domain.VehicleCatalogRepository
import org.julakali.powertrip.shared.domain.VehicleRepository
import org.julakali.powertrip.shared.domain.TripPlanResult
import org.julakali.powertrip.shared.domain.TripPlanning
import org.julakali.powertrip.shared.domain.TripRepository
import org.julakali.powertrip.shared.domain.cancellableRunCatching
import org.julakali.powertrip.shared.domain.unreachable
import org.julakali.powertrip.shared.domain.planWithSettings

/**
 * Plans [Params.from] → [Params.destination] with the selected vehicle and
 * makes it the planned trip and the app-wide destination. A failed plan
 * still sets the destination.
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
) : Interactor<PlanTripInteractor.Params, TripPlanResult>() {

    /**
     * [startSocPercent] plans with a charge level that isn't persisted;
     * `null` takes the stored one.
     */
    data class Params(
        val from: LatLon,
        val destination: Destination,
        val startSocPercent: Double? = null,
    )

    override suspend fun doWork(params: Params): TripPlanResult {
        val result = cancellableRunCatching {
            planner.planWithSettings(vehicles, catalog, preferences, addresses, params.from, params.destination, params.startSocPercent, dispatchers.computation)
        }.getOrDefault(TripPlanResult.NoConnection)
        val why = result.unreachable()
        trips.update { state ->
            when {
                result is TripPlanResult.Planned -> state.planned(params.destination, result.plan)
                why != null -> state.unreachable(params.destination, why)
                else -> state.planDismissed()
            }
        }
        history.addRecentDestination(params.destination)
        return result
    }
}
