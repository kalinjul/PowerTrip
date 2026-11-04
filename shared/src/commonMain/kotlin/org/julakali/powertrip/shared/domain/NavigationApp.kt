package org.julakali.powertrip.shared.domain

/** The app that navigates a handed-off trip on iOS; Android always hands off to Google Maps. */
enum class NavigationApp {
    APPLE_MAPS,
    GOOGLE_MAPS,
    ;

    /** The app that actually takes the trip: Google Maps only while it is installed. */
    fun available(googleMapsInstalled: Boolean): NavigationApp =
        if (this == GOOGLE_MAPS && !googleMapsInstalled) APPLE_MAPS else this
}
