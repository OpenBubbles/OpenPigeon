package com.openbubbles.openpigeon.pool

import android.animation.ValueAnimator
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
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

class PoolRenderer(val holder: SurfaceHolder, val activity: PoolActivity) : Thread(), SurfaceHolder.Callback {
    var running = true

    val bitmap: Bitmap = BitmapFactory.decodeResource(activity.resources, R.drawable.pool_transparent)
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

    val transform: Matrix
        get() = Matrix().apply {
            val desiredWidth = 441.189f
            val desiredHeight = 784.743f
            val scale = holder.surfaceFrame.width() / desiredWidth
            postScale(scale, -scale)
            postRotate(-90f)
            val extra = (holder.surfaceFrame.height().toFloat() - desiredHeight * scale) / 2
            postTranslate(holder.surfaceFrame.width().toFloat(), holder.surfaceFrame.height().toFloat() - extra)
        }


    fun angleDifference(a: Double, b: Double): Double {
        var diff = (a - b + PI) % (2 * PI)
        if (diff < 0) diff += 2 * PI
        return diff - PI
    }

    external fun update(table: Long): Boolean

    private fun drawFrame(canvas: Canvas) {
        synchronized(activity) {
            canvas.concat(transform)

            canvas.drawColor(Color.BLACK, PorterDuff.Mode.CLEAR)

            if (!update(activity.table) && activity.mode == PoolActivity.PoolMode.Playing) {
                activity.handleFinishPlay()
            }

            for (ball in activity.poolBalls) {
                if (!ball.sunk) continue
                ball.draw(canvas)
            }

            canvas.drawBitmap(bitmap, null, RectF(-0.057f, -0.189f, 784.743f, 441.189f), null)

            for (ball in activity.poolBalls) {
                if (ball.sunk) continue
                ball.draw(canvas)
            }

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

            if (activity.mode == PoolActivity.PoolMode.Aiming || activity.mode == PoolActivity.PoolMode.ReplayAiming || activity.mode == PoolActivity.PoolMode.Playing) {
                val translation = if (activity.mode != PoolActivity.PoolMode.Playing) floatArrayOf(
                    activity.cueBall.x,
                    activity.cueBall.y
                ) else cuePos

                if (activity.mode == PoolActivity.PoolMode.Aiming) {

                    if (activity.scratch) {
                        // draw halo around cue ball to indicate it is a touch target
                        canvas.drawCircle(
                            activity.cueBall.x,
                            activity.cueBall.y,
                            15f,
                            Paint().apply {
                                color = Color.WHITE
                                strokeWidth = 2.5f
                                style = Paint.Style.STROKE
                            })
                    }

                    var closestBall: PoolActivity.PoolBall? = null
                    var closestDistance = Float.MAX_VALUE
                    var hitPointX = 0F
                    var hitPointY = 0F
                    // hit visualization time!
                    // see if we hit any balls
                    for (ball in activity.poolBalls) {
                        if (ball.number == 0 || ball.sunk) continue // cue can't hit itself

                        // the pool ball's trajectory is a line at an angle.
                        // The spot where the ball will collide can be represented as a circle of radius otherBall + ourBall = 20
                        // where the line and the circle intersect is our hit location.

                        // let's move our cue ball to position 0, 0 to make our lives easier
                        val otherBallX = ball.x - activity.cueBall.x;
                        val otherBallY = ball.y - activity.cueBall.y;

                        val slope = tan(cueRot)
                        // equation is derived here: https://math.stackexchange.com/questions/228841/how-do-i-calculate-the-intersections-of-a-straight-line-and-a-circle
                        // c is dropped because it is zero (remember we moved the origin?)
                        val A = slope * slope + 1
                        val B = 2 * (-slope * otherBallY - otherBallX)
                        val C = otherBallY * otherBallY + otherBallX * otherBallX - 400
                        val discriminant = B * B - 4 * A * C
                        if (discriminant <= 0) continue // we miss circle, or are tangent (consider miss)

                        // now we're going to have two answers, one bigger and one smaller.
                        // we want to know the first point of contact, so what matters is if our angle points right (smaller one)
                        // or points left (bigger one)
                        val pointsRight = cos(cueRot) > 0
                        val direction = if (pointsRight) -1 else 1
                        val xCoord = (-B + sqrt(discriminant) * direction) / 2 / A

                        // throw away balls that are behind us
                        if (pointsRight && xCoord < 0) continue
                        if (!pointsRight && xCoord > 0) continue

                        if (abs(xCoord) < closestDistance) {
                            closestDistance = abs(xCoord)
                            closestBall = ball
                            hitPointY = slope * xCoord + activity.cueBall.y
                            hitPointX = xCoord + activity.cueBall.x
                        }
                    }
                    if (closestBall != null) {
                        // now we know where we hit, so let's draw a circle there.
                        val paint = Paint().apply {
                            color = Color.WHITE
                            strokeWidth = 2.5f
                            style = Paint.Style.STROKE
                        }
                        canvas.drawCircle(hitPointX, hitPointY, 9f, paint)
                        canvas.drawLine(
                            hitPointX - cos(cueRot) * 10f,
                            hitPointY - sin(cueRot) * 10f,
                            activity.cueBall.x + cos(cueRot) * 10f,
                            activity.cueBall.y + sin(cueRot) * 10f,
                            paint
                        )

                        val stripes = activity.iAmStripes
                        val ballNotMine =
                            stripes != null && ((stripes && !closestBall.isStripe) || (!stripes && !closestBall.isSolid))
                        val hasMoreBalls = stripes == null || activity.poolBalls.count { !it.sunk && ((stripes && it.isStripe) || (!stripes && it.isSolid)) } != 0
                        if ((ballNotMine || (closestBall.number == 8 && hasMoreBalls)) && (closestBall.number != 8 || hasMoreBalls)) {
                            // this is an invalid move
                            canvas.drawLine(
                                hitPointX - 10,
                                hitPointY - 10,
                                hitPointX + 10,
                                hitPointY + 10,
                                paint,
                            )
                            canvas.drawLine(
                                hitPointX + 10,
                                hitPointY - 10,
                                hitPointX - 10,
                                hitPointY + 10,
                                paint,
                            )
                        } else if (!activity.isHard) {
                            val interBallX = closestBall.x - hitPointX
                            val interBallY = closestBall.y - hitPointY

                            val interBallAngle = atan2(interBallY, interBallX)
                            val directness = (angleDifference(
                                interBallAngle.toDouble(),
                                cueRot.toDouble()
                            ) / (PI / 2)).toFloat()
                            canvas.drawLine(
                                closestBall.x,
                                closestBall.y,
                                closestBall.x + cos(interBallAngle) * 70f * (1 - abs(directness)),
                                closestBall.y + sin(interBallAngle) * 70f * (1 - abs(directness)),
                                paint,
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
                                hitPointX + cos(tangentAngle) * 10f + cos(tangentAngle) * 70f * abs(
                                    directness
                                ),
                                hitPointY + sin(tangentAngle) * 10f + sin(tangentAngle) * 70f * abs(
                                    directness
                                ),
                                paint,
                            )
                        }
                    }
                }

                // draw cue
                canvas.translate(translation[0], translation[1])
                canvas.rotate(Math.toDegrees(cueRot.toDouble()).toFloat())

                canvas.drawBitmap(
                    cue,
                    null,
                    RectF(-520f - 20f - cueDraw, -5.0f, -20.0f - cueDraw, 5.0f),
                    Paint().apply {
                        alpha = (cueAlpha * 255).roundToInt()
                    })
            }
        }
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
//            if ((frame % 60) == 0L) {
//                Log.i("PoolRenderer", "Did frame in $timeMillis ms")
//            }

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