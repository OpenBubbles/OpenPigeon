package com.openbubbles.openpigeon.golf

import com.openbubbles.openpigeon.util.OpenPigeonLog
import java.util.Locale

/** Parser/serializer for Mini Golf's non-race replay format. */
object GolfReplay {
    private const val TAG = "GolfNative"

    data class Shot(val dist: Float, val rotation: Float)

    fun parseNonRace(replay: String): List<List<Shot>> {
        OpenPigeonLog.i(TAG, "GolfReplay.parseNonRace enter replayLen=${replay.length}")
        if (replay.isBlank()) return emptyList()

        /*
         * iOS format:
         *   hole segments are separated by '|'
         *   shots inside one hole are separated by '&'
         *   each shot is "dist,rotation"
         *
         * Example:
         *   102.1,0.95&86.19,0.32&132.75,1.75
         */
        val parsed = replay
            .split(GolfConstants.SEG_SEP)
            .map { segment: String ->
                segment
                    .split(GolfConstants.BALL_SEP)
                    .filter { entry: String -> entry.isNotBlank() }
                    .mapNotNull { entry: String ->
                        val parts = entry.split(GolfConstants.FIELD_SEP)
                        if (parts.size < 2) return@mapNotNull null

                        val dist = parts[0].toFloatOrNull() ?: return@mapNotNull null
                        val rot = parts[1].toFloatOrNull() ?: return@mapNotNull null

                        Shot(dist, rot)
                    }
            }

        OpenPigeonLog.i(
            TAG,
            "GolfReplay.parseNonRace complete segments=${parsed.size} shots=${parsed.sumOf { it.size }}"
        )

        return parsed
    }

    fun segmentAt(replay: String, holeIndex: Int): List<Shot> {
        if (holeIndex < 0) return emptyList()
        return parseNonRace(replay).getOrNull(holeIndex).orEmpty()
    }

    fun appendShot(replay: String, shot: Shot): String {
        return appendShot(
            replay = replay,
            holeIndex = 0,
            shot = shot
        )
    }

    fun appendShot(
        replay: String,
        holeIndex: Int,
        shot: Shot
    ): String {
        val entry = String.format(Locale.US, "%.6f,%.6f", shot.dist, shot.rotation)

        val segments = if (replay.isBlank()) {
            mutableListOf()
        } else {
            replay.split(GolfConstants.SEG_SEP).toMutableList()
        }

        while (segments.size <= holeIndex) {
            segments.add("")
        }

        segments[holeIndex] = if (segments[holeIndex].isBlank()) {
            entry
        } else {
            segments[holeIndex] + GolfConstants.BALL_SEP + entry
        }

        /*
         * Avoid sending useless trailing empty hole segments.
         */
        while (segments.isNotEmpty() && segments.last().isBlank()) {
            segments.removeAt(segments.lastIndex)
        }

        val out = segments.joinToString(GolfConstants.SEG_SEP.toString())

        OpenPigeonLog.i(
            TAG,
            "GolfReplay.appendShot holeIndex=$holeIndex oldLen=${replay.length} " +
                    "newLen=${out.length} dist=${shot.dist} rotation=${shot.rotation}"
        )

        return out
    }

    fun hasSegment(replay: String, holeIndex: Int): Boolean {
        return segmentAt(replay, holeIndex).isNotEmpty()
    }
}