package com.openbubbles.openpigeon.golf

import com.openbubbles.openpigeon.util.OpenPigeonLog
import java.util.Locale

/** Minimal parser/serializer for Mini Golf's non-race replay format. */
object GolfReplay {
    private const val TAG = "GolfNative"

    data class Shot(val dist: Float, val rotation: Float)

    fun parseNonRace(replay: String): List<List<Shot>> {
        OpenPigeonLog.i(TAG, "GolfReplay.parseNonRace enter replayLen=${replay.length}")
        if (replay.isBlank()) return emptyList()

        val parsed = replay
            .split(GolfConstants.SEG_SEP)
            .filter { segment: String -> segment.isNotBlank() }
            .map { segment: String ->
                segment
                    .split(GolfConstants.BALL_SEP)
                    .filter { entry: String -> entry.isNotBlank() }
                    .mapNotNull { entry: String ->
                        val parts: List<String> = entry.split(GolfConstants.FIELD_SEP)
                        if (parts.size < 2) return@mapNotNull null
                        val dist = parts[0].toFloatOrNull() ?: return@mapNotNull null
                        val rot = parts[1].toFloatOrNull() ?: return@mapNotNull null
                        Shot(dist, rot)
                    }
            }

        OpenPigeonLog.i(TAG, "GolfReplay.parseNonRace complete segments=${parsed.size} shots=${parsed.sumOf { it.size }}")
        return parsed
    }

    fun appendShot(replay: String, shot: Shot): String {
        val entry = String.format(Locale.US, "%.6f,%.6f", shot.dist, shot.rotation)
        val out = if (replay.isBlank()) entry else replay + GolfConstants.SEG_SEP + entry
        OpenPigeonLog.i(TAG, "GolfReplay.appendShot oldLen=${replay.length} newLen=${out.length} dist=${shot.dist} rotation=${shot.rotation}")
        return out
    }
}
