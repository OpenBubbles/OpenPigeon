package com.example.openbubblesextension.pool

import android.content.Context
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import com.example.openbubblesextension.godot.GodotGameActivity

class PoolGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "pool"
    }

    override fun displayName(): String {
        return "8 Ball"
    }

    override fun buttonId(): Int {
        return R.id.btn_8_ball
    }

    override fun gameClass(): Class<*> {
        return PoolActivity::class.java
    }

    override fun gamePoster(): Int {
        return R.drawable.pool_image
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            // mode h for hard
            put("mode", "n")
            put("v2", "2")
            put("v3", "2")
            put("v4", "2")
            put("v5", "2")
        }
    }

    override fun getDefaultReplay(): String {
        return "board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0|board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0"
    }
}