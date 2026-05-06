package com.openbubbles.openpigeon.tanks

import android.content.Context
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import kotlin.math.PI
import kotlin.random.Random

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
            put("replay", getDefaultReplay())
        }
    }

    override fun getDefaultReplay(): String {
        val tank1x = Random.nextDouble(-180.0, -100.0)
        val tank2x = Random.nextDouble( 100.0,  180.0)
        val height = Random.nextDouble(0.0, 150.0)
        val wind = Random.nextDouble(-1.0, 1.0)
        val tank1rot = Random.nextDouble(0.0, PI / 2.0)
        val tank2rot = Random.nextDouble(0.0, PI / 2.0)
        val tank1power = Random.nextDouble(0.4, 0.9)
        val tank2power = Random.nextDouble(0.4, 0.9)

        fun f(v: Double) = "%.6f".format(v)

        return "board:" +
                "height,${f(height)}&" +
                "wind,${f(wind)}&" +
                "tank1x,${f(tank1x)}&" +
                "tank1rot,${f(tank1rot)}&" +
                "tank1power,${f(tank1power)}&" +
                "tank1hp,3&" +
                "tank2x,${f(tank2x)}&" +
                "tank2rot,${f(tank2rot)}&" +
                "tank2power,${f(tank2power)}&" +
                "tank2hp,3"
    }
}