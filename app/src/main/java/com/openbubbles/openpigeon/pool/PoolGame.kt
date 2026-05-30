package com.openbubbles.openpigeon.pool

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.layout.Box
import androidx.glance.layout.padding
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView

open class PoolGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun isConfigurable(): Boolean {
        return true
    }
    var plusMode = "8 Ball"
    var difficulty = "Normal"

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Game Mode", listOf("8 Ball", "8 Ball+"), plusMode)
        }
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Difficulty", listOf("Normal", "Hard"), difficulty)
        }
    }

    override fun setConfigOption(name: String, value: String) {
        when (name.lowercase()) {
            "game mode" -> plusMode = value
            "difficulty" -> difficulty = value
            else -> {
                println("Warning: unknown config option ‘$name’")
            }
        }
        println("Config option '$name' set to '$value'")
    }

    override fun getName(): String {
        return "pool"
    }

    override fun displayName(): String {
        return plusMode
    }

    override fun gameClass(): Class<*> {
        return PoolActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        val game = config?.get("game") ?: "pool"
        val mode = config?.get("mode") ?: "n"

        return when {
            game == "pool3" && mode == "h" ->
                R.drawable.pool_plus_hard_preview

            game == "pool3" ->
                R.drawable.pool_plus_normal_preview

            mode == "h" ->
                R.drawable.pool_hard_preview

            else ->
                R.drawable.pool_normal_preview
        }
    }

    override fun playName(): String {
        return plusMode
    }

    override fun getDisplaySubtitle(context: Context, message: Map<String, String>): String {
        message["winner"]?.let {
            return super.getDisplaySubtitle(context, message)
        }

        message["caption"]?.takeIf { it.startsWith("Let's") }?.let {
            val gameMode = when (message["game"]) {
                "pool3" -> "8 Ball+"
                "pool2" -> "9 Ball"
                else -> "8 Ball"
            }
            return "Let's play $gameMode!"
        }

        return super.getDisplaySubtitle(context, message)
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)

        val selectedGameName = if (plusMode == "8 Ball+") "pool3" else "pool"

        return super.getNewGameData(context)?.apply {
            put("game", selectedGameName)
            put("game_name", plusMode)
            put("caption", "Let's play $plusMode!")

            put("mode", if (difficulty == "Hard") "h" else "n")
            put("v2", "2")
            put("v3", "2")
            put("v4", "2")
            put("v5", "2")
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun getDefaultReplay(): String {
        return "board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0|board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0"
    }
}

class NineBallGame : PoolGame() {
    override fun getName(): String {
        return "pool2"
    }

    override fun displayName(): String {
        return "9 Ball"
    }

    override fun playName(): String {
        return "9 Ball"
    }

    @Composable
    override fun Configuration(context: Context?) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Difficulty", listOf("Normal", "Hard"), difficulty)
        }
    }

    override fun setConfigOption(name: String, value: String) {
        when (name.lowercase()) {
            "difficulty" -> difficulty = value
            else -> println("Warning: unknown config option ‘$name’")
        }
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        val mode = config?.get("mode") ?: if (difficulty == "Hard") "h" else "n"

        return if (mode == "h") {
            R.drawable.pool_hard_preview
        } else {
            R.drawable.pool_normal_preview
        }
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)

        return super.getNewGameData(context)?.apply {
            put("game", "pool2")
            put("game_name", "9 Ball")
            put("caption", "Let's play 9 Ball!")
            put("mode", if (difficulty == "Hard") "h" else "n")
            put("v2", "2")
            put("v3", "2")
            put("v4", "2")
            put("v5", "2")
            put("avatar2", AvatarView.buildAvatarString())
        }
    }
}