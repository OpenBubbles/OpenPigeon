package com.example.openbubblesextension.pong

import android.content.Context
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import com.example.openbubblesextension.godot.GodotGameActivity
import kotlin.random.Random

class PongActivity : GodotGameActivity() {
    override var baseGame: Game = PongGame()
    override var activityLayout: Int = R.layout.activity_pong
}

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
        return PongActivity::class.java
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