package com.openbubbles.openpigeon.paintball

import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity

class PaintGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "paint"
    }

    override fun displayName(): String {
        return "Paintball"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.paintball
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}