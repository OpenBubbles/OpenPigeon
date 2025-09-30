package com.openbubbles.openpigeon.chess

import android.content.Context
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity

class ChessGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "chess"
    }

    override fun displayName(): String {
        return "Chess"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    // Reuse the checkers poster until a dedicated chess image is added
    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.chess
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            // Placeholder options for parity with other games
            putIfAbsent("mode", "n")
        }
    }

    override fun getDefaultReplay(): String {
        // No predefined replay for Chess yet
        return ""
    }
}
