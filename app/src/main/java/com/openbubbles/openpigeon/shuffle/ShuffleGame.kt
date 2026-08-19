package com.openbubbles.openpigeon.shuffle

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.ImageProvider
import com.openbubbles.openpigeon.ConfigImageOption
import com.openbubbles.openpigeon.DynamicPreviewGame
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigImageOption
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.random.Random

class ShuffleGame : Game, DynamicPreviewGame {
    override fun getVersion(): String {
        return "0"
    }

    override fun getName(): String {
        return "shuffle"
    }

    override fun displayName(): String {
        return "Shuffleboard"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    private var mapMode = "1"

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        RenderConfigImageOption(
            game = this,
            name = "Game Mode",
            settingName = "Map",
            options = listOf(
                ConfigImageOption(
                    label = "Map 1",
                    image = ImageProvider(R.drawable.shuffle_map_1),
                    value = "1",
                ),
                ConfigImageOption(
                    label = "Map 2",
                    image = ImageProvider(R.drawable.shuffle_map_3),
                    value = "3",
                ),
                ConfigImageOption(
                    label = "Map 3",
                    image = ImageProvider(R.drawable.shuffle_map_2),
                    value = "2",
                ),
            ),
            selected = mapMode,
            imageHeight = 86.dp,
        )
    }

    override fun setConfigOption(
        name: String,
        value: String,
    ) {
        when (name.lowercase()) {
            "map", "board" -> {
                mapMode = value.toIntOrNull()?.coerceIn(
                    1,
                    3,
                )?.toString() ?: "1"
            }

            else -> {
                println(
                    "Warning: unknown Shuffleboard config option '$name'",
                )
            }
        }

        println(
            "Shuffleboard config '$name' set to map $mapMode",
        )
    }

    override fun gameClass(): Class<*> {
        return ShuffleActivity::class.java
    }

    override fun gamePoster(
        config: Map<String, String>?,
    ): Int {
        val resolvedMapMode = resolveMapMode(
            config,
        )

        return when (resolvedMapMode) {
            2 -> {
                R.drawable.shuffle_map_2
            }

            3 -> {
                R.drawable.shuffle_map_3
            }

            else -> {
                R.drawable.shuffle_map_1
            }
        }
    }

    private fun resolveMapMode(
        config: Map<String, String>?,
    ): Int {
        val modeFromData = config?.get(
            "mode",
        )?.toIntOrNull()?.takeIf {
            it in 1..3
        }

        if (modeFromData != null) {
            return modeFromData
        }

        val mapValueCount = config?.get(
            "map",
        )?.split(
            ",",
        )?.count {
            it.trim().isNotEmpty()
        }

        val modeFromMap = when (mapValueCount) {
            12 -> 1
            16 -> 2
            21 -> 3
            else -> null
        }

        if (modeFromMap != null) {
            return modeFromMap
        }

        return mapMode.toIntOrNull()?.coerceIn(1, 3) ?: 1
    }

    override fun getNewGameData(
        context: Context,
    ): MutableMap<String, String>? {
        AvatarData.init(context)

        val selectedMode = mapMode.toIntOrNull()?.coerceIn(1, 3) ?: 1

        return super.getNewGameData(context)?.apply {
            put(
                "mode",
                selectedMode.toString(),
            )

            put(
                "map",
                generateMapForMode(selectedMode),
            )

            put("num", "1")
            remove("replay")

            put(
                "avatar2",
                AvatarView.buildAvatarString(),
            )
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }

    override fun gamePreviewBitmap(
        context: Context,
        message: Map<String, String>,
    ): Bitmap? {
        return buildPreview(
            context = context,
            message = message,
            targetWidthPx = 320,
            targetHeightPx = 480,
        )
    }

    override fun gamePreviewBitmap(
        context: Context,
        message: Map<String, String>,
        targetWidthPx: Int,
        targetHeightPx: Int,
    ): Bitmap? {
        return buildPreview(
            context = context,
            message = message,
            targetWidthPx = targetWidthPx,
            targetHeightPx = targetHeightPx,
        )
    }

    private fun buildPreview(
        context: Context,
        message: Map<String, String>,
        targetWidthPx: Int,
        targetHeightPx: Int,
    ): Bitmap? {
        return try {
            val board = extractLatestBoard(
                message["replay"],
            ) ?: defaultPreviewBoard()

            val resolvedMapMode = resolveMapMode(
                message,
            )

            val previewMapScores = parsePreviewMapScores(
                rawMap = message["map"],
                mode = resolvedMapMode,
            )

            ShufflePreviewRenderer.render(
                context = context,
                board = board,
                mapMode = resolvedMapMode,
                mapScores = previewMapScores,
                targetWidthPx = targetWidthPx,
                targetHeightPx = targetHeightPx,
                gameFinished = message["winner"].orEmpty().isNotBlank(),
            )
        } catch (exception: Exception) {
            OpenPigeonLog.w(
                "ShuffleGame",
                "Failed to build Shuffle preview, " + "size=${targetWidthPx}x${targetHeightPx}",
                exception,
            )

            null
        }
    }

    private fun extractLatestBoard(
        replayValue: String?,
    ): ShufflePreviewBoard? {
        if (replayValue.isNullOrBlank()) {
            return null
        }

        val latestBoardSegment = replayValue.split(
            "|",
        ).asReversed().map { segment ->
            segment.trim()
        }.firstOrNull { segment ->
            segment.startsWith(
                "board:",
            )
        } ?: return null

        val payload = latestBoardSegment.removePrefix(
            "board:",
        )

        val parts = payload.split(
            "#",
        )

        val pucks = parts.drop(
            1,
        ).mapNotNull { entry: String ->
            val trimmedEntry = entry.trim()

            if (trimmedEntry.isBlank()) {
                return@mapNotNull null
            }

            val values = trimmedEntry.split(
                ",",
            )

            if (values.size < 3) {
                return@mapNotNull null
            }

            val x = values[0].toFloatOrNull() ?: return@mapNotNull null

            val y = values[1].toFloatOrNull() ?: return@mapNotNull null

            val player = values[2].toIntOrNull()?.coerceIn(
                1,
                2,
            ) ?: return@mapNotNull null

            val rotation = values.getOrNull(
                3,
            )?.toFloatOrNull() ?: 0f

            ShufflePreviewPuck(
                x = x,
                y = y,
                player = player,
                rotation = rotation,
            )
        }

        return ShufflePreviewBoard(
            pucks = pucks,
        )
    }

    private fun defaultPreviewBoard(): ShufflePreviewBoard {
        return ShufflePreviewBoard(
            pucks = listOf(
                ShufflePreviewPuck(
                    x = 0f,
                    y = -215f,
                    player = 1,
                ),
                ShufflePreviewPuck(
                    x = 0f,
                    y = 215f,
                    player = 2,
                ),
            ),
        )
    }

    private fun parsePreviewMapScores(
        rawMap: String?,
        mode: Int,
    ): List<Int> {
        val expectedCount = when (mode) {
            1 -> 12
            2 -> 16
            3 -> 21
            else -> 12
        }

        val parsed = rawMap?.trim()?.removePrefix(
            "[",
        )?.removeSuffix(
            "]",
        )?.split(
            ",",
        )?.mapNotNull { value ->
            value.trim().toIntOrNull()
        }.orEmpty()

        return if (parsed.size == expectedCount) {
            parsed
        } else {
            emptyList()
        }
    }

    private fun generateMapForMode(mode: Int): String {
        return when (mode) {
            1 -> generateRandomMap(MODE_1_SCORE_POOL, 12)
            2 -> generateRandomMap(MODE_2_SCORE_POOL, 16)
            3 -> generateRandomMap(MODE_3_SCORE_POOL, 21)
            else -> generateRandomMap(MODE_1_SCORE_POOL, 12)
        }
    }

    private fun generateRandomMap(
        scorePool: List<Int>, count: Int
    ): String {
        return List(count) {
            scorePool[Random.nextInt(scorePool.size)]
        }.joinToString(",")
    }

    private companion object {
        private val MODE_1_SCORE_POOL = listOf(
            2, 3, 4, 5, 6, 7, 8, 10
        )

        private val MODE_2_SCORE_POOL = listOf(
            2, 3, 4, 5, 6, 7, 8, 10
        )

        private val MODE_3_SCORE_POOL = listOf(
            2, 3, 4, 5, 6, 7, 8, 10
        )
    }
}