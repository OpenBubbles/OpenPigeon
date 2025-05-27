package com.example.openbubblesextension.pool

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.layout.Box
import androidx.glance.layout.padding
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import com.example.openbubblesextension.RenderConfigOption
import com.example.openbubblesextension.godot.GodotGameActivity

class PoolGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "pool"
    }

    override fun displayName(): String {
        return "8 Ball"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    var hard = false

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Difficulty", listOf("Normal", "Hard"), if (hard) "Hard" else "Normal")
        }
    }

    override fun setConfigOption(name: String, value: String) {
        hard = value == "Hard"
    }

    override fun gameClass(): Class<*> {
        return PoolActivity::class.java
    }

    override fun gamePoster(): Int {
        return R.drawable.pool_image
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            // mode h for hard
            put("mode", if (hard) "h" else "n")
            put("v2", "2")
            put("v3", "2")
            put("v4", "2")
            put("v5", "2")
        }
    }

    override fun getDefaultReplay(): String {
        return "board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0|board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0"
    }
}