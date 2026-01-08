package com.openbubbles.openpigeon.gomoku

import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity

class GomokuGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "renju"
    }

    override fun displayName(): String {
        return "Gomoku"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.gomoku
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}