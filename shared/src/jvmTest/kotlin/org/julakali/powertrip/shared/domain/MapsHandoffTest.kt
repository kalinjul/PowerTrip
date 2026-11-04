package org.julakali.powertrip.shared.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MapsHandoffTest {

    @Test
    fun `directions url carries origin and destination and waypoints`() {
        val url = MapsHandoff.directionsUrl(
            origin = LatLon(52.37, 4.9),
            destination = LatLon(48.14, 11.58),
            waypoints = listOf(LatLon(51.47, 6.85)),
        )
        assertTrue(url.startsWith("https://www.google.com/maps/dir/?api=1&travelmode=driving"))
        assertTrue("destination=48.14%2C11.58" in url)
        assertTrue("origin=52.37%2C4.9" in url)
        assertTrue("waypoints=51.47%2C6.85" in url)
    }

    @Test
    fun `apple maps link carries destination and every waypoint in order`() {
        val url = MapsHandoff.appleDirectionsUrl(
            destination = LatLon(48.14, 11.58),
            waypoints = listOf(LatLon(52.1, 9.95), LatLon(51.3, 9.45)),
        )
        assertEquals(
            "https://maps.apple.com/directions?destination=48.14%2C11.58" +
                "&waypoint=52.1%2C9.95&waypoint=51.3%2C9.45&mode=driving",
            url,
        )
    }

    @Test
    fun `the google hand-off is the directions url from the current position`() {
        val waypoints = listOf(LatLon(51.47, 6.85))
        assertEquals(
            MapsHandoff.directionsUrl(origin = null, destination = LatLon(48.14, 11.58), waypoints = waypoints),
            MapsHandoff.handoffUrl(NavigationApp.GOOGLE_MAPS, LatLon(48.14, 11.58), waypoints),
        )
    }

    @Test
    fun `google maps falls back to apple maps when it is not installed`() {
        assertEquals(NavigationApp.APPLE_MAPS, NavigationApp.GOOGLE_MAPS.available(googleMapsInstalled = false))
        assertEquals(NavigationApp.GOOGLE_MAPS, NavigationApp.GOOGLE_MAPS.available(googleMapsInstalled = true))
        assertEquals(NavigationApp.APPLE_MAPS, NavigationApp.APPLE_MAPS.available(googleMapsInstalled = true))
    }

    @Test
    fun `without origin Maps uses the current position`() {
        val url = MapsHandoff.navigateUrl(LatLon(48.14, 11.58))
        assertFalse("origin=" in url)
    }

    @Test
    fun `waypoints are capped at the Maps limit`() {
        val many = (1..15).map { LatLon(50.0 + it, 6.0) }
        val url = MapsHandoff.directionsUrl(origin = null, destination = LatLon(48.0, 11.0), waypoints = many)
        val encoded = url.substringAfter("waypoints=")
        assertEquals(MapsHandoff.MAX_WAYPOINTS, encoded.split("%7C").size)
    }

    @Test
    fun `navigation uri carries destination and waypoints`() {
        val uri = MapsHandoff.navigationUri(
            destination = LatLon(48.14, 11.58),
            waypoints = listOf(LatLon(51.47, 6.85), LatLon(50.1, 8.6)),
        )
        assertEquals("google.navigation:q=48.14,11.58&waypoints=51.47,6.85%7C50.1,8.6", uri)
    }

    @Test
    fun `navigation uri without stops has no waypoints`() {
        assertEquals("google.navigation:q=48.14,11.58", MapsHandoff.navigationUri(LatLon(48.14, 11.58)))
    }

    @Test
    fun `geo uri pins the coordinate and encodes the label`() {
        assertEquals(
            "geo:48.14,11.58?q=48.14,11.58(EnBW%20M%C3%BCnchen%20%28Nord%29)",
            MapsHandoff.geoUri(LatLon(48.14, 11.58), "EnBW München (Nord)"),
        )
    }
}
