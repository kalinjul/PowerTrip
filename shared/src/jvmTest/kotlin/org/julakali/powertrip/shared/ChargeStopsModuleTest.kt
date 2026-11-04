package org.julakali.powertrip.shared

import org.julakali.powertrip.shared.db.DatabaseFactory
import org.julakali.powertrip.shared.domain.Fix
import org.julakali.powertrip.shared.domain.LocationSource
import org.julakali.powertrip.shared.domain.ReverseGeocoder
import org.julakali.powertrip.shared.domain.NetworkRepository
import org.julakali.powertrip.shared.domain.VehicleCatalogRepository
import org.julakali.powertrip.shared.domain.usecases.ChargeNowObserver
import org.julakali.powertrip.shared.domain.usecases.ChargeStopsObserver
import org.julakali.powertrip.shared.domain.usecases.DestinationSearchObserver
import org.julakali.powertrip.shared.domain.usecases.PlanTripInteractor
import org.julakali.powertrip.shared.domain.usecases.RefreshNetworksInteractor
import org.julakali.powertrip.shared.domain.usecases.RefreshVehicleCatalogInteractor
import org.julakali.powertrip.shared.domain.usecases.VehiclePresetsObserver
import org.julakali.powertrip.shared.domain.usecases.CommitTripInteractor
import org.julakali.powertrip.shared.domain.usecases.EndTripInteractor
import org.julakali.powertrip.shared.domain.usecases.RemoveVehicleInteractor
import org.julakali.powertrip.shared.domain.usecases.ReplanWithArrivalSocInteractor
import org.julakali.powertrip.shared.domain.usecases.SelectVehicleInteractor
import org.julakali.powertrip.shared.domain.TripStorage
import org.julakali.powertrip.shared.domain.usecases.UpdateArrivalSocInteractor
import org.julakali.powertrip.shared.domain.usecases.UpdateChargeFiltersInteractor
import org.julakali.powertrip.shared.domain.usecases.UpdateManualSocInteractor
import org.julakali.powertrip.shared.domain.usecases.UpdateNetworksInteractor
import org.julakali.powertrip.shared.settings.InMemoryPreferencesDataStore
import org.julakali.powertrip.shared.settings.settingsModule
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import org.koin.core.Koin
import org.koin.core.parameter.parametersOf
import org.koin.dsl.koinApplication
import org.koin.dsl.module
import kotlin.test.Test
import kotlin.test.assertNotSame
import kotlin.test.assertSame

class ChargeStopsModuleTest {

    private val fakeLocationSource = object : LocationSource {
        override suspend fun currentFix(): Fix? = null
        override val updates: Flow<Fix> = emptyFlow()
    }

    private fun <T> withGraph(block: (Koin) -> T): T {
        val app = koinApplication {
            modules(
                settingsModule { InMemoryPreferencesDataStore() },
                module {
                    single<LocationSource> { fakeLocationSource }
                    single<ReverseGeocoder> { ReverseGeocoder { null } }
                    single { DatabaseFactory() }
                    single<TripStorage> { TripStorage.None }
                    single { BackendConfig("https://backend.invalid", "token") }
                },
                chargeStopsModule(),
            )
        }
        return try {
            block(app.koin)
        } finally {
            app.close()
        }
    }

    @Test
    fun theUseCasesResolve() {
        withGraph { koin ->
            koin.get<PlanTripInteractor>()
            koin.get<UpdateArrivalSocInteractor>()
            koin.get<ReplanWithArrivalSocInteractor>()
            koin.get<CommitTripInteractor>()
            koin.get<EndTripInteractor>()
            koin.get<SelectVehicleInteractor>()
            koin.get<RemoveVehicleInteractor>()
            koin.get<UpdateManualSocInteractor>()
            koin.get<UpdateChargeFiltersInteractor>()
            koin.get<UpdateNetworksInteractor>()
            koin.get<ChargeNowObserver>()
            koin.get<ChargeStopsObserver>()
            koin.get<DestinationSearchObserver>()
            koin.get<RefreshNetworksInteractor>()
            koin.get<NetworkRepository>()
            koin.get<RefreshVehicleCatalogInteractor>()
            koin.get<VehicleCatalogRepository>()
            koin.get<VehiclePresetsObserver>()
        }
    }

    @Test
    fun aSessionFeature_isItsOwn_notThePhoneSingleton() {
        withGraph { koin ->
            val phone = koin.get<ChargeStopsFeature>()
            val session = koin.get<ChargeStopsFeature>(SessionFeature) { parametersOf(fakeLocationSource, null) }
            assertNotSame(phone, session)
            assertSame(phone, koin.get<ChargeStopsFeature>())
            session.close()
        }
    }
}
