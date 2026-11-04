package org.julakali.powertrip.shared.domain

/** Brand colours for the networks we recognise, as ARGB. One table for filter, lists and markers on both platforms. */
object OperatorColors {

    private val BRAND: Map<String, Long> = mapOf(
        "ionity" to 0xFF00C389,
        "tesla" to 0xFFE82127,
        "enbw" to 0xFF1E3A5F,
        "shell-recharge" to 0xFFFBCE07,
        "allego" to 0xFFE3000F,
        "fastned" to 0xFFFFE500,
        "aral-pulse" to 0xFF0060AE,
        "bp-pulse" to 0xFF009E49,
        "eon-drive" to 0xFFE3001B,
        "totalenergies" to 0xFFED1C24,
        "enel-x" to 0xFF26CAD3,
        "mer" to 0xFF00A499,
        "ewe-go" to 0xFF009EE0,
        "pfalzwerke" to 0xFFF39200,
    )

    private val PALETTE: List<Long> = listOf(
        0xFF1A73E8, 0xFF188038, 0xFFF9AB00,
        0xFFD93025, 0xFF9334E6, 0xFF12A4AF,
        0xFFE8710A, 0xFF7CB342, 0xFF00897B,
        0xFF8E24AA, 0xFF3949AB, 0xFFC0CA33,
    )

    private const val UNKNOWN: Long = 0xFF5F6368

    /** The network's brand colour, or a stable one from the palette. */
    fun network(key: String): Long = BRAND[key] ?: paletteFor(key)

    /** A site wears its network's colour; a site of no known network gets a stable colour from its operator name. */
    fun of(site: ChargeSite): Long {
        val key = site.networkKey ?: NetworkCatalog.resolve(site)
        if (key != null) return network(key)
        val operator = OperatorKey.of(site.operator) ?: return UNKNOWN
        return paletteFor(operator)
    }

    private fun paletteFor(name: String): Long = PALETTE[(name.hashCode() and Int.MAX_VALUE) % PALETTE.size]
}
