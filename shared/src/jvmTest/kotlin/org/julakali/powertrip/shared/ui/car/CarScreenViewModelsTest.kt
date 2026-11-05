package org.julakali.powertrip.shared.ui.car

import org.julakali.powertrip.shared.ui.TestMain
import kotlinx.coroutines.flow.flowOf

import org.julakali.powertrip.shared.testDispatchers
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.julakali.powertrip.shared.ChargeStopsFeature
import org.julakali.powertrip.shared.domain.BoundingBox
import org.julakali.powertrip.shared.domain.ChargePointStatus
import org.julakali.powertrip.shared.domain.ChargePointStatusRepository
import org.julakali.powertrip.shared.domain.ChargeSite
import org.julakali.powertrip.shared.domain.Connector
import org.julakali.powertrip.shared.domain.ConnectorType
import org.julakali.powertrip.shared.domain.Destination
import org.julakali.powertrip.shared.domain.Fix
import org.julakali.powertrip.shared.domain.Geocoder
import org.julakali.powertrip.shared.domain.LatLon
import org.julakali.powertrip.shared.domain.LocationSource
import org.julakali.powertrip.shared.domain.MapFilter
import org.julakali.powertrip.shared.domain.Place
import org.julakali.powertrip.shared.domain.SearchArea
import org.julakali.powertrip.shared.domain.SiteRepository
import org.julakali.powertrip.shared.domain.SoCDiagnostics
import org.julakali.powertrip.shared.domain.usecases.ChargeNowObserver
import org.julakali.powertrip.shared.domain.usecases.DestinationSearchObserver
import org.julakali.powertrip.shared.domain.usecases.RefreshChargeNowInteractor
import org.julakali.powertrip.shared.domain.usecases.UpdateManualSocInteractor
import org.julakali.powertrip.shared.settings.InMemoryPreferencesDataStore
import org.julakali.powertrip.shared.settings.DataStoreDestinationHistory
import org.julakali.powertrip.shared.settings.DataStorePreferencesRepository
import org.julakali.powertrip.shared.testVehicleRepository
import org.julakali.powertrip.shared.settings.DataStoreCarDiagnosticsRepository
import org.julakali.powertrip.shared.ui.ChargeNowUiState
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CarScreenViewModelsTest {

    private val main = TestMain()

    @BeforeTest
    fun setUpMainDispatcher() = main.setUp()

    @AfterTest
    fun tearDownMainDispatcher() = main.tearDown()

    private val here = LatLon(48.0, 11.0)
    private val vehicles = testVehicleRepository()
    private val preferences = DataStorePreferencesRepository(InMemoryPreferencesDataStore())
    private val history = DataStoreDestinationHistory(InMemoryPreferencesDataStore())
    private val diagnostics = DataStoreCarDiagnosticsRepository(InMemoryPreferencesDataStore())

    private suspend fun <T> StateFlow<T>.await(matching: (T) -> Boolean): T = withTimeout(5_000) { first(matching) }

    @Test
    fun `charge now waits for a position, then ranks what the refill stored`() = runBlocking<Unit> {
        val fixes = MutableSharedFlow<Fix>(replay = 1)
        val feature = ChargeStopsFeature(
            locationSource = object : LocationSource {
                override suspend fun currentFix(): Fix? = null
                override val updates: Flow<Fix> = fixes
            },
            parentScope = CoroutineScope(Dispatchers.Unconfined),
        ).apply { start() }
        val nearby = ChargeSite(
            id = "near",
            name = "near",
            operator = "Ionity",
            position = LatLon(here.lat + 0.01, here.lon),
            connectors = listOf(Connector(ConnectorType.CCS2, 300.0, 4)),
        )
        val store = MutableStateFlow<List<ChargeSite>>(emptyList())
        val repository = object : SiteRepository {
            override suspend fun covers(area: SearchArea, networkKeys: Set<String>): Boolean = true
            override suspend fun storedSites(ids: Set<String>): Map<String, ChargeSite> = emptyMap()
            override fun storedSitesIn(area: SearchArea): Flow<List<ChargeSite>> = flowOf(emptyList())
            override suspend fun invalidate() {}
            override suspend fun load(area: SearchArea, networkKeys: Set<String>) {
                store.update { listOf(nearby) }
            }

            override fun storedSitesIn(box: BoundingBox, filter: MapFilter): Flow<List<ChargeSite>> = store
        }
        val statusRepository = object : ChargePointStatusRepository {
            override val statuses: Flow<Map<String, List<ChargePointStatus>>> = flowOf(emptyMap())
            override suspend fun refresh(ids: Collection<String>) {}
        }
        val viewModel = main.track(CarChargeNowViewModel(
            feature,
            ChargeNowObserver(repository, statusRepository, preferences, testDispatchers),
            RefreshChargeNowInteractor(repository, statusRepository, preferences),
        ))
        assertEquals(ChargeNowUiState.NoPosition, viewModel.uiState.await { true })

        fixes.emit(Fix(here, null, null, 0L))

        val ready = viewModel.uiState.await { it is ChargeNowUiState.Ready && !it.result.isEmpty }
        assertEquals(listOf("near"), (ready as ChargeNowUiState.Ready).result.candidates.map { it.site.id })
    }

    @Test
    fun `destination search offers recents until text is typed and searches the typed text after a pause`() = runBlocking<Unit> {
        val hamburg = Destination("Hamburg", LatLon(53.55, 9.99))
        val berlin = Place(name = "Berlin Hbf", description = "Berlin Hbf", position = LatLon(52.525, 13.369))
        val geocoder = RecordingGeocoder { listOf(berlin) }
        history.addRecentDestination(hamburg)
        val viewModel = main.track(CarDestinationSearchViewModel(history, DestinationSearchObserver(geocoder, noLocation)))
        assertEquals(listOf(hamburg), viewModel.uiState.await { it.recents.isNotEmpty() }.recents)

        viewModel.onSearchTextChanged("Berlin")
        val typed = viewModel.uiState.await { it.query == "Berlin" }
        assertTrue(typed.recents.isEmpty())
        assertTrue(typed.typing || typed.searching)

        val found = viewModel.uiState.await { it.places.isNotEmpty() && !it.searching }
        assertEquals(listOf(berlin), found.places)
        assertEquals(false, found.typing)
        assertEquals(listOf("Berlin"), geocoder.queries)
    }

    @Test
    fun `dictated text that arrives after an early submit is searched`() = runBlocking<Unit> {
        val station = Place(name = "Berlin Hbf", description = "Berlin Hbf", position = LatLon(52.525, 13.369))
        val geocoder = RecordingGeocoder { query -> if (query == "Berlin Hauptbahnhof") listOf(station) else emptyList() }
        val viewModel = main.track(CarDestinationSearchViewModel(history, DestinationSearchObserver(geocoder, noLocation)))

        viewModel.onSearchTextChanged("Berlin Haupt")
        viewModel.onSearchSubmitted("Berlin Haupt")
        viewModel.onSearchTextChanged("")
        viewModel.onSearchTextChanged("Berlin Hauptbahnhof")

        val found = viewModel.uiState.await { it.places.isNotEmpty() && !it.searching }
        assertEquals(listOf(station), found.places)
        assertEquals("Berlin Hauptbahnhof", found.query)
        assertEquals("Berlin Hauptbahnhof", geocoder.queries.last())
    }

    @Test
    fun `the host emptying its search box right after a dictated submit keeps the search`() = runBlocking<Unit> {
        val station = Place(name = "Kiel Hbf", description = "Kiel Hbf", position = LatLon(54.315, 10.132))
        val geocoder = RecordingGeocoder { listOf(station) }
        val viewModel = main.track(CarDestinationSearchViewModel(history, DestinationSearchObserver(geocoder, noLocation)))

        viewModel.onSearchTextChanged("Kiel Hauptbahnhof")
        viewModel.onSearchSubmitted("Kiel Hauptbahnhof")
        viewModel.onSearchTextChanged("")

        val found = viewModel.uiState.await { it.places.isNotEmpty() && !it.searching }
        assertEquals("Kiel Hauptbahnhof", found.query)
        assertEquals(listOf(station), found.places)
    }

    @Test
    fun `emptying the search box otherwise brings the recents back`() = runBlocking<Unit> {
        val hamburg = Destination("Hamburg", LatLon(53.55, 9.99))
        history.addRecentDestination(hamburg)
        val viewModel = main.track(CarDestinationSearchViewModel(history, DestinationSearchObserver(RecordingGeocoder { emptyList() }, noLocation)))

        viewModel.onSearchSubmitted("Kiel")
        viewModel.onSearchTextChanged("Ki")
        viewModel.onSearchTextChanged("")

        assertEquals(listOf(hamburg), viewModel.uiState.await { it.query.isEmpty() && it.recents.isNotEmpty() }.recents)
    }

    @Test
    fun `destination search keeps the submitted text so the search box can show it again`() = runBlocking<Unit> {
        val geocoder = RecordingGeocoder { emptyList() }
        val viewModel = main.track(CarDestinationSearchViewModel(history, DestinationSearchObserver(geocoder, noLocation)))
        assertEquals("", viewModel.uiState.await { true }.query)

        viewModel.onSearchSubmitted("Berlin Hauptbahnhof")

        assertEquals("Berlin Hauptbahnhof", viewModel.uiState.await { it.query.isNotEmpty() && !it.searching }.query)
    }

    @Test
    fun `picking a charge level stores it and ends the screen`() = runBlocking<Unit> {
        val viewModel = main.track(CarSoCViewModel(vehicles, diagnostics, UpdateManualSocInteractor(vehicles)))
        assertNull(viewModel.uiState.await { true }.currentPercent)

        viewModel.onStepPicked(60)

        val saved = viewModel.uiState.await { it.saved }
        assertEquals(60.0, saved.currentPercent)
    }

    @Test
    fun `the car reading shows only when the car delivered one`() = runBlocking<Unit> {
        val viewModel = main.track(CarSoCViewModel(vehicles, diagnostics, UpdateManualSocInteractor(vehicles)))
        diagnostics.recordSoCDiagnostics(SoCDiagnostics(0L, SoCDiagnostics.Outcome.NO_DATA, detail = "status 2"))
        assertNull(viewModel.uiState.await { true }.carReading)

        diagnostics.recordSoCDiagnostics(SoCDiagnostics(1L, SoCDiagnostics.Outcome.AVAILABLE, detail = "72%"))
        assertEquals("72%", viewModel.uiState.await { it.carReading != null }.carReading)
    }

    private val noLocation = object : LocationSource {
        override suspend fun currentFix(): Fix? = null
        override val updates: Flow<Fix> = emptyFlow()
    }

    private class RecordingGeocoder(private val answer: (String) -> List<Place>) : Geocoder {
        val queries = mutableListOf<String>()
        override suspend fun search(query: String, near: LatLon?, limit: Int): List<Place> {
            queries += query
            return answer(query)
        }
    }
}
