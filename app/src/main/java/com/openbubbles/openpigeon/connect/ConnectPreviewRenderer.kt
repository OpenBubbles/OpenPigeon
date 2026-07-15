package com.openbubbles.openpigeon.connect

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import androidx.core.graphics.createBitmap
import com.openbubbles.openpigeon.util.OpenPigeonLog
import androidx.core.graphics.withTranslation

object ConnectPreviewRenderer {
    private const val BOARD_W = 7
    private const val BOARD_H = 6

    private const val LOGICAL_PREVIEW_SIZE = 720f

    private const val BOARD_ASSET_WIDTH = 730f
    private const val BOARD_ASSET_HEIGHT = 634f

    private const val CELL_SIZE = 88f
    private const val BOARD_WIDTH = CELL_SIZE * BOARD_W
    private const val BOARD_HEIGHT = CELL_SIZE * BOARD_H
    private const val BOARD_LEFT = 52f
    private const val BOARD_TOP = 96f

    private const val PIECE_SIZE = 61f

    private const val ASSET_SLOT_LEFT_X = 89f
    private const val ASSET_SLOT_BOTTOM_Y = 533.5f
    private const val ASSET_SLOT_X_SPACING = 92f
    private const val ASSET_SLOT_Y_SPACING = 94f

    private val boardRect = RectF(
        BOARD_LEFT,
        BOARD_TOP,
        BOARD_LEFT + BOARD_WIDTH,
        BOARD_TOP + BOARD_HEIGHT
    )

    private val cacheLock = Any()

    private var cachedRedPiece: Bitmap? = null
    private var cachedYellowPiece: Bitmap? = null
    private var cachedBoardBack: Bitmap? = null
    private var cachedBoardFront: Bitmap? = null

    private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    fun defaultBoard(): IntArray {
        return IntArray(BOARD_W * BOARD_H)
    }

    fun render(
        context: Context,
        flatBoard: IntArray
    ): Bitmap {
        return render(
            context = context,
            flatBoard = flatBoard,
            targetWidthPx = LOGICAL_PREVIEW_SIZE.toInt(),
            targetHeightPx = LOGICAL_PREVIEW_SIZE.toInt()
        )
    }

    fun render(
        context: Context,
        flatBoard: IntArray,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap {
        ensureAssetCache(context)

        val outputWidth = targetWidthPx.coerceAtLeast(1)
        val outputHeight = targetHeightPx.coerceAtLeast(1)

        val bitmap = createBitmap(
            outputWidth,
            outputHeight
        )

        val canvas = Canvas(bitmap)

        canvas.drawColor(Color.rgb(216, 199, 194))

        val scale = minOf(
            outputWidth / LOGICAL_PREVIEW_SIZE,
            outputHeight / LOGICAL_PREVIEW_SIZE
        )

        val scaledWidth = LOGICAL_PREVIEW_SIZE * scale
        val scaledHeight = LOGICAL_PREVIEW_SIZE * scale

        val offsetX = (outputWidth - scaledWidth) / 2f
        val offsetY = (outputHeight - scaledHeight) / 2f

        canvas.withTranslation(offsetX, offsetY) {
            scale(scale, scale)

            val hasBoardLayers =
                cachedBoardBack != null &&
                        cachedBoardFront != null

            if (hasBoardLayers) {
                drawBoardBitmapLayer(this, cachedBoardBack)
                drawPieces(this, flatBoard)
                drawBoardBitmapLayer(this, cachedBoardFront)
            } else {
                drawFallbackBoardBase(this)
                drawPieces(this, flatBoard)
                drawFallbackBoardFront(this)
            }

        }

        return bitmap
    }

    private fun drawBoardBitmapLayer(
        canvas: Canvas,
        bitmap: Bitmap?
    ) {
        if (bitmap == null) return
        canvas.drawBitmap(bitmap, null, boardRect, imagePaint)
    }

    private fun drawFallbackBoardBase(canvas: Canvas) {
        paint.style = Paint.Style.FILL

        paint.color = Color.argb(80, 0, 0, 0)
        canvas.drawRoundRect(
            RectF(
                boardRect.left + 8f,
                boardRect.top + 14f,
                boardRect.right + 8f,
                boardRect.bottom + 14f
            ),
            26f,
            26f,
            paint
        )

        paint.color = Color.rgb(30, 82, 190)
        canvas.drawRoundRect(boardRect, 28f, 28f, paint)
    }

    private fun drawFallbackBoardFront(canvas: Canvas) {
        val holeRadius = CELL_SIZE * 0.395f
        val rimRadius = CELL_SIZE * 0.442f

        for (sourceY in 0 until BOARD_H) {
            for (x in 0 until BOARD_W) {
                val drawRow = (BOARD_H - 1) - sourceY

                val cx = BOARD_LEFT + x * CELL_SIZE + CELL_SIZE / 2f
                val cy = BOARD_TOP + drawRow * CELL_SIZE + CELL_SIZE / 2f

                paint.style = Paint.Style.FILL
                paint.color = Color.argb(135, 0, 35, 120)
                canvas.drawCircle(cx, cy, rimRadius, paint)

                paint.color = Color.rgb(216, 199, 194)
                canvas.drawCircle(cx, cy, holeRadius, paint)

                paint.style = Paint.Style.STROKE
                paint.strokeWidth = 4f
                paint.color = Color.argb(150, 255, 255, 255)
                canvas.drawCircle(cx, cy, rimRadius, paint)
            }
        }

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 8f
        paint.color = Color.argb(180, 15, 48, 150)
        canvas.drawRoundRect(boardRect, 28f, 28f, paint)

        paint.style = Paint.Style.FILL
    }

    private fun drawPieces(
        canvas: Canvas,
        flatBoard: IntArray
    ) {
        for (sourceY in 0 until BOARD_H) {
            for (x in 0 until BOARD_W) {
                val index = sourceY * BOARD_W + x
                val value = flatBoard.getOrElse(index) { 0 }

                if (value != 1 && value != 2) continue

                val centerX = pieceCenterXForColumn(x)
                val centerY = pieceCenterYForRow(sourceY)

                val dest = RectF(
                    centerX - PIECE_SIZE / 2f,
                    centerY - PIECE_SIZE / 2f,
                    centerX + PIECE_SIZE / 2f,
                    centerY + PIECE_SIZE / 2f
                )

                val pieceBitmap = when (value) {
                    1 -> cachedYellowPiece
                    2 -> cachedRedPiece
                    else -> null
                }

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
        val isYellow = value == 1

        paint.style = Paint.Style.FILL
        paint.color = Color.argb(95, 0, 0, 0)
        canvas.drawOval(
            RectF(
                dest.left + 4f,
                dest.top + 6f,
                dest.right + 4f,
                dest.bottom + 6f
            ),
            paint
        )

        paint.color = if (isYellow) {
            Color.rgb(255, 216, 20)
        } else {
            Color.rgb(215, 20, 20)
        }
        canvas.drawOval(dest, paint)

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 4f
        paint.color = if (isYellow) {
            Color.rgb(190, 150, 0)
        } else {
            Color.rgb(125, 0, 0)
        }
        canvas.drawOval(dest, paint)

        paint.style = Paint.Style.FILL
    }

    private fun ensureAssetCache(context: Context) {
        if (
            cachedRedPiece != null &&
            cachedYellowPiece != null
        ) {
            return
        }

        synchronized(cacheLock) {
            if (
                cachedRedPiece != null &&
                cachedYellowPiece != null
            ) {
                return
            }

            cachedRedPiece = loadAssetBitmap(
                context,
                "connect/red_piece.png",
                "red_piece.png"
            )

            cachedYellowPiece = loadAssetBitmap(
                context,
                "connect/yellow_piece.png",
                "yellow_piece.png"
            )

            cachedBoardBack = loadAssetBitmap(
                context,
                "connect/board_7x6/layer1.png",
                "board_7x6/layer1.png",
                "connect/layer1.png",
                "layer1.png"
            )

            cachedBoardFront = loadAssetBitmap(
                context,
                "connect/board_7x6/layer0.png",
                "board_7x6/layer0.png",
                "connect/layer0.png",
                "layer0.png"
            )
        }
    }

    private fun boardAssetXFromSource(assetX: Float): Float {
        return BOARD_LEFT + (assetX / BOARD_ASSET_WIDTH) * BOARD_WIDTH
    }

    private fun boardAssetYFromSource(assetY: Float): Float {
        return BOARD_TOP + (assetY / BOARD_ASSET_HEIGHT) * BOARD_HEIGHT
    }

    private fun pieceCenterXForColumn(column: Int): Float {
        val assetX = ASSET_SLOT_LEFT_X + column * ASSET_SLOT_X_SPACING
        return boardAssetXFromSource(assetX)
    }

    private fun pieceCenterYForRow(sourceY: Int): Float {
        val assetY = ASSET_SLOT_BOTTOM_Y - sourceY * ASSET_SLOT_Y_SPACING
        return boardAssetYFromSource(assetY)
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
                            "ConnectPreview",
                            "Loaded Four in a Row preview asset from $path"
                        )
                        return bitmap
                    }
                }
            } catch (_: Exception) {
            }
        }

        OpenPigeonLog.w(
            "ConnectPreview",
            "Could not load Four in a Row preview asset from paths=${paths.joinToString()}"
        )

        return null
    }
}