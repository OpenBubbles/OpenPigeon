package com.openbubbles.openpigeon.knockout

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF

object KnockoutPreviewRenderer {

    // Logical world size of the board (matches KnockoutConstants.BOARD_SIZE).
    private const val WORLD_SIZE = 375f
    private const val PIECE_VISUAL_SIZE = 25f   // matches KnockoutConstants.PIECE_VISUAL_SIZE

    // Output thumbnail resolution.
    private const val OUT_SIZE = 320
    private const val PADDING = 10

    fun render(
        context: Context,
        board: KnockoutBoard,
        mapMode: Int
    ): Bitmap {
        return render(
            context = context,
            board = board,
            mapMode = mapMode,
            targetWidthPx = OUT_SIZE,
            targetHeightPx = OUT_SIZE
        )
    }

    fun render(
        context: Context,
        board: KnockoutBoard,
        mapMode: Int,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap {
        val logicalBitmap = renderLogical(
            context = context,
            board = board,
            mapMode = mapMode
        )

        val outputWidth = targetWidthPx.coerceAtLeast(1)
        val outputHeight = targetHeightPx.coerceAtLeast(1)

        val output = Bitmap.createBitmap(
            outputWidth,
            outputHeight,
            Bitmap.Config.ARGB_8888
        )

        val canvas = Canvas(output)
        val paint = Paint(
            Paint.ANTI_ALIAS_FLAG or
                    Paint.FILTER_BITMAP_FLAG
        )

        canvas.drawColor(backgroundColorForMap(mapMode))

        val scale = minOf(
            outputWidth.toFloat() / logicalBitmap.width,
            outputHeight.toFloat() / logicalBitmap.height
        )

        val drawWidth = logicalBitmap.width * scale
        val drawHeight = logicalBitmap.height * scale
        val left = (outputWidth - drawWidth) / 2f
        val top = (outputHeight - drawHeight) / 2f

        canvas.drawBitmap(
            logicalBitmap,
            null,
            RectF(
                left,
                top,
                left + drawWidth,
                top + drawHeight
            ),
            paint
        )

        return output
    }

    private fun renderLogical(
        context: Context,
        board: KnockoutBoard,
        mapMode: Int
    ): Bitmap {
        val boardPx = OUT_SIZE - PADDING * 2

        val bitmap = Bitmap.createBitmap(
            OUT_SIZE,
            OUT_SIZE,
            Bitmap.Config.ARGB_8888
        )

        val canvas = Canvas(bitmap)
        val paint = Paint(
            Paint.ANTI_ALIAS_FLAG or
                    Paint.FILTER_BITMAP_FLAG
        )

        canvas.drawColor(backgroundColorForMap(mapMode))

        val scale = boardPx.toFloat() / WORLD_SIZE
        val cx = OUT_SIZE / 2f
        val cy = OUT_SIZE / 2f

        val boardBmp = loadAsset(
            context,
            boardAssetForMap(mapMode)
        )

        val half = boardPx / 2f

        if (boardBmp != null) {
            canvas.drawBitmap(
                boardBmp,
                null,
                RectF(
                    cx - half,
                    cy - half,
                    cx + half,
                    cy + half
                ),
                paint
            )
        } else {
            paint.color = Color.rgb(232, 240, 242)

            canvas.drawOval(
                RectF(
                    cx - half,
                    cy - half,
                    cx + half,
                    cy + half
                ),
                paint
            )
        }

        if (mapMode == 3) {
            val mushroom = loadAsset(
                context,
                "knockout/mushroom.png"
            )

            val mushroomHalf = 22.5f * scale

            val mushroomPositions = listOf(
                -100f to -100f,
                100f to -100f,
                -100f to 100f,
                100f to 100f
            )

            for ((mx, my) in mushroomPositions) {
                val sx = cx + mx * scale
                val sy = cy - my * scale

                if (mushroom != null) {
                    canvas.drawBitmap(
                        mushroom,
                        null,
                        RectF(
                            sx - mushroomHalf,
                            sy - mushroomHalf,
                            sx + mushroomHalf,
                            sy + mushroomHalf
                        ),
                        paint
                    )
                } else {
                    paint.color = Color.rgb(139, 90, 43)
                    canvas.drawCircle(
                        sx,
                        sy,
                        mushroomHalf,
                        paint
                    )
                }
            }
        }

        val player1Bitmap = loadAsset(
            context,
            "knockout/bw_penguin.png"
        )

        val player2Bitmap = loadAsset(
            context,
            "knockout/gw_penguin.png"
        )

        val pieceHalf =
            PIECE_VISUAL_SIZE / 2f * scale

        board.pieces.forEach { piece ->
            val sx = cx + piece.x * scale
            val sy = cy - piece.y * scale

            val pieceBitmap =
                if (piece.player == 1) {
                    player1Bitmap
                } else {
                    player2Bitmap
                }

            if (pieceBitmap != null) {
                canvas.save()
                canvas.translate(sx, sy)

                canvas.rotate(
                    -Math.toDegrees(
                        piece.rotation.toDouble()
                    ).toFloat()
                )

                canvas.drawBitmap(
                    pieceBitmap,
                    null,
                    RectF(
                        -pieceHalf,
                        -pieceHalf,
                        pieceHalf,
                        pieceHalf
                    ),
                    paint
                )

                canvas.restore()
            } else {
                paint.color =
                    if (piece.player == 1) {
                        Color.rgb(34, 34, 34)
                    } else {
                        Color.rgb(221, 221, 221)
                    }

                canvas.drawCircle(
                    sx,
                    sy,
                    pieceHalf,
                    paint
                )
            }
        }

        return bitmap
    }

    private fun boardAssetForMap(mapMode: Int): String = when (mapMode) {
        2 -> "knockout/ko_map2.png"
        3 -> "knockout/ko_map3.png"
        else -> "knockout/ko_map1.png"
    }

    private fun backgroundColorForMap(mapMode: Int): Int = when (mapMode) {
        2 -> 0xFFFFD84D.toInt()
        3 -> 0xFF6FD68B.toInt()
        else -> 0xFFAAD9F7.toInt()
    }

    private fun loadAsset(context: Context, path: String): Bitmap? = try {
        context.assets.open(path).use { BitmapFactory.decodeStream(it) }
    } catch (_: Exception) {
        null
    }
}