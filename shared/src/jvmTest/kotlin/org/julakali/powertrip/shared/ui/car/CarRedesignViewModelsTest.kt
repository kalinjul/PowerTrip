package org.julakali.powertrip.shared.ui.car

import org.julakali.powertrip.shared.ui.TestMain
import org.julakali.powertrip.shared.FakeVehicleCatalog
import org.julakali.powertrip.shared.ChargeStopsFeature
import org.julakali.powertrip.shared.data.DataStoreTripStorage
import org.julakali.powertrip.shared.domain.AppCoroutineDispatchers
import org.julakali.powertrip.shared.domain.ChargeFilters
import org.julakali.powertrip.shared.domain.ChargePointState
import org.julakali.powertrip.shared.domain.ChargePointStatus
import org.julakali.powertrip.shared.domain.ChargePointStatusRepository
import org.julakali.powertrip.shared.domain.ChargeSite
import org.julakali.powertrip.shared.domain.Connector
import org.julakali.powertrip.shared.domain.ConnectorType
import org.julakali.powertrip.shared.domain.Destination
import org.julakali.powertrip.shared.domain.EnergyState
import org.julakali.powertrip.shared.domain.Fix
import org.julakali.powertrip.shared.domain.LatLon
import org.julakali.powertrip.shared.domain.LocationSource
import org.julakali.powertrip.shared.domain.NetworkPreferences
import org.julakali.powertrip.shared.domain.Route
import org.julakali.powertrip.shared.domain.SoCSource
import org.julakali.powertrip.shared.domain.SoCSourceKind
import org.julakali.powertrip.shared.domain.TimeProvider
import org.julakali.powertrip.shared.domain.TripPlan
import org.julakali.powertrip.shared.domain.TripPlanResult
import org.julakali.powertrip.shared.domain.TripPlanning
import org.julakali.powertrip.shared.domain.TripRepository
import org.julakali.powertrip.shared.domain.VehicleProfile
import org.julakali.powertrip.shared.domain.usecases.CommitTripInteractor
import org.julakali.powertrip.shared.domain.usecases.LiveConnectorsObserver
import org.julakali.powertrip.shared.domain.usecases.PlanTripInteractor
import org.julakali.powertrip.shared.domain.usecases.ReplanCommittedTripInteractor
import org.julakali.powertrip.shared.domain.usecases.UpdateManualSocInteractor
import org.julakali.powertrip.shared.settings.DataStoreDestinationHistory
import org.julakali.powertrip.shared.settings.DataStorePreferencesRepository
import org.julakali.powertrip.shared.testVehicleRepository
import org.julakali.powertrip.shared.settings.InMemoryPreferencesDataStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CarRedesignViewModelsTest {

    private val main = TestMain()

    @BeforeTest
    fun setUpMainDispatcher() = main.setUp()

    @AfterTest
    fun tearDownMainDispatcher() = main.tearDown()

    private val settings = InMemoryPreferencesDataStore()
    private val vehicles = testVehicleRepository(settings)
    private val trips = TripRepository(DataStoreTripStorage(InMemoryPreferencesDataStore()))
    private val time = TimeProvider { 1_700_000_000_000L }
    private val dispatchers = AppCoroutineDispatchers(Dispatchers.Unconfined, Dispatchers.Unconfined, Dispatchers.Unconfined)
    private val plannedWith = MutableStateFlow(emptyList<Double>())

    private suspend fun <T> StateFlow<T>.await(matching: (T) -> Boolean): T = withTimeout(5_000) { first(matching) }

    @Test
    fun `the home tiles show the charge level the feature knows`() = runBlocking<Unit> {
        val energy = MutableStateFlow<EnergyState?>(null)
        val feature = feature(energy, SoCSourceKind.MANUAL)
        val viewModel = main.track(CarHomeViewModel(feature, trips))
        assertNull(viewModel.uiState.await { true }.socPercent)

        energy.value = EnergyState(63.4, SoCSourceKind.MANUAL, 0L)

        assertEquals(63, viewModel.uiState.await { it.socPercent != null }.socPercent)
    }

    @Test
    fun `neu planen plans right away only when the car reports its charge`() = runBlocking<Unit> {
        withVehicleAndCommittedTrip()
        val manual = routeViewModel(feature(MutableStateFlow(EnergyState(50.0, SoCSourceKind.MANUAL, 0L)), SoCSourceKind.MANUAL))
        manual.uiState.await { it is CarRouteUiState.Ready }

        assertFalse(manual.onReplanRequested())
        assertTrue(plannedWith.value.isEmpty())

        val car = routeViewModel(feature(MutableStateFlow(EnergyState(42.0, SoCSourceKind.CAR_HARDWARE, 0L)), SoCSourceKind.CAR_HARDWARE))
        car.uiState.await { it is CarRouteUiState.Ready }

        assertTrue(car.onReplanRequested())
        assertEquals(listOf(42.0), plannedWith.await { it.isNotEmpty() })
    }

    @Test
    fun `starting navigation from a plan made in the car commits it`() = runBlocking<Unit> {
        vehicles.setVehicle(VehicleProfile("Test-EV", 75.0, 18.0, setOf(ConnectorType.CCS2)))
        val viewModel = routeViewModel(feature(MutableStateFlow(EnergyState(55.0, SoCSourceKind.MANUAL, 0L)), SoCSourceKind.MANUAL), activeRoute = false)
        viewModel.uiState.await { it is CarRouteUiState.Ready }
        assertNull(trips.state.value.committed)

        viewModel.onNavigationStarted()

        assertEquals(plan, trips.state.value.committed!!.plan)
        assertEquals(55.0, trips.state.value.committed!!.startSocPercent)
    }

    @Test
    fun `a picked level re-plans with it and keeps it as the manual one`() = runBlocking<Unit> {
        withVehicleAndCommittedTrip()
        val viewModel = routeViewModel(feature(MutableStateFlow(null), SoCSourceKind.MANUAL))
        viewModel.uiState.await { it is CarRouteUiState.Ready }

        viewModel.onReplanWith(30)

        assertEquals(listOf(30.0), plannedWith.await { it.isNotEmpty() })
        assertEquals(30.0, withTimeout(5_000) { vehicles.manualSocPercent.first { it != null } })
    }

    @Test
    fun `the detail measures from the fix and shows the live points`() = runBlocking<Unit> {
        val statuses = MutableStateFlow(mapOf("live:1" to listOf(ChargePointStatus(ChargePointState.AVAILABLE, 150.0, listOf(ConnectorType.CCS2)))))
        val repository = object : ChargePointStatusRepository {
            override val statuses: Flow<Map<String, List<ChargePointStatus>>> = statuses
            override suspend fun refresh(ids: Collection<String>) = Unit
        }
        val feature = feature(MutableStateFlow(null), SoCSourceKind.MANUAL)
        val viewModel = main.track(CarSiteDetailViewModel(feature, site.copy(liveStatusId = "live:1"), LiveConnectorsObserver(repository)))

        val state = viewModel.uiState.await { it.distanceKm != null && it.live != null }

        assertTrue(state.distanceKm!! in 100.0..120.0, "was ${state.distanceKm}")
        assertEquals(1, state.live!!.single().available)
    }

    private fun feature(energy: Flow<EnergyState?>, kind: SoCSourceKind): ChargeStopsFeature =
        ChargeStopsFeature(
            locationSource = object : LocationSource {
                override val updates: Flow<Fix> = flowOf(Fix(hamburg, null, null, 0L))
                override suspend fun currentFix(): Fix = Fix(hamburg, null, null, 0L)
            },
            socSource = object : SoCSource {
                override val kind: SoCSourceKind = kind
                override val energy: Flow<EnergyState?> = energy
            },
            parentScope = CoroutineScope(Dispatchers.Unconfined),
        ).apply { start() }

    private fun withVehicleAndCommittedTrip() = runBlocking {
        vehicles.setVehicle(VehicleProfile("Test-EV", 75.0, 18.0, setOf(ConnectorType.CCS2)))
        CommitTripInteractor(trips, time)(CommitTripInteractor.Params(plan, startSocPercent = 60.0)).getOrThrow()
    }

    private fun routeViewModel(feature: ChargeStopsFeature, activeRoute: Boolean = true): CarRouteViewModel {
        val preferences = DataStorePreferencesRepository(settings)
        val planner = object : TripPlanning {
            override suspend fun plan(
                from: LatLon,
                destination: Destination,
                vehicle: VehicleProfile,
                startSocPercent: Double,
                arrivalSocPercent: Double,
                filters: ChargeFilters,
                networks: NetworkPreferences,
            ): TripPlanResult {
                plannedWith.update { it + startSocPercent }
                return TripPlanResult.Planned(plan)
            }
        }
        return main.track(CarRouteViewModel(
            feature = feature,
            destination = plan.destination,
            activeRoute = activeRoute,
            planTrip = PlanTripInteractor(planner, vehicles, FakeVehicleCatalog(), preferences, { null }, DataStoreDestinationHistory(settings), trips, dispatchers),
            replanCommittedTrip = ReplanCommittedTripInteractor(planner, vehicles, FakeVehicleCatalog(), preferences, { null }, trips, UpdateManualSocInteractor(vehicles), time, dispatchers),
            commitTrip = CommitTripInteractor(trips, time),
            trips = trips,
        ))
    }

    private companion object {
        val hamburg = LatLon(53.55, 9.99)
        val site = ChargeSite("test:1", "Lader", "Operator", position = LatLon(54.5, 10.1), connectors = listOf(Connector(ConnectorType.CCS2, 150.0, 2)))
        val munich = Destination("München", LatLon(48.137, 11.575))
        val plan = TripPlan(
            route = Route(listOf(hamburg, munich.position), distanceKm = 776.0, durationMinutes = 470.0),
            destination = munich,
            stops = emptyList(),
            driveMinutes = 470.0,
            chargeMinutes = 0.0,
            arrivalSocPercent = 22.0,
        )
    }
}
