package com.example.openbubblesextension.checkers

import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import com.example.openbubblesextension.wordhunt.WordHuntActivity
import org.json.JSONObject

class CheckersGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "checkers"
    }

    override fun displayName(): String {
        return "Checkers"
    }

    override fun buttonId(): Int {
        return R.id.checkers
    }

    override fun gameClass(): Class<*> {
        return CheckersActivity::class.java
    }

    override fun gamePoster(): Int {
        return R.drawable.checkers
    }

    override fun getNewGameData(): MutableMap<String, String> {
        return super.getNewGameData().apply {
            put("mode", "n")
        }
    }

    fun getDefaultReplay(): String {
        return "board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0|board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0"
    }
}