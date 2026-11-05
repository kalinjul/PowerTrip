package org.julakali.powertrip.shared.ui

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import org.julakali.powertrip.shared.ChargeStopFormatter
import org.julakali.powertrip.shared.ChargeStopsFeature
import org.julakali.powertrip.shared.domain.Destination
import org.julakali.powertrip.shared.domain.LatLon
import org.julakali.powertrip.shared.domain.usecases.DestinationSearchObserver
import org.julakali.powertrip.shared.domain.Place
import org.julakali.powertrip.shared.domain.VehicleRepository
import org.julakali.powertrip.shared.domain.DestinationHistory
import org.julakali.powertrip.shared.domain.distanceKmTo
import org.julakali.powertrip.shared.toDestination
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import org.julakali.powertrip.shared.combine
import org.julakali.powertrip.shared.domain.TripRepository
import kotlinx.coroutines.flow.stateIn
import kotlin.math.roundToInt
import org.julakali.powertrip.shared.formatDecimal

/** One line of the results panel: a recent destination or a geocoder hit. */
data class SearchRow(
    val destination: Destination,
    val title: String,
    val detail: String?,
    /** Straight-line from the current fix; `null` without one. */
    val distanceKm: Double?,
    val recent: Boolean,
)

/** What a picked row becomes. */
enum class SearchTarget { DESTINATION, START }

data class SearchUiState(
    /** The bar has focus and the results panel is open. */
    val expanded: Boolean = false,
    val target: SearchTarget = SearchTarget.DESTINATION,
    /** The trip starts where the driver is, not at a picked place. */
    val startIsCurrentPosition: Boolean = true,
    /** The current position's address, when the trip starts there and one was found. */
    val currentPositionAddress: String? = null,
    val query: String = "",
    val rows: List<SearchRow> = emptyList(),
    val searching: Boolean = false,
    /** The geocoder itself failed. */
    val failed: Boolean = false,
    val hasVehicle: Boolean = false,
    /** Raw hits, for the iOS search sheet. */
    val results: List<Place>? = emptyList(),
) {
    val isQueryTooShort: Boolean get() = query.trim().length < MIN_QUERY_LENGTH

    companion object {
        const val MIN_QUERY_LENGTH = DestinationSearchObserver.MIN_QUERY_LENGTH
    }
}

/** Recents while the query is too short to search on, hits once it is. */
fun searchRows(query: String, results: List<Place>?, recent: List<Destination>, from: LatLon?): List<SearchRow> =
    if (query.trim().length < SearchUiState.MIN_QUERY_LENGTH) {
        recent.map { SearchRow(it, it.name, it.address, from?.distanceKmTo(it.position), recent = true) }
    } else {
        results.orEmpty().map { place ->
            val destination = place.toDestination()
            SearchRow(destination, place.name, destination.address, from?.distanceKmTo(place.position), recent = false)
        }
    }

/** "< 1", "4,2" / "4.2", "42" — the unit is the caller's resource string. */
fun Double.asKmLabel(): String = when {
    this < 1 -> "< 1"
    this < 10 -> formatDecimal((this * 10).roundToInt() / 10.0, 1)
    else -> roundToInt().toString()
}

class SearchViewModel(
    private val feature: ChargeStopsFeature,
    private val observeDestinationSearch: DestinationSearchObserver,
    vehicles: VehicleRepository,
    history: DestinationHistory,
    trips: TripRepository,
    private val savedState: SavedStateHandle,
) : ViewModel() {

    private val input = MutableStateFlow(Input())
    private val expanded = MutableStateFlow(savedState.get<Boolean>(KEY_EXPANDED) ?: false)
    private val target = MutableStateFlow(savedState.get<String>(KEY_TARGET)?.let(SearchTarget::valueOf) ?: SearchTarget.DESTINATION)

    val uiState: StateFlow<SearchUiState> = combine(
        combine(expanded, input, ::Pair),
        target,
        observeDestinationSearch.flow,
        history.recentDestinations,
        vehicles.vehicle,
        feature.currentFix,
        trips.state,
    ) { (open, entry), searchTarget, search, recent, vehicle, fix, trip ->
        val (query, pick) = entry
        SearchUiState(
            expanded = open,
            target = searchTarget,
            startIsCurrentPosition = trip.start == null,
            currentPositionAddress = trip.planned?.startAddress?.takeIf { trip.start == null },
            query = query,
            rows = pick?.let { listOf(SearchRow(it, it.name, it.address, fix?.position?.distanceKmTo(it.position), recent = false)) }
                ?: searchRows(query, search.results, recent, fix?.position),
            searching = search.searching,
            failed = search.results == null,
            hasVehicle = vehicle != null,
            results = search.results,
        )
    }.stateIn(viewModelScope, WhileUiSubscribed, SearchUiState())

    init {
        search("")
    }

    /**
     * The bar took focus. A [prefill] (the current destination when re-planning)
     * sits in the field as a pick, not as a query: typing over it starts searching.
     */
    fun onOpened(prefill: Destination? = null) {
        // The field reports focus again while already open; that must not wipe the query.
        if (expanded.value && prefill == null) return
        setTarget(SearchTarget.DESTINATION)
        setExpanded(true)
        input.value = Input(query = prefill?.let(ChargeStopFormatter::label) ?: "", pick = prefill)
        search("")
    }

    /** The trip sheet asked for a different start; a pick from here re-plans from that place. */
    fun onStartSearchOpened() {
        setTarget(SearchTarget.START)
        setExpanded(true)
        input.value = Input()
        search("")
    }

    fun onQueryChanged(query: String) {
        input.value = Input(query)
        search(query)
    }

    fun onClosed() {
        setExpanded(false)
        setTarget(SearchTarget.DESTINATION)
        onQueryChanged("")
    }

    private fun setExpanded(value: Boolean) {
        expanded.value = value
        savedState[KEY_EXPANDED] = value
    }

    private fun setTarget(value: SearchTarget) {
        target.value = value
        savedState[KEY_TARGET] = value.name
    }

    private fun search(query: String) {
        observeDestinationSearch(DestinationSearchObserver.Params(query.trim()))
    }

    private data class Input(val query: String = "", val pick: Destination? = null)
}

private const val KEY_EXPANDED = "expanded"
private const val KEY_TARGET = "target"
