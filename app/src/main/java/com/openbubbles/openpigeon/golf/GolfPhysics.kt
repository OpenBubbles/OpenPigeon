package com.openbubbles.openpigeon.golf

import android.graphics.PointF
import kotlin.math.pow
import kotlin.math.sqrt

object GolfPhysics {
    private const val FLAG_PULL_RADIUS = 30f

    private const val HOLE_CAPTURE_RADIUS = 6.5f
    private const val HOLE_CAPTURE_MAX_SPEED = 400f

    private const val HOLE_PULL_MIN_SPEED = 14f
    private const val HOLE_SINK_RADIUS = 2.0f
    private const val HOLE_SINK_DAMPING_PER_60FPS_FRAME = 0.95f

    private const val HOLE_SETTLED_SPEED = 1.0f

    /**
     * Physics movement and collision resolution are native Box2D only.
     * This wrapper intentionally has no Kotlin wall/obstacle/slope fallback.
     */
    fun step(
        map: GolfMap,
        positionCourse: PointF,
        velocityCourse: PointF,
        dtSeconds: Float
    ): Boolean {
        return GolfNativePhysics.step(
            map = map,
            positionCourse = positionCourse,
            velocityCourse = velocityCourse,
            dtSeconds = dtSeconds
        )
    }

    data class HoleStep(
        val flagPulled: Boolean,
        val captured: Boolean,
        val settled: Boolean = false
    )

    /**
     * Game-rule cup behavior stays outside collision physics. The ball movement,
     * walls, obstacles, bounces, damping, and slopes remain in native Box2D.
     */
    fun applyHoleCup(
        map: GolfMap,
        positionCourse: PointF,
        velocityCourse: PointF,
        dtSeconds: Float,
        alreadyCaptured: Boolean = false
    ): HoleStep {
        val dxToHole = map.hole.x - positionCourse.x
        val dyToHole = map.hole.y - positionCourse.y
        val distanceToHole = sqrt(dxToHole * dxToHole + dyToHole * dyToHole)
        val speed = length(velocityCourse.x, velocityCourse.y)

        val capturedNow =
            alreadyCaptured ||
                    (
                            distanceToHole < HOLE_CAPTURE_RADIUS &&
                                    speed < HOLE_CAPTURE_MAX_SPEED
                            )

        if (!capturedNow) {
            return HoleStep(
                flagPulled = distanceToHole < FLAG_PULL_RADIUS,
                captured = false,
                settled = false
            )
        }

        /*
         * iOS behavior:
         * Once inside/captured, if the ball is not fully holed yet, replace the
         * velocity with a vector aimed at the cup center. The magnitude is at least 14.
         */
        if (distanceToHole > 0.001f && distanceToHole >= HOLE_SINK_RADIUS) {
            val pullSpeed = maxOf(speed, HOLE_PULL_MIN_SPEED)
            val nx = dxToHole / distanceToHole
            val ny = dyToHole / distanceToHole

            velocityCourse.x = nx * pullSpeed
            velocityCourse.y = ny * pullSpeed
        }

        val sunk =
            distanceToHole < HOLE_SINK_RADIUS &&
                    speed < HOLE_CAPTURE_MAX_SPEED

        if (sunk) {
            val damping = HOLE_SINK_DAMPING_PER_60FPS_FRAME.pow(dtSeconds * 60f)
            velocityCourse.x *= damping
            velocityCourse.y *= damping
        }

        val afterSpeed = length(velocityCourse.x, velocityCourse.y)

        val settled = sunk && afterSpeed < HOLE_SETTLED_SPEED
        if (settled) {
            velocityCourse.set(0f, 0f)
        }

        return HoleStep(
            flagPulled = true,
            captured = true,
            settled = settled
        )
    }

    private fun length(x: Float, y: Float): Float {
        return sqrt(x * x + y * y)
    }
}
