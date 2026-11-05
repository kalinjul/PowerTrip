package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.FakeVehicleCatalog
import org.julakali.powertrip.shared.persistenceJson
import org.julakali.powertrip.shared.testDispatchers
import org.julakali.powertrip.shared.testVehicleRepository
import org.julakali.powertrip.shared.domain.Address
import org.julakali.powertrip.shared.domain.ChargeFilters
import org.julakali.powertrip.shared.domain.CommittedTrip
import org.julakali.powertrip.shared.domain.ConnectorType
import org.julakali.powertrip.shared.domain.Destination
import org.julakali.powertrip.shared.domain.LatLon
import org.julakali.powertrip.shared.domain.NetworkPreferences
import org.julakali.powertrip.shared.domain.Route
import org.julakali.powertrip.shared.domain.StartChoice
import org.julakali.powertrip.shared.domain.TripPlan
import org.julakali.powertrip.shared.domain.TripPlanResult
import org.julakali.powertrip.shared.domain.TripPlanning
import org.julakali.powertrip.shared.domain.TripRepository
import org.julakali.powertrip.shared.domain.TripStart
import org.julakali.powertrip.shared.domain.TripState
import org.julakali.powertrip.shared.domain.TripStorage
import org.julakali.powertrip.shared.domain.VehicleProfile
import org.julakali.powertrip.shared.settings.DataStoreDestinationHistory
import org.julakali.powertrip.shared.settings.DataStorePreferencesRepository
import org.julakali.powertrip.shared.settings.InMemoryPreferencesDataStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlinx.coroutines.runBlocking

class TripStartTest {

    private val here = LatLon(53.55, 9.99)
    private val hotel = Destination("Hotel Adlon", LatLon(52.516, 13.380), "Unter den Linden 77, 10117 Berlin")
    private val munich = Destination("München", LatLon(48.14, 11.58))
    private val kiel = Destination("Kiel", LatLon(54.32, 10.14))
    private val vehicles = testVehicleRepository()
    private val preferences = DataStorePreferencesRepository(InMemoryPreferencesDataStore())
    private val history = DataStoreDestinationHistory(InMemoryPreferencesDataStore())

    private val origins = mutableListOf<LatLon>()
    private var addressLookups = 0

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
            origins += from
            return TripPlanResult.Planned(
                TripPlan(
                    route = Route(listOf(from, destination.position), distanceKm = 300.0, durationMinutes = 180.0),
                    destination = destination,
                    stops = emptyList(),
                    driveMinutes = 180.0,
                    chargeMinutes = 0.0,
                    arrivalSocPercent = 30.0,
                ),
            )
        }
    }

    private fun planTrip(trips: TripRepository) = PlanTripInteractor(
        planner, vehicles, FakeVehicleCatalog(), preferences,
        { addressLookups++; Address(street = "Feldstraße 66", town = "Hamburg") },
        history, trips, testDispatchers,
    )

    private suspend fun withVehicle() {
        vehicles.setVehicle(VehicleProfile("Testwagen", 77.0, 18.0, setOf(ConnectorType.CCS2)))
    }

    @Test
    fun `a picked start plans from there and brings its own address`() = runBlocking<Unit> {
        withVehicle()
        val trips = TripRepository()

        planTrip(trips)(PlanTripInteractor.Params(here, munich, start = StartChoice.Place(hotel))).getOrThrow()

        assertEquals(listOf(hotel.position), origins)
        assertEquals(hotel, trips.state.value.start?.place)
        assertEquals("Unter den Linden 77, 10117 Berlin", trips.state.value.planned?.startAddress)
        assertEquals(0, addressLookups)
    }

    @Test
    fun `re-planning the same trip keeps the picked start`() = runBlocking<Unit> {
        withVehicle()
        val trips = TripRepository()
        val planTrip = planTrip(trips)
        planTrip(PlanTripInteractor.Params(here, munich, start = StartChoice.Place(hotel))).getOrThrow()

        planTrip(PlanTripInteractor.Params(here, munich, startSocPercent = 40.0)).getOrThrow()

        assertEquals(listOf(hotel.position, hotel.position), origins)
        assertEquals(hotel, trips.state.value.start?.place)
    }

    @Test
    fun `a new destination keeps the start picked in this process`() = runBlocking<Unit> {
        withVehicle()
        val trips = TripRepository()
        val planTrip = planTrip(trips)
        planTrip(PlanTripInteractor.Params(here, munich, start = StartChoice.Place(hotel))).getOrThrow()

        planTrip(PlanTripInteractor.Params(here, kiel)).getOrThrow()

        assertEquals(hotel.position, origins.last())
        assertEquals(hotel, trips.state.value.start?.place)
    }

    @Test
    fun `after a restart the start only holds for the restored trip`() = runBlocking<Unit> {
        withVehicle()
        val storage = MemoryStorage()
        planTrip(TripRepository(storage))(PlanTripInteractor.Params(here, munich, start = StartChoice.Place(hotel))).getOrThrow()
        val restored = TripRepository(storage).also { it.restore() }
        val planTrip = planTrip(restored)

        planTrip(PlanTripInteractor.Params(here, munich)).getOrThrow()
        assertEquals(hotel.position, origins.last())

        planTrip(PlanTripInteractor.Params(here, kiel)).getOrThrow()
        assertEquals(here, origins.last())
        assertNull(restored.state.value.start)
    }

    @Test
    fun `the current position resets a picked start`() = runBlocking<Unit> {
        withVehicle()
        val trips = TripRepository()
        val planTrip = planTrip(trips)
        planTrip(PlanTripInteractor.Params(here, munich, start = StartChoice.Place(hotel))).getOrThrow()

        planTrip(PlanTripInteractor.Params(here, munich, start = StartChoice.CurrentPosition)).getOrThrow()

        assertEquals(here, origins.last())
        assertNull(trips.state.value.start)
        assertEquals("Feldstraße 66, Hamburg", trips.state.value.planned?.startAddress)
    }

    @Test
    fun `without a fix only a picked start can be planned from`() = runBlocking<Unit> {
        withVehicle()
        val trips = TripRepository()
        val planTrip = planTrip(trips)

        assertNull(planTrip(PlanTripInteractor.Params(null, munich)).getOrThrow())
        assertEquals(emptyList(), origins)

        val result = planTrip(PlanTripInteractor.Params(null, munich, start = StartChoice.Place(hotel))).getOrThrow()
        assertIs<TripPlanResult.Planned>(result)
        assertEquals(listOf(hotel.position), origins)
    }

    @Test
    fun `a new arrival level re-plans from the picked start`() = runBlocking<Unit> {
        withVehicle()
        val trips = TripRepository()
        val planTrip = planTrip(trips)
        planTrip(PlanTripInteractor.Params(here, munich, start = StartChoice.Place(hotel))).getOrThrow()

        ReplanWithArrivalSocInteractor(UpdateArrivalSocInteractor(vehicles), trips, planTrip)(
            ReplanWithArrivalSocInteractor.Params(20.0, from = null),
        ).getOrThrow()

        assertEquals(listOf(hotel.position, hotel.position), origins)
    }

    @Test
    fun `dismissing and committing drop the picked start`() {
        val start = TripStart(hotel, carriesOver = true)
        val plan = TripPlan(Route(listOf(hotel.position, munich.position), 500.0, 300.0), munich, emptyList(), 300.0, 0.0, 30.0)
        val state = TripState().planned(munich, plan, start)

        assertNull(state.planDismissed().start)
        assertNull(state.committed(CommittedTrip(plan, null, 0L)).start)
    }

    private class MemoryStorage : TripStorage {
        private var stored: String? = null

        override suspend fun read(): TripState? =
            stored?.let { persistenceJson.decodeFromString(TripState.serializer(), it) }

        override suspend fun write(state: TripState) {
            stored = persistenceJson.encodeToString(TripState.serializer(), state)
        }
    }
}
