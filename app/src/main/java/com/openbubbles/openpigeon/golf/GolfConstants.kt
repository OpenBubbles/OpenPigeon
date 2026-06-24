package com.openbubbles.openpigeon.golf

/**
 * Mini Golf constants verified against the iOS GamePigeon Mini Golf runtime.
 *
 * iOS naming note:
 *   map_size  = xCells * 65
 *   map_size2 = yCells * 65
 */
object GolfConstants {
    const val TILE_SIZE = 65f

    // Replay separators used by iOS Mini Golf.
    const val SEG_SEP: Char = '|'
    const val BALL_SEP: Char = '&'
    const val FIELD_SEP: Char = ','

    const val BALL_RADIUS = 4f
    const val POWER_TO_VELOCITY = 1.55f

    const val MODE_RACE = "race"
    const val DEFAULT_MODE = "3"
    const val DEFAULT_SEED = 1931763971

    fun holeCountFor(mode: String): Int = when (mode) {
        "5" -> 5
        "3" -> 3
        else -> mode.toIntOrNull()?.coerceAtLeast(1) ?: 3
    }

    /** Non-race board dimensions from iOS createMap. Pair is xCells to yCells. */
    fun dimensionsFor(mode: String, mapNum: Int): Pair<Int, Int> {
        val hole = mapNum.coerceAtLeast(0)
        return when (mode) {
            "3", "5" -> when (hole) {
                0 -> 6 to 4
                1 -> 7 to 5
                2 -> 7 to 7
                3 -> 10 to 6
                else -> 9 to 8
            }
            else -> 5 to 5
        }
    }

    const val INTRO_FADE_IN_MS = 200L
    const val INTRO_HOLD_MS = 600L
    const val INTRO_SCALE_MS = 400L
    const val INTRO_FADE_OUT_DELAY_MS = 900L
    const val INTRO_FADE_OUT_MS = 250L
}
