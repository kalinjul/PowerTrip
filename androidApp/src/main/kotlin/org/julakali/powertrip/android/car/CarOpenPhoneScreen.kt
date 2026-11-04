package org.julakali.powertrip.android.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.Header
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Template
import androidx.lifecycle.lifecycleScope
import org.julakali.powertrip.android.PhoneUiVisibility
import org.julakali.powertrip.android.phone.R
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.julakali.powertrip.shared.resources.Res
import org.julakali.powertrip.shared.resources.car_route_next_stop_only
import org.julakali.powertrip.shared.resources.car_route_open_phone
import org.julakali.powertrip.shared.resources.car_route_send_all
import org.julakali.powertrip.shared.Texts

/**
 * Asks the driver to open the app on the phone for the whole-route hand-off,
 * and goes ahead by itself once it is visible. The next stop alone is offered
 * as the alternative.
 */
class CarOpenPhoneScreen(
    carContext: CarContext,
    private val onPhoneOpened: () -> Unit,
    private val onNextStopOnly: () -> Unit,
) : Screen(carContext) {

    init {
        lifecycleScope.launch {
            PhoneUiVisibility.isVisible.first { it }
            screenManager.pop()
            onPhoneOpened()
        }
    }

    override fun onGetTemplate(): Template =
        MessageTemplate.Builder(Texts.string(Res.string.car_route_open_phone))
            .setHeader(
                Header.Builder()
                    .setTitle(Texts.string(Res.string.car_route_send_all))
                    .setStartHeaderAction(Action.BACK)
                    .build(),
            )
            .setIcon(icon(R.drawable.ic_near_me))
            .addAction(
                Action.Builder()
                    .setTitle(Texts.string(Res.string.car_route_next_stop_only))
                    .setOnClickListener {
                        screenManager.pop()
                        onNextStopOnly()
                    }
                    .build(),
            )
            .build()
}
