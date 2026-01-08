package com.openbubbles.openpigeon.dots

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

class DotsGame : Game {
    override fun getVersion(): String {
        return "0"
    }

    override fun getName(): String {
        return "dots"
    }

    override fun displayName(): String {
        return "Dots"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    var boardsize = "4x4"

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Board Size", listOf("4x4", "5x5", "6x6"), boardsize)
        }
    }

    override fun setConfigOption(name: String, value: String) {
        boardsize = value
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        val size = config?.get("size")
        return when (size) {
            "4" -> R.drawable.dots4x4
            "5" -> R.drawable.dots5x5
            "6" -> R.drawable.dots6x6
            else -> {R.drawable.dots4x4}
        }
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        return super.getNewGameData(context)?.apply {
            put("size", when(boardsize) {
                "4x4" -> "4"
                "5x5" -> "5"
                "6x6" -> "6"
                else -> "4"
            })
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}