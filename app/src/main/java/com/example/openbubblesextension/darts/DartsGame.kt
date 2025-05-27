package com.example.openbubblesextension.darts

import android.content.Context
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import com.example.openbubblesextension.godot.GodotGameActivity

class DartsActivity : GodotGameActivity() {
    override var baseGame: Game = DartsGame()
    override var activityLayout: Int = R.layout.activity_connect
}

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
        return DartsActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.darts
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            put("mode", "101")
            put("style2", "0")
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}