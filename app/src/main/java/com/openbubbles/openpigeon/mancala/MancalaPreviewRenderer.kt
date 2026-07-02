package com.openbubbles.openpigeon.mancala

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RectF
import androidx.core.graphics.createBitmap
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

object MancalaPreviewRenderer {
    private const val PIT_COUNT = 14

    private const val PREVIEW_SIZE = 720
    private const val OUTPUT_SIZE = 384

    private const val BOARD_SOURCE_WIDTH = 350f
    private const val BOARD_SOURCE_HEIGHT = 800f

    private const val BOARD_DRAW_HEIGHT = 688f
    private const val BOARD_DRAW_WIDTH = BOARD_DRAW_HEIGHT * (712f / 2048f)
    private const val BOARD_LEFT = (PREVIEW_SIZE - BOARD_DRAW_WIDTH) / 2f
    private const val BOARD_TOP = 16f

    private const val STONE_DRAW_SIZE = 20f
    private const val MAX_VISIBLE_STONES_PER_PIT = 14

    private const val GOLDEN_ANGLE = 2.3999632f

    private val boardRect = RectF(
        BOARD_LEFT,
        BOARD_TOP,
        BOARD_LEFT + BOARD_DRAW_WIDTH,
        BOARD_TOP + BOARD_DRAW_HEIGHT
    )

    private val cacheLock = Any()
    private var attemptedAssetLoad = false

    private var boardBitmap: Bitmap? = null
    private var stoneBitmap: Bitmap? = null

    private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val downsamplePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private class ParsedBoard(
        val pits: List<List<Int>>
    )

    fun render(
        context: Context,
        replay: String?,
        previewPlayer: Int
    ): Bitmap {
        ensureAssetCache(context)

        val board = parseLatestBoard(replay)
        val player = previewPlayer.coerceIn(1, 2)

        val bitmap = createBitmap(
            PREVIEW_SIZE,
            PREVIEW_SIZE,
            Bitmap.Config.ARGB_8888
        )

        val canvas = Canvas(bitmap)

        canvas.drawColor(Color.rgb(132, 106, 92))

        drawBoard(canvas)
        drawPits(canvas, board, player)

        return compactForRemoteViews(bitmap)
    }

    private fun drawBoard(canvas: Canvas) {
        val board = boardBitmap

        if (board != null) {
            canvas.drawBitmap(board, null, boardRect, imagePaint)
        } else {
            fillPaint.style = Paint.Style.FILL
            fillPaint.color = Color.rgb(225, 166, 78)
            canvas.drawRoundRect(boardRect, 20f, 20f, fillPaint)
        }
    }

    private fun drawPits(
        canvas: Canvas,
        board: ParsedBoard,
        previewPlayer: Int
    ) {
        val offsets = offsetsForPlayer(previewPlayer)

        for (pitIndex in 0 until PIT_COUNT) {
            val stones = board.pits.getOrElse(pitIndex) { emptyList() }
            val center = offsets[pitIndex]

            drawPitStones(
                canvas = canvas,
                pitIndex = pitIndex,
                sourceCenterX = center.first,
                sourceCenterY = center.second,
                stones = stones
            )
        }
    }

    private fun drawPitStones(
        canvas: Canvas,
        pitIndex: Int,
        sourceCenterX: Float,
        sourceCenterY: Float,
        stones: List<Int>
    ) {
        if (stones.isEmpty()) return

        val visibleCount = min(stones.size, MAX_VISIBLE_STONES_PER_PIT)
        val centerX = mapSourceX(sourceCenterX)
        val centerY = mapSourceY(sourceCenterY)

        val isStore = pitIndex == 6 || pitIndex == 13
        val radiusX = if (isStore) {
            mapSourceWidth(56f)
        } else {
            mapSourceWidth(28f)
        }

        val radiusY = if (isStore) {
            mapSourceHeight(22f)
        } else {
            mapSourceHeight(28f)
        }

        for (i in 0 until visibleCount) {
            val stoneLabel = stones[i]

            val t = (i + 0.5f) / visibleCount.toFloat()
            val radial = sqrt(t) * 0.78f
            val angle = GOLDEN_ANGLE * i.toFloat()

            val x = centerX + cos(angle) * radiusX * radial
            val y = centerY + sin(angle) * radiusY * radial

            drawStone(
                canvas = canvas,
                centerX = x,
                centerY = y,
                label = stoneLabel,
                rotationDegrees = (stoneLabel * 37 + i * 29) % 360
            )
        }
    }

    private fun drawStone(
        canvas: Canvas,
        centerX: Float,
        centerY: Float,
        label: Int,
        rotationDegrees: Int
    ) {
        val stone = stoneBitmap

        val shadowRect = RectF(
            centerX - STONE_DRAW_SIZE / 2f + 2.5f,
            centerY - STONE_DRAW_SIZE / 2f + 3f,
            centerX + STONE_DRAW_SIZE / 2f + 2.5f,
            centerY + STONE_DRAW_SIZE / 2f + 3f
        )

        fillPaint.style = Paint.Style.FILL
        fillPaint.color = Color.argb(70, 0, 0, 0)
        canvas.drawOval(shadowRect, fillPaint)

        val dest = RectF(
            centerX - STONE_DRAW_SIZE / 2f,
            centerY - STONE_DRAW_SIZE / 2f,
            centerX + STONE_DRAW_SIZE / 2f,
            centerY + STONE_DRAW_SIZE / 2f
        )

        if (stone != null) {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                isFilterBitmap = true
                isDither = true
                colorFilter = PorterDuffColorFilter(
                    stoneColor(label),
                    PorterDuff.Mode.SRC_IN
                )
            }

            canvas.save()
            canvas.rotate(rotationDegrees.toFloat(), centerX, centerY)
            canvas.drawBitmap(stone, null, dest, paint)
            canvas.restore()
        } else {
            fillPaint.color = stoneColor(label)
            canvas.drawOval(dest, fillPaint)
        }
    }

    private fun parseLatestBoard(replay: String?): ParsedBoard {
        val latestBoard = replay
            ?.split("|")
            ?.lastOrNull { it.startsWith("board:") }
            ?.removePrefix("board:")

        return parseBoardString(latestBoard)
    }

    private fun parseBoardString(boardString: String?): ParsedBoard {
        val pits = MutableList(PIT_COUNT) { mutableListOf<Int>() }

        if (boardString.isNullOrBlank()) {
            return ParsedBoard(pits)
        }

        val chunks = boardString.split("&")

        for (i in 0 until min(chunks.size, PIT_COUNT)) {
            val chunk = chunks[i].trim()

            if (chunk.isEmpty()) continue

            val labels = chunk
                .split(",")
                .mapNotNull { it.trim().toIntOrNull() }

            pits[i].addAll(labels)
        }

        return ParsedBoard(pits)
    }

    private fun offsetsForPlayer(player: Int): List<Pair<Float, Float>> {
        return if (player == 2) {
            listOf(
                223f to 629.5f,
                223f to 537.5f,
                223f to 446.5f,
                223f to 355.5f,
                223f to 262.5f,
                223f to 171.5f,
                170f to 75.5f,
                125f to 171.5f,
                125f to 262.5f,
                125f to 355.5f,
                125f to 446.5f,
                125f to 537.5f,
                125f to 629.5f,
                170f to 723.5f
            )
        } else {
            listOf(
                125f to 171.5f,
                125f to 262.5f,
                125f to 355.5f,
                125f to 446.5f,
                125f to 537.5f,
                125f to 629.5f,
                170f to 723.5f,
                223f to 629.5f,
                223f to 537.5f,
                223f to 446.5f,
                223f to 355.5f,
                223f to 262.5f,
                223f to 171.5f,
                170f to 75.5f
            )
        }
    }

    private fun mapSourceX(sourceX: Float): Float {
        return boardRect.left + (sourceX / BOARD_SOURCE_WIDTH) * boardRect.width()
    }

    private fun mapSourceY(sourceY: Float): Float {
        return boardRect.top + (sourceY / BOARD_SOURCE_HEIGHT) * boardRect.height()
    }

    private fun mapSourceWidth(sourceWidth: Float): Float {
        return (sourceWidth / BOARD_SOURCE_WIDTH) * boardRect.width()
    }

    private fun mapSourceHeight(sourceHeight: Float): Float {
        return (sourceHeight / BOARD_SOURCE_HEIGHT) * boardRect.height()
    }

    private fun stoneColor(label: Int): Int {
        return when (label) {
            1, 11 -> Color.rgb(255, 252, 242)
            2, 12 -> Color.rgb(65, 72, 81)
            3, 13 -> Color.rgb(23, 108, 171)
            else -> Color.rgb(245, 245, 245)
        }
    }

    private fun compactForRemoteViews(source: Bitmap): Bitmap {
        val output = createBitmap(
            OUTPUT_SIZE,
            OUTPUT_SIZE,
            Bitmap.Config.RGB_565
        )

        val canvas = Canvas(output)

        canvas.drawBitmap(
            source,
            null,
            RectF(
                0f,
                0f,
                OUTPUT_SIZE.toFloat(),
                OUTPUT_SIZE.toFloat()
            ),
            downsamplePaint
        )

        return output
    }

    private fun ensureAssetCache(context: Context) {
        if (attemptedAssetLoad) {
            return
        }

        synchronized(cacheLock) {
            if (attemptedAssetLoad) {
                return
            }

            boardBitmap = loadAssetBitmap(
                context,
                "mancala/board.png",
                "assets/mancala/board.png",
                "board.png"
            )

            stoneBitmap = loadAssetBitmap(
                context,
                "mancala/stone.png",
                "assets/mancala/stone.png",
                "stone.png"
            )?.let {
                trimTransparentPadding(it)
            }

            OpenPigeonLog.i(
                "MancalaPreview",
                "Mancala preview assets board=${boardBitmap != null} stone=${stoneBitmap != null}"
            )

            attemptedAssetLoad = true
        }
    }

    private fun loadAssetBitmap(
        context: Context,
        vararg paths: String
    ): Bitmap? {
        for (path in paths) {
            try {
                context.assets.open(path).use { stream ->
                    val bitmap = BitmapFactory.decodeStream(stream)

                    if (bitmap != null) {
                        OpenPigeonLog.i(
                            "MancalaPreview",
                            "Loaded Mancala preview asset from $path"
                        )
                        return bitmap
                    }
                }
            } catch (_: Exception) {
                // Try the next path.
            }
        }

        OpenPigeonLog.w(
            "MancalaPreview",
            "Could not load Mancala preview asset from paths=${paths.joinToString()}"
        )

        return null
    }

    private fun trimTransparentPadding(source: Bitmap): Bitmap {
        val bitmap = if (source.config == Bitmap.Config.ARGB_8888) {
            source
        } else {
            source.copy(Bitmap.Config.ARGB_8888, false)
        }

        val width = bitmap.width
        val height = bitmap.height

        if (width <= 1 || height <= 1) {
            return bitmap
        }

        val pixels = IntArray(width * height)

        bitmap.getPixels(
            pixels,
            0,
            width,
            0,
            0,
            width,
            height
        )

        var left = width
        var top = height
        var right = -1
        var bottom = -1

        for (y in 0 until height) {
            for (x in 0 until width) {
                val alpha = Color.alpha(pixels[y * width + x])

                if (alpha > 8) {
                    if (x < left) left = x
                    if (x > right) right = x
                    if (y < top) top = y
                    if (y > bottom) bottom = y
                }
            }
        }

        if (right < left || bottom < top) {
            return bitmap
        }

        val cropWidth = right - left + 1
        val cropHeight = bottom - top + 1

        if (
            cropWidth == width &&
            cropHeight == height
        ) {
            return bitmap
        }

        val pad = min(width, height) * 0.04f
        val padInt = pad.toInt().coerceAtLeast(1)

        val paddedLeft = (left - padInt).coerceAtLeast(0)
        val paddedTop = (top - padInt).coerceAtLeast(0)
        val paddedRight = (right + padInt).coerceAtMost(width - 1)
        val paddedBottom = (bottom + padInt).coerceAtMost(height - 1)

        val outWidth = paddedRight - paddedLeft + 1
        val outHeight = paddedBottom - paddedTop + 1

        return Bitmap.createBitmap(
            bitmap,
            paddedLeft,
            paddedTop,
            outWidth,
            outHeight
        )
    }
}