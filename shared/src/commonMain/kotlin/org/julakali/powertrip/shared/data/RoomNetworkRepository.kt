package org.julakali.powertrip.shared.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import org.julakali.powertrip.shared.db.ChargeSiteDatabase
import org.julakali.powertrip.shared.db.NetworkEntity
import org.julakali.powertrip.shared.domain.Network
import org.julakali.powertrip.shared.domain.NetworkListSource
import org.julakali.powertrip.shared.domain.NetworkRepository

class RoomNetworkRepository(
    private val source: NetworkListSource,
    database: ChargeSiteDatabase,
) : NetworkRepository {

    private val dao = database.networks()

    override val networks: Flow<List<Network>> = dao.observeAll().map { entities ->
        entities.map { Network(key = it.key, name = it.name, rank = it.rank) }
    }

    override suspend fun refresh() {
        val listed = source.networks()
        // An empty list means the backend has no site data yet, not that no network exists.
        if (listed.isEmpty()) return
        dao.replaceListed(listed.mapIndexed { index, network -> NetworkEntity(network.key, network.name, index) })
    }
}
