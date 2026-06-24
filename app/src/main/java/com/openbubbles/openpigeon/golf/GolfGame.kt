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

    override fun getVersion(): String = "41"
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
            val holeText = when (holes) {
                5 -> "5"
                else -> "3"
            }

            put("game", "golf")
            put("game_name", "Mini Golf")
            put("caption", "Let's play Mini Golf!")
            put("subcaption", "$holeText Holes")

            /*
             * Match iOS Mini Golf new-game metadata.
             * iOS sends version=41 and v3=3 for current Mini Golf messages.
             */
            put("version", "41")
            put("v3", "3")

            put("mode", holeText)
            put("seed", Random.nextInt().toString())
            put("num", "1")

            /*
             * Important:
             * iOS new Mini Golf messages are created as player 2 with sender/player2/avatar2.
             * Our previous player=1 conflicted with the player2/avatar2 fields from the base message.
             */
            put("player", "2")

            /*
             * iOS new-game payload does not need empty replay fields.
             * Do not send blank replay strings unless there is an actual replay.
             */
            remove("replay")
            remove("replay2")

            /*
             * Your captured Android payload had a newline in id. iOS id has no newline.
             * Trim any base-generated value so it cannot poison iOS parsing.
             */
            get("id")?.trim()?.takeIf { it.isNotBlank() }?.let { put("id", it) }

            OpenPigeonLog.i(
                TAG,
                "GolfGame.getNewGameData output keys=${keys.sorted()} " +
                        "version=${get("version")} v3=${get("v3")} " +
                        "player=${get("player")} player2Blank=${get("player2").isNullOrBlank()} " +
                        "mode=${get("mode")} seed=${get("seed")} num=${get("num")} " +
                        "id='${get("id").orEmpty()}'"
            )
        }
    }

    override fun getDefaultReplay(): String {
        OpenPigeonLog.i(TAG, "GolfGame.getDefaultReplay")
        return ""
    }
}
