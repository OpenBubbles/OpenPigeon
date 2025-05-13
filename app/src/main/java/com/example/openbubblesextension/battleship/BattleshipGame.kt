package com.example.openbubblesextension.battleship

import android.content.Context
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import com.example.openbubblesextension.godot.GodotGameActivity

class BattleshipActivity : GodotGameActivity() {
    override var baseGame: Game = BattleshipGame()
    override var activityLayout: Int = R.layout.activity_checkers
}

class BattleshipGame : Game {
    override fun getVersion(): String {
        return "19"
    }

    override fun getName(): String {
        return "sea"
    }

    override fun displayName(): String {
        return "Sea Battle"
    }

    override fun buttonId(): Int {
        return R.id.btn_battleship
    }

    override fun gameClass(): Class<*> {
        return BattleshipActivity::class.java
    }

    override fun gamePoster(): Int {
        return R.drawable.battleship
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            put("size", "8")
            put("mode", "1,3,3,0")
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}