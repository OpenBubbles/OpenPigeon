package com.openbubbles.openpigeon.connect

import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity

class ConnectGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "connect"
    }

    override fun displayName(): String {
        return "Four in a Row"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.connect4
    }

    override fun getDefaultReplay(): String {
        return "board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"
    }
}