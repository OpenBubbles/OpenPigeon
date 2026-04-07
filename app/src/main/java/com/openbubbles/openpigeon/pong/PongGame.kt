package com.openbubbles.openpigeon.pong

import android.content.Context
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import kotlin.random.Random

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
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.cuppong
    }

    override fun isSupported(message: Map<String, String>): Boolean {
        return message["mode"] != "h"
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)
        return super.getNewGameData(context)?.apply {
            put("seed", "${Random.nextInt()}")
            put("mode", "n")
            put("style2", "0")
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}