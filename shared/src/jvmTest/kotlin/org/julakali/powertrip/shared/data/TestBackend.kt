package org.julakali.powertrip.shared.data

import org.julakali.powertrip.shared.BackendConfig

/** Where the mocked backend "is"; the engine never connects anywhere. */
val TestBackend = BackendConfig("https://example.invalid/", "test-token")
