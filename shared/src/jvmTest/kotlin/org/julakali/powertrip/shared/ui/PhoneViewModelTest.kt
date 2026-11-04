package org.julakali.powertrip.shared.ui

import org.julakali.powertrip.shared.FakeVehicleCatalog
import org.julakali.powertrip.shared.testAppScope
import org.julakali.powertrip.shared.testDispatchers
import org.julakali.powertrip.shared.ChargeStopsFeature
import org.julakali.powertrip.shared.ChargeStopsState
import org.julakali.powertrip.shared.core.CorridorPlanner
import org.julakali.powertrip.shared.data.CachingChargePointStatusRepository
import org.julakali.powertrip.shared.data.TiledSiteRepository
import org.julakali.powertrip.shared.db.DatabaseFactory
import org.julakali.powertrip.shared.db.createChargeSiteDatabase
import org.julakali.powertrip.shared.domain.Address
import org.julakali.powertrip.shared.domain.BoundingBox
import org.julakali.powertrip.shared.domain.ChargeFilters
import org.julakali.powertrip.shared.domain.ChargePointState
import org.julakali.powertrip.shared.domain.ChargePointStatus
import org.julakali.powertrip.shared.domain.ChargePointStatusSource
import org.julakali.powertrip.shared.domain.ChargeSite
import org.julakali.powertrip.shared.domain.ChargeSiteSource
import org.julakali.powertrip.shared.domain.Connector
import org.julakali.powertrip.shared.domain.ConnectorType
import org.julakali.powertrip.shared.domain.Destination
import org.julakali.powertrip.shared.domain.Fix
import org.julakali.powertrip.shared.domain.LatLon
import org.julakali.powertrip.shared.domain.SectionSelection
import org.julakali.powertrip.shared.domain.LocationSource
import org.julakali.powertrip.shared.domain.NetworkPreferences
import org.julakali.powertrip.shared.domain.PreferencesRepository
import org.julakali.powertrip.shared.domain.Geocoder
import org.julakali.powertrip.shared.domain.usecases.ChargeStopsObserver
import org.julakali.powertrip.shared.domain.usecases.DestinationSearchObserver
import org.julakali.powertrip.shared.domain.LiveConnectorGroup
import org.julakali.powertrip.shared.domain.MapCharger
import org.julakali.powertrip.shared.domain.usecases.LiveConnectorsObserver
import org.julakali.powertrip.shared.domain.ChargeMode
import org.julakali.powertrip.shared.domain.usecases.UpdateNetworksInteractor
import org.julakali.powertrip.shared.domain.usecases.SetChargeModeInteractor
import org.julakali.powertrip.shared.domain.usecases.UpdateChargeFiltersInteractor
import org.julakali.powertrip.shared.domain.usecases.MapChargersObserver
import org.julakali.powertrip.shared.domain.usecases.RefreshLiveConnectorsInteractor
import org.julakali.powertrip.shared.domain.usecases.RefreshChargeStopsInteractor
import org.julakali.powertrip.shared.domain.usecases.RefreshChargerAvailabilityInteractor
import org.julakali.powertrip.shared.domain.usecases.RefreshMapChargersInteractor
import org.julakali.powertrip.shared.domain.usecases.SelectVehicleInteractor
import org.julakali.powertrip.shared.domain.usecases.GarageObserver
import org.julakali.powertrip.shared.domain.usecases.VehiclePresetsObserver
import org.julakali.powertrip.shared.domain.usecases.UpdateArrivalSocInteractor
import org.julakali.powertrip.shared.domain.usecases.UpdateManualSocInteractor
import org.julakali.powertrip.shared.domain.Place
import org.julakali.powertrip.shared.domain.SearchArea
import org.julakali.powertrip.shared.domain.SiteAvailability
import org.julakali.powertrip.shared.domain.TimeProvider
import org.julakali.powertrip.shared.domain.TripRepository
import org.julakali.powertrip.shared.settings.InMemoryPreferencesDataStore
import org.julakali.powertrip.shared.settings.DataStorePreferencesRepository
import org.julakali.powertrip.shared.testVehicleRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * [TestMain] provides the Main dispatcher `viewModelScope` needs and keeps
 * writes in order.
 *
 * `uiState` only produces while someone collects; [await] subscribes and
 * waits for the first matching state.
 */
class PhoneViewModelTest {

    private val main = TestMain()

    @BeforeTest
    fun setUpMainDispatcher() = main.setUp()

    @AfterTest
    fun tearDownMainDispatcher() = main.tearDown()

    @Test
    fun `the garage reports what the settings hold`() = runBlocking<Unit> {
        val vehicles = testVehicleRepository()
        val catalog = FakeVehicleCatalog()
        val addCar = main.track(AddCarViewModel(VehiclePresetsObserver(catalog, vehicles, testDispatchers), SelectVehicleInteractor(vehicles)))
        val garage = main.track(GarageViewModel(
            vehicles,
            GarageObserver(vehicles, catalog),
            SelectVehicleInteractor(vehicles),
            UpdateArrivalSocInteractor(vehicles),
            UpdateManualSocInteractor(vehicles),
        ))

        val preset = addCar.uiState.await { it.matches.isNotEmpty() }.matches.first()
        addCar.onPresetAdded(preset)

        val state = garage.uiState.await { it.selected != null }
        assertEquals(preset.name, state.selected?.displayName)
        assertEquals(listOf(preset.name), state.vehicles.map { it.displayName })
        assertEquals(preset.usableBatteryKwh / preset.consumptionKwhPer100Km * 100, state.fullRangeKm.getValue(state.selected!!.id), 0.5)
        // Already owned, so the add screen stops offering it.
        assertTrue(addCar.uiState.await { preset !in it.matches }.matches.none { it.name == preset.name })
    }

    /** The stops between `a` and `b` travel as waypoints and must look selected. */
    @Test
    fun `a picked section covers every point between its ends`() {
        val section = SectionSelection(selecting = true).picked(3).picked(1)

        assertTrue(section.includes(1) && section.includes(2) && section.includes(3))
        assertTrue(!section.includes(0) && !section.includes(4))
    }

    @Test
    fun `a half-picked section covers only the point tapped so far`() {
        val section = SectionSelection(selecting = true).picked(2)

        assertTrue(section.includes(2))
        assertTrue(!section.includes(1) && !section.includes(3))
        assertTrue(!SectionSelection(selecting = true).includes(0), "nothing is selected before the first tap")
    }

    /** Issue #17: a filter change must re-run the marker query, not only a viewport change. */
    @Test
    fun `changing the minimum power reloads the map markers`() = runBlocking<Unit> {
        val preferences = DataStorePreferencesRepository(InMemoryPreferencesDataStore())
        val viewModel = homeViewModel(mapSites, preferences)

        viewModel.onViewportChanged(VIEWPORT)
        // Default minimum is 150 kW, so the 50 kW site starts out hidden.
        assertEquals(listOf("demo:hpc"), viewModel.uiState.await { it.chargers.isNotEmpty() }.chargers.map { it.site.id })

        preferences.setChargeFilters(ChargeFilters(minPowerKw = 50.0))
        assertEquals(
            listOf("demo:hpc", "demo:slow"),
            viewModel.uiState.await { it.chargers.size == 2 }.chargers.map { it.site.id },
        )
    }

    /** Same reasoning for the other filter the map applies. */
    @Test
    fun `picking networks reloads the map markers`() = runBlocking<Unit> {
        val preferences = DataStorePreferencesRepository(InMemoryPreferencesDataStore())
        val viewModel = homeViewModel(mapSites, preferences)

        viewModel.onViewportChanged(VIEWPORT)
        viewModel.uiState.await { it.chargers.isNotEmpty() }

        preferences.setNetworks(NetworkPreferences(onlyPreferred = true, preferredOperators = setOf("fastned")))
        assertTrue(viewModel.uiState.await { it.chargers.isEmpty() }.chargers.isEmpty())
    }

    @Test
    fun `a viewport change brings the markers' live availability`() = runBlocking {
        val preferences = DataStorePreferencesRepository(InMemoryPreferencesDataStore())
        val site = mapSite("hpc", "Ionity", 300.0).copy(liveStatusId = "live-hpc")
        val statusSource = ChargePointStatusSource { ids ->
            ids.associateWith { listOf(ChargePointStatus(ChargePointState.AVAILABLE), ChargePointStatus(ChargePointState.OCCUPIED)) }
        }
        val viewModel = homeViewModel(listOf(site), preferences, statusSource = statusSource)

        viewModel.onViewportChanged(VIEWPORT)

        val charger = viewModel.uiState.await { state -> state.chargers.any { it.availability != null } }.chargers.single()
        assertEquals(SiteAvailability.Live(free = 1, total = 2), charger.availability)
    }

    @Test
    fun `a selected charger shows its live connectors until dismissed`() = runBlocking {
        val preferences = DataStorePreferencesRepository(InMemoryPreferencesDataStore())
        val site = mapSite("hpc", "Ionity", 300.0).copy(liveStatusId = "live-hpc")
        val statusSource = ChargePointStatusSource { ids ->
            ids.associateWith {
                listOf(
                    ChargePointStatus(ChargePointState.AVAILABLE, 300.0, listOf(ConnectorType.CCS2)),
                    ChargePointStatus(ChargePointState.OCCUPIED, 300.0, listOf(ConnectorType.CCS2)),
                )
            }
        }
        val viewModel = homeViewModel(listOf(site), preferences, statusSource = statusSource)

        viewModel.onChargerSelected(MapCharger(site, 300.0))

        val live = viewModel.uiState.await { it.selectedStopLive != null }.selectedStopLive
        assertEquals(
            listOf(LiveConnectorGroup(listOf(ConnectorType.CCS2), 300.0, available = 1, occupied = 1, outOfOrder = 0, unknown = 0)),
            live,
        )

        viewModel.onSelectedStopDismissed()
        assertNull(viewModel.uiState.await { it.selectedStop == null }.selectedStopLive)
    }

    private val mapSites = listOf(
        mapSite("hpc", "Ionity", 300.0),
        mapSite("slow", "EnBW", 50.0),
    )

    private fun mapSite(id: String, operator: String, powerKw: Double) = ChargeSite(
        id = "demo:$id",
        name = id,
        operator = operator,
        position = LatLon(51.2, 6.7),
        connectors = listOf(Connector(ConnectorType.CCS2, powerKw, 2)),
    )

    private fun fixedSource(sites: List<ChargeSite>) = object : ChargeSiteSource {
        override val id = "fixed"
        override suspend fun query(area: SearchArea, networkKeys: Set<String>): List<ChargeSite> = sites
    }

    /** On the *same* store the ViewModel gets, over an in-memory database. */
    private fun homeViewModel(
        sites: List<ChargeSite>,
        preferences: PreferencesRepository,
        locationTimeoutMillis: Long = HomeViewModel.DEFAULT_LOCATION_TIMEOUT_MILLIS,
        statusSource: ChargePointStatusSource = ChargePointStatusSource { emptyMap() },
    ): HomeViewModel {
        val repository = TiledSiteRepository(fixedSource(sites), createChargeSiteDatabase(DatabaseFactory(), Dispatchers.IO), TimeProvider { 0L }, testAppScope, testDispatchers.computation)
        val statuses = CachingChargePointStatusRepository(statusSource, TimeProvider { 0L })
        return main.track(HomeViewModel(
            stubFeature(),
            MapChargersObserver(repository, statuses, preferences, testDispatchers),
            RefreshMapChargersInteractor(repository, preferences),
            RefreshChargerAvailabilityInteractor(repository, statuses, preferences, testDispatchers),
            LiveConnectorsObserver(statuses),
            RefreshLiveConnectorsInteractor(statuses),
            preferences,
            SetChargeModeInteractor(preferences, UpdateChargeFiltersInteractor(preferences), UpdateNetworksInteractor(preferences)),
            locationTimeoutMillis,
        ))
    }

    /** The map says which mode is on, and its pill switches that mode off again. */
    @Test
    fun `the map shows the mode and dismisses it`() = runBlocking<Unit> {
        val preferences = DataStorePreferencesRepository(InMemoryPreferencesDataStore())
        val viewModel = homeViewModel(mapSites, preferences)
        assertEquals(ChargeMode.NORMAL, viewModel.uiState.await { true }.mode)

        preferences.setChargeFilters(ChargeFilters(slowMode = true))
        assertEquals(ChargeMode.AC, viewModel.uiState.await { it.mode == ChargeMode.AC }.mode)
        viewModel.onModeDismissed()
        assertEquals(ChargeMode.NORMAL, viewModel.uiState.await { it.mode == ChargeMode.NORMAL }.mode)

        preferences.setNetworks(NetworkPreferences(onlyPreferred = false))
        assertEquals(ChargeMode.BROWSE, viewModel.uiState.await { it.mode == ChargeMode.BROWSE }.mode)
        viewModel.onModeDismissed()
        assertEquals(true, preferences.networks.first().onlyPreferred)
    }

    @Test
    fun `the corridor list waits for a fix and then shows the stored stops`() = runBlocking {
        val fixes = MutableSharedFlow<Fix>(extraBufferCapacity = 1)
        val feature = ChargeStopsFeature(
            locationSource = object : LocationSource {
                override suspend fun currentFix(): Fix? = null
                override val updates: Flow<Fix> = fixes
            },
            parentScope = CoroutineScope(Dispatchers.Unconfined),
        )
        val repository = TiledSiteRepository(fixedSource(mapSites), createChargeSiteDatabase(DatabaseFactory(), Dispatchers.IO), TimeProvider { 0L }, testAppScope, testDispatchers.computation)
        val viewModel = main.track(CorridorViewModel(
            feature,
            ChargeStopsObserver(repository, testVehicleRepository(), FakeVehicleCatalog(), DataStorePreferencesRepository(InMemoryPreferencesDataStore()), TripRepository(), CorridorPlanner(), testDispatchers),
            RefreshChargeStopsInteractor(repository, DataStorePreferencesRepository(InMemoryPreferencesDataStore())),
        ))

        viewModel.uiState.await { it.phase == ChargeStopsState.Phase.WAITING_FOR_LOCATION }
        feature.start()
        fixes.emit(Fix(LatLon(51.21, 6.7), bearingDeg = null, speedMps = null, timestampMillis = 0L))

        val ready = viewModel.uiState.await { it.phase == ChargeStopsState.Phase.READY && it.stops.isNotEmpty() }
        assertEquals(setOf("demo:hpc", "demo:slow"), ready.stops.map { it.site.id }.toSet())
        feature.close()
    }

    @Test
    fun `without a fix the location button says it is searching`() = runBlocking {
        val preferences = DataStorePreferencesRepository(InMemoryPreferencesDataStore())
        val viewModel = homeViewModel(emptyList(), preferences)

        viewModel.onLocateRequested()

        // Spinner yes, hint no: the deadline is twenty seconds away.
        val searching = viewModel.uiState.await { it.searchingLocation }
        assertTrue(!searching.locationUnavailable)
    }

    @Test
    fun `past the deadline the map says why it is still empty`() = runBlocking {
        val preferences = DataStorePreferencesRepository(InMemoryPreferencesDataStore())
        val viewModel = homeViewModel(emptyList(), preferences, locationTimeoutMillis = 50L)

        viewModel.onLocateRequested()

        // The request is still running — that is the point of showing both.
        val givenUp = viewModel.uiState.await { it.locationUnavailable }
        assertTrue(givenUp.searchingLocation)
    }

    private suspend fun <T> StateFlow<T>.await(matching: (T) -> Boolean): T =
        withTimeout(TIMEOUT_MILLIS) { first(matching) }

    /** Same for a store flow: the writes behind it are asynchronous. */
    private suspend fun <T> Flow<T>.awaitValue(matching: (T) -> Boolean): T =
        withTimeout(TIMEOUT_MILLIS) { first(matching) }

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

    private companion object {
        const val TIMEOUT_MILLIS = 5_000L

        val VIEWPORT = BoundingBox(south = 51.0, west = 6.5, north = 51.4, east = 7.0)
    }
}
