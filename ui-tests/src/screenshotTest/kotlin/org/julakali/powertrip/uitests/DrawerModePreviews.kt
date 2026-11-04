package org.julakali.powertrip.uitests

import android.content.res.Configuration
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.android.tools.screenshot.PreviewTest
import org.julakali.powertrip.android.phone.DrawerContent
import org.julakali.powertrip.shared.ui.SearchUiState
import org.julakali.powertrip.shared.ui.HomeUiState
import org.julakali.powertrip.android.phone.HomeScreen
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
import org.julakali.powertrip.shared.domain.ChargeMode
import org.julakali.powertrip.shared.ui.DrawerUiState

@Composable
private fun Drawer(mode: ChargeMode) {
    PreviewScaffold {
        Box(Modifier.padding(vertical = 8.dp)) {
            DrawerContent(
                uiState = DrawerUiState(vehicleName = "VW ID.3", preferredNetworkCount = 3, mode = mode),
                onOpen = {},
                onFilters = {},
                onModeSelected = {},
            )
        }
    }
}

@PreviewTest
@Preview(locale = "de", showBackground = true, widthDp = 360, heightDp = 620)
@Composable
fun DrawerModesOff() = Drawer(ChargeMode.NORMAL)

@PreviewTest
@Preview(locale = "de", showBackground = true, widthDp = 360, heightDp = 620)
@Composable
fun DrawerModeAcOn() = Drawer(ChargeMode.AC)

@PreviewTest
@Preview(locale = "de", showBackground = true, widthDp = 360, heightDp = 620)
@Composable
fun DrawerModeBrowseOn() = Drawer(ChargeMode.BROWSE)

@PreviewTest
@Preview(
    locale = "de",
    showBackground = true,
    backgroundColor = 0xFF121212,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
    widthDp = 360,
    heightDp = 620,
)
@Composable
fun DrawerModeAcOnDark() = Drawer(ChargeMode.AC)

/** The map side of the same feature: the glow bleeding in from the edges and the flag on the right. */
@Composable
private fun Map(mode: ChargeMode) {
    PreviewScaffold {
        Box(Modifier.width(320.dp).height(560.dp)) {
            HomeScreen(
                uiState = HomeUiState(mode = mode),
                search = SearchUiState(),
                trip = null,
                destination = null,
                hasPermission = true,
                planningInProgress = false,
                mapBottomInset = 0.dp,
                onViewportChanged = {},
                onChargerTapped = {},
                onRequestPermission = {},
                onLocate = {},
                onSettings = {},
                onChargeNow = {},
                activeRouteEnabled = false,
                onActiveRoute = {},
                onModeDismiss = {},
                onStopTapped = {},
                onSearchExpandedChange = {},
                onQueryChange = {},
                onPick = {},
                onClearTrip = {},
            )
        }
    }
}

@PreviewTest
@Preview(locale = "de", showBackground = true)
@Composable
fun MapAcMode() = Map(ChargeMode.AC)

@PreviewTest
@Preview(
    locale = "de",
    showBackground = true,
    backgroundColor = 0xFF121212,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
)
@Composable
fun MapBrowseModeDark() = Map(ChargeMode.BROWSE)
