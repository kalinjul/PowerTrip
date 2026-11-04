package org.julakali.powertrip.shared.domain.usecases

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOn
import org.julakali.powertrip.shared.domain.AppCoroutineDispatchers
import org.julakali.powertrip.shared.domain.SubjectInteractor
import org.julakali.powertrip.shared.domain.VehicleCatalogRepository
import org.julakali.powertrip.shared.domain.VehiclePreset
import org.julakali.powertrip.shared.domain.VehicleRepository
import org.julakali.powertrip.shared.domain.presetOf

/** The catalog cars one can still add: not in the garage yet, matching the query. */
class VehiclePresetsObserver(
    private val catalog: VehicleCatalogRepository,
    private val vehicles: VehicleRepository,
    private val dispatchers: AppCoroutineDispatchers,
) : SubjectInteractor<VehiclePresetsObserver.Params, List<VehiclePreset>>() {

    data class Params(val query: String)

    override fun createObservable(params: Params): Flow<List<VehiclePreset>> {
        val needle = params.query.trim()
        return combine(catalog.presets, vehicles.vehicles) { presets, owned ->
            val ownedIds = owned.mapNotNullTo(HashSet()) { presets.presetOf(it)?.id }
            presets.filter { it.id !in ownedIds && it.name.contains(needle, ignoreCase = true) }
        }.flowOn(dispatchers.computation)
    }
}
