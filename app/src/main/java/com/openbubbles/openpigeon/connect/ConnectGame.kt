package com.openbubbles.openpigeon.connect

import android.content.Context
import android.graphics.Bitmap
import com.openbubbles.openpigeon.DynamicPreviewGame
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog

class ConnectGame : Game, DynamicPreviewGame {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "connect"
    }

    override fun displayName(): String {
        return "Four in a Row"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.connect4
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
            val board = extractRenderedBoard(message["replay"])
                ?: ConnectPreviewRenderer.defaultBoard()

            ConnectPreviewRenderer.render(
                context = context,
                flatBoard = board,
                targetWidthPx = targetWidthPx,
                targetHeightPx = targetHeightPx
            )
        } catch (e: Exception) {
            OpenPigeonLog.w(
                "ConnectGame",
                "Failed to build dynamic Four in a Row preview, " +
                        "size=${targetWidthPx}x${targetHeightPx}, " +
                        "falling back to static image: ${e.message}"
            )
            null
        }
    }

    private fun extractRenderedBoard(replay: String?): IntArray? {
        if (replay.isNullOrBlank()) return null

        val board = IntArray(BOARD_W * BOARD_H)
        var foundBoard = false

        val parts = replay.split("|")

        for (part in parts) {
            when {
                part.startsWith("board:") -> {
                    val values = part
                        .removePrefix("board:")
                        .split(",")
                        .mapNotNull { it.trim().toIntOrNull() }

                    if (values.size >= BOARD_W * BOARD_H) {
                        for (i in 0 until BOARD_W * BOARD_H) {
                            board[i] = values[i]
                        }
                        foundBoard = true
                    } else {
                        OpenPigeonLog.w(
                            "ConnectGame",
                            "Ignoring malformed board. Expected 42 cells, got ${values.size}"
                        )
                    }
                }

                part.startsWith("move:") -> {
                    if (!foundBoard) continue

                    val move = part
                        .removePrefix("move:")
                        .split(",")
                        .mapNotNull { it.trim().toIntOrNull() }

                    if (move.size >= 3) {
                        val x = move[0]
                        val y = move[1]
                        val pid = move[2]

                        if (
                            x in 0 until BOARD_W &&
                            y in 0 until BOARD_H &&
                            (pid == 1 || pid == 2)
                        ) {
                            board[y * BOARD_W + x] = pid
                        } else {
                            OpenPigeonLog.w(
                                "ConnectGame",
                                "Ignoring malformed move x=$x y=$y pid=$pid"
                            )
                        }
                    } else {
                        OpenPigeonLog.w(
                            "ConnectGame",
                            "Ignoring malformed move part=$part"
                        )
                    }
                }
            }
        }

        return if (foundBoard) board else null
    }

    override fun getDefaultReplay(): String {
        return "board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"
    }

    private companion object {
        private const val BOARD_W = 7
        private const val BOARD_H = 6
    }
}