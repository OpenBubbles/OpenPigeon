package com.openbubbles.openpigeon.knockout

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.view.SurfaceHolder

class KnockoutRenderer(
    private val holder: SurfaceHolder,
    private val activity: KnockoutActivity
) : Thread(), SurfaceHolder.Callback {
    @Volatile var running = true

    private val targetFps = 60
    private val frameTimeMs = 1000L / targetFps
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    val transform = Matrix()
    private val boardTransform = Matrix()
    private val inverseTransform = Matrix()

    private val map1: Bitmap? = activity.loadAssetBitmap("knockout/ko_map1.png")
    private val map2: Bitmap? = activity.loadAssetBitmap("knockout/ko_map2.png")
    private val map3: Bitmap? = activity.loadAssetBitmap("knockout/ko_map3.png")

    init {
        holder.addCallback(this)
    }

    external fun update(table: Long): Boolean

    override fun run() {
        while (running) {
            val start = System.currentTimeMillis()
            val canvas = holder.lockCanvas()
            if (canvas != null) {
                try {
                    drawFrame(canvas)
                } finally {
                    holder.unlockCanvasAndPost(canvas)
                }
            }
            val elapsed = System.currentTimeMillis() - start
            val sleep = frameTimeMs - elapsed
            if (sleep > 0) sleep(sleep)
        }
    }

    private fun drawFrame(canvas: Canvas) {
        synchronized(activity) {
            canvas.drawColor(if (activity.darkMode) 0xff1f2933.toInt() else 0xff68d4f6.toInt())

            computeTransforms(canvas.width, canvas.height)
            activity.updateLaunchButtonPlacement(canvas.width, canvas.height)

            if (!activity.closing && activity.table != 0L && activity.mode == KnockoutActivity.Mode.Playing) {
                val moving = update(activity.table)

                val syncPieces = activity.pieces.toList()
                syncPieces.forEach { it.syncFromNative() }

                activity.updateKillZonesFromRenderer()

                if (!moving) activity.onNativePlayFinished()
            }

            val drawPieces = activity.pieces.toList()

            canvas.save()
            canvas.concat(boardTransform)
            drawBoard(canvas)
            canvas.restore()

            canvas.save()
            canvas.concat(transform)

            fun iosArrowAlpha(visibility: Float = 1f): Int {
                return (KnockoutConstants.ARROW_ALPHA * visibility * 255f)
                    .toInt()
                    .coerceIn(0, 255)
            }

            drawPieces.forEach { piece ->
                piece.draw(canvas, paint)
            }

            if (activity.showAllReplayArrows) {

                drawPieces
                    .filter { it.alive && !it.dying && it.hasPower() }
                    .forEach { piece ->
                        piece.drawArrow(canvas, paint, iosArrowAlpha(activity.replayArrowAlpha))
                    }

            } else if (
                activity.mode == KnockoutActivity.Mode.Aiming &&
                !activity.isIntroPopupShowing()
            ) {

                drawPieces
                    .filter { it.player == activity.player && it.alive && !it.dying && it.hasPower() }
                    .forEach { piece ->
                        piece.drawArrow(canvas, paint, iosArrowAlpha(1f))
                    }
            }

            if (
                activity.mode == KnockoutActivity.Mode.Aiming &&
                !activity.isIntroPopupShowing() &&
                !activity.showAllReplayArrows
            ) {
                val pulse = highlightPulseScale()

                drawPieces
                    .filter { it.player == activity.player && it.alive && !it.hasPower() }
                    .forEach { piece ->
                        piece.drawHighlightRing(canvas, paint, pulse)
                    }
            }

            canvas.restore()
        }
    }
    private fun highlightPulseScale(): Float {
        val period = KnockoutConstants.HIGHLIGHT_PULSE_PERIOD_MS
        val phase = (System.currentTimeMillis() % period).toFloat() / period.toFloat()
        val triangle = if (phase <= 0.5f) phase * 2f else (1f - phase) * 2f

        return 1.0f + (KnockoutConstants.HIGHLIGHT_PULSE_MAX_SCALE - 1f) * triangle
    }

    private fun boardVisualScale(): Float {
        return (
                1f - activity.visualBoardIndex.coerceAtLeast(0f) * 0.1f
                ).coerceAtLeast(0.3f)
    }

    private fun drawBoard(canvas: Canvas) {
        val half = KnockoutConstants.BOARD_SIZE / 2f
        val rect = RectF(-half, -half, half, half)

        val bitmap = when (activity.mapMode) {
            2 -> map2 ?: map1
            3 -> map3 ?: map1
            else -> map1
        }

        if (bitmap != null) {
            canvas.drawBitmap(bitmap, null, rect, paint)
        } else {
            paint.style = Paint.Style.FILL
            paint.color = 0xffe8f0f2.toInt()
            canvas.drawOval(rect, paint)
        }
    }

    fun screenToWorld(sx: Float, sy: Float): FloatArray {
        inverseTransform.reset()
        transform.invert(inverseTransform)
        val pts = floatArrayOf(sx, sy)
        inverseTransform.mapPoints(pts)
        return floatArrayOf(pts[0], -pts[1])
    }

    private fun computeTransforms(width: Int, height: Int) {
        val baseScale = width.toFloat() / KnockoutConstants.BOARD_SIZE
        val boardScale = baseScale * boardVisualScale()

        // World transform: pieces, arrows, rings, touches, physics coordinates.
        transform.reset()
        transform.postScale(baseScale, baseScale)
        transform.postTranslate(width / 2f, height / 2f)

        // Board transform: board image only.
        boardTransform.reset()
        boardTransform.postScale(boardScale, boardScale)
        boardTransform.postTranslate(width / 2f, height / 2f)
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        if (!isAlive) start()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        running = false
    }
}
