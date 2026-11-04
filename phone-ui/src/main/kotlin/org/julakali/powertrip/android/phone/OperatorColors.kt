package org.julakali.powertrip.android.phone

import androidx.compose.ui.graphics.Color
import org.julakali.powertrip.shared.domain.ChargeSite
import org.julakali.powertrip.shared.domain.OperatorColors

fun networkColor(key: String): Color = Color(OperatorColors.network(key))

fun operatorColor(site: ChargeSite): Color = Color(OperatorColors.of(site))
