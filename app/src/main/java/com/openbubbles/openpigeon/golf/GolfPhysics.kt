package com.openbubbles.openpigeon.golf

import android.graphics.PointF
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

object GolfPhysics {
    private const val FLAG_PULL_RADIUS = 30f

    private const val HOLE_CAPTURE_RADIUS = 6.5f
    private const val HOLE_CAPTURE_MAX_SPEED = 400f

    private const val HOLE_PULL_MIN_SPEED = 14f

    private const val HOLE_RIM_HALF_SIZE = 1.42f
    private const val HOLE_RIM_RESTITUTION = 0.5f
    private const val MAX_CUP_RIM_BOUNCES_PER_FRAME = 2

    private const val HOLE_SINK_RADIUS = 2.0f
    private const val HOLE_SINK_DAMPING_PER_60FPS_FRAME = 0.95f

    private const val HOLE_SETTLED_SPEED = 1.30f

    private const val EPSILON = 0.000001f

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

    fun applyHoleCup(
        map: GolfMap,
        positionCourse: PointF,
        velocityCourse: PointF,
        dtSeconds: Float,
        alreadyCaptured: Boolean = false
    ): HoleStep {
        val rawX = positionCourse.x
        val rawY = positionCourse.y
        val rawVx = velocityCourse.x
        val rawVy = velocityCourse.y

        val dxToHole = map.hole.x - rawX
        val dyToHole = map.hole.y - rawY
        val distanceToHole = length(dxToHole, dyToHole)
        val speed = length(rawVx, rawVy)

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

        val previousPosition = PointF(
            rawX - rawVx * dtSeconds,
            rawY - rawVy * dtSeconds
        )

        val rimBounce = applySweptCupRimIfNeeded(
            hole = map.hole,
            previousPosition = previousPosition,
            positionCourse = positionCourse,
            velocityCourse = velocityCourse,
            dtSeconds = dtSeconds,
            capturedNow = capturedNow
        )

        if (rimBounce) {
            applySinkDamping(velocityCourse, dtSeconds)
        } else {
            val currentDxToHole = map.hole.x - positionCourse.x
            val currentDyToHole = map.hole.y - positionCourse.y
            val currentDistanceToHole = length(currentDxToHole, currentDyToHole)
            val currentSpeed = length(velocityCourse.x, velocityCourse.y)

            if (currentDistanceToHole > EPSILON && currentDistanceToHole >= HOLE_SINK_RADIUS) {
                val pullSpeed = maxOf(currentSpeed, HOLE_PULL_MIN_SPEED)
                val nx = currentDxToHole / currentDistanceToHole
                val ny = currentDyToHole / currentDistanceToHole

                velocityCourse.x = nx * pullSpeed
                velocityCourse.y = ny * pullSpeed
            } else {
                applySinkDamping(velocityCourse, dtSeconds)
            }
        }

        val afterSpeed = length(velocityCourse.x, velocityCourse.y)
        val afterDistanceToHole = distance(
            positionCourse.x,
            positionCourse.y,
            map.hole.x,
            map.hole.y
        )

        val settled =
            afterDistanceToHole <= HOLE_SINK_RADIUS &&
                    afterSpeed < HOLE_SETTLED_SPEED

        if (settled) {
            velocityCourse.set(0f, 0f)
        }

        return HoleStep(
            flagPulled = true,
            captured = true,
            settled = settled
        )
    }

    private data class CupRimHit(
        val t: Float,
        val hitXWall: Boolean,
        val hitYWall: Boolean
    )

    private fun applySweptCupRimIfNeeded(
        hole: PointF,
        previousPosition: PointF,
        positionCourse: PointF,
        velocityCourse: PointF,
        dtSeconds: Float,
        capturedNow: Boolean
    ): Boolean {
        if (!capturedNow || dtSeconds <= EPSILON) {
            return false
        }

        var localX = previousPosition.x - hole.x
        var localY = previousPosition.y - hole.y

        var vx = velocityCourse.x
        var vy = velocityCourse.y

        var remainingDt = dtSeconds
        var bounceCount = 0
        var bounced = false

        while (bounceCount < MAX_CUP_RIM_BOUNCES_PER_FRAME && remainingDt > EPSILON) {
            val hit = findNextCupRimHit(
                startLocalX = localX,
                startLocalY = localY,
                velocityX = vx,
                velocityY = vy,
                dtSeconds = remainingDt
            ) ?: break

            val hitT = clamp(hit.t, 0f, 1f)
            val hitDt = remainingDt * hitT

            localX += vx * hitDt
            localY += vy * hitDt

            localX = clamp(
                localX,
                -HOLE_RIM_HALF_SIZE,
                HOLE_RIM_HALF_SIZE
            )
            localY = clamp(
                localY,
                -HOLE_RIM_HALF_SIZE,
                HOLE_RIM_HALF_SIZE
            )

            if (hit.hitXWall) {
                vx = -vx * HOLE_RIM_RESTITUTION
            }

            if (hit.hitYWall) {
                vy = -vy * HOLE_RIM_RESTITUTION
            }

            remainingDt -= hitDt
            bounceCount++
            bounced = true
        }

        if (!bounced) {
            return false
        }

        localX += vx * remainingDt
        localY += vy * remainingDt

        positionCourse.x = hole.x + clamp(
            localX,
            -HOLE_RIM_HALF_SIZE,
            HOLE_RIM_HALF_SIZE
        )
        positionCourse.y = hole.y + clamp(
            localY,
            -HOLE_RIM_HALF_SIZE,
            HOLE_RIM_HALF_SIZE
        )

        velocityCourse.x = vx
        velocityCourse.y = vy

        return true
    }

    private fun findNextCupRimHit(
        startLocalX: Float,
        startLocalY: Float,
        velocityX: Float,
        velocityY: Float,
        dtSeconds: Float
    ): CupRimHit? {
        val endLocalX = startLocalX + velocityX * dtSeconds
        val endLocalY = startLocalY + velocityY * dtSeconds

        var hitT = Float.POSITIVE_INFINITY
        var hitXWall = false
        var hitYWall = false

        if (velocityX > 0f &&
            startLocalX <= HOLE_RIM_HALF_SIZE &&
            endLocalX > HOLE_RIM_HALF_SIZE
        ) {
            val t = crossingT(
                start = startLocalX,
                end = endLocalX,
                boundary = HOLE_RIM_HALF_SIZE
            )
            if (t != null) {
                if (t < hitT - 0.0001f) {
                    hitT = t
                    hitXWall = true
                    hitYWall = false
                } else if (abs(t - hitT) < 0.0001f) {
                    hitXWall = true
                }
            }
        } else if (velocityX < 0f &&
            startLocalX >= -HOLE_RIM_HALF_SIZE &&
            endLocalX < -HOLE_RIM_HALF_SIZE
        ) {
            val t = crossingT(
                start = startLocalX,
                end = endLocalX,
                boundary = -HOLE_RIM_HALF_SIZE
            )
            if (t != null) {
                if (t < hitT - 0.0001f) {
                    hitT = t
                    hitXWall = true
                    hitYWall = false
                } else if (abs(t - hitT) < 0.0001f) {
                    hitXWall = true
                }
            }
        }

        if (velocityY > 0f &&
            startLocalY <= HOLE_RIM_HALF_SIZE &&
            endLocalY > HOLE_RIM_HALF_SIZE
        ) {
            val t = crossingT(
                start = startLocalY,
                end = endLocalY,
                boundary = HOLE_RIM_HALF_SIZE
            )
            if (t != null) {
                if (t < hitT - 0.0001f) {
                    hitT = t
                    hitXWall = false
                    hitYWall = true
                } else if (abs(t - hitT) < 0.0001f) {
                    hitYWall = true
                }
            }
        } else if (velocityY < 0f &&
            startLocalY >= -HOLE_RIM_HALF_SIZE &&
            endLocalY < -HOLE_RIM_HALF_SIZE
        ) {
            val t = crossingT(
                start = startLocalY,
                end = endLocalY,
                boundary = -HOLE_RIM_HALF_SIZE
            )
            if (t != null) {
                if (t < hitT - 0.0001f) {
                    hitT = t
                    hitXWall = false
                    hitYWall = true
                } else if (abs(t - hitT) < 0.0001f) {
                    hitYWall = true
                }
            }
        }

        if (!hitXWall && !hitYWall) {
            return null
        }

        return CupRimHit(
            t = clamp(hitT, 0f, 1f),
            hitXWall = hitXWall,
            hitYWall = hitYWall
        )
    }

    private fun crossingT(
        start: Float,
        end: Float,
        boundary: Float
    ): Float? {
        val delta = end - start
        if (abs(delta) <= EPSILON) {
            return null
        }

        val t = (boundary - start) / delta
        if (t < 0f || t > 1f) {
            return null
        }

        return t
    }

    private fun applySinkDamping(
        velocityCourse: PointF,
        dtSeconds: Float
    ) {
        val damping = HOLE_SINK_DAMPING_PER_60FPS_FRAME.pow(dtSeconds * 60f)
        velocityCourse.x *= damping
        velocityCourse.y *= damping
    }

    private fun length(x: Float, y: Float): Float {
        return sqrt(x * x + y * y)
    }

    private fun distance(
        ax: Float,
        ay: Float,
        bx: Float,
        by: Float
    ): Float {
        return length(ax - bx, ay - by)
    }

    private fun clamp(
        value: Float,
        minValue: Float,
        maxValue: Float
    ): Float {
        return max(minValue, min(value, maxValue))
    }
}