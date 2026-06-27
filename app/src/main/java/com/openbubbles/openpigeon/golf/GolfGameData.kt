package com.openbubbles.openpigeon.golf

import com.openbubbles.openpigeon.util.OpenPigeonLog

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
                msg["holeNumber"],
                msg["number"]
            )?.toIntOrNull()

            val mapNumRaw = firstNonBlank(
                msg["map_num"],
                msg["mapNum"],
                msg["map"],
                msg["hole_index"],
                msg["holeIndex"]
            )?.toIntOrNull()

            val player = firstNonBlank(msg["player"], msg["p"])
                ?.toIntOrNull()
                ?.coerceIn(1, 2)
                ?: previous?.player
                ?: 1

            val player1Id = firstNonBlank(
                msg["player1"],
                msg["player_id1"],
                msg["player1_id"]
            )
                ?: previous?.player1Id
                ?: ""

            val player2Id = firstNonBlank(
                msg["player2"],
                msg["player_id2"],
                msg["player2_id"]
            )
                ?: previous?.player2Id
                ?: ""

            val replayInfo = parseReplayFields(
                msg = msg,
                player = player
            )

            val replay = replayInfo.replay
            val replay2 = replayInfo.replay2

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

                /*
                 * iOS sometimes sends num/number as a game-progress value that does not
                 * directly match our zero-based map index. If replay data exists, the
                 * segment count is the safer source for the current replay hole.
                 */
                replayDrivenMapNum != null -> replayDrivenMapNum

                rawNum != null -> rawNum - 1
                previous != null -> previous.mapNum
                else -> 0
            }.coerceIn(0, (holeCount - 1).coerceAtLeast(0))

            val renderKey = buildString {
                append(seed)
                append('|').append(mode)
                append('|').append(holeCount)
                append('|').append(mapNum)
                append('|').append(player)

                /*
                 * Use content hashes, not only lengths.
                 * Different replay strings can have identical lengths.
                 */
                append('|').append(replay.hashCode())
                append('|').append(replay2.hashCode())
                append('|').append(replay.length)
                append('|').append(replay2.length)

                append('|').append(player1Id)
                append('|').append(player2Id)
                append('|').append(msg["sender"].orEmpty())
                append('|').append(msg["winner"].orEmpty())
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
                        "rawNum=$rawNum mapNumRaw=$mapNumRaw replaySegments=$replaySegmentCount " +
                        "mapNum=${data.mapNum} player=${data.player} " +
                        "replaySource=${replayInfo.replaySource} replay2Source=${replayInfo.replay2Source} " +
                        "replayLen=${replay.length} replay2Len=${replay2.length} " +
                        "replay=${safeLogReplay(replay)} replay2=${safeLogReplay(replay2)} " +
                        "renderKey=${data.renderKey}"
            )

            return data
        }

        private data class ReplayParseResult(
            val replay: String,
            val replay2: String,
            val replaySource: String,
            val replay2Source: String
        )

        private fun parseReplayFields(
            msg: Map<String, String>,
            player: Int
        ): ReplayParseResult {
            /*
             * Canonical fields from real iOS Mini Golf messages.
             *
             * The raw iOS payload has shown that completed shots arrive in "replay":
             *
             *   replay=125.459976,1.129438&136.476028,2.182604&20.355270,-2.072401
             *
             * Therefore replay/replay2 must win over replay_send.
             */
            val explicitReplay1 = firstNonBlank(
                msg["replay"],
                msg["replay1"],
                msg["p1Replay"],
                msg["p1_replay"],
                msg["player1_replay"],
                msg["replay_string"],
                msg["replayString"]
            )

            val explicitReplay2 = firstNonBlank(
                msg["replay2"],
                msg["replay_2"],
                msg["p2Replay"],
                msg["p2_replay"],
                msg["player2_replay"],
                msg["replay_string2"],
                msg["replayString2"]
            )

            /*
             * replay_send is an iOS internal/live-send field.
             * It is useful only as a fallback if the canonical replay field is absent.
             * Do not let replay_send overwrite a real replay/replay2 payload.
             */
            val replaySend = firstNonBlank(
                msg["replay_send"],
                msg["replaySend"],
                msg["send_replay"],
                msg["replay_send1"],
                msg["replaySend1"]
            )

            val replaySend2 = firstNonBlank(
                msg["replay_send2"],
                msg["replaySend2"],
                msg["send_replay2"]
            )

            var replay1 = explicitReplay1.orEmpty()
            var replay2 = explicitReplay2.orEmpty()

            var replay1Source = if (explicitReplay1 != null) {
                "replay/replay_string"
            } else {
                "blank"
            }

            var replay2Source = if (explicitReplay2 != null) {
                "replay2/replay_string2"
            } else {
                "blank"
            }

            /*
             * Fallback only.
             *
             * If iOS sends only replay_send and no replay/replay2, apply it to the
             * sending player slot. But never override canonical replay fields.
             */
            if (!replaySend.isNullOrBlank()) {
                if (player == 2) {
                    if (replay2.isBlank()) {
                        replay2 = replaySend
                        replay2Source = "replay_send/player2 fallback"
                    }
                } else {
                    if (replay1.isBlank()) {
                        replay1 = replaySend
                        replay1Source = "replay_send/player1 fallback"
                    }
                }
            }

            if (!replaySend2.isNullOrBlank() && replay2.isBlank()) {
                replay2 = replaySend2
                replay2Source = "replay_send2 fallback"
            }

            return ReplayParseResult(
                replay = replay1,
                replay2 = replay2,
                replaySource = replay1Source,
                replay2Source = replay2Source
            )
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

        private fun firstNonBlank(vararg values: String?): String? {
            return values.firstOrNull { !it.isNullOrBlank() }?.trim()
        }

        private fun safeLogReplay(value: String): String {
            if (value.isBlank()) return ""

            val escaped = value
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")

            return if (escaped.length <= 220) {
                escaped
            } else {
                escaped.take(220) + "...(${escaped.length})"
            }
        }
    }
}