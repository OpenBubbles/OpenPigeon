package com.example.openbubblesextension.checkers

import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
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
        TODO("Not yet implemented")
    }

    override fun gamePoster(): Int {
        return R.drawable.empty
    }

    override fun getNewGameData(): JSONObject {
        return super.getNewGameData().apply {
            put("mode", "n")
        }
    }
}