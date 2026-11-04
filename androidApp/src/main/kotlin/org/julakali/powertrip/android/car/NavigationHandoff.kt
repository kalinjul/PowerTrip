package org.julakali.powertrip.android.car

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import org.julakali.powertrip.shared.domain.LatLon
import org.julakali.powertrip.shared.resources.Res
import org.julakali.powertrip.shared.resources.car_no_navigation_app
import org.julakali.powertrip.shared.Texts

/**
 * Hands one charging site off to the host's navigation app, as `geo:` with
 * coordinates and the name in parentheses.
 */
internal fun navigateTo(carContext: CarContext, name: String, position: LatLon) {
    val label = Uri.encode(name)
    val uri = Uri.parse("geo:${position.lat},${position.lon}?q=${position.lat},${position.lon}($label)")

    try {
        carContext.startCarApp(Intent(CarContext.ACTION_NAVIGATE, uri))
    } catch (notFound: ActivityNotFoundException) {
        // Without a navigation app.
        CarToast.makeText(
            carContext,
            Texts.string(Res.string.car_no_navigation_app),
            CarToast.LENGTH_LONG,
        ).show()
    }
}
