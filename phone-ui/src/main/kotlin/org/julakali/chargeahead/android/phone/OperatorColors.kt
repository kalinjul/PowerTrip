package org.julakali.chargeahead.android.phone

import androidx.compose.ui.graphics.Color
import org.julakali.chargeahead.shared.domain.ChargeSite
import org.julakali.chargeahead.shared.domain.OperatorColors

fun networkColor(key: String): Color = Color(OperatorColors.network(key))

fun operatorColor(site: ChargeSite): Color = Color(OperatorColors.of(site))
