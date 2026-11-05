package org.julakali.powertrip.shared.ui

import org.julakali.powertrip.shared.FakeVehicleCatalog
import org.julakali.powertrip.shared.testDispatchers
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
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
import org.julakali.powertrip.shared.domain.UnreachableTrip
import org.julakali.powertrip.shared.domain.VehicleProfile
import org.julakali.powertrip.shared.domain.usecases.CommitTripInteractor
import org.julakali.powertrip.shared.domain.usecases.DismissPlannedTripInteractor
import org.julakali.powertrip.shared.domain.usecases.PlanTripInteractor
import org.julakali.powertrip.shared.domain.usecases.ReplanWithArrivalSocInteractor
import org.julakali.powertrip.shared.domain.usecases.UpdateArrivalSocInteractor
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
import kotlin.test.assertTrue

class TripViewModelTest {

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
    private var plannedSoc: Double? = null
    private var plannedFrom: LatLon? = null
    private var plans = 0
    private var outcome: () -> TripPlanResult = { TripPlanResult.Planned(plan()) }

    private fun plan() = TripPlan(
        route = Route(listOf(hamburg, muenchen.position), distanceKm = 776.0, durationMinutes = 470.0),
        destination = muenchen,
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
            return outcome()
        }
    }

    private fun feature(carSoc: Double?) = ChargeStopsFeature(
        locationSource = object : LocationSource {
            override val updates: Flow<Fix> = MutableSharedFlow()
            override suspend fun currentFix() = Fix(hamburg, null, null, 0L)
        },
        socSource = carSoc?.let { soc ->
            object : SoCSource {
                override val kind = SoCSourceKind.CAR_HARDWARE
                override val energy: Flow<EnergyState?> = flowOf(EnergyState(soc, SoCSourceKind.CAR_HARDWARE, 0L))
            }
        },
        parentScope = CoroutineScope(Dispatchers.Unconfined),
    )

    private fun viewModel(feature: ChargeStopsFeature): TripViewModel {
        val planTrip = PlanTripInteractor(planner, vehicles, FakeVehicleCatalog(), preferences, { null }, history, trips, testDispatchers)
        return main.track(
            TripViewModel(
                feature = feature,
                planTrip = planTrip,
                replanWithArrivalSoc = ReplanWithArrivalSocInteractor(UpdateArrivalSocInteractor(vehicles), trips, planTrip),
                commitTrip = CommitTripInteractor(trips) { 0L },
                updateManualSoc = UpdateManualSocInteractor(vehicles),
                dismissPlannedTrip = DismissPlannedTripInteractor(trips),
                trips = trips,
                vehicles = vehicles,
            ),
        )
    }

    private suspend fun planned(feature: ChargeStopsFeature): TripViewModel {
        vehicles.setVehicle(VehicleProfile("Testwagen", 77.0, 18.0, setOf(ConnectorType.CCS2)))
        vehicles.setManualSocPercent(55.0)
        feature.start()
        feature.locate()
        val viewModel = viewModel(feature)
        viewModel.plan(muenchen)
        withTimeout(5_000) { viewModel.uiState.first { it is TripUiState.Planned } }
        return viewModel
    }

    @Test
    fun `neu planen without a car reading opens the charge-level prompt, seeded with the stored level`() = runBlocking {
        val viewModel = planned(feature(carSoc = null))
        val before = plans

        viewModel.onReplanRequested()

        val state = withTimeout(5_000) { viewModel.uiState.first { (it as? TripUiState.Planned)?.socInput != null } }
        assertEquals("55", (state as TripUiState.Planned).socInput)
        assertEquals(before, plans, "nothing planned until the level is confirmed")
    }

    @Test
    fun `neu planen with a car reading plans straight away`() = runBlocking {
        val feature = feature(carSoc = 42.0)
        val viewModel = planned(feature)
        withTimeout(5_000) { feature.currentEnergy.first { it != null } }
        val before = plans

        viewModel.onReplanRequested()

        val state = withTimeout(5_000) { viewModel.uiState.first { it is TripUiState.Planned && plans == before + 1 } }
        assertEquals(TripEvent.SheetReady, viewModel.event.value)
        assertNull((state as TripUiState.Planned).socInput)
    }

    @Test
    fun `no charger in reach keeps the sheet on the destination, start level still editable`() = runBlocking {
        outcome = { TripPlanResult.NoChargerInReach(afterKm = 0.0) }
        val feature = feature(carSoc = null)
        vehicles.setVehicle(VehicleProfile("Testwagen", 77.0, 18.0, setOf(ConnectorType.CCS2)))
        vehicles.setManualSocPercent(5.0)
        feature.start()
        feature.locate()
        val viewModel = viewModel(feature)

        viewModel.plan(muenchen)

        val state = withTimeout(5_000) { viewModel.uiState.first { it is TripUiState.Unreachable } } as TripUiState.Unreachable
        assertEquals(muenchen, state.destination)
        assertEquals(UnreachableTrip.NoCharger(afterKm = 0.0), state.why)
        assertEquals(5.0, state.startSocPercent)

        viewModel.onStartSocEditRequested()
        withTimeout(5_000) { viewModel.uiState.first { (it as? TripUiState.Unreachable)?.socInput == "5" } }
        outcome = { TripPlanResult.Planned(plan()) }
        viewModel.onStartSocInputChanged("60")
        viewModel.onStartSocConfirmed()

        withTimeout(5_000) { viewModel.uiState.first { it is TripUiState.Planned } }
        assertEquals(60.0, plannedSoc)
    }

    @Test
    fun `closing an unreachable trip goes back to browsing`() = runBlocking {
        outcome = { TripPlanResult.NoChargerInReach(afterKm = 0.0) }
        val feature = feature(carSoc = null)
        vehicles.setVehicle(VehicleProfile("Testwagen", 77.0, 18.0, setOf(ConnectorType.CCS2)))
        feature.start()
        feature.locate()
        val viewModel = viewModel(feature)
        viewModel.plan(muenchen)
        withTimeout(5_000) { viewModel.uiState.first { it is TripUiState.Unreachable } }

        viewModel.clear()

        withTimeout(5_000) { viewModel.uiState.first { it == TripUiState.NoPlan } }
        assertNull(trips.state.value.unreachable)
    }

    private val hotel = Destination("Hotel Adlon", LatLon(52.516, 13.380), "Unter den Linden 77, 10117 Berlin")

    @Test
    fun `picking a start re-plans the same destination from there, leaving the charge level alone`() = runBlocking {
        val viewModel = planned(feature(carSoc = null))

        viewModel.onStartPicked(hotel)

        val state = withTimeout(5_000) { viewModel.uiState.first { (it as? TripUiState.Planned)?.start != null } } as TripUiState.Planned
        assertEquals(hotel, state.start)
        assertEquals(muenchen, state.destination)
        assertEquals(hotel.position, plannedFrom)
        assertEquals(55.0, plannedSoc)
        assertEquals(55.0, state.startSocPercent)
    }

    @Test
    fun `a far-away start says how far it is, the current position does not`() = runBlocking {
        val viewModel = planned(feature(carSoc = null))
        assertNull((viewModel.uiState.value as TripUiState.Planned).startDistanceKm)

        viewModel.onStartPicked(hotel)

        val state = withTimeout(5_000) { viewModel.uiState.first { (it as? TripUiState.Planned)?.start != null } } as TripUiState.Planned
        assertTrue(state.startDistanceKm!! in 250.0..260.0, "was ${state.startDistanceKm}")
    }

    @Test
    fun `a start next to the driver shows no distance`() = runBlocking {
        val viewModel = planned(feature(carSoc = null))

        viewModel.onStartPicked(Destination("Nebenan", LatLon(53.553, 9.99)))

        val state = withTimeout(5_000) { viewModel.uiState.first { (it as? TripUiState.Planned)?.start != null } } as TripUiState.Planned
        assertNull(state.startDistanceKm)
    }

    @Test
    fun `the current position resets the start`() = runBlocking {
        val viewModel = planned(feature(carSoc = null))
        viewModel.onStartPicked(hotel)
        withTimeout(5_000) { viewModel.uiState.first { (it as? TripUiState.Planned)?.start != null } }

        viewModel.onStartPicked(null)

        withTimeout(5_000) { viewModel.uiState.first { it is TripUiState.Planned && it.start == null } }
        assertEquals(hamburg, plannedFrom)
    }

    @Test
    fun `a changed start level re-plans from the picked start`() = runBlocking {
        val viewModel = planned(feature(carSoc = null))
        viewModel.onStartPicked(hotel)
        withTimeout(5_000) { viewModel.uiState.first { (it as? TripUiState.Planned)?.start != null } }
        plannedFrom = null

        viewModel.onStartSocEditRequested()
        withTimeout(5_000) { viewModel.uiState.first { (it as? TripUiState.Planned)?.socInput != null } }
        viewModel.onStartSocInputChanged("70")
        viewModel.onStartSocConfirmed()

        withTimeout(5_000) { viewModel.uiState.first { it is TripUiState.Planned && plannedSoc == 70.0 } }
        assertEquals(hotel.position, plannedFrom)
    }

    @Test
    fun `an unreachable trip can take a different start`() = runBlocking {
        outcome = { TripPlanResult.NoChargerInReach(afterKm = 0.0) }
        val feature = feature(carSoc = null)
        vehicles.setVehicle(VehicleProfile("Testwagen", 77.0, 18.0, setOf(ConnectorType.CCS2)))
        feature.start()
        feature.locate()
        val viewModel = viewModel(feature)
        viewModel.plan(muenchen)
        withTimeout(5_000) { viewModel.uiState.first { it is TripUiState.Unreachable } }

        viewModel.onStartPicked(hotel)

        val state = withTimeout(5_000) { viewModel.uiState.first { (it as? TripUiState.Unreachable)?.start != null } }
        assertEquals(hotel, (state as TripUiState.Unreachable).start)
        assertEquals(hotel.position, plannedFrom)
    }

    @Test
    fun `without a fix a trip plans from the picked start`() = runBlocking {
        vehicles.setVehicle(VehicleProfile("Testwagen", 77.0, 18.0, setOf(ConnectorType.CCS2)))
        PlanTripInteractor(planner, vehicles, FakeVehicleCatalog(), preferences, { null }, history, trips, testDispatchers)(
            PlanTripInteractor.Params(null, muenchen, start = StartChoice.Place(hotel)),
        )
        val viewModel = viewModel(feature(carSoc = null))
        val kiel = Destination("Kiel", LatLon(54.32, 10.14))

        viewModel.plan(kiel)

        val state = withTimeout(5_000) { viewModel.uiState.first { it is TripUiState.Planned } }
        assertEquals(hotel, (state as TripUiState.Planned).start)
        assertEquals(hotel.position, plannedFrom)
    }
}
