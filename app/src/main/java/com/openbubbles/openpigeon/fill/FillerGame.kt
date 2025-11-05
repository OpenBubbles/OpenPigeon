package com.openbubbles.openpigeon.fill

import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity

class FillerGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "fill"
    }

    override fun displayName(): String {
        return "Filler"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.filler
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}