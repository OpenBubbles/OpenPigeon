package com.openbubbles.openpigeon.basketball

import android.content.Context
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import kotlin.random.Random

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

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.basketball
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)
        return super.getNewGameData(context)?.apply {
            put("mode", "n")
            put("skip_score1", "0")
            put("skip_score2", "0")
            put("score1", "0")
            put("score2", "0")
            put("seed", "${Random.nextInt()}")
            put("seed2", "${Random.nextInt()}")
            put("round", "1")
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun isSupported(message: Map<String, String>): Boolean {
        return message["mode"] != "h"
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}