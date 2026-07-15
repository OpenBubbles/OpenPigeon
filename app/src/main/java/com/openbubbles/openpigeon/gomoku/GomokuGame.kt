package com.openbubbles.openpigeon.gomoku

import android.content.Context
import android.graphics.Bitmap
import com.openbubbles.openpigeon.DynamicPreviewGame
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.math.roundToInt
import kotlin.math.sqrt

class GomokuGame : Game, DynamicPreviewGame {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "renju"
    }

    override fun displayName(): String {
        return "Gomoku"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.gomoku
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
            val board = extractRenderedBoard(
                map = message["map"],
                move = message["move"]
            ) ?: GomokuPreviewRenderer.defaultBoard()

            GomokuPreviewRenderer.render(
                context = context,
                flatBoard = board,
                targetWidthPx = targetWidthPx,
                targetHeightPx = targetHeightPx
            )
        } catch (e: Exception) {
            OpenPigeonLog.w(
                "GomokuGame",
                "Failed to build dynamic Gomoku preview, " +
                        "size=${targetWidthPx}x${targetHeightPx}, " +
                        "falling back to static image: ${e.message}"
            )
            null
        }
    }

    private fun extractRenderedBoard(
        map: String?,
        move: String?
    ): IntArray? {
        if (map.isNullOrBlank() && move.isNullOrBlank()) {
            return null
        }

        val dim = inferDimFromMap(map)
        val board = IntArray(dim * dim)

        if (!map.isNullOrBlank()) {
            val limit = minOf(map.length, board.size)

            for (i in 0 until limit) {
                val value = when (map[i]) {
                    '1' -> 1
                    '2' -> 2
                    else -> 0
                }

                if (value == 0) continue

                val protoRow = i / dim
                val protoCol = i % dim

                val gridRow = (dim - 1) - protoRow

                board[gridRow * dim + protoCol] = value
            }
        }

        if (!move.isNullOrBlank()) {
            val parts = move
                .split(",")
                .mapNotNull { it.trim().toIntOrNull() }

            if (parts.size >= 3) {
                val protoRow = parts[0]
                val protoCol = parts[1]
                val player = parts[2]

                val gridRow = (dim - 1) - protoRow

                if (
                    gridRow in 0 until dim &&
                    protoCol in 0 until dim &&
                    (player == 1 || player == 2)
                ) {
                    board[gridRow * dim + protoCol] = player
                } else {
                    OpenPigeonLog.w(
                        "GomokuGame",
                        "Ignoring malformed move protoRow=$protoRow protoCol=$protoCol player=$player dim=$dim"
                    )
                }
            } else {
                OpenPigeonLog.w(
                    "GomokuGame",
                    "Ignoring malformed move=$move"
                )
            }
        }

        return board
    }

    private fun inferDimFromMap(map: String?): Int {
        if (map.isNullOrBlank()) return DEFAULT_DIM

        val root = sqrt(map.length.toDouble()).roundToInt()

        return if (root * root == map.length && root in 4..32) {
            root
        } else {
            DEFAULT_DIM
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }

    private companion object {
        private const val DEFAULT_DIM = 13
    }
}