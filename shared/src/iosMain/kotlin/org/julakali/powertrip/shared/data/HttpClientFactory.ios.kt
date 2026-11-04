package org.julakali.powertrip.shared.data

import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.engine.darwin.Darwin

internal actual fun defaultHttpEngine(): HttpClientEngine = Darwin.create()
