package com.openbubbles.openpigeon.gomoku

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import androidx.core.graphics.createBitmap
import com.openbubbles.openpigeon.util.OpenPigeonLog

object GomokuPreviewRenderer {
    private const val DIM = 13

    private const val PREVIEW_SIZE = 720
    private const val BOARD_SOURCE_SIZE = 1600f
    private const val GRID_SOURCE_MIN = 80f
    private const val GRID_SOURCE_MAX = 1520f
    private const val GRID_SOURCE_SPACING = 120f
    private const val BOARD_LEFT = 42f
    private const val BOARD_TOP = 42f
    private const val BOARD_SIZE = 636f
    private const val STONE_SIZE = 40f

    private val boardRect = RectF(
        BOARD_LEFT,
        BOARD_TOP,
        BOARD_LEFT + BOARD_SIZE,
        BOARD_TOP + BOARD_SIZE
    )

    private val cacheLock = Any()

    private var cachedBoard: Bitmap? = null
    private var cachedWhiteStone: Bitmap? = null
    private var cachedBlackStone: Bitmap? = null

    private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val fallbackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    fun defaultBoard(): IntArray {
        return IntArray(DIM * DIM)
    }

    fun render(
        context: Context,
        flatBoard: IntArray
    ): Bitmap {
        ensureAssetCache(context)

        val bitmap = createBitmap(PREVIEW_SIZE, PREVIEW_SIZE)
        val canvas = Canvas(bitmap)

        canvas.drawColor(Color.rgb(148, 121, 114))

        drawBoardShadow(canvas)
        drawBoard(canvas)
        drawStones(canvas, flatBoard)

        return bitmap
    }

    private fun drawBoardShadow(canvas: Canvas) {
        fallbackPaint.style = Paint.Style.FILL
        fallbackPaint.color = Color.argb(75, 0, 0, 0)

        canvas.drawRoundRect(
            RectF(
                boardRect.left + 6f,
                boardRect.top + 10f,
                boardRect.right + 6f,
                boardRect.bottom + 10f
            ),
            10f,
            10f,
            fallbackPaint
        )
    }

    private fun drawBoard(canvas: Canvas) {
        val board = cachedBoard

        if (board != null) {
            canvas.drawBitmap(board, null, boardRect, imagePaint)
            return
        }

        drawFallbackBoard(canvas)
    }

    private fun drawFallbackBoard(canvas: Canvas) {
        fallbackPaint.style = Paint.Style.FILL
        fallbackPaint.color = Color.rgb(197, 146, 93)
        canvas.drawRect(boardRect, fallbackPaint)

        fallbackPaint.style = Paint.Style.STROKE
        fallbackPaint.strokeWidth = 2.5f
        fallbackPaint.color = Color.rgb(50, 30, 15)

        for (i in 0 until DIM) {
            val p = boardCoordFromSource(GRID_SOURCE_MIN + i * GRID_SOURCE_SPACING)

            canvas.drawLine(
                boardCoordFromSource(GRID_SOURCE_MIN),
                p,
                boardCoordFromSource(GRID_SOURCE_MAX),
                p,
                fallbackPaint
            )

            canvas.drawLine(
                p,
                boardCoordFromSource(GRID_SOURCE_MIN),
                p,
                boardCoordFromSource(GRID_SOURCE_MAX),
                fallbackPaint
            )
        }

        fallbackPaint.strokeWidth = 4.5f
        canvas.drawRect(
            boardCoordFromSource(GRID_SOURCE_MIN),
            boardCoordFromSource(GRID_SOURCE_MIN),
            boardCoordFromSource(GRID_SOURCE_MAX),
            boardCoordFromSource(GRID_SOURCE_MAX),
            fallbackPaint
        )

        fallbackPaint.style = Paint.Style.FILL
        fallbackPaint.color = Color.rgb(18, 18, 18)

        val starPoints = arrayOf(
            3 to 3,
            9 to 3,
            6 to 6,
            3 to 9,
            9 to 9
        )

        for ((x, y) in starPoints) {
            canvas.drawCircle(
                boardCoordFromSource(GRID_SOURCE_MIN + x * GRID_SOURCE_SPACING),
                boardCoordFromSource(GRID_SOURCE_MIN + y * GRID_SOURCE_SPACING),
                5.5f,
                fallbackPaint
            )
        }
    }

    private fun drawStones(
        canvas: Canvas,
        flatBoard: IntArray
    ) {
        for (row in 0 until DIM) {
            for (col in 0 until DIM) {
                val index = row * DIM + col
                val value = flatBoard.getOrElse(index) { 0 }

                if (value != 1 && value != 2) continue

                val centerX = boardCoordFromSource(
                    GRID_SOURCE_MIN + col * GRID_SOURCE_SPACING
                )

                val centerY = boardCoordFromSource(
                    GRID_SOURCE_MIN + row * GRID_SOURCE_SPACING
                )

                val dest = RectF(
                    centerX - STONE_SIZE / 2f,
                    centerY - STONE_SIZE / 2f,
                    centerX + STONE_SIZE / 2f,
                    centerY + STONE_SIZE / 2f
                )

                val stoneBitmap = when (value) {
                    1 -> cachedWhiteStone
                    2 -> cachedBlackStone
                    else -> null
                }

                if (stoneBitmap != null) {
                    canvas.drawBitmap(stoneBitmap, null, dest, imagePaint)
                } else {
                    drawFallbackStone(canvas, dest, value)
                }
            }
        }
    }

    private fun drawFallbackStone(
        canvas: Canvas,
        dest: RectF,
        value: Int
    ) {
        val isWhite = value == 1

        fallbackPaint.style = Paint.Style.FILL
        fallbackPaint.color = Color.argb(75, 0, 0, 0)
        canvas.drawOval(
            RectF(
                dest.left + 3f,
                dest.top + 4f,
                dest.right + 3f,
                dest.bottom + 4f
            ),
            fallbackPaint
        )

        fallbackPaint.color = if (isWhite) {
            Color.rgb(242, 239, 232)
        } else {
            Color.rgb(30, 30, 30)
        }
        canvas.drawOval(dest, fallbackPaint)

        fallbackPaint.style = Paint.Style.STROKE
        fallbackPaint.strokeWidth = 1.8f
        fallbackPaint.color = if (isWhite) {
            Color.rgb(180, 176, 168)
        } else {
            Color.rgb(80, 80, 80)
        }
        canvas.drawOval(dest, fallbackPaint)

        fallbackPaint.style = Paint.Style.FILL
    }

    private fun ensureAssetCache(context: Context) {
        if (
            cachedBoard != null &&
            cachedWhiteStone != null &&
            cachedBlackStone != null
        ) {
            return
        }

        synchronized(cacheLock) {
            if (
                cachedBoard != null &&
                cachedWhiteStone != null &&
                cachedBlackStone != null
            ) {
                return
            }

            cachedBoard = loadAssetBitmap(
                context,
                "gomoku/12x12_board_gomoku.png",
                "12x12_board_gomoku.png"
            )

            val sourceStone = loadAssetBitmap(
                context,
                "gomoku/gomoku_tile.png",
                "gomoku_tile.png"
            )

            if (sourceStone != null) {
                cachedWhiteStone = sourceStone
                cachedBlackStone = makeBlackStone(sourceStone)
            }
        }
    }

    private fun boardCoordFromSource(sourceCoord: Float): Float {
        return BOARD_LEFT + (sourceCoord / BOARD_SOURCE_SIZE) * BOARD_SIZE
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
                            "GomokuPreview",
                            "Loaded Gomoku preview asset from $path"
                        )
                        return bitmap
                    }
                }
            } catch (_: Exception) {
                // Try next path.
            }
        }

        OpenPigeonLog.w(
            "GomokuPreview",
            "Could not load Gomoku preview asset from paths=${paths.joinToString()}"
        )

        return null
    }

    private fun makeBlackStone(source: Bitmap): Bitmap {
        val src = source.copy(Bitmap.Config.ARGB_8888, false)
        val width = src.width
        val height = src.height

        val pixels = IntArray(width * height)
        src.getPixels(pixels, 0, width, 0, 0, width, height)

        for (i in pixels.indices) {
            val color = pixels[i]
            val alpha = Color.alpha(color)

            if (alpha == 0) continue

            val r = Color.red(color)
            val g = Color.green(color)
            val b = Color.blue(color)

            val lum = (
                    0.2126f * r.toFloat() +
                            0.7152f * g.toFloat() +
                            0.0722f * b.toFloat()
                    ) / 255f

            val highlightT = ((lum - 0.88f) / 0.12f).coerceIn(0f, 1f)
            val highlightSmooth = highlightT * highlightT * (3f - 2f * highlightT)

            val shade = (
                    14f +
                            lum * 34f +
                            highlightSmooth * 90f
                    ).toInt().coerceIn(0, 255)

            pixels[i] =
                (alpha shl 24) or
                        (shade shl 16) or
                        (shade shl 8) or
                        shade
        }

        val out = createBitmap(width, height)
        out.setPixels(pixels, 0, width, 0, 0, width, height)
        return out
    }
}