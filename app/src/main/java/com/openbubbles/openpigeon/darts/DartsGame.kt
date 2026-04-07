package com.openbubbles.openpigeon.darts

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

class DartsGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "darts"
    }

    override fun displayName(): String {
        return "Darts"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.darts
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    var gameMode = "101"

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Game Mode", listOf("101", "201", "301"), gameMode)
        }
    }

    override fun setConfigOption(name: String, value: String) {
        gameMode = value
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)
        return super.getNewGameData(context)?.apply {
            put("mode", gameMode)
            put("style2", "0")
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}