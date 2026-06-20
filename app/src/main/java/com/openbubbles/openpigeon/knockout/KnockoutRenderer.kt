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
) : SurfaceHolder.Callback {
    @Volatile var running = false
    private var renderThread: Thread? = null

    private val targetFps = 60
    private val frameTimeMs = 1000L / targetFps
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    private val mushroomHitStartMs = LongArray(4) { 0L }

    val transform = Matrix()
    private val boardTransform = Matrix()
    private val inverseTransform = Matrix()

    private val map1: Bitmap? = activity.loadAssetBitmap("knockout/ko_map1.png")
    private val map2: Bitmap? = activity.loadAssetBitmap("knockout/ko_map2.png")
    private val map3: Bitmap? = activity.loadAssetBitmap("knockout/ko_map3.png")
    private val mushroom: Bitmap? = activity.loadAssetBitmap("knockout/mushroom.png")

    init {
        holder.addCallback(this)

        if (holder.surface?.isValid == true) {
            startRenderThread()
        }
    }

    external fun update(table: Long): Boolean

    private fun startRenderThread() {
        if (running) return

        running = true

        renderThread = Thread({
            while (running) {
                val start = System.currentTimeMillis()

                val canvas = try {
                    holder.lockCanvas()
                } catch (_: Exception) {
                    null
                }

                if (canvas != null) {
                    try {
                        drawFrame(canvas)
                    } catch (t: Throwable) {
                        t.printStackTrace()
                    } finally {
                        try {
                            holder.unlockCanvasAndPost(canvas)
                        } catch (_: Exception) {
                        }
                    }
                }

                val elapsed = System.currentTimeMillis() - start
                val sleep = frameTimeMs - elapsed

                if (sleep > 0) {
                    try {
                        Thread.sleep(sleep)
                    } catch (_: InterruptedException) {
                        return@Thread
                    }
                }
            }
        }, "KnockoutRenderer").apply {
            start()
        }
    }

    private fun stopRenderThread() {
        running = false

        val thread = renderThread
        renderThread = null

        if (thread != null && thread !== Thread.currentThread()) {
            try {
                thread.join(500L)
            } catch (_: InterruptedException) {
            }
        }
    }

    private fun drawFrame(canvas: Canvas) {
        synchronized(activity) {
            if (activity.darkMode) {
                canvas.drawColor(backgroundColorForMap())  // dark mode keeps its opaque fill, water hidden
            } else {
                canvas.drawColor(android.graphics.Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR)
            }

            computeTransforms(canvas.width, canvas.height)
            activity.updateLaunchButtonPlacement(canvas.width, canvas.height)

            if (!activity.closing && activity.table != 0L && activity.mode == KnockoutActivity.Mode.Playing) {
                val moving = update(activity.table)

                val mushroomHits = activity.consumeNativeMushroomHits()
                if (mushroomHits != 0) {
                    startMushroomHitAnimations(mushroomHits)
                }

                val syncPieces = activity.pieces.toList()
                syncPieces.forEach { it.syncFromNative() }

                activity.updateKillZonesFromRenderer()

                if (!moving) activity.onNativePlayFinished()
            }

            val drawPieces = activity.pieces.toList()

            canvas.save()
            canvas.concat(boardTransform)
            drawBoard(canvas)
            drawMushrooms(canvas)
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
                        piece.drawArrow(canvas, paint, iosArrowAlpha(activity.replayArrowAlpha), activity.mapMode)
                    }

            } else if (
                activity.mode == KnockoutActivity.Mode.Aiming &&
                !activity.isIntroPopupShowing()
            ) {

                drawPieces
                    .filter { it.player == activity.player && it.alive && !it.dying && it.hasPower() }
                    .forEach { piece ->
                        piece.drawArrow(canvas, paint, iosArrowAlpha(1f), activity.mapMode)
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
                        piece.drawHighlightRing(canvas, paint, pulse, activity.mapMode)
                    }
            }

            canvas.restore()
            activity.revealGameAfterCorrectFrameDrawn()
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

    private fun backgroundColorForMap(): Int {
        if (activity.darkMode) {
            return 0xff1f2933.toInt()
        }

        return when (activity.mapMode) {
            2 -> 0xffffd84d.toInt()
            3 -> 0xff6fd68b.toInt()
            else -> 0xffaad9f7.toInt()
        }
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

    private fun startMushroomHitAnimations(mask: Int) {
        val now = System.currentTimeMillis()

        for (i in 0 until 4) {
            if ((mask and (1 shl i)) != 0) {
                mushroomHitStartMs[i] = now
            }
        }
    }

    private fun mushroomHitScale(index: Int): Float {
        val start = mushroomHitStartMs.getOrNull(index) ?: return 1f
        if (start <= 0L) return 1f

        val elapsed = (System.currentTimeMillis() - start).coerceAtLeast(0L)

        return when {
            elapsed <= 10L -> {
                1f + 0.35f * (elapsed.toFloat() / 10f)
            }

            elapsed <= 160L -> {
                val t = (elapsed - 10L).toFloat() / 150f
                1.35f + (1f - 1.35f) * t
            }

            else -> 1f
        }
    }

    private fun drawMushrooms(canvas: Canvas) {
        if (activity.mapMode != 3) return

        val mushroomHalf = 22.5f
        val shadowOffsetY = -6f

        val positions = arrayOf(
            -100f to -100f,
            100f to -100f,
            -100f to  100f,
            100f to  100f
        )

        positions.forEachIndexed { index, pair ->
            val worldX = pair.first
            val worldY = pair.second

            val hitScale = mushroomHitScale(index)
            val visualHalf = mushroomHalf * hitScale

            val screenY = -worldY
            val shadowScreenY = -(worldY + shadowOffsetY)

            val oldStyle = paint.style
            val oldColor = paint.color
            val oldAlpha = paint.alpha

            paint.style = Paint.Style.FILL
            paint.color = 0xff000000.toInt()
            paint.alpha = 55

            canvas.drawOval(
                RectF(
                    worldX - visualHalf,
                    shadowScreenY - visualHalf * 0.45f,
                    worldX + visualHalf,
                    shadowScreenY + visualHalf * 0.45f
                ),
                paint
            )

            paint.style = oldStyle
            paint.color = oldColor
            paint.alpha = oldAlpha

            if (mushroom != null) {
                canvas.drawBitmap(
                    mushroom,
                    null,
                    RectF(
                        worldX - visualHalf,
                        screenY - visualHalf,
                        worldX + visualHalf,
                        screenY + visualHalf
                    ),
                    paint
                )
            } else {
                paint.style = Paint.Style.FILL
                paint.color = 0xff8b5a2b.toInt()
                canvas.drawCircle(worldX, screenY, visualHalf, paint)

                paint.style = oldStyle
                paint.color = oldColor
            }
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
        startRenderThread()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        stopRenderThread()
    }

    fun shutdown() {
        stopRenderThread()
        holder.removeCallback(this)
    }
}
