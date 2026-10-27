package org.julakali.chargeahead.android.phone

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.compose.CameraMoveStartedReason
import com.google.maps.android.compose.CameraPositionState
import com.google.maps.android.compose.GoogleMapComposable
import com.google.maps.android.compose.MarkerComposable
import com.google.maps.android.compose.rememberUpdatedMarkerState
import org.jetbrains.compose.resources.stringResource
import org.julakali.chargeahead.android.phone.components.RankBadge
import org.julakali.chargeahead.shared.domain.ChargeNowCandidate
import org.julakali.chargeahead.shared.domain.LatLon
import org.julakali.chargeahead.shared.resources.Res
import org.julakali.chargeahead.shared.resources.cn_distance_power
import org.julakali.chargeahead.shared.ui.ChargeNowSheetUiState
import kotlin.math.roundToInt

/** The top candidates as numbered discs, the selected one as a callout with its distance and power. */
@Composable
@GoogleMapComposable
fun ChargeNowMarkers(
    chargeNow: ChargeNowSheetUiState.Open,
    onCandidateTapped: (ChargeNowCandidate) -> Unit,
    onCandidateOpened: (ChargeNowCandidate) -> Unit,
) {
    val result = chargeNow.result ?: return
    val selected = chargeNow.selected
    result.candidates.forEachIndexed { index, candidate ->
        if (candidate.site.id == selected?.site?.id) return@forEachIndexed
        key(candidate.site.id) {
            val color = operatorColor(candidate.site)
            MarkerComposable(
                keys = arrayOf<Any>(candidate.site.id, index, color.value),
                state = rememberUpdatedMarkerState(position = candidate.site.position.toLatLng()),
                title = candidate.site.name,
                anchor = Offset(0.5f, 0.5f),
                zIndex = CANDIDATE_Z,
                onClick = { onCandidateTapped(candidate); true },
            ) {
                ChargeBadge(color = color) {
                    Text(text = "${index + 1}", color = Color.White, style = MaterialTheme.typography.labelLarge)
                }
            }
        }
    }
    val rank = chargeNow.selectedRank
    if (selected != null && rank != null) {
        val color = operatorColor(selected.site)
        val title = selected.site.operator ?: selected.site.name
        val meta = stringResource(Res.string.cn_distance_power, selected.distanceKm.oneDecimal(), selected.maxPowerKw.roundToInt())
        val surface = MaterialTheme.colorScheme.surface
        key(selected.site.id) {
            MarkerComposable(
                keys = arrayOf<Any>(selected.site.id, rank, title, meta, color.value, surface.value),
                state = rememberUpdatedMarkerState(position = selected.site.position.toLatLng()),
                title = selected.site.name,
                // The tail's tip sits on the site.
                anchor = Offset(0.5f, 1f),
                zIndex = SELECTED_Z,
                onClick = { onCandidateOpened(selected); true },
            ) {
                ChargeNowCallout(rank = rank, color = color, title = title, meta = meta)
            }
        }
    }
}

@Composable
fun ChargeNowCallout(rank: Int, color: Color, title: String, meta: String, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(14.dp)
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .background(MaterialTheme.colorScheme.surface, shape)
                .border(2.dp, color, shape)
                .padding(start = 7.dp, end = 12.dp, top = 6.dp, bottom = 6.dp),
        ) {
            RankBadge(rank, color)
            Column(Modifier.widthIn(max = 200.dp)) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(meta, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
        }
        Box(Modifier.size(width = 14.dp, height = 8.dp).background(color, CalloutTail))
    }
}

/**
 * Fits the driver and the top candidates between [coveredTop] and [coveredBottom] until the
 * driver moves the map, brings a pick that is out of sight into view, and puts the camera
 * back on close — unless a new [route] took the map over meanwhile, which brings its own fit.
 */
@Composable
fun ChargeNowCamera(
    chargeNow: ChargeNowSheetUiState.Open?,
    position: LatLon?,
    route: RouteOverlay?,
    mapLoaded: Boolean,
    camera: CameraPositionState,
    mapSize: () -> IntSize,
    coveredTop: Dp,
    coveredBottom: Dp,
) {
    val open = chargeNow != null
    var cameraBefore by rememberSaveable { mutableStateOf<CameraPosition?>(null) }
    var routeBefore by remember { mutableStateOf(route) }
    val currentRoute by rememberUpdatedState(route)
    // Once the driver moves the map, the camera is theirs until the sheet closes.
    var driverMoved by remember { mutableStateOf(false) }
    LaunchedEffect(open) {
        if (open) {
            driverMoved = false
            if (cameraBefore == null) {
                cameraBefore = camera.position
                routeBefore = currentRoute
            }
        } else {
            val back = cameraBefore ?: return@LaunchedEffect
            cameraBefore = null
            if (currentRoute == routeBefore) camera.animate(CameraUpdateFactory.newCameraPosition(back))
        }
    }
    LaunchedEffect(camera) {
        snapshotFlow { camera.isMoving && camera.cameraMoveStartedReason == CameraMoveStartedReason.GESTURE }
            .collect { if (it) driverMoved = true }
    }

    val candidates = chargeNow?.result?.candidates.orEmpty()
    LaunchedEffect(mapLoaded, candidates.map { it.site.id }) {
        if (!mapLoaded || candidates.isEmpty() || driverMoved) return@LaunchedEffect
        val bounds = LatLngBounds.builder().apply {
            candidates.forEach { include(it.site.position.toLatLng()) }
            position?.let { include(it.toLatLng()) }
        }.build()
        camera.animate(CameraUpdateFactory.newLatLngBounds(bounds, FIT_PADDING_PX))
    }

    // Only the driver's pick: the nearest one, selected on its own, is part of the fit.
    val picked = chargeNow?.selected?.takeIf { it.site.id == chargeNow.selectedSiteId }?.site?.position
    val density = LocalDensity.current
    LaunchedEffect(mapLoaded, picked) {
        val target = picked?.toLatLng() ?: return@LaunchedEffect
        if (!mapLoaded) return@LaunchedEffect
        val point = camera.projection?.toScreenLocation(target) ?: return@LaunchedEffect
        val size = mapSize()
        // The callout rises above its site, so the site needs room below the top bar.
        val top = with(density) { (coveredTop + CALLOUT_HEIGHT).roundToPx() }
        val bottom = size.height - with(density) { coveredBottom.roundToPx() }
        val inSight = point.x in 0..size.width && point.y in top..bottom
        if (!inSight) camera.animate(CameraUpdateFactory.newLatLng(target))
    }
}

private val CalloutTail = GenericShape { size, _ ->
    moveTo(0f, 0f)
    lineTo(size.width, 0f)
    lineTo(size.width / 2f, size.height)
    close()
}

/** Above the faded pills; the callout above the discs. */
private const val CANDIDATE_Z = 1f
private const val SELECTED_Z = 2f

private val CALLOUT_HEIGHT = 64.dp

/** Room for the discs and the callout at the edges. */
private const val FIT_PADDING_PX = 160
