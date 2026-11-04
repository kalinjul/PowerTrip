package org.julakali.powertrip.shared.domain

import kotlin.test.Test
import kotlin.test.assertEquals

class OperatorColorsTest {

    private fun site(operator: String?, networkKey: String? = null) = ChargeSite(
        id = "test:1",
        name = "Somewhere",
        operator = operator,
        position = LatLon(53.55, 9.99),
        connectors = emptyList(),
        networkKey = networkKey,
    )

    @Test
    fun aKnownNetworkWearsItsBrandColour() {
        assertEquals(0xFF00C389, OperatorColors.of(site(operator = "whatever", networkKey = "ionity")))
        assertEquals(0xFF1E3A5F, OperatorColors.network("enbw"))
    }

    @Test
    fun aSiteWithoutOperatorIsGrey() {
        assertEquals(0xFF5F6368, OperatorColors.of(site(operator = null)))
    }

    // Pinned values: Android and iOS hash the same names to the same palette entry.
    @Test
    fun anUnknownNetworkGetsTheSamePaletteColourOnEveryPlatform() {
        assertEquals(0xFF7CB342, OperatorColors.network("stadtwerke-musterstadt"))
        assertEquals(0xFF1A73E8, OperatorColors.of(site(operator = "Stadtwerke Musterstadt")))
    }
}
