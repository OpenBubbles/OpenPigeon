package com.openbubbles.openpigeon.tanks

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

class TanksGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "tanks"
    }

    override fun displayName(): String {
        return "Tanks"
    }
    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.tanks
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}