package org.julakali.powertrip.shared.domain.usecases

import org.julakali.powertrip.shared.domain.DataSource
import org.julakali.powertrip.shared.domain.DataSourceDirectory
import org.julakali.powertrip.shared.domain.Interactor

/** The sources for the licence page. */
class LoadDataSourcesInteractor(
    private val directory: DataSourceDirectory,
) : Interactor<Unit, List<DataSource>>() {

    override suspend fun doWork(params: Unit): List<DataSource> = directory.dataSources()
}
