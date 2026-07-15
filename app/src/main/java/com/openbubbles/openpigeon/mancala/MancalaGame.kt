package com.openbubbles.openpigeon.mancala

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.layout.Box
import androidx.glance.layout.padding
import com.openbubbles.openpigeon.DynamicPreviewGame
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.random.Random

class MancalaGame : Game, DynamicPreviewGame {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "mancala"
    }

    override fun displayName(): String {
        return "Mancala"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    var gameMode = "Capture"
    var gameDifficulty = "Normal"

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Game Mode", listOf("Capture", "Avalanche"), gameMode)
        }

        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Difficulty", listOf("Normal", "Random"), gameDifficulty)
        }
    }

    override fun setConfigOption(name: String, value: String) {
        when (name.lowercase()) {
            "game mode" -> gameMode = value
            "difficulty" -> gameDifficulty = value
            else -> {
                println("Warning: unknown config option ‘$name’")
            }
        }

        println("Config option '$name' set to '$value'")
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        val mode = config?.get("mode")

        return when (mode) {
            "n" -> R.drawable.mancala
            "h" -> R.drawable.mancala
            "an" -> R.drawable.mancala_avalanche
            "ah" -> R.drawable.mancala_avalanche
            else -> R.drawable.mancala
        }
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)

        return super.getNewGameData(context)?.apply {
            val modePrefix = when (gameMode) {
                "Capture" -> ""
                "Avalanche" -> "a"
                else -> ""
            }

            val difficultySuffix = when (gameDifficulty) {
                "Normal" -> "n"
                "Random" -> "h"
                else -> "n"
            }

            put("mode", modePrefix + difficultySuffix)
            put("replay", getDefaultReplay())
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun gamePreviewBitmap(
        context: Context,
        message: Map<String, String>
    ): Bitmap? {
        return buildPreview(
            context = context,
            message = message,
            targetWidthPx = 384,
            targetHeightPx = 384
        )
    }

    override fun gamePreviewBitmap(
        context: Context,
        message: Map<String, String>,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap? {
        return buildPreview(
            context = context,
            message = message,
            targetWidthPx = targetWidthPx,
            targetHeightPx = targetHeightPx
        )
    }

    private fun buildPreview(
        context: Context,
        message: Map<String, String>,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap? {
        return try {
            val replay = message["replay"].orEmpty()
            val previewPlayer = resolvePreviewPlayer(message)

            MancalaPreviewRenderer.render(
                context = context,
                replay = replay.ifBlank { getDefaultReplay() },
                previewPlayer = previewPlayer,
                targetWidthPx = targetWidthPx,
                targetHeightPx = targetHeightPx
            )
        } catch (e: Exception) {
            OpenPigeonLog.w(
                "MancalaGame",
                "Failed to build dynamic Mancala preview, " +
                        "size=${targetWidthPx}x${targetHeightPx}, " +
                        "falling back to static image: ${e.message}"
            )
            null
        }
    }

    private fun resolvePreviewPlayer(message: Map<String, String>): Int {
        val messagePlayer = message["player"]
            ?.toIntOrNull()
            ?.coerceIn(1, 2)
            ?: 1

        val isYourTurn = parseBoolean(message["isYourTurn"])

        return if (isYourTurn) {
            messagePlayer
        } else {
            3 - messagePlayer
        }
    }

    private fun parseBoolean(value: String?): Boolean {
        return value.equals("true", ignoreCase = true) ||
                value == "1" ||
                value.equals("yes", ignoreCase = true)
    }

    override fun getDefaultReplay(): String {
        return "board:" + generateBoardString(gameDifficulty)
    }

    private fun generateBoardString(difficulty: String): String {
        val pits = MutableList(14) { mutableListOf<Int>() }

        if (difficulty == "Normal") {
            for (i in 0..5) {
                repeat(4) {
                    pits[i].add(Random.nextInt(1, 4))
                }
            }

            for (i in 7..12) {
                repeat(4) {
                    pits[i].add(Random.nextInt(11, 14))
                }
            }
        } else if (difficulty == "Random") {
            var totalStones = 0
            val maxStones = 48
            val nonStorePits = (0..5) + (7..12)
            val stonesPerPit = MutableList(nonStorePits.size) { 0 }

            for (i in nonStorePits.indices) {
                stonesPerPit[i] = Random.nextInt(1, 6)
                totalStones += stonesPerPit[i]
            }

            while (totalStones != maxStones) {
                val pitIndex = Random.nextInt(nonStorePits.size)

                if (totalStones < maxStones) {
                    if (stonesPerPit[pitIndex] < 5) {
                        stonesPerPit[pitIndex]++
                        totalStones++
                    }
                } else {
                    if (stonesPerPit[pitIndex] > 1) {
                        stonesPerPit[pitIndex]--
                        totalStones--
                    }
                }
            }

            var currentStoneIndex = 0

            for (i in 0..5) {
                val numStones = stonesPerPit[currentStoneIndex++]

                repeat(numStones) {
                    pits[i].add(Random.nextInt(1, 4))
                }
            }

            for (i in 7..12) {
                val numStones = stonesPerPit[currentStoneIndex++]

                repeat(numStones) {
                    pits[i].add(Random.nextInt(11, 14))
                }
            }
        }

        OpenPigeonLog.d("MancalaGame", "Generated Board Array (pits): $pits")

        return pits.joinToString("&") { pit ->
            if (pit.isEmpty()) {
                ""
            } else {
                pit.joinToString(",")
            }
        }
    }
}