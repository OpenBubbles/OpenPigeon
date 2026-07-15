package com.openbubbles.openpigeon.chess

import android.content.Context
import android.graphics.Bitmap
import com.openbubbles.openpigeon.DynamicPreviewGame
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog

class ChessGame : Game, DynamicPreviewGame {
    override fun getVersion(): String = "1"

    override fun getName(): String = "chess"

    override fun displayName(): String = "Chess"

    override fun gameClass(): Class<*> = GodotGameActivity::class.java

    override fun gamePoster(config: Map<String, String>?): Int = R.drawable.chess

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)

        return super.getNewGameData(context)?.apply {
            put("replay", getDefaultReplay())
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
            targetWidthPx = 384,
            targetHeightPx = 384
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
            val replay = message["replay"].orEmpty()
            val flipBoard = shouldFlipBoardForPreview(message)

            ChessPreviewRenderer.render(
                context = context,
                replay = replay.ifBlank { getDefaultReplay() },
                flipBoard = flipBoard,
                targetWidthPx = targetWidthPx,
                targetHeightPx = targetHeightPx
            )
        } catch (e: Exception) {
            OpenPigeonLog.w(
                "ChessGame",
                "Failed to build dynamic Chess preview, " +
                        "size=${targetWidthPx}x${targetHeightPx}, " +
                        "falling back to static image: ${e.message}"
            )
            null
        }
    }

    private fun shouldFlipBoardForPreview(message: Map<String, String>): Boolean {
        val messagePlayer = message["player"]?.toIntOrNull()?.coerceIn(1, 2) ?: 2
        val isYourTurn = parseBoolean(message["isYourTurn"])

        val myPlayerIndex = if (isYourTurn) {
            messagePlayer
        } else {
            3 - messagePlayer
        }

        return myPlayerIndex == 1
    }

    private fun parseBoolean(value: String?): Boolean {
        return value.equals("true", ignoreCase = true) ||
                value == "1" ||
                value.equals("yes", ignoreCase = true)
    }

    override fun getDefaultReplay(): String {
        return "board:12,13,14,15,16,14,13,12,11,11,11,11,11,11,11,11,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,21,21,21,21,21,21,21,21,22,23,24,25,26,24,23,22"
    }
}