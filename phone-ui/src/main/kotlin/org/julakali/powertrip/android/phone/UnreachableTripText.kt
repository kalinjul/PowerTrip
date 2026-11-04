package org.julakali.powertrip.android.phone

import androidx.compose.runtime.Composable
import org.jetbrains.compose.resources.getString
import org.jetbrains.compose.resources.stringResource
import org.julakali.powertrip.shared.domain.UnreachableTrip
import org.julakali.powertrip.shared.messageResource

@Composable
fun UnreachableTrip.message(): String = messageResource().let { (resource, args) -> stringResource(resource, *args) }

suspend fun UnreachableTrip.loadMessage(): String = messageResource().let { (resource, args) -> getString(resource, *args) }
