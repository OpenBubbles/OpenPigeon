package com.example.openbubblesextension.connect

import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import com.example.openbubblesextension.godot.GodotGameActivity

class ConnectActivity : GodotGameActivity() {
    override var baseGame: Game = ConnectGame()
    override var activityLayout: Int = R.layout.activity_connect
}

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

    override fun buttonId(): Int {
        return R.id.btn_connect
    }

    override fun gameClass(): Class<*> {
        return ConnectActivity::class.java
    }

    override fun gamePoster(): Int {
        return R.drawable.connect4
    }

    override fun getDefaultReplay(): String {
        return "board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"
    }
}