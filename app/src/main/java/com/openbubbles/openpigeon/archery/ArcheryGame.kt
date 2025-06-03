package com.openbubbles.openpigeon.archery

import android.content.Context
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
import kotlin.random.Random

class ArcheryGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "archery"
    }

    override fun displayName(): String {
        return "Archery"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.archery
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            put("seed", "${Random.nextInt()}")
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}