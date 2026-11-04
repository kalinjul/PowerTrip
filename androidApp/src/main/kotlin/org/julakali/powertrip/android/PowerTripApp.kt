package org.julakali.powertrip.android

import android.app.Application
import org.julakali.powertrip.shared.chargeStopsModule
import org.julakali.powertrip.shared.ui.sharedUiModule
import org.koin.android.ext.koin.androidContext
import org.koin.core.context.startKoin
import org.julakali.powertrip.shared.ui.car.carUiModule
import org.julakali.powertrip.shared.domain.usecases.StartAppInteractor
import org.julakali.powertrip.shared.domain.invoke
import org.julakali.powertrip.shared.AppScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.CoroutineScope

class PowerTripApp : Application() {
    override fun onCreate() {
        super.onCreate()
        PhoneUiVisibility.register(this)
        val koin = startKoin {
            androidContext(this@PowerTripApp)
            modules(appModule, chargeStopsModule(), sharedUiModule(), carUiModule())
        }.koin
        koin.get<CoroutineScope>(AppScope).launch { koin.get<StartAppInteractor>()() }
    }
}
