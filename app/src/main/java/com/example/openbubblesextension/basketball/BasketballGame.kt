package com.example.openbubblesextension.basketball

import android.content.Context
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import com.example.openbubblesextension.godot.GodotGameActivity

class BasketballActivity : GodotGameActivity() {
    override var baseGame: Game = BasketballGame()
    override var activityLayout: Int = R.layout.activity_basketball
}

class BasketballGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "basketball"
    }

    override fun displayName(): String {
        return "Basketball"
    }

    override fun buttonId(): Int {
        return R.id.btn_basketball
    }

    override fun gameClass(): Class<*> {
        return BasketballActivity::class.java
    }

    override fun gamePoster(): Int {
        return R.drawable.basketball
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            put("mode", "n")
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}