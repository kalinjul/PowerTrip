package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.CommittedTrip
import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.TimeProvider
import org.julakali.powertrip.shared.domain.TripPlan
import org.julakali.powertrip.shared.domain.TripRepository

/** Makes [Params.plan] the trip the driver is on and takes it off the map; the previous one is replaced. */
class CommitTripInteractor(
    private val trips: TripRepository,
    private val time: TimeProvider,
) : Interactor<CommitTripInteractor.Params, CommittedTrip>() {

    data class Params(val plan: TripPlan, val startSocPercent: Double?)

    override suspend fun doWork(params: Params): CommittedTrip {
        val trip = CommittedTrip(params.plan, params.startSocPercent, time.nowMillis())
        trips.update { it.committed(trip) }
        return trip
    }
}
