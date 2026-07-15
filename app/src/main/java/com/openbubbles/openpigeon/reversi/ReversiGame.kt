package com.openbubbles.openpigeon.reversi

import android.content.Context
import android.graphics.Bitmap
import com.openbubbles.openpigeon.DynamicPreviewGame
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog

class ReversiGame : Game, DynamicPreviewGame {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "reversi"
    }

    override fun displayName(): String {
        return "Reversi"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.reversi
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)

        return super.getNewGameData(context)?.apply {
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun gamePreviewBitmap(
        context: Context,
        message: Map<String, String>
    ): Bitmap? {
        return buildPreview(
            context = context,
            message = message,
            targetWidthPx = 720,
            targetHeightPx = 720
        )
    }

    override fun gamePreviewBitmap(
        context: Context,
        message: Map<String, String>,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap? {
        return buildPreview(
            context = context,
            message = message,
            targetWidthPx = targetWidthPx,
            targetHeightPx = targetHeightPx
        )
    }

    private fun buildPreview(
        context: Context,
        message: Map<String, String>,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap? {
        return try {
            val board = extractLatestReplayBoard(message["replay"])
                ?: ReversiPreviewRenderer.defaultBoard()

            ReversiPreviewRenderer.render(
                context = context,
                flatBoard = board,
                targetWidthPx = targetWidthPx,
                targetHeightPx = targetHeightPx
            )
        } catch (e: Exception) {
            OpenPigeonLog.w(
                "ReversiGame",
                "Failed to build dynamic Reversi preview, " +
                        "size=${targetWidthPx}x${targetHeightPx}, " +
                        "falling back to static image",
                e
            )
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
            .mapNotNull { it.trim().toIntOrNull() }

        return if (values.size == 64) {
            values.toIntArray()
        } else {
            OpenPigeonLog.w(
                "ReversiGame",
                "Ignoring malformed replay board. Expected 64 cells, got ${values.size}"
            )
            null
        }
    }

    override fun getDefaultReplay(): String {
        return "board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,1,0,0,0,0,0,0,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0|move:3,1,2|board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,1,0,0,0,0,0,0,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"
    }
}