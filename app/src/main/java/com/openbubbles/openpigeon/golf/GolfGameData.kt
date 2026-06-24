package com.openbubbles.openpigeon.golf

import com.openbubbles.openpigeon.util.OpenPigeonLog

/**
 * Normalized Mini Golf game-data parser.
 *
 * iOS/GamePigeon seeds are effectively 32-bit signed values. Some Android/opening
 * paths may surface the same seed as an unsigned decimal string, so parsing must
 * preserve the low 32 bits instead of failing and falling back to the default seed.
 */
data class GolfGameData(
    val seed: Int,
    val seedText: String,
    val seedWasUnsignedDecimal: Boolean,
    val mode: String,
    val holeCount: Int,
    val mapNum: Int,
    val rawNum: Int?,
    val player: Int,
    val player1Id: String,
    val player2Id: String,
    val replay: String,
    val replay2: String,
    val renderKey: String
) {
    companion object {
        private const val TAG = "GolfNative"

        fun default(): GolfGameData = fromMessage(
            mapOf(
                "game" to "golf",
                "mode" to GolfConstants.DEFAULT_MODE,
                "seed" to GolfConstants.DEFAULT_SEED.toString(),
                "num" to "1",
                "player" to "1",
                "replay" to "",
                "replay2" to ""
            ),
            previous = null
        )

        fun fromMessage(msg: Map<String, String>, previous: GolfGameData? = null): GolfGameData {
            val seedRaw = firstNonBlank(
                msg["seed"],
                msg["game_seed"],
                msg["random_seed"]
            )
            val parsedSeed = parseIosSeed(seedRaw)
            val fallbackSeed = previous?.seed ?: GolfConstants.DEFAULT_SEED
            val seed = parsedSeed?.first ?: fallbackSeed
            val seedText = seedRaw ?: seed.toString()
            val seedWasUnsigned = parsedSeed?.second ?: false

            val modeRaw = firstNonBlank(
                msg["mode"],
                msg["game_mode"],
                msg["holes"],
                msg["hole_count"],
                msg["subcaption"]
            ) ?: previous?.mode ?: GolfConstants.DEFAULT_MODE

            val holeCount = parseHoleCount(modeRaw)
                ?: previous?.holeCount
                ?: GolfConstants.holeCountFor(GolfConstants.DEFAULT_MODE)
            val mode = when {
                modeRaw.equals(GolfConstants.MODE_RACE, ignoreCase = true) -> GolfConstants.MODE_RACE
                holeCount == 5 -> "5"
                else -> "3"
            }

            val rawNum = firstNonBlank(
                msg["num"],
                msg["hole"],
                msg["hole_num"],
                msg["holeNumber"]
            )?.toIntOrNull()

            val mapNumRaw = firstNonBlank(
                msg["map_num"],
                msg["mapNum"],
                msg["map"],
                msg["hole_index"],
                msg["holeIndex"]
            )?.toIntOrNull()

            val replay = msg["replay"].orEmpty()
            val replay2 = msg["replay2"].orEmpty()

            /*
             * iOS sets num=2 after player 1 finishes the first round, but that still
             * refers to the first hole/round for replay/player-2 response purposes.
             *
             * If replay data exists, use the replay segment count to decide which board
             * this data belongs to.
             */
            val replaySegmentCount = maxOf(
                replaySegmentCount(replay),
                replaySegmentCount(replay2)
            )

            val replayDrivenMapNum = if (replaySegmentCount > 0) {
                replaySegmentCount - 1
            } else {
                null
            }

            val mapNum = when {
                mapNumRaw != null -> mapNumRaw
                replayDrivenMapNum != null -> replayDrivenMapNum
                rawNum != null -> rawNum - 1
                previous != null -> previous.mapNum
                else -> 0
            }.coerceIn(0, (holeCount - 1).coerceAtLeast(0))

            val player = firstNonBlank(msg["player"], msg["p"])
                ?.toIntOrNull()
                ?.coerceIn(1, 2)
                ?: previous?.player
                ?: 1

            val player1Id = firstNonBlank(msg["player1"], msg["player_id1"], msg["player1_id"])
                ?: previous?.player1Id
                ?: ""
            val player2Id = firstNonBlank(msg["player2"], msg["player_id2"], msg["player2_id"])
                ?: previous?.player2Id
                ?: ""

            val renderKey = buildString {
                append(seed)
                append('|').append(mode)
                append('|').append(holeCount)
                append('|').append(mapNum)
                append('|').append(player)
                append('|').append(replay.length)
                append('|').append(replay2.length)
                append('|').append(msg["turn"].orEmpty())
                append('|').append(msg["isYourTurn"].orEmpty())
            }

            val data = GolfGameData(
                seed = seed,
                seedText = seedText,
                seedWasUnsignedDecimal = seedWasUnsigned,
                mode = mode,
                holeCount = holeCount,
                mapNum = mapNum,
                rawNum = rawNum,
                player = player,
                player1Id = player1Id,
                player2Id = player2Id,
                replay = replay,
                replay2 = replay2,
                renderKey = renderKey
            )

            OpenPigeonLog.i(
                TAG,
                "GameData.parse keys=${msg.keys.sorted()} " +
                    "seedRaw=${seedRaw.orEmpty()} seed=${data.seed} unsigned=$seedWasUnsigned " +
                    "modeRaw=$modeRaw mode=${data.mode} holes=${data.holeCount} " +
                    "rawNum=$rawNum mapNumRaw=$mapNumRaw mapNum=${data.mapNum} player=${data.player} " +
                    "replayLen=${replay.length} replay2Len=${replay2.length} renderKey=${data.renderKey}"
            )

            return data
        }

        fun parseIosSeed(raw: String?): Pair<Int, Boolean>? {
            val text = raw?.trim()?.takeIf { it.isNotBlank() } ?: return null
            text.toIntOrNull()?.let { return it to false }

            val longValue = text.toLongOrNull() ?: return null
            val unsigned = longValue >= 0 && longValue > Int.MAX_VALUE.toLong()
            val low32 = longValue and 0xffffffffL
            return low32.toInt() to unsigned
        }

        private fun parseHoleCount(raw: String): Int? {
            val trimmed = raw.trim()
            if (trimmed.equals(GolfConstants.MODE_RACE, ignoreCase = true)) return 3

            trimmed.toIntOrNull()?.let { number ->
                return when {
                    number <= 3 -> 3
                    number >= 5 -> 5
                    else -> 3
                }
            }

            val match = Regex("""(\d+)""").find(trimmed)
            val fromText = match?.groupValues?.getOrNull(1)?.toIntOrNull()
            return when {
                fromText == null -> null
                fromText <= 3 -> 3
                fromText >= 5 -> 5
                else -> 3
            }
        }

        private fun replaySegmentCount(replay: String): Int {
            if (replay.isBlank()) return 0
            return replay.split(GolfConstants.SEG_SEP).size
        }

        private fun firstNonBlank(vararg values: String?): String? =
            values.firstOrNull { !it.isNullOrBlank() }?.trim()
    }
}
