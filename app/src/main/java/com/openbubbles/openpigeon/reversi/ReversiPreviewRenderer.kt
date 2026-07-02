package com.openbubbles.openpigeon.reversi

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import com.openbubbles.openpigeon.util.OpenPigeonLog
import androidx.core.graphics.createBitmap

object ReversiPreviewRenderer {
    private const val BOARD_SIZE = 8

    private const val PREVIEW_SIZE = 720
    private const val PADDING = 72f
    private const val CELL_SIZE = 72f
    private const val PIECE_PADDING = 6.5f

    private val starPointIntersections = arrayOf(
        2 to 2, // C3
        6 to 2, // G3
        2 to 6, // C7
        6 to 6  // G7
    )

    private val cacheLock = Any()
    private var cachedWhitePiece: Bitmap? = null
    private var cachedBlackPiece: Bitmap? = null

    private val piecePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    fun defaultBoard(): IntArray {
        val board = IntArray(BOARD_SIZE * BOARD_SIZE)

        board[27] = 2
        board[28] = 1
        board[35] = 1
        board[36] = 2

        return board
    }

    fun render(context: Context, flatBoard: IntArray): Bitmap {
        ensurePieceCache(context)

        val bitmap = createBitmap(PREVIEW_SIZE, PREVIEW_SIZE)

        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        canvas.drawColor(Color.rgb(229, 229, 229))

        drawBoardShadow(canvas, paint)
        drawBoard(canvas, paint)
        drawStarPoints(canvas, paint)
        drawPieces(canvas, paint, flatBoard)

        return bitmap
    }

    private fun drawBoardShadow(canvas: Canvas, paint: Paint) {
        val boardRect = RectF(
            PADDING,
            PADDING,
            PADDING + BOARD_SIZE * CELL_SIZE,
            PADDING + BOARD_SIZE * CELL_SIZE
        )

        paint.style = Paint.Style.FILL
        paint.color = Color.argb(80, 0, 0, 0)

        canvas.drawRoundRect(
            RectF(
                boardRect.left + 8f,
                boardRect.top + 14f,
                boardRect.right + 8f,
                boardRect.bottom + 14f
            ),
            20f,
            20f,
            paint
        )
    }

    private fun drawBoard(canvas: Canvas, paint: Paint) {
        val boardLeft = PADDING
        val boardTop = PADDING
        val boardRight = PADDING + BOARD_SIZE * CELL_SIZE
        val boardBottom = PADDING + BOARD_SIZE * CELL_SIZE

        paint.style = Paint.Style.FILL
        paint.color = Color.rgb(0, 105, 58)

        canvas.drawRect(
            boardLeft,
            boardTop,
            boardRight,
            boardBottom,
            paint
        )

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 4f
        paint.color = Color.argb(170, 0, 45, 25)

        for (i in 0..BOARD_SIZE) {
            val p = PADDING + i * CELL_SIZE

            canvas.drawLine(
                boardLeft,
                p,
                boardRight,
                p,
                paint
            )

            canvas.drawLine(
                p,
                boardTop,
                p,
                boardBottom,
                paint
            )
        }

        paint.strokeWidth = 8f
        paint.color = Color.argb(190, 0, 35, 20)

        canvas.drawRect(
            boardLeft,
            boardTop,
            boardRight,
            boardBottom,
            paint
        )

        paint.style = Paint.Style.FILL
    }

    private fun drawStarPoints(canvas: Canvas, paint: Paint) {
        paint.style = Paint.Style.FILL
        paint.color = Color.argb(190, 0, 35, 20)

        for ((gridX, gridY) in starPointIntersections) {
            canvas.drawCircle(
                PADDING + gridX * CELL_SIZE,
                PADDING + gridY * CELL_SIZE,
                8.5f,
                paint
            )
        }
    }

    private fun drawPieces(canvas: Canvas, paint: Paint, flatBoard: IntArray) {
        for (replayY in 0 until BOARD_SIZE) {
            for (x in 0 until BOARD_SIZE) {
                val replayIndex = replayY * BOARD_SIZE + x
                val value = flatBoard.getOrElse(replayIndex) { 0 }

                if (value != 1 && value != 2) continue

                val drawY = (BOARD_SIZE - 1) - replayY

                val left = PADDING + x * CELL_SIZE + PIECE_PADDING
                val top = PADDING + drawY * CELL_SIZE + PIECE_PADDING

                val dest = RectF(
                    left,
                    top,
                    left + CELL_SIZE - PIECE_PADDING * 2f,
                    top + CELL_SIZE - PIECE_PADDING * 2f
                )

                val pieceBitmap = if (value == 1) {
                    cachedBlackPiece
                } else {
                    cachedWhitePiece
                }

                if (pieceBitmap != null) {
                    canvas.drawBitmap(pieceBitmap, null, dest, piecePaint)
                } else {
                    drawFallbackPiece(canvas, paint, dest, value)
                }
            }
        }
    }

    private fun drawFallbackPiece(
        canvas: Canvas,
        paint: Paint,
        dest: RectF,
        value: Int
    ) {
        paint.color = Color.argb(70, 0, 0, 0)
        canvas.drawOval(
            RectF(
                dest.left + 2f,
                dest.top + 3f,
                dest.right + 2f,
                dest.bottom + 3f
            ),
            paint
        )

        paint.color = if (value == 1) {
            Color.rgb(22, 22, 22)
        } else {
            Color.rgb(245, 245, 245)
        }
        canvas.drawOval(dest, paint)

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1.5f
        paint.color = if (value == 1) {
            Color.rgb(70, 70, 70)
        } else {
            Color.rgb(190, 190, 190)
        }
        canvas.drawOval(dest, paint)
        paint.style = Paint.Style.FILL
    }

    private fun ensurePieceCache(context: Context) {
        if (cachedWhitePiece != null && cachedBlackPiece != null) return

        synchronized(cacheLock) {
            if (cachedWhitePiece != null && cachedBlackPiece != null) return

            val source = loadPieceBitmap(context)
            if (source == null) {
                OpenPigeonLog.w(
                    "ReversiPreview",
                    "Could not load reversi_tile.png. Preview will use fallback circles."
                )
                return
            }

            cachedWhitePiece = source
            cachedBlackPiece = makeBlackPiece(source)
        }
    }

    private fun loadPieceBitmap(context: Context): Bitmap? {
        val paths = listOf(
            "reversi/reversi_tile.png",
            "reversi_tile.png"
        )

        for (path in paths) {
            try {
                context.assets.open(path).use { stream ->
                    val bitmap = BitmapFactory.decodeStream(stream)
                    if (bitmap != null) {
                        OpenPigeonLog.i(
                            "ReversiPreview",
                            "Loaded Reversi preview piece asset from $path"
                        )
                        return bitmap
                    }
                }
            } catch (_: Exception) {
                // Try the next path.
            }
        }

        return null
    }

    private fun makeBlackPiece(source: Bitmap): Bitmap {
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

            val highlightT = ((lum - 0.965f) / 0.035f).coerceIn(0f, 1f)
            val highlightSmooth = highlightT * highlightT * (3f - 2f * highlightT)

            val shade = (
                    12f +
                            lum * 28f +
                            highlightSmooth * 175f
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