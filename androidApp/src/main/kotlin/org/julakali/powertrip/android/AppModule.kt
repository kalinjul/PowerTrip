package org.julakali.powertrip.android

import org.julakali.powertrip.shared.AppScope
import org.julakali.powertrip.shared.BackendConfig
import org.julakali.powertrip.shared.data.AndroidReverseGeocoder
import org.julakali.powertrip.shared.data.DataStoreTripStorage
import org.julakali.powertrip.shared.data.FusedLocationSource
import org.julakali.powertrip.shared.db.DatabaseFactory
import org.julakali.powertrip.shared.domain.AppCoroutineDispatchers
import org.julakali.powertrip.shared.domain.LocationSource
import org.julakali.powertrip.shared.domain.ReverseGeocoder
import org.julakali.powertrip.shared.domain.TripStorage
import org.julakali.powertrip.shared.settings.createSettingsDataStore
import org.julakali.powertrip.shared.settings.createTripDataStore
import org.julakali.powertrip.shared.settings.settingsModule
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.plus
import org.koin.android.ext.koin.androidContext
import org.koin.core.scope.Scope
import org.koin.dsl.module

/** What only Android can supply to `chargeStopsModule`. */
val appModule = module {
    includes(settingsModule { createSettingsDataStore(androidContext(), dataStoreScope()) })
    single<TripStorage> { DataStoreTripStorage(createTripDataStore(androidContext(), dataStoreScope()), legacy = get()) }

    // The phone's location; a car session passes its own.
    single<LocationSource> { FusedLocationSource(androidContext()) }
    single<ReverseGeocoder> { AndroidReverseGeocoder(androidContext(), get<AppCoroutineDispatchers>().io) }
    single { DatabaseFactory(androidContext()) }

    single {
        requireNotNull(BackendConfig.of(BuildConfig.CHARGEAHEAD_BASE_URL, BuildConfig.CHARGEAHEAD_TOKEN)) {
            "chargeAheadBaseUrl and chargeAheadToken must be set in local.properties"
        }
    }
}

private fun Scope.dataStoreScope(): CoroutineScope = get<CoroutineScope>(AppScope) + get<AppCoroutineDispatchers>().io
