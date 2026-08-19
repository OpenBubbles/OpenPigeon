package com.openbubbles.openpigeon.checkers

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import com.openbubbles.openpigeon.DynamicPreviewGame
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog

class CheckersGame : Game, DynamicPreviewGame {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "checkers"
    }

    override fun displayName(): String {
        return "Checkers"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    var mode = "Checkers"

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        RenderConfigOption(
            game = this,
            name = "Game Mode",
            options = listOf("Checkers", "Newbie Checkers"),
            selected = mode,
        )
    }

    override fun playName(): String {
        return mode
    }

    override fun setConfigOption(name: String, value: String) {
        mode = value
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.checkers
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)

        return super.getNewGameData(context)?.apply {
            put("mode", if (mode == "Checkers") "n" else "h")
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
                ?: CheckersPreviewRenderer.defaultBoard()

            val previewPlayer = message["player"]?.toIntOrNull() ?: 1

            CheckersPreviewRenderer.render(
                context = context,
                flatBoard = board,
                previewPlayer = previewPlayer,
                targetWidthPx = targetWidthPx,
                targetHeightPx = targetHeightPx
            )
        } catch (e: Exception) {
            OpenPigeonLog.w(
                "CheckersGame",
                "Failed to build dynamic Checkers preview, " +
                        "size=${targetWidthPx}x${targetHeightPx}, " +
                        "falling back to static image: ${e.message}"
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
                "CheckersGame",
                "Ignoring malformed replay board. Expected 64 cells, got ${values.size}"
            )
            null
        }
    }

    override fun getDefaultReplay(): String {
        return "board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0|board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0"
    }
}