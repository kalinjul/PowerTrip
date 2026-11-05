package org.julakali.powertrip.shared.ui.car

import org.julakali.powertrip.shared.ui.TestMain
import org.julakali.powertrip.shared.FakeVehicleCatalog
import org.julakali.powertrip.shared.testDispatchers
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.julakali.powertrip.shared.ChargeStopsFeature
import org.julakali.powertrip.shared.domain.ChargeFilters
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
import org.julakali.powertrip.shared.domain.StartChoice
import org.julakali.powertrip.shared.domain.TripPlan
import org.julakali.powertrip.shared.domain.TripPlanResult
import org.julakali.powertrip.shared.domain.TripPlanning
import org.julakali.powertrip.shared.domain.TripRepository
import org.julakali.powertrip.shared.domain.VehicleProfile
import org.julakali.powertrip.shared.domain.invoke
import org.julakali.powertrip.shared.domain.usecases.CommitTripInteractor
import org.julakali.powertrip.shared.domain.usecases.EndTripInteractor
import org.julakali.powertrip.shared.domain.usecases.PlanTripInteractor
import org.julakali.powertrip.shared.domain.usecases.ReplanCommittedTripInteractor
import org.julakali.powertrip.shared.domain.usecases.UpdateManualSocInteractor
import org.julakali.powertrip.shared.settings.InMemoryPreferencesDataStore
import org.julakali.powertrip.shared.settings.DataStoreDestinationHistory
import org.julakali.powertrip.shared.settings.DataStorePreferencesRepository
import org.julakali.powertrip.shared.testVehicleRepository
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class CarRouteViewModelTest {

    private val main = TestMain()

    @BeforeTest
    fun setUpMainDispatcher() = main.setUp()

    @AfterTest
    fun tearDownMainDispatcher() = main.tearDown()

    private val hamburg = LatLon(53.55, 9.99)
    private val muenchen = Destination("München", LatLon(48.137, 11.575))
    private val vehicles = testVehicleRepository()
    private val preferences = DataStorePreferencesRepository(InMemoryPreferencesDataStore())
    private val history = DataStoreDestinationHistory(InMemoryPreferencesDataStore())
    private val trips = TripRepository()
    private val fixes = MutableSharedFlow<Fix>(replay = 1)
    private var plannedSoc: Double? = null
    private var plans = 0
    private var plannedFrom: LatLon? = null

    private fun plan(destination: Destination = muenchen) = TripPlan(
        route = Route(listOf(hamburg, destination.position), distanceKm = 776.0, durationMinutes = 470.0),
        destination = destination,
        stops = emptyList(),
        driveMinutes = 470.0,
        chargeMinutes = 0.0,
        arrivalSocPercent = 30.0,
    )

    private val planner = object : TripPlanning {
        override suspend fun plan(
            from: LatLon,
            destination: Destination,
            vehicle: VehicleProfile,
            startSocPercent: Double,
            arrivalSocPercent: Double,
            filters: ChargeFilters,
            networks: NetworkPreferences,
        ): TripPlanResult {
            plans++
            plannedSoc = startSocPercent
            plannedFrom = from
            return TripPlanResult.Planned(plan(destination))
        }
    }

    private val feature = ChargeStopsFeature(
        locationSource = object : LocationSource {
            override suspend fun currentFix(): Fix? = null
            override val updates: Flow<Fix> = fixes
        },
        socSource = object : SoCSource {
            override val kind = SoCSourceKind.CAR_HARDWARE
            override val energy: Flow<EnergyState?> = flowOf(EnergyState(64.0, SoCSourceKind.CAR_HARDWARE, 0L))
        },
        parentScope = CoroutineScope(Dispatchers.Unconfined),
    ).apply { start() }

    private fun viewModel(activeRoute: Boolean = false) =
        main.track(CarRouteViewModel(
            feature,
            muenchen,
            activeRoute,
            PlanTripInteractor(planner, vehicles, FakeVehicleCatalog(), preferences, { null }, history, trips, testDispatchers),
            ReplanCommittedTripInteractor(planner, vehicles, FakeVehicleCatalog(), preferences, { null }, trips, UpdateManualSocInteractor(vehicles), { 9L }, testDispatchers),
            CommitTripInteractor(trips) { 9L },
            trips,
        ))

    private suspend fun <T> StateFlow<T>.await(matching: (T) -> Boolean): T = withTimeout(5_000) { first(matching) }

    private suspend fun withVehicle() {
        vehicles.setVehicle(VehicleProfile("Testwagen", 77.0, 18.0, setOf(ConnectorType.CCS2)))
    }

    @Test
    fun `waits for a position, then plans with the car's charge level`() = runBlocking<Unit> {
        withVehicle()
        val viewModel = viewModel()
        assertEquals(CarRouteUiState.Loading(waitingForLocation = true), viewModel.uiState.await { true })

        fixes.emit(Fix(hamburg, null, null, 0L))

        val ready = viewModel.uiState.await { it is CarRouteUiState.Ready } as CarRouteUiState.Ready
        assertEquals(muenchen, ready.plan.destination)
        assertEquals(64.0, plannedSoc)
    }

    @Test
    fun `a failed plan shows why`() = runBlocking<Unit> {
        fixes.emit(Fix(hamburg, null, null, 0L))
        val viewModel = viewModel()

        assertEquals(
            CarRouteUiState.Failed(TripPlanResult.NoVehicle),
            viewModel.uiState.await { it is CarRouteUiState.Failed },
        )
    }

    @Test
    fun `the active route shows the committed trip without planning, and ends with it`() = runBlocking<Unit> {
        fixes.emit(Fix(hamburg, null, null, 0L))
        CommitTripInteractor(trips) { 0L }(CommitTripInteractor.Params(plan(), startSocPercent = 50.0))
        val viewModel = viewModel(activeRoute = true)

        viewModel.uiState.await { it is CarRouteUiState.Ready }
        assertEquals(0, plans)

        EndTripInteractor(trips).invoke()
        viewModel.uiState.await { it == CarRouteUiState.Ended }
    }

    @Test
    fun `refreshing the active route replans the committed trip with the car's level, without storing it`() = runBlocking<Unit> {
        withVehicle()
        vehicles.setManualSocPercent(40.0)
        fixes.emit(Fix(hamburg, null, null, 0L))
        CommitTripInteractor(trips) { 0L }(CommitTripInteractor.Params(plan(), startSocPercent = 50.0))
        val viewModel = viewModel(activeRoute = true)
        viewModel.uiState.await { it is CarRouteUiState.Ready }

        viewModel.onRefresh()

        val committed = trips.state.await { it.committed?.committedAtEpochMillis == 9L }.committed!!
        assertEquals(64.0, committed.startSocPercent)
        assertEquals(64.0, plannedSoc)
        assertEquals(40.0, vehicles.manualSocPercent.first())
        assertNull(trips.state.value.planned)
        viewModel.uiState.await { it is CarRouteUiState.Ready }
    }

    @Test
    fun `the car plans from where it is and drops a start picked on the phone`() = runBlocking<Unit> {
        withVehicle()
        val hotel = Destination("Hotel Adlon", LatLon(52.516, 13.380))
        PlanTripInteractor(planner, vehicles, FakeVehicleCatalog(), preferences, { null }, history, trips, testDispatchers)(
            PlanTripInteractor.Params(hamburg, muenchen, start = StartChoice.Place(hotel)),
        )
        val viewModel = viewModel()

        fixes.emit(Fix(hamburg, null, null, 0L))

        viewModel.uiState.await { it is CarRouteUiState.Ready && plans == 2 }
        assertEquals(hamburg, plannedFrom)
        assertNull(trips.state.value.start)
    }
}
