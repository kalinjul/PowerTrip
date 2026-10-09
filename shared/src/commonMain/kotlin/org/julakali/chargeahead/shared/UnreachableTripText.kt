package org.julakali.chargeahead.shared

import org.jetbrains.compose.resources.StringResource
import org.julakali.chargeahead.shared.domain.UnreachableTrip
import org.julakali.chargeahead.shared.resources.Res
import org.julakali.chargeahead.shared.resources.plan_failed_no_charger
import org.julakali.chargeahead.shared.resources.plan_failed_no_charger_at_start
import org.julakali.chargeahead.shared.resources.plan_failed_no_connection
import org.julakali.chargeahead.shared.resources.plan_failed_no_route
import kotlin.math.roundToInt

/** Why there is no plan, as a resource and its arguments. */
fun UnreachableTrip.messageResource(): Pair<StringResource, Array<Any>> = when (this) {
    is UnreachableTrip.NoCharger -> {
        val km = afterKm.roundToInt()
        if (km == 0) Res.string.plan_failed_no_charger_at_start to emptyArray() else Res.string.plan_failed_no_charger to arrayOf(km)
    }
    UnreachableTrip.NoRoute -> Res.string.plan_failed_no_route to emptyArray()
    UnreachableTrip.NoConnection -> Res.string.plan_failed_no_connection to emptyArray()
}
