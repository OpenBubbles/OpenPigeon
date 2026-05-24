package com.openbubbles.openpigeon.pool

import android.animation.ValueAnimator
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.util.Log
import android.view.SurfaceHolder
import androidx.core.animation.doOnEnd
import com.openbubbles.openpigeon.R
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan
import kotlin.math.min
import android.util.TypedValue
import kotlin.math.max

class PoolRenderer(val holder: SurfaceHolder, val activity: PoolActivity) : Thread(), SurfaceHolder.Callback {
    var running = true

    var bitmap: Bitmap = BitmapFactory.decodeResource(activity.resources, R.drawable.pool_transparent)
    val cue: Bitmap = BitmapFactory.decodeResource(activity.resources, R.drawable.cue)

    init {
        holder.addCallback(this)
    }

    private val TARGET_FPS: Int = 60
    private val FRAME_TIME: Long = (1000 / TARGET_FPS).toLong()

    var cueRot = 0.0f
    var cueDraw = 0.0f
    var cueAlpha = 1.0f
    var cuePos = floatArrayOf(0f, 0f)
    var scratchRingPhase = 0f

    companion object {
        private const val WORLD_WIDTH = 784.743f
        private const val WORLD_HEIGHT = 441.189f
    }

    private data class PoolWallSegment(
        val ax: Float,
        val ay: Float,
        val bx: Float,
        val by: Float
    )

    private val iosAimWallSegments = listOf(
        PoolWallSegment(370.000000f, 50.000000f, 75.000000f, 50.000000f),
        PoolWallSegment(414.000000f, 50.000000f, 709.000000f, 50.000000f),
        PoolWallSegment(75.000000f, 50.000000f, 63.130043f, 33.903290f),
        PoolWallSegment(63.130043f, 33.903290f, 54.456924f, 19.282175f),
        PoolWallSegment(54.456924f, 19.282175f, 27.072823f, 9.736966f),
        PoolWallSegment(50.000000f, 75.000000f, 33.903290f, 63.130043f),
        PoolWallSegment(33.903290f, 63.130043f, 19.282175f, 54.456924f),
        PoolWallSegment(19.282175f, 54.456924f, 9.736966f, 27.072823f),
        PoolWallSegment(27.072823f, 9.736966f, 9.736966f, 27.072823f),
        PoolWallSegment(709.000000f, 50.000000f, 720.869934f, 33.903290f),
        PoolWallSegment(720.869934f, 33.903290f, 729.543030f, 19.282177f),
        PoolWallSegment(729.543030f, 19.282177f, 756.927124f, 9.736967f),
        PoolWallSegment(734.000000f, 75.000000f, 750.096680f, 63.130039f),
        PoolWallSegment(750.096680f, 63.130039f, 764.717773f, 54.456917f),
        PoolWallSegment(764.717773f, 54.456917f, 774.263000f, 27.072817f),
        PoolWallSegment(756.927124f, 9.736967f, 774.263000f, 27.072817f),
        PoolWallSegment(709.000000f, 390.000000f, 720.869934f, 406.096710f),
        PoolWallSegment(720.869934f, 406.096710f, 729.543030f, 420.717834f),
        PoolWallSegment(729.543030f, 420.717834f, 756.927124f, 430.263031f),
        PoolWallSegment(734.000000f, 365.000000f, 750.096680f, 376.869965f),
        PoolWallSegment(750.096680f, 376.869965f, 764.717773f, 385.543091f),
        PoolWallSegment(764.717773f, 385.543091f, 774.263000f, 412.927185f),
        PoolWallSegment(756.927124f, 430.263031f, 774.263000f, 412.927185f),
        PoolWallSegment(75.000000f, 390.000000f, 63.130043f, 406.096710f),
        PoolWallSegment(63.130043f, 406.096710f, 54.456924f, 420.717834f),
        PoolWallSegment(54.456924f, 420.717834f, 27.072823f, 430.263031f),
        PoolWallSegment(50.000000f, 365.000000f, 33.903290f, 376.869965f),
        PoolWallSegment(33.903290f, 376.869965f, 19.282175f, 385.543091f),
        PoolWallSegment(19.282175f, 385.543091f, 9.736966f, 412.927185f),
        PoolWallSegment(27.072823f, 430.263031f, 9.736966f, 412.927185f),
        PoolWallSegment(370.000000f, 50.000000f, 376.160095f, 34.155334f),
        PoolWallSegment(376.160095f, 34.155334f, 370.340881f, 17.121933f),
        PoolWallSegment(370.340881f, 17.121933f, 392.000000f, 0.000000f),
        PoolWallSegment(414.000000f, 50.000000f, 408.504089f, 33.912899f),
        PoolWallSegment(408.504089f, 33.912899f, 415.026520f, 17.136196f),
        PoolWallSegment(415.026520f, 17.136196f, 392.000000f, 0.000000f),
        PoolWallSegment(370.000000f, 390.000000f, 376.160095f, 405.844666f),
        PoolWallSegment(376.160095f, 405.844666f, 370.340881f, 422.878052f),
        PoolWallSegment(370.340881f, 422.878052f, 392.000000f, 440.000000f),
        PoolWallSegment(414.000000f, 390.000000f, 408.504089f, 406.087097f),
        PoolWallSegment(408.504089f, 406.087097f, 415.026520f, 422.863800f),
        PoolWallSegment(415.026520f, 422.863800f, 392.000000f, 440.000000f),
        PoolWallSegment(75.000000f, 390.000000f, 370.000000f, 390.000000f),
        PoolWallSegment(414.000000f, 390.000000f, 709.000000f, 390.000000f),
        PoolWallSegment(50.000000f, 75.000000f, 50.000000f, 365.000000f),
        PoolWallSegment(734.000000f, 75.000000f, 734.000000f, 365.000000f)
    )

    // 1.0f = maximum fitted size. Smaller values leave room for UI around the table.
    var tableVisualScale = 1f

    // Positive moves the table downward on screen, negative upward.
    var tableOffsetYPx = 0f

    private fun sideUiInsetPx(): Float {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            50f,
            activity.resources.displayMetrics
        )
    }

    val transform: Matrix
        get() = Matrix().apply {
            val surfaceWidth = holder.surfaceFrame.width().toFloat()
            val surfaceHeight = holder.surfaceFrame.height().toFloat()

            val rotatedWidth = WORLD_HEIGHT
            val rotatedHeight = WORLD_WIDTH

            val sideInset = sideUiInsetPx()
            val availableWidth = max(1f, surfaceWidth - sideInset * 2f)

            val fitScale = min(
                availableWidth / rotatedWidth,
                surfaceHeight / rotatedHeight
            )

            val scale = fitScale * tableVisualScale
            val visualWidth = rotatedWidth * scale
            val visualHeight = rotatedHeight * scale

            val left = sideInset + (availableWidth - visualWidth) * 0.5f
            val top = (surfaceHeight - visualHeight) * 0.5f + tableOffsetYPx

            postScale(scale, -scale)
            postRotate(-90f)
            postTranslate(left + visualWidth, top + visualHeight)
        }

    fun angleDifference(a: Double, b: Double): Double {
        var diff = (a - b + PI) % (2 * PI)
        if (diff < 0) diff += 2 * PI
        return diff - PI
    }

    private fun hasRemainingClaimedBalls(): Boolean {
        val stripes = activity.iAmStripes ?: return true
        return activity.poolBalls.any {
            !it.sunk && it.number != 0 && ((stripes && it.isStripe) || (!stripes && it.isSolid))
        }
    }

    private fun rayEndAtTableEdge(startX: Float, startY: Float, dirX: Float, dirY: Float): Pair<Float, Float> {
        var bestT = Float.POSITIVE_INFINITY
        var bestX = startX
        var bestY = startY

        fun cross(ax: Float, ay: Float, bx: Float, by: Float): Float {
            return ax * by - ay * bx
        }

        for (seg in iosAimWallSegments) {
            val sx = seg.bx - seg.ax
            val sy = seg.by - seg.ay
            val denom = cross(dirX, dirY, sx, sy)

            if (abs(denom) < 0.0001f)
                continue

            val qx = seg.ax - startX
            val qy = seg.ay - startY

            val t = cross(qx, qy, sx, sy) / denom
            val u = cross(qx, qy, dirX, dirY) / denom

            if (t > 0.001f && u >= -0.001f && u <= 1.001f && t < bestT) {
                bestT = t
                bestX = startX + dirX * t
                bestY = startY + dirY * t
            }
        }

        if (!bestT.isFinite()) {
            return Pair(startX, startY)
        }

        return Pair(bestX, bestY)
    }
    private fun drawAimAssist(canvas: Canvas) {
        if (activity.mode != PoolActivity.PoolMode.Aiming) return
        val cueBall = activity.cueBall ?: return
        val paint = Paint().apply {
            color = Color.WHITE
            strokeWidth = 2.5f
            style = Paint.Style.STROKE
            isAntiAlias = true
        }

        var closestBall: PoolActivity.PoolBall? = null
        var closestDistance = Float.MAX_VALUE
        var hitPointX = 0f
        var hitPointY = 0f

        for (ball in activity.poolBalls) {
            if (ball.number == 0 || ball.sunk) continue

            val otherBallX = ball.x - cueBall.x
            val otherBallY = ball.y - cueBall.y

            val slope = tan(cueRot)
            val a = slope * slope + 1
            val b = 2 * (-slope * otherBallY - otherBallX)
            val c = otherBallY * otherBallY + otherBallX * otherBallX - 400
            val discriminant = b * b - 4 * a * c
            if (discriminant <= 0) continue

            val pointsRight = cos(cueRot) > 0
            val direction = if (pointsRight) -1 else 1
            val xCoord = (-b + sqrt(discriminant) * direction) / 2 / a

            if (pointsRight && xCoord < 0) continue
            if (!pointsRight && xCoord > 0) continue

            if (abs(xCoord) < closestDistance) {
                closestDistance = abs(xCoord)
                closestBall = ball
                hitPointY = slope * xCoord + cueBall.y
                hitPointX = xCoord + cueBall.x
            }
        }

        if (closestBall == null) {
            val dirX = cos(cueRot)
            val dirY = sin(cueRot)
            val edge = rayEndAtTableEdge(cueBall.x, cueBall.y, dirX, dirY)

            val markerRadius = 9f
            val markerX = edge.first - dirX * markerRadius
            val markerY = edge.second - dirY * markerRadius
            val lineEndX = markerX - dirX * markerRadius
            val lineEndY = markerY - dirY * markerRadius

            canvas.drawLine(
                cueBall.x + dirX * 10f,
                cueBall.y + dirY * 10f,
                lineEndX,
                lineEndY,
                paint
            )

            canvas.drawCircle(markerX, markerY, markerRadius, paint)
            return
        }

        canvas.drawCircle(hitPointX, hitPointY, 9f, paint)
        canvas.drawLine(
            hitPointX - cos(cueRot) * 10f,
            hitPointY - sin(cueRot) * 10f,
            cueBall.x + cos(cueRot) * 10f,
            cueBall.y + sin(cueRot) * 10f,
            paint
        )

        val stripes = activity.iAmStripes
        val ball = closestBall

        if (stripes == null) {
            // Open table: allow trajectories for solids and stripes, but not the 8-ball.
            if (ball.number == 8) {
                canvas.drawLine(
                    hitPointX - 10f,
                    hitPointY - 10f,
                    hitPointX + 10f,
                    hitPointY + 10f,
                    paint
                )
                canvas.drawLine(
                    hitPointX + 10f,
                    hitPointY - 10f,
                    hitPointX - 10f,
                    hitPointY + 10f,
                    paint
                )
                return
            }
        } else {
            val hasMoreBalls = hasRemainingClaimedBalls()
            val isWrongBall =
                (stripes && !ball.isStripe && !(ball.number == 8 && !hasMoreBalls)) ||
                        (!stripes && !ball.isSolid && !(ball.number == 8 && !hasMoreBalls))

            if (isWrongBall) {
                canvas.drawLine(
                    hitPointX - 10f,
                    hitPointY - 10f,
                    hitPointX + 10f,
                    hitPointY + 10f,
                    paint
                )
                canvas.drawLine(
                    hitPointX + 10f,
                    hitPointY - 10f,
                    hitPointX - 10f,
                    hitPointY + 10f,
                    paint
                )
                return
            }
        }

        if (activity.isHard) {
            return
        }

        val interBallX = ball.x - hitPointX
        val interBallY = ball.y - hitPointY
        val interBallAngle = atan2(interBallY, interBallX)

        val directness = (angleDifference(
            interBallAngle.toDouble(),
            cueRot.toDouble()
        ) / (PI / 2)).toFloat()

        canvas.drawLine(
            ball.x,
            ball.y,
            ball.x + cos(interBallAngle) * 70f * (1 - abs(directness)),
            ball.y + sin(interBallAngle) * 70f * (1 - abs(directness)),
            paint
        )

        var tangentAngle = interBallAngle
        if (directness < 0) {
            tangentAngle += PI.toFloat() / 2
        } else {
            tangentAngle -= PI.toFloat() / 2
        }

        canvas.drawLine(
            hitPointX + cos(tangentAngle) * 10f,
            hitPointY + sin(tangentAngle) * 10f,
            hitPointX + cos(tangentAngle) * 10f + cos(tangentAngle) * 70f * abs(directness),
            hitPointY + sin(tangentAngle) * 10f + sin(tangentAngle) * 70f * abs(directness),
            paint
        )
    }

    external fun update(table: Long): Boolean

    private fun getBackgroundColor(): Int {
        return if (activity.isPoolDarkModeEnabled()) {
            0xFF2E2B2E.toInt()
        } else {
            0xFFC8C5C8.toInt()
        }
    }

    private fun drawFrame(canvas: Canvas) {
        synchronized(activity) {
            canvas.drawColor(getBackgroundColor())

            canvas.save()
            canvas.concat(transform)

            if (!update(activity.table) && activity.mode == PoolActivity.PoolMode.Playing) {
                activity.handleFinishPlay()
            }

            for (ball in activity.poolBalls) {
                if (!ball.sunk) continue
                ball.draw(canvas)
            }

            drawPockets(canvas)
            canvas.drawBitmap(bitmap, null, RectF(-0.057f, -0.189f, WORLD_WIDTH, WORLD_HEIGHT), null)

            for (ball in activity.poolBalls) {
                if (ball.sunk) continue
                ball.draw(canvas)
            }

            drawScratchRing(canvas)
            drawAimAssist(canvas)

            if (activity.call8Ball) {
                for (hole in activity.holes) {
                    canvas.drawCircle(
                        hole[0].toFloat(),
                        hole[1].toFloat(),
                        20f,
                        Paint().apply {
                            color = 0x55FFFFFF
                        }
                    )
                }
            }

            if (
                activity.mode == PoolActivity.PoolMode.Aiming ||
                activity.mode == PoolActivity.PoolMode.ReplayAiming ||
                activity.mode == PoolActivity.PoolMode.Playing
            ) {
                val translation = if (activity.mode != PoolActivity.PoolMode.Playing) {
                    val cueBall = activity.cueBall
                    if (cueBall == null) {
                        canvas.restore()
                        return
                    }
                    floatArrayOf(cueBall.x, cueBall.y)
                } else {
                    cuePos
                }

                canvas.translate(translation[0], translation[1])
                canvas.rotate(Math.toDegrees(cueRot.toDouble()).toFloat())

                canvas.drawBitmap(
                    cue,
                    null,
                    RectF(-520f - 20f - cueDraw, -5.0f, -20.0f - cueDraw, 5.0f),
                    Paint().apply {
                        alpha = (cueAlpha * 255).roundToInt()
                    }
                )
            }

            canvas.restore()
        }
    }

    private fun drawPockets(canvas: Canvas) {
        val pocketPaint = Paint().apply {
            color = Color.BLACK
            isAntiAlias = true
        }

        val pocketRadius = 28f

        for (hole in activity.holes) {
            canvas.drawCircle(
                hole[0].toFloat(),
                hole[1].toFloat(),
                pocketRadius,
                pocketPaint
            )
        }
    }

    private fun drawScratchRing(canvas: Canvas) {
        if (!(activity.mode == PoolActivity.PoolMode.Aiming && activity.scratch)) return
        val cueBall = activity.cueBall ?: return

        scratchRingPhase += 0.05f
        if (scratchRingPhase > (PI * 2).toFloat()) {
            scratchRingPhase -= (PI * 2).toFloat()
        }

        val baseRadius = 15f
        val pulse = ((sin(scratchRingPhase.toDouble()).toFloat() + 1f) * 0.5f) * 3f
        val radius = baseRadius + pulse

        canvas.drawCircle(
            cueBall.x,
            cueBall.y,
            radius,
            Paint().apply {
                color = Color.WHITE
                strokeWidth = 2.5f
                style = Paint.Style.STROKE
                isAntiAlias = true
                alpha = 180
            }
        )
    }

    var cueAnimator: ValueAnimator? = null
    fun setCueVisible(visible: Boolean) {
        cueAnimator?.cancel()
        cueAnimator = ValueAnimator.ofFloat(cueAlpha, if (visible) 1f else 0f)?.apply {
            duration = 200L
            doOnEnd { cueAnimator = null }
            addUpdateListener { animation -> cueAlpha = animation.animatedValue as Float }
            start()
        }
    }

    var hasSurface = false
    override fun run() {
        var startTime: Long
        var timeMillis: Long
        var waitTime: Long
        var frame = 0L

        while (running) {
            startTime = System.nanoTime()

            if (hasSurface) {
                val canvas = holder.lockHardwareCanvas()
                if (canvas != null) {
                    drawFrame(canvas)
                    holder.unlockCanvasAndPost(canvas)

                    frame += 1
                }
            }

            timeMillis = (System.nanoTime() - startTime) / 1000000

            waitTime = FRAME_TIME - timeMillis

            if (waitTime > 0) {
                try {
                    sleep(waitTime)
                } catch (e: InterruptedException) {
                }
            }
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        Log.d("Surface", "Created")
        hasSurface = true
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        Log.d("Surface", "Changed width: $width, Height: $height")
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        Log.d("Surface", "Destroyed")
        hasSurface = false
    }
}