package org.julakali.chargeahead.android.phone

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.material3.rememberStandardBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.findRootCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.filter
import org.jetbrains.compose.resources.stringResource
import org.julakali.chargeahead.android.phone.components.AppCard
import org.julakali.chargeahead.android.phone.components.SectionLabel
import org.julakali.chargeahead.android.phone.components.SheetHandle
import org.julakali.chargeahead.android.phone.components.SkeletonBar
import org.julakali.chargeahead.android.phone.components.StationCard
import org.julakali.chargeahead.android.phone.components.rememberShimmerBrush
import org.julakali.chargeahead.android.phone.components.sheetListPadding
import org.julakali.chargeahead.shared.ChargeStopFormatter
import org.julakali.chargeahead.shared.domain.ChargeNowCandidate
import org.julakali.chargeahead.shared.domain.ChargeNowResult
import org.julakali.chargeahead.shared.resources.Res
import org.julakali.chargeahead.shared.resources.cn_close
import org.julakali.chargeahead.shared.resources.cn_distance_power
import org.julakali.chargeahead.shared.resources.cn_empty
import org.julakali.chargeahead.shared.resources.cn_more
import org.julakali.chargeahead.shared.resources.cn_navigate
import org.julakali.chargeahead.shared.resources.cn_relaxed
import org.julakali.chargeahead.shared.resources.cn_subtitle
import org.julakali.chargeahead.shared.resources.cn_title
import org.julakali.chargeahead.shared.resources.home_no_position
import org.julakali.chargeahead.shared.ui.ChargeNowSheetUiState
import org.julakali.chargeahead.shared.ui.ChargeNowUiState
import kotlin.math.roundToInt

/** How far the sheet rises when it opens; the map fits the candidates above it. */
@Composable
fun chargeNowPeekHeight(): Dp = (LocalConfiguration.current.screenHeightDp / 2).dp

/**
 * [content] — the map — under the "charge now" sheet. The sheet is not modal: the map
 * above it stays live, so its markers can be tapped while the list is open.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChargeNowSheetScaffold(
    uiState: ChargeNowSheetUiState,
    onClose: () -> Unit,
    onNavigate: (ChargeNowCandidate) -> Unit,
    onOpen: (ChargeNowCandidate) -> Unit,
    /** The search covers the screen: the open sheet steps aside until it closes. */
    suspended: Boolean,
    content: @Composable () -> Unit,
) {
    val sheetState = rememberStandardBottomSheetState(initialValue = SheetValue.Hidden, skipHiddenState = false)
    val open = uiState as? ChargeNowSheetUiState.Open
    // Kept while the sheet slides out, so it doesn't empty on its way down.
    var lastOpen by remember { mutableStateOf(open) }
    LaunchedEffect(open) { if (open != null) lastOpen = open }

    val shown = open != null && !suspended
    LaunchedEffect(open != null, shown) {
        when {
            shown -> sheetState.partialExpand()
            open != null -> sheetState.hide()
            else -> {
                sheetState.hide()
                lastOpen = null
            }
        }
    }
    // Swiped away.
    val currentOnClose by rememberUpdatedState(onClose)
    val isShown by rememberUpdatedState(shown)
    LaunchedEffect(sheetState) {
        snapshotFlow { sheetState.currentValue }
            .filter { it == SheetValue.Hidden }
            .collect { if (isShown) currentOnClose() }
    }

    BottomSheetScaffold(
        scaffoldState = rememberBottomSheetScaffoldState(bottomSheetState = sheetState),
        sheetPeekHeight = chargeNowPeekHeight(),
        sheetShape = RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp),
        sheetContainerColor = MaterialTheme.colorScheme.background,
        sheetDragHandle = { SheetHandle() },
        sheetContent = {
            val state = open ?: lastOpen ?: return@BottomSheetScaffold
            ChargeNowSheetContent(
                uiState = state.content,
                selectedSiteId = state.selected?.site?.id,
                onNavigate = onNavigate,
                onOpen = onOpen,
                onClose = onClose,
                modifier = Modifier.fillMaxHeight(SHEET_HEIGHT_FRACTION).padding(horizontal = 18.dp),
            )
        },
    ) { _ ->
        content()
    }
}

/** The best chargers nearby. States: no position, loading, empty, list — plus the relax notice. */
@Composable
fun ChargeNowSheetContent(
    uiState: ChargeNowUiState,
    /** The candidate the map shows as its callout; its card is highlighted. */
    selectedSiteId: String?,
    onNavigate: (ChargeNowCandidate) -> Unit,
    onOpen: (ChargeNowCandidate) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(Res.string.cn_title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            IconButton(onClick = onClose) {
                Icon(Icons.Outlined.Close, contentDescription = stringResource(Res.string.cn_close))
            }
        }

        when (uiState) {
            ChargeNowUiState.NoPosition -> Text(
                stringResource(Res.string.home_no_position),
                modifier = Modifier.navigationBarsPadding().padding(bottom = 24.dp),
            )

            ChargeNowUiState.Loading -> {
                val shimmer = rememberShimmerBrush()
                SkeletonBar(shimmer, Modifier.fillMaxWidth(0.5f).height(12.dp))
                Column(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .navigationBarsPadding()
                        .padding(bottom = 24.dp)
                        .verticalScroll(rememberScrollState()),
                ) {
                    repeat(3) { ChargeNowSkeletonCard(shimmer) }
                }
            }

            is ChargeNowUiState.Ready -> {
                val result = uiState.result
                if (result.candidates.isEmpty()) {
                    Text(
                        stringResource(Res.string.cn_empty),
                        modifier = Modifier.navigationBarsPadding().padding(bottom = 24.dp),
                    )
                    return@Column
                }
                // Relaxed filters are context, not an error: same line, same tone.
                Text(
                    stringResource(if (result.relaxed.isEmpty()) Res.string.cn_subtitle else Res.string.cn_relaxed),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                val listState = rememberLazyListState()
                val onScreen = remember { ListOnScreen() }
                val navigationBar = WindowInsets.navigationBars.getBottom(LocalDensity.current)
                ScrollToSelected(listState, onScreen, result, selectedSiteId)
                LazyColumn(
                    state = listState,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = sheetListPadding(),
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .onGloballyPositioned { onScreen.update(it, navigationBar) },
                ) {
                    itemsIndexed(result.candidates, key = { _, c -> c.site.id }) { index, candidate ->
                        ChargeNowCard(index + 1, candidate, candidate.site.id == selectedSiteId, onNavigate, onOpen)
                    }
                    if (result.more.isNotEmpty()) {
                        item { SectionLabel(stringResource(Res.string.cn_more), modifier = Modifier.padding(top = 8.dp)) }
                        itemsIndexed(result.more, key = { _, c -> "more-${c.site.id}" }) { index, candidate ->
                            ChargeNowCard(
                                rank = result.candidates.size + index + 1,
                                candidate = candidate,
                                selected = candidate.site.id == selectedSiteId,
                                onNavigate = onNavigate,
                                onOpen = onOpen,
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Where the list sits on screen: the half-open sheet shows only its upper part. */
private class ListOnScreen {
    var top = 0f
        private set
    var bottom = Float.MAX_VALUE
        private set

    fun update(coordinates: LayoutCoordinates, navigationBar: Int) {
        top = coordinates.positionInRoot().y
        bottom = coordinates.findRootCoordinates().size.height.toFloat() - navigationBar
    }
}

/** A marker tapped on the map selects a card that may be scrolled away or below the screen edge. */
@Composable
private fun ScrollToSelected(listState: LazyListState, onScreen: ListOnScreen, result: ChargeNowResult, selectedSiteId: String?) {
    LaunchedEffect(selectedSiteId) {
        val rank = selectedSiteId?.let(result::rankOf) ?: return@LaunchedEffect
        // The "more" label sits between the two lists.
        val index = if (rank <= result.candidates.size) rank - 1 else rank
        val item = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.index == index }
        val inSight = item != null && item.offset >= 0 && onScreen.top + item.offset + item.size <= onScreen.bottom
        if (!inSight) listState.animateScrollToItem(index)
    }
}

@Composable
private fun ChargeNowCard(
    rank: Int,
    candidate: ChargeNowCandidate,
    selected: Boolean,
    onNavigate: (ChargeNowCandidate) -> Unit,
    onOpen: (ChargeNowCandidate) -> Unit,
) {
    StationCard(
        rank = rank,
        badgeColor = operatorColor(candidate.site),
        title = candidate.site.operator ?: candidate.site.name,
        metaLine = stringResource(Res.string.cn_distance_power, candidate.distanceKm.oneDecimal(), candidate.maxPowerKw.roundToInt()),
        address = ChargeStopFormatter.addressLine(candidate.site),
        onSend = { onNavigate(candidate) },
        sendContentDescription = stringResource(Res.string.cn_navigate, candidate.site.name),
        selected = selected,
        onClick = { onOpen(candidate) },
    )
}

/** A placeholder card mirroring [StationCard]'s shape while the ranking runs. */
@Composable
private fun ChargeNowSkeletonCard(shimmer: Brush) {
    AppCard {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(11.dp),
            modifier = Modifier.padding(horizontal = 13.dp, vertical = 12.dp),
        ) {
            SkeletonBar(shimmer, Modifier.size(24.dp), shape = CircleShape)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SkeletonBar(shimmer, Modifier.fillMaxWidth(0.55f).height(15.dp))
                SkeletonBar(shimmer, Modifier.fillMaxWidth(0.35f).height(12.dp))
                SkeletonBar(shimmer, Modifier.fillMaxWidth(0.7f).height(12.dp))
            }
        }
    }
}

private const val SHEET_HEIGHT_FRACTION = 0.9f
