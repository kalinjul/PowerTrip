package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.Interactor
import org.julakali.powertrip.shared.domain.TripRepository

/** The driver is done with the committed trip; nothing keeps it. */
class EndTripInteractor(
    private val trips: TripRepository,
) : Interactor<Unit, Unit>() {

    override suspend fun doWork(params: Unit) {
        trips.update { it.ended() }
    }
}
