package org.julakali.powertrip.shared.data

import org.julakali.powertrip.shared.domain.EnergyState
import org.julakali.powertrip.shared.domain.VehicleRepository
import org.julakali.powertrip.shared.domain.SoCSource
import org.julakali.powertrip.shared.domain.SoCSourceKind
import org.julakali.powertrip.shared.domain.TimeProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * The typed-in charge level.
 *
 * The timestamp is the one at read time, not at entry time.
 */
class ManualSoCSource(
    vehicles: VehicleRepository,
    private val time: TimeProvider,
) : SoCSource {

    override val kind: SoCSourceKind = SoCSourceKind.MANUAL

    override val energy: Flow<EnergyState?> =
        vehicles.manualSocPercent.map { socPercent ->
            socPercent?.let { EnergyState(it, SoCSourceKind.MANUAL, time.nowMillis()) }
        }
}
