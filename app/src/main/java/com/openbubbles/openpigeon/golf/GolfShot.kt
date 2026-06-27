package com.openbubbles.openpigeon.golf

import android.graphics.PointF
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

object GolfShot {
    const val AIM_POWER_MULTIPLIER = 2f
    const val AIM_POWER_OFFSET = 15f
    const val AIM_MAX_DIST = 300f
    const val AIM_DOT_COUNT = 13

    const val AIM_CANCEL_DIST = 12f

    const val LAUNCH_SPEED_MULTIPLIER = 2.0f

    data class Aim(
        val dist: Float,
        val rotation: Float
    ) {
        val active: Boolean get() = dist >= AIM_CANCEL_DIST

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

        if (dist < AIM_CANCEL_DIST) {
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
}