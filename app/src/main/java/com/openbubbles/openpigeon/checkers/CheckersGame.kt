package com.openbubbles.openpigeon.checkers

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

class CheckersGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "checkers"
    }

    override fun displayName(): String {
        return "Checkers"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    var mode = "Checkers"

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Game Mode", listOf("Checkers", "Newbie Checkers"), mode)
        }
    }

    override fun playName(): String {
        return mode
    }

    override fun setConfigOption(name: String, value: String) {
        mode = value
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.checkers
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            put("mode", if (mode == "Checkers") "n" else "h")
        }
    }

    override fun getDefaultReplay(): String {
        return "board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0|board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0"
    }
}