package org.julakali.powertrip.shared.ui

import androidx.lifecycle.SavedStateHandle
import org.julakali.powertrip.shared.ChargeStopsFeature
import org.julakali.powertrip.shared.domain.Address
import org.julakali.powertrip.shared.domain.Destination
import org.julakali.powertrip.shared.domain.Fix
import org.julakali.powertrip.shared.domain.Geocoder
import org.julakali.powertrip.shared.domain.LatLon
import org.julakali.powertrip.shared.domain.LocationSource
import org.julakali.powertrip.shared.domain.usecases.DestinationSearchObserver
import org.julakali.powertrip.shared.domain.Place
import org.julakali.powertrip.shared.domain.Route
import org.julakali.powertrip.shared.domain.TripPlan
import org.julakali.powertrip.shared.domain.TripRepository
import org.julakali.powertrip.shared.domain.TripStart
import org.julakali.powertrip.shared.settings.InMemoryPreferencesDataStore
import org.julakali.powertrip.shared.settings.DataStoreDestinationHistory
import org.julakali.powertrip.shared.testVehicleRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SearchViewModelTest {

    private val main = TestMain()

    @BeforeTest
    fun setUpMainDispatcher() = main.setUp()

    @AfterTest
    fun tearDownMainDispatcher() = main.tearDown()

    private val hamburg = Destination("Hamburg", LatLon(53.55, 9.99), "Hamburg")
    private val berlin = Place(
        name = "Berlin Hbf",
        description = "Berlin Hbf, Europaplatz 1, 10557 Berlin",
        position = LatLon(52.525, 13.369),
        address = Address(street = "Europaplatz 1", postalCode = "10557", town = "Berlin"),
    )
    private val frankfurt = LatLon(50.11, 8.68)

    /** An empty query lists what was searched before, nothing else. */
    @Test
    fun `an empty query shows recents as rows`() {
        val rows = searchRows(query = "", results = emptyList(), recent = listOf(hamburg), from = null)
        assertEquals(listOf(SearchRow(hamburg, "Hamburg", "Hamburg", distanceKm = null, recent = true)), rows)
    }

    /** Once the query is long enough the geocoder's hits replace the recents. */
    @Test
    fun `a typed query shows geocoder results with their address`() {
        val rows = searchRows(query = "Berlin", results = listOf(berlin), recent = listOf(hamburg), from = frankfurt)
        val row = rows.single()
        assertEquals("Berlin Hbf", row.title)
        assertEquals("Europaplatz 1, 10557 Berlin", row.detail)
        assertFalse(row.recent)
        assertEquals(Destination("Berlin Hbf", berlin.position, "Europaplatz 1, 10557 Berlin"), row.destination)
    }

    @Test
    fun `distance is measured from the fix and missing without one`() {
        val withFix = searchRows("", emptyList(), listOf(hamburg), from = frankfurt).single().distanceKm
        assertTrue(withFix!! in 390.0..400.0, "was $withFix")
        assertNull(searchRows("", emptyList(), listOf(hamburg), from = null).single().distanceKm)
    }

    @Test
    fun `km labels round the way the list expects`() {
        val saved = java.util.Locale.getDefault()
        try {
            java.util.Locale.setDefault(java.util.Locale.GERMANY)
            assertEquals("< 1", 0.4.asKmLabel())
            assertEquals("4,2", 4.24.asKmLabel())
            assertEquals("42", 41.6.asKmLabel())
            java.util.Locale.setDefault(java.util.Locale.US)
            assertEquals("4.2", 4.24.asKmLabel())
        } finally {
            java.util.Locale.setDefault(saved)
        }
    }

    /** "Neu planen" reopens the search on the current destination as a pick; typing discards it. */
    @Test
    fun `opening with a prefill shows it as the committed pick`() = runBlocking<Unit> {
        val viewModel = searchViewModel()
        viewModel.onOpened(hamburg)
        val opened = viewModel.uiState.await { it.query.isNotEmpty() }
        assertEquals("Hamburg, Hamburg", opened.query)
        assertEquals(listOf(hamburg), opened.rows.map { it.destination })
        viewModel.onQueryChanged("Ha")
        assertTrue(viewModel.uiState.await { it.query == "Ha" }.rows.isEmpty())
        viewModel.onClosed()
        assertEquals("", viewModel.uiState.await { it.query.isEmpty() }.query)
    }

    @Test
    fun `without a vehicle the state says so`() = runBlocking<Unit> {
        val viewModel = searchViewModel()
        assertFalse(viewModel.uiState.await { true }.hasVehicle)
    }

    @Test
    fun `opening and closing toggles the panel`() = runBlocking<Unit> {
        val viewModel = searchViewModel()
        viewModel.onOpened()
        viewModel.uiState.await { it.expanded }
        viewModel.onClosed()
        viewModel.uiState.await { !it.expanded }
    }

    /** The field reports focus again while the panel is open. */
    @Test
    fun `reopening an open panel keeps the query`() = runBlocking<Unit> {
        val viewModel = searchViewModel()
        viewModel.onOpened()
        viewModel.onQueryChanged("Ham")
        viewModel.onOpened()
        assertEquals("Ham", viewModel.uiState.await { it.expanded }.query)
    }

    /** #133 */
    @Test
    fun `an open panel comes back after process death`() = runBlocking<Unit> {
        val savedState = SavedStateHandle()
        searchViewModel(savedState).onOpened()
        assertTrue(searchViewModel(savedState).uiState.await { it.expanded }.expanded)
    }

    private val trips = TripRepository()

    private fun searchViewModel(savedState: SavedStateHandle = SavedStateHandle()) =
        main.track(SearchViewModel(stubFeature(), DestinationSearchObserver(NoGeocoder, NoLocation), vehicles(), history(), trips, savedState))

    private val munichPlan = TripPlan(
        route = Route(listOf(frankfurt, LatLon(48.14, 11.58)), distanceKm = 390.0, durationMinutes = 240.0),
        destination = Destination("München", LatLon(48.14, 11.58)),
        stops = emptyList(),
        driveMinutes = 240.0,
        chargeMinutes = 0.0,
        arrivalSocPercent = 30.0,
        startAddress = "Feldstraße 66, Hamburg",
    )

    @Test
    fun `the start search opens empty and closes back into the destination search`() = runBlocking<Unit> {
        val viewModel = searchViewModel()

        viewModel.onStartSearchOpened()
        val opened = viewModel.uiState.await { it.expanded }
        assertEquals(SearchTarget.START, opened.target)
        assertEquals("", opened.query)

        viewModel.onClosed()
        assertEquals(SearchTarget.DESTINATION, viewModel.uiState.await { !it.expanded }.target)
        viewModel.onOpened()
        assertEquals(SearchTarget.DESTINATION, viewModel.uiState.await { it.expanded }.target)
    }

    @Test
    fun `the start search knows whether the trip starts at the current position`() = runBlocking<Unit> {
        trips.update { it.planned(munichPlan.destination, munichPlan) }
        val viewModel = searchViewModel()
        viewModel.onStartSearchOpened()

        val here = viewModel.uiState.await { it.expanded && it.currentPositionAddress != null }
        assertTrue(here.startIsCurrentPosition)
        assertEquals("Feldstraße 66, Hamburg", here.currentPositionAddress)

        val hotel = Destination("Hotel Adlon", LatLon(52.516, 13.380), "Unter den Linden 77, 10117 Berlin")
        trips.update { it.planned(munichPlan.destination, munichPlan.copy(startAddress = hotel.address), TripStart(hotel)) }
        val picked = viewModel.uiState.await { !it.startIsCurrentPosition }
        assertNull(picked.currentPositionAddress)
    }

    @Test
    fun `an open start search comes back after process death`() = runBlocking<Unit> {
        val savedState = SavedStateHandle()
        searchViewModel(savedState).onStartSearchOpened()
        assertEquals(SearchTarget.START, searchViewModel(savedState).uiState.await { it.expanded }.target)
    }

    private fun vehicles() = testVehicleRepository()

    private fun history() = DataStoreDestinationHistory(InMemoryPreferencesDataStore())

    private suspend fun <T> StateFlow<T>.await(matching: (T) -> Boolean): T = withTimeout(5_000) { first(matching) }

    private fun stubFeature() = ChargeStopsFeature(
        locationSource = object : LocationSource {
            override suspend fun currentFix(): Fix? = null
            override val updates: Flow<Fix> = emptyFlow()
        },
        parentScope = CoroutineScope(Dispatchers.Unconfined),
    )

    private object NoGeocoder : Geocoder {
        override suspend fun search(query: String, near: LatLon?, limit: Int): List<Place> = emptyList()
    }

    private object NoLocation : LocationSource {
        override suspend fun currentFix(): Fix? = null
        override val updates: Flow<Fix> = emptyFlow()
    }
}
