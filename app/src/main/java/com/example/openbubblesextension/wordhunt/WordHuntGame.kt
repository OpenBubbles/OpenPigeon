package com.example.openbubblesextension.wordhunt

import android.content.Context
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R

class WordHuntGame : Game {
    val mode = 1 // Mode 1: 4x4, Mode 2: 5x5 circle shape, Mode 3: 5x5 X shape, Mode 4: 5x5
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
        return when (mode) {
            1 -> R.drawable.wordhunt
            2 -> R.drawable.wordhunt_2
            3 -> R.drawable.wordhunt_3
            4 -> R.drawable.wordhunt_4
            else -> {R.drawable.empty}
        }
    }

    override fun displayName(): String {
        return "Word Hunt"
    }

    override fun getVersion(): String {
        return "47"
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            put("letters", WordHuntActivity.generateLetterPool(WordHuntActivity.mode(mode)).joinToString(""))
            put("lang", "gp_en2")
            put("avatar2", "body,1|eyes,0|mouth,2|acc,0|wins,65|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,3|stache,0|backdrop,7|hair,0|clothes,3|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021")
            put("mode", "$mode")
        }
    }

    override fun getDefaultReplay(): String {
        TODO("Not yet implemented")
    }
}
