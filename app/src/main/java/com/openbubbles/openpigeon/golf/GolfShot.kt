package com.openbubbles.openpigeon.golf

import android.graphics.PointF
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * iOS Mini Golf shot/aim mechanics decoded from GolfScene/GolfScene2.
 *
 * Confirmed:
 *   touchMovedToPoint:
 *     dist = clamp(distance(move_start, touch) * 2 - 15, 0, 300)
 *     rotation = atan2(move_start.y - touch.y, move_start.x - touch.x)
 *
 *   GolfBall aim setter:
 *     if dist < 5, dist = 0
 *     13 preview dots at dist / 13 * index
 *
 *   ShootShoot:
 *     velocity = dist * 1.55 * direction(rotation)
 */
object GolfShot {
    const val AIM_POWER_MULTIPLIER = 2f
    const val AIM_POWER_OFFSET = 15f
    const val AIM_MAX_DIST = 300f
    const val AIM_DEADZONE = 5f
    const val AIM_DOT_COUNT = 13

    const val LAUNCH_SPEED_MULTIPLIER = 1.55f

    /*
     * Temporary until we fully decode -[GolfScene update:].
     * This only gives the ball a usable first-pass roll/stop.
     */
    private const val TEMP_DAMPING_PER_60FPS_FRAME = 0.985f
    private const val TEMP_STOP_SPEED = 3.0f

    data class Aim(
        val dist: Float,
        val rotation: Float
    ) {
        val active: Boolean get() = dist > 0f

        companion object {
            val NONE = Aim(0f, 0f)
        }
    }

    fun computeAim(moveStartVisual: PointF, currentTouchVisual: PointF): Aim {
        val dx = moveStartVisual.x - currentTouchVisual.x
        val dy = moveStartVisual.y - currentTouchVisual.y

        val rawDistance = sqrt(dx * dx + dy * dy)

        var dist = (rawDistance * AIM_POWER_MULTIPLIER - AIM_POWER_OFFSET)
            .coerceIn(0f, AIM_MAX_DIST)

        if (dist < AIM_DEADZONE) {
            dist = 0f
        }

        val rotation = atan2(dy, dx)

        return Aim(
            dist = dist,
            rotation = rotation
        )
    }

    fun launchVelocityVisual(aim: Aim): PointF {
        if (!aim.active) return PointF(0f, 0f)

        return PointF(
            aim.dist * LAUNCH_SPEED_MULTIPLIER * cos(aim.rotation),
            aim.dist * LAUNCH_SPEED_MULTIPLIER * sin(aim.rotation)
        )
    }

    fun previewDotsVisual(ballVisual: PointF, aim: Aim): List<PointF> {
        if (!aim.active) return emptyList()

        val out = ArrayList<PointF>(AIM_DOT_COUNT)
        val cosR = cos(aim.rotation)
        val sinR = sin(aim.rotation)

        for (i in 0 until AIM_DOT_COUNT) {
            val r = aim.dist / AIM_DOT_COUNT * i

            out.add(
                PointF(
                    ballVisual.x + cosR * r,
                    ballVisual.y + sinR * r
                )
            )
        }

        return out
    }

    fun temporaryDampingFactor(dtSeconds: Float): Float {
        val framesAt60 = dtSeconds * 60f
        return TEMP_DAMPING_PER_60FPS_FRAME.pow(framesAt60)
    }

    fun isTemporaryStopped(vx: Float, vy: Float): Boolean {
        return vx * vx + vy * vy <= TEMP_STOP_SPEED * TEMP_STOP_SPEED
    }
}