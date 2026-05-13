package com.openbubbles.openpigeon.pong

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
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import kotlin.random.Random

class PongGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "beer"
    }

    override fun displayName(): String {
        return "Cup Pong"
    }


    override fun isConfigurable(): Boolean {
        return true
    }

    var gameDifficulty = false

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Game Mode", listOf("Triangle", "Random"), if (gameDifficulty) "Random" else "Triangle")
        }
    }

    override fun setConfigOption(name: String, value: String) {
        gameDifficulty = value == "Random"
        println("Config option '$name' set to '$value'")
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return when (config?.get("mode")) {
            "h" -> R.drawable.cuppong
            "n" -> R.drawable.cuppong
            else -> R.drawable.cuppong
        }
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)
        return super.getNewGameData(context)?.apply {
            put("seed", "${Random.nextInt()}")
            put("mode", if (gameDifficulty) "h" else "n")
            put("style2", "0")
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}