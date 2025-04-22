package com.example.openbubblesextension.wordhunt

import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import org.json.JSONObject

class WordHuntGame : Game {
    override fun getName(): String {
        return "hunt"
    }

    override fun buttonId(): Int {
        return R.id.btn_wordhunt
    }

    override fun gameClass(): Class<*> {
        return WordHuntActivity::class.java
    }

    override fun gamePoster(): Int {
        return R.drawable.wordhunt
    }

    override fun displayName(): String {
        return "Word Hunt"
    }

    override fun getVersion(): String {
        return "47"
    }

    override fun getNewGameData(): MutableMap<String, String> {
        return super.getNewGameData().apply {
            put("letters", WordHuntActivity.generateLetterPool().joinToString(""))
            put("lang", "en")
        }
    }
}