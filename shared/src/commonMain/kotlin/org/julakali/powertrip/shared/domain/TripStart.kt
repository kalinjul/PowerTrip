package org.julakali.powertrip.shared.domain

import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/** A start the driver picked instead of the current position. */
@Serializable
data class TripStart(
    val place: Destination,
    /** New destinations plan from here too. Not kept across a restart, so it only holds in the process that picked it. */
    @Transient val carriesOver: Boolean = false,
)

/** Where a plan starts. */
sealed interface StartChoice {

    /** The trip's picked start while it still applies, otherwise the current position. */
    data object Keep : StartChoice

    data object CurrentPosition : StartChoice

    data class Place(val place: Destination) : StartChoice
}

/** The start a plan to [destination] takes: a new pick, or the trip's own start while it still applies. */
fun TripState.startFor(destination: Destination, choice: StartChoice): TripStart? = when (choice) {
    StartChoice.Keep -> start?.takeIf { it.carriesOver || destination == currentDestination }
    StartChoice.CurrentPosition -> null
    is StartChoice.Place -> TripStart(choice.place, carriesOver = true)
}
