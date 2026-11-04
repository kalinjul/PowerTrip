package org.julakali.powertrip.shared.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import org.julakali.powertrip.shared.domain.CarDataPoint
import org.julakali.powertrip.shared.domain.CarDiagnosticsRepository
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

data class CarDataUiState(
    val points: List<CarDataPoint> = emptyList(),
)

/** The read-only car-data debug view. */
class CarDataViewModel(
    diagnostics: CarDiagnosticsRepository,
) : ViewModel() {

    val uiState: StateFlow<CarDataUiState> = diagnostics.carDebugData
        .map { CarDataUiState(points = it) }
        .stateIn(viewModelScope, WhileUiSubscribed, CarDataUiState())
}
