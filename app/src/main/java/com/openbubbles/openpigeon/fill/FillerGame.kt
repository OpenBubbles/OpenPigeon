package com.openbubbles.openpigeon.fill

import android.content.Context
import android.graphics.Bitmap
import com.openbubbles.openpigeon.util.OpenPigeonLog
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import kotlin.random.Random
import com.openbubbles.openpigeon.DynamicPreviewGame

class FillerGame : Game, DynamicPreviewGame {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "fill"
    }

    override fun displayName(): String {
        return "Filler"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.filler
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)

        return super.getNewGameData(context)?.apply {
            val seed = Random.nextInt()

            put("seed", seed.toString())
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun gamePreviewBitmap(context: Context, message: Map<String, String>): Bitmap? {
        return try {
            val player = message["player"]?.toIntOrNull() ?: 2

            val replayBoard = extractLatestReplayBoard(message["replay"])
            if (replayBoard != null) {
                FillerPreviewRenderer.renderBoard(replayBoard, player)
            } else {
                val seed = message["seed"]?.toIntOrNull() ?: return null
                FillerPreviewRenderer.render(seed, player)
            }
        } catch (e: Exception) {
            OpenPigeonLog.w("FillerGame", "Failed to build dynamic Filler preview, falling back to static image", e)
            null
        }
    }

    private fun extractLatestReplayBoard(replay: String?): IntArray? {
        if (replay.isNullOrBlank()) return null

        val latestBoardPart = replay
            .split("|")
            .lastOrNull { it.startsWith("board:") }
            ?: return null

        val values = latestBoardPart
            .removePrefix("board:")
            .split(",")
            .mapNotNull { it.toIntOrNull() }

        return if (values.size == 56) values.toIntArray() else null
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}