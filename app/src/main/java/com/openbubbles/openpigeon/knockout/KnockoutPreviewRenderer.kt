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

    fun render(context: Context, board: KnockoutBoard, mapMode: Int): Bitmap {
        val boardPx = OUT_SIZE - PADDING * 2
        val bitmap = Bitmap.createBitmap(OUT_SIZE, OUT_SIZE, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

        // Background color = the map's solid color (same values as backgroundColorForMap()).
        canvas.drawColor(backgroundColorForMap(mapMode))

        // World→thumbnail scale: WORLD_SIZE maps to boardPx.
        val scale = boardPx.toFloat() / WORLD_SIZE
        val cx = OUT_SIZE / 2f
        val cy = OUT_SIZE / 2f

        // Board image (ice floe), centered.
        val boardBmp = loadAsset(context, boardAssetForMap(mapMode))
        val half = boardPx / 2f
        if (boardBmp != null) {
            canvas.drawBitmap(
                boardBmp, null,
                RectF(cx - half, cy - half, cx + half, cy + half),
                paint
            )
        } else {
            paint.color = Color.rgb(232, 240, 242)
            canvas.drawOval(RectF(cx - half, cy - half, cx + half, cy + half), paint)
        }

        // Mushrooms on map 3 (same world positions as the in-game renderer).
        if (mapMode == 3) {
            val mush = loadAsset(context, "knockout/mushroom.png")
            val mushHalf = 22.5f * scale
            for ((mx, my) in listOf(-100f to -100f, 100f to -100f, -100f to 100f, 100f to 100f)) {
                val sx = cx + mx * scale
                val sy = cy - my * scale
                if (mush != null) {
                    canvas.drawBitmap(
                        mush, null,
                        RectF(sx - mushHalf, sy - mushHalf, sx + mushHalf, sy + mushHalf),
                        paint
                    )
                } else {
                    paint.color = Color.rgb(139, 90, 43)
                    canvas.drawCircle(sx, sy, mushHalf, paint)
                }
            }
        }

        // Penguins.
        val p1 = loadAsset(context, "knockout/bw_penguin.png")
        val p2 = loadAsset(context, "knockout/gw_penguin.png")
        val pieceHalf = (PIECE_VISUAL_SIZE / 2f) * scale

        board.pieces.forEach { piece ->
            val sx = cx + piece.x * scale
            val sy = cy - piece.y * scale
            val bmp = if (piece.player == 1) p1 else p2

            if (bmp != null) {
                canvas.save()
                canvas.translate(sx, sy)
                canvas.rotate(-Math.toDegrees(piece.rotation.toDouble()).toFloat())
                canvas.drawBitmap(
                    bmp, null,
                    RectF(-pieceHalf, -pieceHalf, pieceHalf, pieceHalf),
                    paint
                )
                canvas.restore()
            } else {
                paint.color = if (piece.player == 1) Color.rgb(34, 34, 34) else Color.rgb(221, 221, 221)
                canvas.drawCircle(sx, sy, pieceHalf, paint)
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