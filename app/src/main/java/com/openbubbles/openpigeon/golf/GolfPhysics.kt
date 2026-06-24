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

object GolfPhysics {
    private const val BALL_RADIUS = 4f
    private const val WALL_HALF_THICKNESS = 3f
    private const val WALL_COLLISION_RADIUS = BALL_RADIUS + WALL_HALF_THICKNESS

    private const val WALL_RESTITUTION = 0.72f
    private const val OBSTACLE_RESTITUTION = 0.78f
    private const val BOUNCY_RESTITUTION = 0.95f

    private const val FRICTION_PER_60FPS_FRAME = 0.985f
    private const val STOP_SPEED = 3.0f
    private const val FLAG_PULL_RADIUS = 26f

    private const val HOLE_CAPTURE_RADIUS = 6.5f
    private const val HOLE_CAPTURE_MAX_SPEED = 85f

    private const val HOLE_CUP_PULL_RADIUS = 11f
    private const val HOLE_CUP_PULL_ACCELERATION = 150f
    private const val HOLE_TRAP_RADIUS = 5.0f
    private const val HOLE_TRAP_PULL_ACCELERATION = 260f
    private const val HOLE_TRAP_DAMPING_PER_60FPS_FRAME = 0.88f
    private const val HOLE_SETTLED_RADIUS = 0.75f
    private const val HOLE_SETTLED_SPEED = 2.0f
    private const val SLOPE_ACCELERATION = 240f
    private const val SLOPE_INFLUENCE_RADIUS = 44f

    private const val MAX_SUBSTEP_MOVE = 2.0f

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

            resolveDiagonalWallCollisions(map, positionCourse, velocityCourse)

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

        if (!isBallPlayable(map, pos.x, pos.y)) {
            pos.set(oldX, oldY)
            vel.x *= -0.35f
            vel.y *= -0.35f
        }
    }

    private fun isBallPlayable(map: GolfMap, x: Float, y: Float): Boolean {
        val r = WALL_COLLISION_RADIUS
        val d = r * 0.70710677f

        return isPlayableCenter(map, x, y) &&

                // Cardinal probes.
                isPlayableCenter(map, x + r, y) &&
                isPlayableCenter(map, x - r, y) &&
                isPlayableCenter(map, x, y + r) &&
                isPlayableCenter(map, x, y - r) &&

                // Diagonal/corner probes.
                isPlayableCenter(map, x + d, y + d) &&
                isPlayableCenter(map, x + d, y - d) &&
                isPlayableCenter(map, x - d, y + d) &&
                isPlayableCenter(map, x - d, y - d)
    }

    private fun isPlayableCenter(map: GolfMap, x: Float, y: Float): Boolean {
        val outerRow = (y / GolfConstants.TILE_SIZE).roundToInt()
        val innerCol = (x / GolfConstants.TILE_SIZE).roundToInt()

        return map.isOpen(outerRow, innerCol)
    }

    private data class DiagonalWall(
        val ax: Float,
        val ay: Float,
        val bx: Float,
        val by: Float,
        val nx: Float,
        val ny: Float
    )

    private fun resolveDiagonalWallCollisions(
        map: GolfMap,
        posCourse: PointF,
        velCourse: PointF
    ) {
        val posVisual = PointF(
            posCourse.x,
            map.mapSize - posCourse.y
        )

        val velVisual = PointF(
            velCourse.x,
            -velCourse.y
        )

        forEachDiagonalWallVisual(map) { wall ->
            resolveOneSidedSegmentCollision(
                pos = posVisual,
                vel = velVisual,
                wall = wall,
                radius = WALL_COLLISION_RADIUS,
                restitution = WALL_RESTITUTION
            )
        }

        posCourse.x = posVisual.x
        posCourse.y = map.mapSize - posVisual.y

        velCourse.x = velVisual.x
        velCourse.y = -velVisual.y
    }

    private inline fun forEachDiagonalWallVisual(
        map: GolfMap,
        block: (DiagonalWall) -> Unit
    ) {
        for (visualRow in 0 until visualRows(map)) {
            for (visualCol in 0 until visualCols(map)) {
                if (visualCellValue(map, visualCol, visualRow) != 3) continue

                val rect = visualCellRectCourseUnits(visualCol, visualRow)
                val corner = specialValue3CutCornerPhysics(map, visualCol, visualRow)

                when (corner) {
                    CutCornerPhysics.TOP_LEFT -> {
                        block(
                            makeDiagonalWall(
                                ax = rect.right,
                                ay = rect.top,
                                bx = rect.left,
                                by = rect.bottom,
                                playableX = rect.right,
                                playableY = rect.bottom
                            )
                        )
                    }

                    CutCornerPhysics.TOP_RIGHT -> {
                        block(
                            makeDiagonalWall(
                                ax = rect.left,
                                ay = rect.top,
                                bx = rect.right,
                                by = rect.bottom,
                                playableX = rect.left,
                                playableY = rect.bottom
                            )
                        )
                    }

                    CutCornerPhysics.BOTTOM_LEFT -> {
                        block(
                            makeDiagonalWall(
                                ax = rect.left,
                                ay = rect.top,
                                bx = rect.right,
                                by = rect.bottom,
                                playableX = rect.right,
                                playableY = rect.top
                            )
                        )
                    }

                    CutCornerPhysics.BOTTOM_RIGHT -> {
                        block(
                            makeDiagonalWall(
                                ax = rect.right,
                                ay = rect.top,
                                bx = rect.left,
                                by = rect.bottom,
                                playableX = rect.left,
                                playableY = rect.top
                            )
                        )
                    }
                }
            }
        }
    }

    private fun resolveOneSidedSegmentCollision(
        pos: PointF,
        vel: PointF,
        wall: DiagonalWall,
        radius: Float,
        restitution: Float
    ) {
        val abx = wall.bx - wall.ax
        val aby = wall.by - wall.ay
        val ab2 = abx * abx + aby * aby

        if (ab2 <= 0.0001f) return

        val apx = pos.x - wall.ax
        val apy = pos.y - wall.ay

        val t = (apx * abx + apy * aby) / ab2

        if (t <= 0.001f || t >= 0.999f) return

        val closestX = wall.ax + abx * t
        val closestY = wall.ay + aby * t

        val signedDistance =
            (pos.x - closestX) * wall.nx +
                    (pos.y - closestY) * wall.ny

        if (signedDistance >= radius) return
        if (signedDistance <= -radius) return

        val correction = radius - signedDistance
        pos.x += wall.nx * correction
        pos.y += wall.ny * correction

        val vn = vel.x * wall.nx + vel.y * wall.ny
        if (vn < 0f) {
            vel.x -= (1f + restitution) * vn * wall.nx
            vel.y -= (1f + restitution) * vn * wall.ny
        }
    }

    private fun makeDiagonalWall(
        ax: Float,
        ay: Float,
        bx: Float,
        by: Float,
        playableX: Float,
        playableY: Float
    ): DiagonalWall {
        val abx = bx - ax
        val aby = by - ay
        val len = sqrt(abx * abx + aby * aby).coerceAtLeast(0.0001f)

        var nx = -aby / len
        var ny = abx / len

        val side = (playableX - ax) * nx + (playableY - ay) * ny
        if (side < 0f) {
            nx = -nx
            ny = -ny
        }

        return DiagonalWall(
            ax = ax,
            ay = ay,
            bx = bx,
            by = by,
            nx = nx,
            ny = ny
        )
    }

    private enum class CutCornerPhysics {
        TOP_LEFT,
        TOP_RIGHT,
        BOTTOM_LEFT,
        BOTTOM_RIGHT
    }

    private data class PhysicsRectF(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float
    )

    private fun visualCellRectCourseUnits(
        visualCol: Int,
        visualRow: Int
    ): PhysicsRectF {
        val half = GolfConstants.TILE_SIZE * 0.5f

        val centerX = visualCol * GolfConstants.TILE_SIZE
        val centerY = (visualRow + 1) * GolfConstants.TILE_SIZE

        return PhysicsRectF(
            left = centerX - half,
            top = centerY - half,
            right = centerX + half,
            bottom = centerY + half
        )
    }

    private fun visualCellCenterCourseUnits(
        visualCol: Int,
        visualRow: Int
    ): PointF {
        val r = visualCellRectCourseUnits(visualCol, visualRow)
        return PointF(
            (r.left + r.right) * 0.5f,
            (r.top + r.bottom) * 0.5f
        )
    }

    private fun specialValue3CutCornerPhysics(
        map: GolfMap,
        visualCol: Int,
        visualRow: Int
    ): CutCornerPhysics {
        val topBlocked = !visualIsOpen(map, visualCol, visualRow - 1)
        val bottomBlocked = !visualIsOpen(map, visualCol, visualRow + 1)
        val leftBlocked = !visualIsOpen(map, visualCol - 1, visualRow)
        val rightBlocked = !visualIsOpen(map, visualCol + 1, visualRow)

        return when {
            topBlocked && leftBlocked -> CutCornerPhysics.TOP_LEFT
            topBlocked && rightBlocked -> CutCornerPhysics.TOP_RIGHT
            bottomBlocked && leftBlocked -> CutCornerPhysics.BOTTOM_LEFT
            bottomBlocked && rightBlocked -> CutCornerPhysics.BOTTOM_RIGHT
            else -> CutCornerPhysics.BOTTOM_LEFT
        }
    }

    private fun visualCols(map: GolfMap): Int {
        return map.yCells
    }

    private fun visualRows(map: GolfMap): Int {
        return map.xCells
    }

    private fun visualIsOpen(
        map: GolfMap,
        visualCol: Int,
        visualRow: Int
    ): Boolean {
        val original = visualToOriginalCellPhysics(map, visualCol, visualRow) ?: return false
        return map.isOpen(original.x, original.y)
    }

    private fun visualCellValue(
        map: GolfMap,
        visualCol: Int,
        visualRow: Int
    ): Int {
        val original = visualToOriginalCellPhysics(map, visualCol, visualRow) ?: return 1
        return map.grid[original.x][original.y]
    }

    private fun visualToOriginalCellPhysics(
        map: GolfMap,
        visualCol: Int,
        visualRow: Int
    ): Cell? {
        val outerRow = map.xCells - 1 - visualRow
        val innerCol = visualCol

        if (outerRow !in 0 until map.xCells || innerCol !in 0 until map.yCells) {
            return null
        }

        return Cell(outerRow, innerCol)
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

    private enum class ObstacleCollisionShape {
        RECT,
        CIRCLE,
        TRIANGLE,
        CROSS
    }

    private data class ObstacleCollisionSpec(
        val image: String,
        val width: Float,
        val height: Float,
        val shape: ObstacleCollisionShape
    )

    private fun resolveObstacleCollisions(
        map: GolfMap,
        pos: PointF,
        vel: PointF
    ) {
        for (obstacle in map.obstacles) {
            val spec = obstacleCollisionSpec(obstacle)
            val restitution = if (obstacle.bouncy) BOUNCY_RESTITUTION else OBSTACLE_RESTITUTION

            val width = spec.width * obstacle.scale
            val height = spec.height * obstacle.scale

            when (spec.shape) {
                ObstacleCollisionShape.CIRCLE -> {
                    val radius = (if (width < height) width else height) * 0.5f

                    resolveCircleCollision(
                        pos = pos,
                        vel = vel,
                        cx = obstacle.x,
                        cy = obstacle.y,
                        radius = radius + BALL_RADIUS,
                        restitution = restitution
                    )
                }

                ObstacleCollisionShape.TRIANGLE -> {
                    resolveRotatedRightTriangleCollision(
                        pos = pos,
                        vel = vel,
                        cx = obstacle.x,
                        cy = obstacle.y,
                        width = width,
                        height = height,
                        rotationRadians = obstacle.rotation,
                        restitution = restitution
                    )
                }

                ObstacleCollisionShape.CROSS -> {
                    resolveCrossCollision(
                        pos = pos,
                        vel = vel,
                        cx = obstacle.x,
                        cy = obstacle.y,
                        width = width,
                        height = height,
                        rotationRadians = obstacle.rotation,
                        restitution = restitution
                    )
                }

                ObstacleCollisionShape.RECT -> {
                    resolveRotatedRectCollision(
                        pos = pos,
                        vel = vel,
                        cx = obstacle.x,
                        cy = obstacle.y,
                        width = width,
                        height = height,
                        rotationRadians = obstacle.rotation,
                        restitution = restitution
                    )
                }
            }
        }
    }

    private fun obstacleCollisionSpec(obstacle: GolfObstacle): ObstacleCollisionSpec {
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

        return when (image) {
            "golf_obstacle_square" -> ObstacleCollisionSpec(
                image = image,
                width = 30f,
                height = 30f,
                shape = ObstacleCollisionShape.RECT
            )

            "golf_obstacle_square2" -> ObstacleCollisionSpec(
                image = image,
                width = 70f,
                height = 70f,
                shape = ObstacleCollisionShape.RECT
            )

            "golf_obstacle_bar" -> ObstacleCollisionSpec(
                image = image,
                width = 46f,
                height = 8f,
                shape = ObstacleCollisionShape.RECT
            )

            "golf_obstacle_bar2",
            "golf_obstacles_bar2" -> ObstacleCollisionSpec(
                image = image,
                width = 95f,
                height = 16f,
                shape = ObstacleCollisionShape.RECT
            )

            "golf_obstacle_round" -> ObstacleCollisionSpec(
                image = image,
                width = 37f,
                height = 37f,
                shape = ObstacleCollisionShape.CIRCLE
            )

            "golf_obstacle_round2" -> ObstacleCollisionSpec(
                image = image,
                width = 72f,
                height = 72f,
                shape = ObstacleCollisionShape.CIRCLE
            )

            "golf_obstacle_triangle" -> ObstacleCollisionSpec(
                image = image,
                width = 30f,
                height = 30f,
                shape = ObstacleCollisionShape.TRIANGLE
            )

            "golf_obstacle_triangle2" -> ObstacleCollisionSpec(
                image = image,
                width = 70f,
                height = 70f,
                shape = ObstacleCollisionShape.TRIANGLE
            )

            "golf_obstacle_cross" -> ObstacleCollisionSpec(
                image = image,
                width = 95f,
                height = 95f,
                shape = ObstacleCollisionShape.CROSS
            )

            else -> ObstacleCollisionSpec(
                image = image,
                width = 30f,
                height = 30f,
                shape = ObstacleCollisionShape.RECT
            )
        }
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

        pos.x = cx + nx * radius
        pos.y = cy + ny * radius

        val vn = vel.x * nx + vel.y * ny
        if (vn < 0f) {
            vel.x -= (1f + restitution) * vn * nx
            vel.y -= (1f + restitution) * vn * ny
        }
    }

    private fun resolveCrossCollision(
        pos: PointF,
        vel: PointF,
        cx: Float,
        cy: Float,
        width: Float,
        height: Float,
        rotationRadians: Float,
        restitution: Float
    ) {
        val minSide = if (width < height) width else height
        val armThickness = (minSide * 0.17f).coerceIn(12f, 18f)

        repeat(2) {
            // Horizontal arm.
            resolveRotatedRectCollision(
                pos = pos,
                vel = vel,
                cx = cx,
                cy = cy,
                width = width,
                height = armThickness,
                rotationRadians = rotationRadians,
                restitution = restitution
            )

            // Vertical arm.
            resolveRotatedRectCollision(
                pos = pos,
                vel = vel,
                cx = cx,
                cy = cy,
                width = armThickness,
                height = height,
                rotationRadians = rotationRadians,
                restitution = restitution
            )
        }
    }

    private fun resolveRotatedRectCollision(
        pos: PointF,
        vel: PointF,
        cx: Float,
        cy: Float,
        width: Float,
        height: Float,
        rotationRadians: Float,
        restitution: Float
    ) {
        val dx = pos.x - cx
        val dy = pos.y - cy

        val cosR = cos(rotationRadians)
        val sinR = sin(rotationRadians)

        var localX = dx * cosR + dy * sinR
        var localY = -dx * sinR + dy * cosR

        val halfW = width * 0.5f
        val halfH = height * 0.5f

        val closestX = localX.coerceIn(-halfW, halfW)
        val closestY = localY.coerceIn(-halfH, halfH)

        var deltaX = localX - closestX
        var deltaY = localY - closestY
        val d2 = deltaX * deltaX + deltaY * deltaY

        var normalLocalX: Float
        var normalLocalY: Float
        var penetration: Float

        if (d2 > 0.0001f) {
            if (d2 >= BALL_RADIUS * BALL_RADIUS) {
                return
            }

            val d = sqrt(d2)
            normalLocalX = deltaX / d
            normalLocalY = deltaY / d
            penetration = BALL_RADIUS - d
        } else {
            val overlapX = halfW - abs(localX)
            val overlapY = halfH - abs(localY)

            if (overlapX < overlapY) {
                normalLocalX = if (localX >= 0f) 1f else -1f
                normalLocalY = 0f
                penetration = BALL_RADIUS + overlapX
            } else {
                normalLocalX = 0f
                normalLocalY = if (localY >= 0f) 1f else -1f
                penetration = BALL_RADIUS + overlapY
            }
        }

        localX += normalLocalX * penetration
        localY += normalLocalY * penetration

        pos.x = cx + localX * cosR - localY * sinR
        pos.y = cy + localX * sinR + localY * cosR

        val normalWorldX = normalLocalX * cosR - normalLocalY * sinR
        val normalWorldY = normalLocalX * sinR + normalLocalY * cosR

        val vn = vel.x * normalWorldX + vel.y * normalWorldY

        if (vn < 0f) {
            vel.x -= (1f + restitution) * vn * normalWorldX
            vel.y -= (1f + restitution) * vn * normalWorldY
        }
    }

    private fun resolveRotatedRightTriangleCollision(
        pos: PointF,
        vel: PointF,
        cx: Float,
        cy: Float,
        width: Float,
        height: Float,
        rotationRadians: Float,
        restitution: Float
    ) {
        val dx = pos.x - cx
        val dy = pos.y - cy

        val cosR = cos(rotationRadians)
        val sinR = sin(rotationRadians)

        val localPos = PointF(
            dx * cosR + dy * sinR,
            -dx * sinR + dy * cosR
        )

        val localVel = PointF(
            vel.x * cosR + vel.y * sinR,
            -vel.x * sinR + vel.y * cosR
        )

        val halfW = width * 0.5f
        val halfH = height * 0.5f

        val ax = -halfW
        val ay = -halfH
        val bx = halfW
        val by = halfH
        val cx2 = halfW
        val cy2 = -halfH

        resolveCircleVsTriangleLocal(
            pos = localPos,
            vel = localVel,
            ax = ax,
            ay = ay,
            bx = bx,
            by = by,
            cx = cx2,
            cy = cy2,
            restitution = restitution
        )

        pos.x = cx + localPos.x * cosR - localPos.y * sinR
        pos.y = cy + localPos.x * sinR + localPos.y * cosR

        vel.x = localVel.x * cosR - localVel.y * sinR
        vel.y = localVel.x * sinR + localVel.y * cosR
    }

    private fun resolveCircleVsTriangleLocal(
        pos: PointF,
        vel: PointF,
        ax: Float,
        ay: Float,
        bx: Float,
        by: Float,
        cx: Float,
        cy: Float,
        restitution: Float
    ) {
        val e0 = makeLocalTriangleEdge(ax, ay, bx, by, cx, cy)
        val e1 = makeLocalTriangleEdge(bx, by, cx, cy, ax, ay)
        val e2 = makeLocalTriangleEdge(cx, cy, ax, ay, bx, by)

        val s0 = signedDistanceToEdge(pos, ax, ay, e0)
        val s1 = signedDistanceToEdge(pos, bx, by, e1)
        val s2 = signedDistanceToEdge(pos, cx, cy, e2)

        val insideTriangle = s0 <= 0f && s1 <= 0f && s2 <= 0f

        if (insideTriangle) {
            var nx = e0.nx
            var ny = e0.ny
            var signed = s0

            if (s1 > signed) {
                signed = s1
                nx = e1.nx
                ny = e1.ny
            }

            if (s2 > signed) {
                signed = s2
                nx = e2.nx
                ny = e2.ny
            }

            val penetration = BALL_RADIUS - signed

            pos.x += nx * penetration
            pos.y += ny * penetration

            val vn = vel.x * nx + vel.y * ny
            if (vn < 0f) {
                vel.x -= (1f + restitution) * vn * nx
                vel.y -= (1f + restitution) * vn * ny
            }

            return
        }
        var bestX = 0f
        var bestY = 0f
        var bestD2 = Float.MAX_VALUE
        var bestNx = 0f
        var bestNy = 0f

        fun considerSegment(
            x1: Float,
            y1: Float,
            x2: Float,
            y2: Float,
            fallbackNx: Float,
            fallbackNy: Float
        ) {
            val abx = x2 - x1
            val aby = y2 - y1
            val ab2 = abx * abx + aby * aby

            if (ab2 <= 0.0001f) return

            val t = (((pos.x - x1) * abx + (pos.y - y1) * aby) / ab2).coerceIn(0f, 1f)

            val qx = x1 + abx * t
            val qy = y1 + aby * t

            val dx = pos.x - qx
            val dy = pos.y - qy
            val d2 = dx * dx + dy * dy

            if (d2 < bestD2) {
                bestD2 = d2
                bestX = qx
                bestY = qy

                if (d2 > 0.0001f) {
                    val d = sqrt(d2)
                    bestNx = dx / d
                    bestNy = dy / d
                } else {
                    bestNx = fallbackNx
                    bestNy = fallbackNy
                }
            }
        }

        considerSegment(ax, ay, bx, by, e0.nx, e0.ny)
        considerSegment(bx, by, cx, cy, e1.nx, e1.ny)
        considerSegment(cx, cy, ax, ay, e2.nx, e2.ny)

        if (bestD2 >= BALL_RADIUS * BALL_RADIUS) return

        val d = sqrt(bestD2).coerceAtLeast(0.0001f)
        val penetration = BALL_RADIUS - d

        pos.x += bestNx * penetration
        pos.y += bestNy * penetration

        val vn = vel.x * bestNx + vel.y * bestNy
        if (vn < 0f) {
            vel.x -= (1f + restitution) * vn * bestNx
            vel.y -= (1f + restitution) * vn * bestNy
        }
    }

    private fun signedDistanceToEdge(
        pos: PointF,
        edgeX: Float,
        edgeY: Float,
        edge: LocalTriangleEdge
    ): Float {
        return (pos.x - edgeX) * edge.nx + (pos.y - edgeY) * edge.ny
    }

    private data class LocalTriangleEdge(
        val nx: Float,
        val ny: Float
    )

    private fun makeLocalTriangleEdge(
        ax: Float,
        ay: Float,
        bx: Float,
        by: Float,
        insideX: Float,
        insideY: Float
    ): LocalTriangleEdge {
        val ex = bx - ax
        val ey = by - ay
        val len = sqrt(ex * ex + ey * ey).coerceAtLeast(0.0001f)

        var nx = -ey / len
        var ny = ex / len

        val insideSide = (insideX - ax) * nx + (insideY - ay) * ny
        if (insideSide > 0f) {
            nx = -nx
            ny = -ny
        }

        return LocalTriangleEdge(nx, ny)
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
        val dxToHole = map.hole.x - positionCourse.x
        val dyToHole = map.hole.y - positionCourse.y
        val distanceToHole = sqrt(dxToHole * dxToHole + dyToHole * dyToHole)
        val speed = length(velocityCourse.x, velocityCourse.y)
        val capturedNow =
            alreadyCaptured ||
                    (
                            distanceToHole <= HOLE_CAPTURE_RADIUS &&
                                    speed <= HOLE_CAPTURE_MAX_SPEED
                            )

        if (capturedNow) {
            applyCapturedHoleTrap(
                map = map,
                positionCourse = positionCourse,
                velocityCourse = velocityCourse,
                dtSeconds = dtSeconds
            )

            val afterDx = map.hole.x - positionCourse.x
            val afterDy = map.hole.y - positionCourse.y
            val afterDistance = sqrt(afterDx * afterDx + afterDy * afterDy)
            val afterSpeed = length(velocityCourse.x, velocityCourse.y)

            val settled =
                afterDistance <= HOLE_SETTLED_RADIUS &&
                        afterSpeed <= HOLE_SETTLED_SPEED

            if (settled) {
                positionCourse.set(map.hole.x, map.hole.y)
                velocityCourse.set(0f, 0f)
            }

            return HoleStep(
                flagPulled = true,
                captured = true,
                settled = settled
            )
        }

        if (distanceToHole > FLAG_PULL_RADIUS) {
            return HoleStep(
                flagPulled = false,
                captured = false
            )
        }

        if (distanceToHole <= HOLE_CUP_PULL_RADIUS && distanceToHole > 0.001f) {
            val nx = dxToHole / distanceToHole
            val ny = dyToHole / distanceToHole
            val pullStrength = (1f - distanceToHole / HOLE_CUP_PULL_RADIUS).coerceIn(0f, 1f)

            velocityCourse.x += nx * HOLE_CUP_PULL_ACCELERATION * pullStrength * dtSeconds
            velocityCourse.y += ny * HOLE_CUP_PULL_ACCELERATION * pullStrength * dtSeconds

            val damp = (1f - 0.24f * pullStrength).coerceIn(0.80f, 1f)
            velocityCourse.x *= damp
            velocityCourse.y *= damp
        }

        return HoleStep(
            flagPulled = true,
            captured = false
        )
    }

    private fun applyCapturedHoleTrap(
        map: GolfMap,
        positionCourse: PointF,
        velocityCourse: PointF,
        dtSeconds: Float
    ) {
        val dxToHole = map.hole.x - positionCourse.x
        val dyToHole = map.hole.y - positionCourse.y
        val distanceToHole = sqrt(dxToHole * dxToHole + dyToHole * dyToHole)

        if (distanceToHole > 0.001f) {
            val nx = dxToHole / distanceToHole
            val ny = dyToHole / distanceToHole

            val pullStrength = (distanceToHole / HOLE_TRAP_RADIUS).coerceIn(0.25f, 1.25f)

            velocityCourse.x += nx * HOLE_TRAP_PULL_ACCELERATION * pullStrength * dtSeconds
            velocityCourse.y += ny * HOLE_TRAP_PULL_ACCELERATION * pullStrength * dtSeconds
        }

        val damping = HOLE_TRAP_DAMPING_PER_60FPS_FRAME.pow(dtSeconds * 60f)
        velocityCourse.x *= damping
        velocityCourse.y *= damping

        val outX = positionCourse.x - map.hole.x
        val outY = positionCourse.y - map.hole.y
        val outDistance = sqrt(outX * outX + outY * outY)

        if (outDistance > HOLE_TRAP_RADIUS && outDistance > 0.001f) {
            val nx = outX / outDistance
            val ny = outY / outDistance

            positionCourse.x = map.hole.x + nx * HOLE_TRAP_RADIUS
            positionCourse.y = map.hole.y + ny * HOLE_TRAP_RADIUS

            val outwardSpeed = velocityCourse.x * nx + velocityCourse.y * ny
            if (outwardSpeed > 0f) {
                velocityCourse.x -= outwardSpeed * nx
                velocityCourse.y -= outwardSpeed * ny
            }
        }
    }

    private fun isStopped(vel: PointF): Boolean {
        return vel.x * vel.x + vel.y * vel.y <= STOP_SPEED * STOP_SPEED
    }

    private fun length(x: Float, y: Float): Float {
        return sqrt(x * x + y * y)
    }
}