package org.julakali.powertrip.uitests

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.julakali.powertrip.android.phone.HomeTopBar
import org.julakali.powertrip.shared.domain.Destination
import org.julakali.powertrip.shared.domain.LatLon
import org.julakali.powertrip.shared.domain.TripPlan
import org.julakali.powertrip.shared.ui.SearchTarget
import org.julakali.powertrip.shared.ui.SearchUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.julakali.powertrip.shared.resources.Res
import org.julakali.powertrip.shared.resources.home_search_current_position
import org.julakali.powertrip.shared.resources.home_search_hint
import org.julakali.powertrip.shared.resources.home_search_start_hint
import org.julakali.powertrip.shared.resources.home_trip_clear

@RunWith(RobolectricTestRunner::class)
class HomeTopBarTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun topBar(
        search: SearchUiState = SearchUiState(),
        trip: TripPlan? = null,
        destination: Destination? = trip?.destination,
        onClearTrip: () -> Unit = {},
        onFlyTo: (LatLon) -> Unit = {},
        onPickCurrentPosition: () -> Unit = {},
    ) = compose.setThemedContent {
        HomeTopBar(
            search = search,
            trip = trip,
            onExpandedChange = {},
            onQueryChange = {},
            onPick = {},
            onPickCurrentPosition = onPickCurrentPosition,
            onClearTrip = onClearTrip,
            onFlyTo = onFlyTo,
            destination = destination,
        )
    }

    private val hint get() = compose.onNodeWithText(compose.string(Res.string.home_search_hint))
    private val header get() = compose.onNodeWithText(Fixtures.plan.destination.name)

    @Test
    fun `the start search asks for a start and offers the current position first`() {
        var picked = false
        topBar(
            search = SearchUiState(expanded = true, target = SearchTarget.START, currentPositionAddress = "Feldstraße 66, Hamburg"),
            trip = Fixtures.plan,
            onPickCurrentPosition = { picked = true },
        )
        compose.onNodeWithText(compose.string(Res.string.home_search_start_hint)).assertIsDisplayed()
        compose.onNodeWithText("Feldstraße 66, Hamburg").assertIsDisplayed()
        compose.onNodeWithText(compose.string(Res.string.home_search_current_position)).assertIsSelected()

        compose.onNodeWithText(compose.string(Res.string.home_search_current_position)).performClick()
        assertTrue(picked)
    }

    @Test
    fun `the destination search has no current-position row`() {
        topBar(search = SearchUiState(expanded = true))
        compose.onNodeWithText(compose.string(Res.string.home_search_current_position)).assertDoesNotExist()
    }

    @Test
    fun `without a trip the search bar shows`() {
        topBar()
        hint.assertIsDisplayed()
        header.assertDoesNotExist()
    }

    @Test
    fun `a destination no plan reached still replaces the bar`() {
        topBar(destination = Fixtures.plan.destination)
        header.assertIsDisplayed()
        hint.assertDoesNotExist()
    }

    @Test
    fun `a planned trip replaces the bar with its destination`() {
        topBar(trip = Fixtures.plan)
        header.assertIsDisplayed()
        hint.assertDoesNotExist()
    }

    @Test
    fun `an open search wins over the trip header`() {
        topBar(search = SearchUiState(expanded = true), trip = Fixtures.plan)
        header.assertDoesNotExist()
    }

    @Test
    fun `the header's title flies to the destination`() {
        var target: LatLon? = null
        topBar(trip = Fixtures.plan, onFlyTo = { target = it })
        header.performClick()
        assertEquals(Fixtures.plan.destination.position, target)
    }

    @Test
    fun `the header's x clears the trip`() {
        var cleared = false
        topBar(trip = Fixtures.plan, onClearTrip = { cleared = true })
        compose.onNodeWithContentDescription(compose.string(Res.string.home_trip_clear)).performClick()
        assertTrue(cleared)
    }
}
