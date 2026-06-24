package com.openbubbles.openpigeon.golf

import android.graphics.PointF
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * First native runtime physics layer for Mini Golf.
 *
 * This is intentionally isolated from GolfActivity so we can replace pieces
 * with exact iOS update: logic as we decode it.
 */
object GolfPhysics {
    private const val BALL_RADIUS = 6f

    private const val WALL_RESTITUTION = 0.72f
    private const val OBSTACLE_RESTITUTION = 0.78f
    private const val BOUNCY_RESTITUTION = 0.95f

    private const val FRICTION_PER_60FPS_FRAME = 0.985f
    private const val STOP_SPEED = 3.0f

    /*
     * Temporary slope strength. This makes slopes affect the ball now.
     * We can replace this with the decoded iOS value after update: is fully read.
     */
    private const val SLOPE_ACCELERATION = 240f
    private const val SLOPE_INFLUENCE_RADIUS = 44f

    private const val MAX_SUBSTEP_MOVE = 3.5f

    fun step(
        map: GolfMap,
        positionCourse: PointF,
        velocityCourse: PointF,
        dtSeconds: Float
    ): Boolean {
        if (dtSeconds <= 0f) return isStopped(velocityCourse)

        val speed = length(velocityCourse.x, velocityCourse.y)
        val subSteps = max(
            1,
            ceil((speed * dtSeconds) / MAX_SUBSTEP_MOVE).toInt()
        )

        val subDt = dtSeconds / subSteps.toFloat()

        repeat(subSteps) {
            applySlopes(map, positionCourse, velocityCourse, subDt)
            moveWithWallCollision(map, positionCourse, velocityCourse, subDt)
            resolveObstacleCollisions(map, positionCourse, velocityCourse)
        }

        val damping = FRICTION_PER_60FPS_FRAME.pow(dtSeconds * 60f)
        velocityCourse.x *= damping
        velocityCourse.y *= damping

        if (isStopped(velocityCourse)) {
            velocityCourse.set(0f, 0f)
            return true
        }

        return false
    }

    private fun moveWithWallCollision(
        map: GolfMap,
        pos: PointF,
        vel: PointF,
        dt: Float
    ) {
        val oldX = pos.x
        val oldY = pos.y

        val nextX = pos.x + vel.x * dt
        if (isBallPlayable(map, nextX, pos.y)) {
            pos.x = nextX
        } else {
            vel.x = -vel.x * WALL_RESTITUTION
            pos.x = oldX
        }

        val nextY = pos.y + vel.y * dt
        if (isBallPlayable(map, pos.x, nextY)) {
            pos.y = nextY
        } else {
            vel.y = -vel.y * WALL_RESTITUTION
            pos.y = oldY
        }

        /*
         * If the separated axis test still left us outside the playable path,
         * hard-reset to the last known safe point and heavily damp the bounce.
         */
        if (!isBallPlayable(map, pos.x, pos.y)) {
            pos.set(oldX, oldY)
            vel.x *= -0.35f
            vel.y *= -0.35f
        }
    }

    private fun isBallPlayable(map: GolfMap, x: Float, y: Float): Boolean {
        /*
         * Check the center and four radius probes. This is enough to make the
         * ball bounce before its sprite center crosses into blocked cells.
         */
        return isPlayableCenter(map, x, y) &&
                isPlayableCenter(map, x + BALL_RADIUS, y) &&
                isPlayableCenter(map, x - BALL_RADIUS, y) &&
                isPlayableCenter(map, x, y + BALL_RADIUS) &&
                isPlayableCenter(map, x, y - BALL_RADIUS)
    }

    private fun isPlayableCenter(map: GolfMap, x: Float, y: Float): Boolean {
        val outerRow = (y / GolfConstants.TILE_SIZE).roundToInt()
        val innerCol = (x / GolfConstants.TILE_SIZE).roundToInt()

        return map.isOpen(outerRow, innerCol)
    }

    private fun applySlopes(
        map: GolfMap,
        pos: PointF,
        vel: PointF,
        dt: Float
    ) {
        for (slope in map.slopes) {
            val dx = pos.x - slope.x
            val dy = pos.y - slope.y
            val d2 = dx * dx + dy * dy

            if (d2 > SLOPE_INFLUENCE_RADIUS * SLOPE_INFLUENCE_RADIUS) {
                continue
            }

            vel.x += slope.vx * SLOPE_ACCELERATION * dt
            vel.y += slope.vy * SLOPE_ACCELERATION * dt
        }
    }

    private fun resolveObstacleCollisions(
        map: GolfMap,
        pos: PointF,
        vel: PointF
    ) {
        for (obstacle in map.obstacles) {
            val radius = obstacleCollisionRadius(obstacle)
            val restitution = if (obstacle.bouncy) BOUNCY_RESTITUTION else OBSTACLE_RESTITUTION

            resolveCircleCollision(
                pos = pos,
                vel = vel,
                cx = obstacle.x,
                cy = obstacle.y,
                radius = radius + BALL_RADIUS,
                restitution = restitution
            )
        }
    }

    private fun obstacleCollisionRadius(obstacle: GolfObstacle): Float {
        val image = obstacle.image.ifBlank {
            when {
                obstacle.bouncy -> "golf_obstacle_round"
                obstacle.type == 2 -> "golf_obstacle_bar"
                obstacle.type == 3 -> "golf_obstacle_triangle"
                obstacle.type == 4 -> "golf_obstacle_round"
                obstacle.type == 5 -> "golf_obstacle_cross"
                else -> "golf_obstacle_square"
            }
        }

        val base = when (image) {
            "golf_obstacle_square2" -> 35f
            "golf_obstacle_round" -> 18.5f
            "golf_obstacle_round2" -> 36f
            "golf_obstacle_triangle" -> 15f
            "golf_obstacle_triangle2" -> 35f
            "golf_obstacle_bar" -> 23f
            "golf_obstacle_bar2",
            "golf_obstacles_bar2" -> 47.5f
            "golf_obstacle_cross" -> 47.5f
            else -> 15f
        }

        return base * obstacle.scale
    }

    private fun resolveCircleCollision(
        pos: PointF,
        vel: PointF,
        cx: Float,
        cy: Float,
        radius: Float,
        restitution: Float
    ) {
        val dx = pos.x - cx
        val dy = pos.y - cy
        val d2 = dx * dx + dy * dy

        if (d2 <= 0.0001f || d2 >= radius * radius) {
            return
        }

        val d = sqrt(d2)
        val nx = dx / d
        val ny = dy / d

        /*
         * Push the ball out of the obstacle.
         */
        pos.x = cx + nx * radius
        pos.y = cy + ny * radius

        /*
         * Reflect only if moving into the obstacle.
         */
        val vn = vel.x * nx + vel.y * ny
        if (vn < 0f) {
            vel.x -= (1f + restitution) * vn * nx
            vel.y -= (1f + restitution) * vn * ny
        }
    }

    private fun isStopped(vel: PointF): Boolean {
        return vel.x * vel.x + vel.y * vel.y <= STOP_SPEED * STOP_SPEED
    }

    private fun length(x: Float, y: Float): Float {
        return sqrt(x * x + y * y)
    }
}