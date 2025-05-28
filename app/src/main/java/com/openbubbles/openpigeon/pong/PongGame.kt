package com.openbubbles.openpigeon.pong

import android.content.Context
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
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

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.cuppong
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            put("seed", "${Random.nextInt()}")
            put("mode", "n")
            put("style2", "0")
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}