package org.julakali.powertrip.shared.ui.car

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import org.julakali.powertrip.shared.domain.Destination
import org.julakali.powertrip.shared.domain.Place
import org.julakali.powertrip.shared.domain.DestinationHistory
import org.julakali.powertrip.shared.domain.usecases.DestinationSearchObserver
import org.julakali.powertrip.shared.ui.WhileUiSubscribed
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

data class CarDestinationSearchUiState(
    val query: String = "",
    val searching: Boolean = false,
    /** Offered while nothing is typed. */
    val recents: List<Destination> = emptyList(),
    val places: List<Place> = emptyList(),
    /** No search has finished for the typed text yet, so an empty list means "not searched yet". */
    val typing: Boolean = false,
)

/**
 * Typing or dictating a destination in the car. The text is searched after a pause, since the host may submit
 * dictation before it is complete and send the final text only as a change.
 */
class CarDestinationSearchViewModel(
    history: DestinationHistory,
    private val observeDestinationSearch: DestinationSearchObserver,
) : ViewModel() {

    private val query = MutableStateFlow("")

    val uiState: StateFlow<CarDestinationSearchUiState> = combine(
        query,
        history.recentDestinations,
        observeDestinationSearch.flow,
    ) { query, recents, search ->
        val blank = query.isBlank()
        val trimmed = query.trim()
        CarDestinationSearchUiState(
            query = query,
            searching = search.searching,
            recents = if (blank) recents else emptyList(),
            places = if (blank) emptyList() else search.results.orEmpty(),
            typing = !blank && (search.query != trimmed || trimmed.length < DestinationSearchObserver.MIN_QUERY_LENGTH),
        )
    }.stateIn(viewModelScope, WhileUiSubscribed, CarDestinationSearchUiState())

    init {
        observeDestinationSearch(DestinationSearchObserver.Params(query = ""))
    }

    private var justSubmitted = false

    fun onSearchTextChanged(text: String) {
        // After a dictated submit the host may empty its search box; that is not the driver clearing it.
        val hostClearedAfterSubmit = justSubmitted && text.isBlank()
        justSubmitted = false
        if (hostClearedAfterSubmit) return
        query.value = text
        observeDestinationSearch(DestinationSearchObserver.Params(text))
    }

    fun onSearchSubmitted(text: String) {
        justSubmitted = true
        query.value = text
        observeDestinationSearch(DestinationSearchObserver.Params(text, debounce = false))
    }
}
