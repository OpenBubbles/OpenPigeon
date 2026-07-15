package com.openbubbles.openpigeon.dots

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.layout.Box
import androidx.glance.layout.padding
import com.openbubbles.openpigeon.DynamicPreviewGame
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog

class DotsGame : Game, DynamicPreviewGame {
    override fun getVersion(): String {
        return "0"
    }

    override fun getName(): String {
        return "dots"
    }

    override fun displayName(): String {
        return "Dots"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    var boardsize = "4x4"

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(
                this,
                "Board Size",
                listOf("4x4", "5x5", "6x6"),
                boardsize
            )
        }
    }

    override fun setConfigOption(name: String, value: String) {
        boardsize = value
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        val size = config?.get("size")

        return when (size) {
            "4" -> R.drawable.dots4x4
            "5" -> R.drawable.dots5x5
            "6" -> R.drawable.dots6x6
            else -> R.drawable.dots4x4
        }
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)

        return super.getNewGameData(context)?.apply {
            put(
                "size",
                when (boardsize) {
                    "4x4" -> "4"
                    "5x5" -> "5"
                    "6x6" -> "6"
                    else -> "4"
                }
            )

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
            targetWidthPx = 320,
            targetHeightPx = 320
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
            val boardSize = resolveBoardSize(message)

            DotsPreviewRenderer.render(
                context = context,
                replay = message["replay"],
                boardSize = boardSize,
                targetWidthPx = targetWidthPx,
                targetHeightPx = targetHeightPx
            )
        } catch (e: Exception) {
            OpenPigeonLog.w(
                "DotsGame",
                "Failed to build dynamic Dots preview, " +
                        "size=${targetWidthPx}x${targetHeightPx}, " +
                        "falling back to static image: ${e.message}"
            )
            null
        }
    }

    private fun resolveBoardSize(message: Map<String, String>): Int {
        val directSize = message["size"]?.toIntOrNull()
        if (directSize != null) {
            return directSize.coerceIn(4, 6)
        }

        val boardSizeName = message["boardsize"]
            ?.substringBefore("x")
            ?.toIntOrNull()

        if (boardSizeName != null) {
            return boardSizeName.coerceIn(4, 6)
        }

        return boardsize
            .substringBefore("x")
            .toIntOrNull()
            ?.coerceIn(4, 6)
            ?: 4
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}