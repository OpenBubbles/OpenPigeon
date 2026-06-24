package com.openbubbles.openpigeon.golf

import android.content.Context
import androidx.compose.runtime.Composable
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.random.Random

class GolfGame : Game {
    companion object {
        private const val TAG = "GolfNative"
    }

    /** The iOS game supports 3-hole and 5-hole matches. Board generation is the same sequence. */
    var holes: Int = 3

    override fun getVersion(): String = "1"
    override fun getName(): String = "golf"
    override fun displayName(): String = "Mini Golf"
    override fun isConfigurable(): Boolean = true

    override fun gameClass(): Class<*> {
        OpenPigeonLog.i(TAG, "GolfGame.gameClass requested")
        return GolfActivity::class.java
    }

    @Composable
    override fun Configuration(context: Context?) {
        context?.let { OpenPigeonLog.installContext(it) }
        OpenPigeonLog.i(TAG, "GolfGame.Configuration holes=$holes contextNull=${context == null}")
        RenderConfigOption(this, "Holes", listOf("3", "5"), holes.toString())
    }

    override fun setConfigOption(name: String, value: String) {
        OpenPigeonLog.i(TAG, "GolfGame.setConfigOption name=$name value=$value previousHoles=$holes")
        if (name == "Holes") holes = value.toIntOrNull()?.coerceIn(3, 5) ?: 3
        OpenPigeonLog.i(TAG, "GolfGame.setConfigOption result holes=$holes")
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        OpenPigeonLog.i(TAG, "GolfGame.gamePoster configKeys=${config?.keys?.sorted().orEmpty()}")
        return android.R.drawable.ic_menu_compass
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        OpenPigeonLog.installContext(context)
        OpenPigeonLog.i(TAG, "GolfGame.getNewGameData enter holes=$holes")
        return super.getNewGameData(context)?.apply {
            put("game", getName())
            put("game_name", displayName())
            put("mode", holes.toString())
            put("seed", Random.nextInt().toString())
            put("num", "1")
            put("player", "1")
            put("replay", "")
            put("replay2", "")
            put("caption", "Let's play Mini Golf!")
            put("subcaption", "$holes Holes")
            OpenPigeonLog.i(TAG, "GolfGame.getNewGameData output keys=${keys.sorted()} mode=${get("mode")} seed=${get("seed")} num=${get("num")}")
        }
    }

    override fun getDefaultReplay(): String {
        OpenPigeonLog.i(TAG, "GolfGame.getDefaultReplay")
        return ""
    }
}
