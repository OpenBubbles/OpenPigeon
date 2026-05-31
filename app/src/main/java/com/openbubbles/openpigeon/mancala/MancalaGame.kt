package com.openbubbles.openpigeon.mancala

import android.content.Context
import com.openbubbles.openpigeon.util.OpenPigeonLog
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.layout.Box
import androidx.glance.layout.padding
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import kotlin.random.Random

class MancalaGame : Game {
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
            else -> {R.drawable.mancala}
        }
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)
        return super.getNewGameData(context)?.apply {
            val modePrefix = when(gameMode) {
                "Capture" -> ""
                "Avalanche" -> "a"
                else -> ""
            }
            val difficultySuffix = when(gameDifficulty) {
                "Normal" -> "n"
                "Random" -> "h"
                else -> "n"
            }
            put("mode", modePrefix + difficultySuffix)
            put("replay", getDefaultReplay())
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun getDefaultReplay(): String {
        return "board:" + generateBoardString(gameDifficulty)
    }

    private fun generateBoardString(difficulty: String): String {
        val pits = MutableList(14) { mutableListOf<Int>() } // Initialize 14 empty pits

        if (difficulty == "Normal") {
            // Normal difficulty: 4 stones per non-store pit
            for (i in 0..5) { // Pits 0-5 (Player 1's side)
                for (j in 0 until 4) {
                    pits[i].add(Random.nextInt(1, 4)) // Randomly 1, 2, or 3
                }
            }
            for (i in 7..12) { // Pits 7-12 (Player 2's side)
                for (j in 0 until 4) {
                    pits[i].add(Random.nextInt(11, 14)) // Randomly 11, 12, or 13
                }
            }
            // Pits 6 and 13 (store pits) remain empty
        } else if (difficulty == "Random") { // "h" difficulty
            var totalStones = 0
            val maxStones = 48 // Total number of stones for "Random" difficulty

            // Determine the number of stones for each non-store pit (0-5 and 7-12)
            val nonStorePits = (0..5) + (7..12)
            val stonesPerPit = MutableList(nonStorePits.size) { 0 }

            // Distribute stones randomly between 1 and 5 per pit
            for (i in 0 until nonStorePits.size) {
                stonesPerPit[i] = Random.nextInt(1, 6) // 1 to 5 stones
                totalStones += stonesPerPit[i]
            }

            // Adjust stones to ensure total is 48
            while (totalStones != maxStones) {
                val pitIndex = Random.nextInt(nonStorePits.size)
                if (totalStones < maxStones) {
                    if (stonesPerPit[pitIndex] < 5) {
                        stonesPerPit[pitIndex]++
                        totalStones++
                    }
                } else { // totalStones > maxStones
                    if (stonesPerPit[pitIndex] > 1) {
                        stonesPerPit[pitIndex]--
                        totalStones--
                    }
                }
            }

            var currentStoneIndex = 0
            for (i in 0..5) {
                val numStones = stonesPerPit[currentStoneIndex++]
                for (j in 0 until numStones) {
                    pits[i].add(Random.nextInt(1, 4)) // Randomly 1, 2, or 3
                }
            }
            for (i in 7..12) {
                val numStones = stonesPerPit[currentStoneIndex++]
                for (j in 0 until numStones) {
                    pits[i].add(Random.nextInt(11, 14)) // Randomly 11, 12, or 13
                }
            }
            // Pits 6 and 13 (store pits) remain empty
        }
            OpenPigeonLog.d("MancalaGame", "Generated Board Array (pits): $pits")

        // Build the board string
        return pits.joinToString("&") { pit ->
            if (pit.isEmpty()) {
                "" // Empty pit (for store pits)
            } else {
                pit.joinToString(",") // Join stone labels with commas
            }
        }
    }
}