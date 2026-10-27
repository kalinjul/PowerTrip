package org.julakali.chargeahead.shared.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import org.julakali.chargeahead.shared.ChargeStopsFeature
import org.julakali.chargeahead.shared.domain.ChargeNowCandidate
import org.julakali.chargeahead.shared.domain.ChargeNowResult
import org.julakali.chargeahead.shared.domain.usecases.ChargeNowObserver
import org.julakali.chargeahead.shared.domain.usecases.RefreshChargeNowInteractor
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** The best chargers around the current position, ranked. */
sealed interface ChargeNowUiState {

    /** No location yet. */
    data object NoPosition : ChargeNowUiState

    data object Loading : ChargeNowUiState

    data class Ready(val result: ChargeNowResult) : ChargeNowUiState
}

/** The phone's "Charge now" sheet, whose candidates the map shows while it is open. */
sealed interface ChargeNowSheetUiState {

    data object Closed : ChargeNowSheetUiState

    data class Open(
        val content: ChargeNowUiState,
        /** The driver's pick; `null` until there is one. */
        val selectedSiteId: String? = null,
    ) : ChargeNowSheetUiState {

        val result: ChargeNowResult? = (content as? ChargeNowUiState.Ready)?.result

        /** The place of [selected] in the list: the driver's pick, else the nearest. */
        val selectedRank: Int? = result?.let { result ->
            selectedSiteId?.let(result::rankOf) ?: 1.takeUnless { result.isEmpty }
        }

        /** The candidate the list and the map highlight. */
        val selected: ChargeNowCandidate? = selectedRank?.let { result?.atRank(it) }
    }
}

/** "Charge now": ranks what is nearby against the driver's filters, from where the sheet was opened. */
@OptIn(ExperimentalCoroutinesApi::class)
class ChargeNowViewModel(
    private val feature: ChargeStopsFeature,
    private val observeChargeNow: ChargeNowObserver,
    private val refreshChargeNow: RefreshChargeNowInteractor,
) : ViewModel() {

    private val open = MutableStateFlow(false)
    private val selectedSiteId = MutableStateFlow<String?>(null)
    private var refreshJob: Job? = null

    // Subscribed only while open, so a reopened sheet never shows the last opening's result.
    val uiState: StateFlow<ChargeNowSheetUiState> = open.flatMapLatest { open ->
        if (open) combine(content(), selectedSiteId, ChargeNowSheetUiState::Open) else flowOf(ChargeNowSheetUiState.Closed)
    }.stateIn(viewModelScope, WhileUiSubscribed, ChargeNowSheetUiState.Closed)

    private fun content(): Flow<ChargeNowUiState> = combine(
        observeChargeNow.flow,
        refreshChargeNow.inProgress,
    ) { result, refreshing ->
        when {
            result == null -> ChargeNowUiState.NoPosition
            // Nothing stored yet: wait for the refill rather than say "nothing nearby".
            result.isEmpty && refreshing -> ChargeNowUiState.Loading
            else -> ChargeNowUiState.Ready(result)
        }
    }.onStart { emit(ChargeNowUiState.Loading) }

    /** The sheet was opened: rank from the current position. */
    fun onSheetOpened() {
        val position = feature.currentFix.value?.position
        selectedSiteId.value = null
        observeChargeNow(ChargeNowObserver.Params(position))
        refreshJob?.cancel()
        // A failed refill leaves the stored sites to rank.
        refreshJob = position?.let {
            viewModelScope.launch { refreshChargeNow(RefreshChargeNowInteractor.Params(it)) }
        }
        open.value = true
    }

    fun onSheetClosed() {
        open.value = false
        refreshJob?.cancel()
    }

    /** A card or a map marker was tapped. */
    fun onCandidateSelected(siteId: String) {
        selectedSiteId.value = siteId
    }
}
