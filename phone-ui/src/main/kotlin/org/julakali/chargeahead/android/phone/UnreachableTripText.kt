package org.julakali.chargeahead.android.phone

import androidx.compose.runtime.Composable
import org.jetbrains.compose.resources.getString
import org.jetbrains.compose.resources.stringResource
import org.julakali.chargeahead.shared.domain.UnreachableTrip
import org.julakali.chargeahead.shared.messageResource

@Composable
fun UnreachableTrip.message(): String = messageResource().let { (resource, args) -> stringResource(resource, *args) }

suspend fun UnreachableTrip.loadMessage(): String = messageResource().let { (resource, args) -> getString(resource, *args) }
