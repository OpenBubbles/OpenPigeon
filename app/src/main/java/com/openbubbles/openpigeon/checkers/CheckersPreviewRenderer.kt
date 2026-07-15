package com.openbubbles.openpigeon.checkers

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import androidx.core.graphics.createBitmap
import com.openbubbles.openpigeon.util.OpenPigeonLog
import androidx.core.graphics.withSave

object CheckersPreviewRenderer {
    private const val BOARD_SIZE = 8

    private const val PREVIEW_SIZE = 720
    private const val PADDING = 56f
    private const val BOARD_SIDE = 608f
    private const val CELL_SIZE = BOARD_SIDE / BOARD_SIZE

    private const val PIECE_FILL = 0.92f

    private val boardRect = RectF(
        PADDING,
        PADDING,
        PADDING + BOARD_SIDE,
        PADDING + BOARD_SIDE
    )

    private val outputPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val cacheLock = Any()

    private var cachedBoard: Bitmap? = null
    private var cachedRed: Bitmap? = null
    private var cachedBlack: Bitmap? = null
    private var cachedRedKing: Bitmap? = null
    private var cachedBlackKing: Bitmap? = null

    private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val fallbackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    fun defaultBoard(): IntArray {
        return intArrayOf(
            0, 2, 0, 2, 0, 2, 0, 2,
            2, 0, 2, 0, 2, 0, 2, 0,
            0, 2, 0, 2, 0, 2, 0, 2,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            1, 0, 1, 0, 1, 0, 1, 0,
            0, 1, 0, 1, 0, 1, 0, 1,
            1, 0, 1, 0, 1, 0, 1, 0
        )
    }

    fun render(
        context: Context,
        flatBoard: IntArray,
        previewPlayer: Int = 1
    ): Bitmap {
        return render(
            context = context,
            flatBoard = flatBoard,
            previewPlayer = previewPlayer,
            targetWidthPx = PREVIEW_SIZE,
            targetHeightPx = PREVIEW_SIZE
        )
    }

    fun render(
        context: Context,
        flatBoard: IntArray,
        previewPlayer: Int = 1,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap {
        ensureAssetCache(context)

        val logicalBitmap = createBitmap(
            PREVIEW_SIZE,
            PREVIEW_SIZE
        )

        val logicalCanvas = Canvas(logicalBitmap)

        logicalCanvas.drawColor(Color.rgb(229, 229, 229))

        drawBoardShadow(logicalCanvas)
        drawBoard(logicalCanvas, previewPlayer)
        drawPieces(logicalCanvas, flatBoard, previewPlayer)

        return fitLogicalBitmap(
            source = logicalBitmap,
            targetWidthPx = targetWidthPx,
            targetHeightPx = targetHeightPx,
            backgroundColor = Color.rgb(229, 229, 229)
        )
    }

    private fun fitLogicalBitmap(
        source: Bitmap,
        targetWidthPx: Int,
        targetHeightPx: Int,
        backgroundColor: Int
    ): Bitmap {
        val outputWidth = targetWidthPx.coerceAtLeast(1)
        val outputHeight = targetHeightPx.coerceAtLeast(1)

        val output = createBitmap(outputWidth, outputHeight)
        val canvas = Canvas(output)

        canvas.drawColor(backgroundColor)

        val scale = minOf(
            outputWidth.toFloat() / source.width,
            outputHeight.toFloat() / source.height
        )

        val drawWidth = source.width * scale
        val drawHeight = source.height * scale
        val left = (outputWidth - drawWidth) / 2f
        val top = (outputHeight - drawHeight) / 2f

        canvas.drawBitmap(
            source,
            null,
            RectF(left, top, left + drawWidth, top + drawHeight),
            outputPaint
        )

        return output
    }

    private fun drawBoardShadow(canvas: Canvas) {
        fallbackPaint.style = Paint.Style.FILL
        fallbackPaint.color = Color.argb(85, 0, 0, 0)

        canvas.drawRect(
            boardRect.left + 8f,
            boardRect.top + 14f,
            boardRect.right + 8f,
            boardRect.bottom + 14f,
            fallbackPaint
        )
    }

    private fun drawBoard(
        canvas: Canvas,
        previewPlayer: Int
    ) {
        val board = cachedBoard

        if (board != null) {
            val cx = boardRect.centerX()
            val cy = boardRect.centerY()

            canvas.withSave {

                if (previewPlayer == 2) {
                    rotate(180f, cx, cy)
                }

                drawBitmap(board, null, boardRect, imagePaint)
            }
            return
        }

        drawFallbackBoard(canvas, previewPlayer)
    }

    private fun drawFallbackBoard(
        canvas: Canvas,
        previewPlayer: Int
    ) {
        fallbackPaint.style = Paint.Style.FILL

        for (sourceRow in 0 until BOARD_SIZE) {
            for (sourceCol in 0 until BOARD_SIZE) {
                val (drawRow, drawCol) = visualBoardCellFor(
                    sourceRow = sourceRow,
                    sourceCol = sourceCol,
                    previewPlayer = previewPlayer
                )

                fallbackPaint.color = if ((sourceCol + sourceRow) % 2 == 0) {
                    Color.rgb(17, 17, 17)
                } else {
                    Color.rgb(190, 72, 73)
                }

                val left = PADDING + drawCol * CELL_SIZE
                val top = PADDING + drawRow * CELL_SIZE

                canvas.drawRect(
                    left,
                    top,
                    left + CELL_SIZE,
                    top + CELL_SIZE,
                    fallbackPaint
                )
            }
        }
    }

    private fun drawPieces(
        canvas: Canvas,
        flatBoard: IntArray,
        previewPlayer: Int
    ) {
        val pieceSize = CELL_SIZE * PIECE_FILL

        for (sourceRow in 0 until BOARD_SIZE) {
            for (sourceCol in 0 until BOARD_SIZE) {
                val index = sourceRow * BOARD_SIZE + sourceCol
                val value = flatBoard.getOrElse(index) { 0 }

                if (value == 0) continue

                val pieceBitmap = when (value) {
                    1 -> cachedRed
                    2 -> cachedBlack
                    3 -> cachedRedKing
                    4 -> cachedBlackKing
                    else -> null
                }

                val (drawRow, drawCol) = visualPieceCellFor(
                    sourceRow = sourceRow,
                    sourceCol = sourceCol,
                    previewPlayer = previewPlayer
                )

                val centerX = PADDING + drawCol * CELL_SIZE + CELL_SIZE / 2f
                val centerY = PADDING + drawRow * CELL_SIZE + CELL_SIZE / 2f

                val dest = RectF(
                    centerX - pieceSize / 2f,
                    centerY - pieceSize / 2f,
                    centerX + pieceSize / 2f,
                    centerY + pieceSize / 2f
                )

                if (pieceBitmap != null) {
                    canvas.drawBitmap(pieceBitmap, null, dest, imagePaint)
                } else {
                    drawFallbackPiece(canvas, dest, value)
                }
            }
        }
    }

    private fun drawFallbackPiece(
        canvas: Canvas,
        dest: RectF,
        value: Int
    ) {
        val isRed = value == 1 || value == 3
        val isKing = value == 3 || value == 4

        fallbackPaint.style = Paint.Style.FILL
        fallbackPaint.color = Color.argb(90, 0, 0, 0)

        canvas.drawOval(
            RectF(
                dest.left + 2f,
                dest.top + 3f,
                dest.right + 2f,
                dest.bottom + 3f
            ),
            fallbackPaint
        )

        fallbackPaint.color = if (isRed) {
            Color.rgb(215, 30, 35)
        } else {
            Color.rgb(32, 32, 32)
        }

        canvas.drawOval(dest, fallbackPaint)

        fallbackPaint.style = Paint.Style.STROKE
        fallbackPaint.strokeWidth = 1.5f
        fallbackPaint.color = if (isRed) {
            Color.rgb(120, 0, 0)
        } else {
            Color.rgb(85, 85, 85)
        }

        canvas.drawOval(dest, fallbackPaint)

        if (isKing) {
            fallbackPaint.style = Paint.Style.FILL
            fallbackPaint.color = Color.WHITE
            fallbackPaint.textAlign = Paint.Align.CENTER
            fallbackPaint.textSize = dest.height() * 0.48f
            fallbackPaint.isFakeBoldText = true

            val baseline = dest.centerY() - (fallbackPaint.descent() + fallbackPaint.ascent()) / 2f
            canvas.drawText("K", dest.centerX(), baseline, fallbackPaint)

            fallbackPaint.isFakeBoldText = false
        }

        fallbackPaint.style = Paint.Style.FILL
    }

    private fun visualBoardCellFor(
        sourceRow: Int,
        sourceCol: Int,
        previewPlayer: Int
    ): Pair<Int, Int> {
        return if (previewPlayer == 2) {
            (BOARD_SIZE - 1 - sourceRow) to (BOARD_SIZE - 1 - sourceCol)
        } else {
            sourceRow to sourceCol
        }
    }

    private fun visualPieceCellFor(
        sourceRow: Int,
        sourceCol: Int,
        previewPlayer: Int
    ): Pair<Int, Int> {
        val mirroredCol = BOARD_SIZE - 1 - sourceCol

        return if (previewPlayer == 2) {
            (BOARD_SIZE - 1 - sourceRow) to (BOARD_SIZE - 1 - mirroredCol)
        } else {
            sourceRow to mirroredCol
        }
    }

    private fun ensureAssetCache(context: Context) {
        if (
            cachedBoard != null &&
            cachedRed != null &&
            cachedBlack != null &&
            cachedRedKing != null &&
            cachedBlackKing != null
        ) {
            return
        }

        synchronized(cacheLock) {
            if (
                cachedBoard != null &&
                cachedRed != null &&
                cachedBlack != null &&
                cachedRedKing != null &&
                cachedBlackKing != null
            ) {
                return
            }

            cachedBoard = loadAssetBitmap(
                context,
                "checkers/checkersboard_plain.png",
                "checkersboard_plain.png"
            )

            cachedRed = loadAssetBitmap(
                context,
                "checkers/checker_red.png",
                "checker_red.png"
            )

            cachedBlack = loadAssetBitmap(
                context,
                "checkers/checker_black.png",
                "checker_black.png"
            )

            cachedRedKing = loadAssetBitmap(
                context,
                "checkers/checker_red_king.png",
                "checker_red_king.png"
            )

            cachedBlackKing = loadAssetBitmap(
                context,
                "checkers/checker_black_king.png",
                "checker_black_king.png"
            )
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
                            "CheckersPreview",
                            "Loaded Checkers preview asset from $path"
                        )
                        return bitmap
                    }
                }
            } catch (_: Exception) {
            }
        }

        OpenPigeonLog.w(
            "CheckersPreview",
            "Could not load Checkers preview asset from paths=${paths.joinToString()}"
        )

        return null
    }
}