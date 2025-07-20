package com.openbubbles.openpigeon.mancala

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.layout.Box
import androidx.glance.layout.padding
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.godot.GodotGameActivity

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
            "0" -> R.drawable.mancala
            "1" -> R.drawable.mancala_avalanche
            else -> {R.drawable.mancala}
        }
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            put("mode", when(gameMode) {
                "Capture" -> "0"
                "Avalanche" -> "1"
                else -> "0"
            })
            put("difficulty", when(gameDifficulty) {
                "Normal" -> "0"
                "Random" -> "1"
                else -> "0"
            })
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}