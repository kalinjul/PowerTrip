package org.julakali.powertrip.shared.ui

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.julakali.powertrip.shared.domain.CarDataKind
import org.julakali.powertrip.shared.domain.CarDataPoint
import org.julakali.powertrip.shared.domain.CarDataStatus
import org.julakali.powertrip.shared.settings.DataStoreCarDiagnosticsRepository
import org.julakali.powertrip.shared.settings.InMemoryPreferencesDataStore
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

class CarDataViewModelTest {

    private val main = TestMain()

    private val diagnostics = DataStoreCarDiagnosticsRepository(InMemoryPreferencesDataStore())

    @BeforeTest
    fun setUpMainDispatcher() = main.setUp()

    @AfterTest
    fun tearDownMainDispatcher() = main.tearDown()

    @Test
    fun `the points the car delivered show up`() = runBlocking<Unit> {
        val speed = CarDataPoint(CarDataKind.SPEED, CarDataStatus.AVAILABLE, "97 km/h", 10L)
        diagnostics.recordCarDataPoint(speed)

        val state = withTimeout(5_000) {
            main.track(CarDataViewModel(diagnostics)).uiState.first { it.points.isNotEmpty() }
        }

        assertEquals(listOf(speed), state.points)
    }
}
