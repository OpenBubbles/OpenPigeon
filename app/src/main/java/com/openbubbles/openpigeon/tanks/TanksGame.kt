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
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView

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

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)
        return super.getNewGameData(context)?.apply {
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun getDefaultReplay(): String {
        fun rand(min: Double, max: Double): Double {
            return min + Math.random() * (max - min)
        }

        fun fmt(d: Double): String {
            return String.format("%.6f", d)
        }

        val height = rand(0.0, 100.0)
        val wind = rand(-1.0, 1.0)

        val tank1x = rand(-200.0, -80.0)
        val tank2x = rand(80.0, 200.0)

        val tank1rot = rand(0.0, Math.PI)
        val tank2rot = rand(-Math.PI, 0.0)

        val tank1power = rand(0.4, 1.0)
        val tank2power = rand(0.4, 1.0)

        val tank1hp = 3
        val tank2hp = 3

        return "board:" +
                "height,${fmt(height)}&" +
                "wind,${fmt(wind)}&" +
                "tank1x,${fmt(tank1x)}&" +
                "tank1rot,${fmt(tank1rot)}&" +
                "tank1power,${fmt(tank1power)}&" +
                "tank1hp,$tank1hp&" +
                "tank2x,${fmt(tank2x)}&" +
                "tank2rot,${fmt(tank2rot)}&" +
                "tank2power,${fmt(tank2power)}&" +
                "tank2hp,$tank2hp"
    }
}