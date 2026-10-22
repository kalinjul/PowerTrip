package org.julakali.chargeahead.shared.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class RouteWeatherTest {

    private val dwd = "Datenbasis: Deutscher Wetterdienst, Einzelwerte interpoliert"

    private fun route(vararg temperatures: Double?, attribution: String? = dwd) = Route(
        points = listOf(LatLon(54.39, 10.22), LatLon(53.55, 10.0)),
        distanceKm = 10.0 * temperatures.size,
        durationMinutes = 10.0 * temperatures.size,
        segments = temperatures.mapIndexed { i, temperature -> RouteSegment(10.0 * i, 10.0, 10.0, 0.0, 0.0, temperature) },
        weatherAttribution = attribution,
    )

    @Test
    fun `start and destination are the first and last segment's forecast`() {
        val route = route(4.0, 6.0, 8.0)

        assertEquals(4.0, route.startTemperatureC)
        assertEquals(8.0, route.destinationTemperatureC)
    }

    @Test
    fun `the attribution comes with a temperature at either end`() {
        assertEquals(dwd, route(4.0, null).endTemperaturesAttribution)
        assertEquals(dwd, route(null, 8.0).endTemperaturesAttribution)
    }

    /** Weather only between the ends is priced but not shown, so nothing on screen needs the notice. */
    @Test
    fun `no attribution when neither end shows a temperature`() {
        assertNull(route(null, 6.0, null).endTemperaturesAttribution)
    }

    @Test
    fun `no attribution without one from the backend`() {
        assertNull(route(4.0, 8.0, attribution = null).endTemperaturesAttribution)
    }
}
