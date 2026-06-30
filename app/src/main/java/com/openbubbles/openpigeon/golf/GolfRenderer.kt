package com.openbubbles.openpigeon.golf

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.math.min
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import kotlin.math.abs
import android.os.SystemClock
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.cos
import android.util.TypedValue
import androidx.core.graphics.withRotation
import androidx.core.graphics.withTranslation

class GolfRenderer @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    companion object {
        private const val TAG = "GolfNative"
        private const val DEFAULT_SHOW_COLLISION_DEBUG = false

        private const val FLIP_BOARD_Y_ONLY = true
        private const val DEFAULT_SHOW_DEBUG_LABEL = false
        private var showPathPreview = false
        private var showObjectDebugDots = false
        private var logRenderScreenCoords = false
        private const val IOS_TILE_DRAW_SIZE = 66f
        private const val IOS_BALL_DRAW_SIZE = 8f
        private const val IOS_BALL_SUNK_DRAW_SIZE = 6f
        private const val BALL_SHADOW_ALPHA = 96
        private const val IOS_WALL_PATH_TILE_SIZE = 65f
        private const val IOS_WALL_DRAW_SIZE = 1.25f
        private const val IOS_WALL_VISUAL_BAND_DRAW_SIZE = 12f
        private const val IOS_WALL_VISUAL_BAND_SHADOW_SIZE = 14f
        private const val TRACE_PHYSICS_BALL_RADIUS_COURSE = 4f
        private const val TRACE_WALL_COLLISION_RADIUS_COURSE =
            TRACE_PHYSICS_BALL_RADIUS_COURSE
        private const val IOS_SLOPE_WIDTH = 65f
        private const val IOS_SLOPE_HEIGHT = 52f
        private const val IOS_OBSTACLE_BASE_SIZE = 30f
        private const val IOS_SHADOW_COURSE_Y_OFFSET = -2f
        private const val AIM_CAMERA_MAX_ZOOM_MULTIPLIER = 1.62f
        private const val AIM_CAMERA_MIN_ZOOM_MULTIPLIER = 1.06f
        private const val AIM_CAMERA_VERTICAL_MIN_SCREEN_FRACTION = 0.25f
        private const val AIM_CAMERA_VERTICAL_MAX_SCREEN_FRACTION = 0.75f
        private const val CAMERA_ANIMATION_DAMPING_PER_60FPS_FRAME = 0.80f
        private const val CAMERA_ANIMATION_EPSILON = 0.35f

        private const val DEBUG_NATIVE_BALL_RADIUS_COURSE = 4f

        private const val DEBUG_NATIVE_DIAGONAL_WALL_THICKNESS_COURSE = 1f
        private const val DEBUG_NATIVE_DIAGONAL_WALL_HALF_THICKNESS_COURSE = 0.5f
        private const val DEBUG_NATIVE_OUTER_WALL_THICKNESS_COURSE = 65f

        private const val DEBUG_NATIVE_SMALL_BAR_WIDTH_COURSE = 44f
        private const val DEBUG_NATIVE_SMALL_BAR_HEIGHT_COURSE = 6f

        private const val DEBUG_NATIVE_LARGE_BAR_WIDTH_COURSE = 95f
        private const val DEBUG_NATIVE_LARGE_BAR_HEIGHT_COURSE = 6f

        private const val DEBUG_NATIVE_CROSS_BASE_SIZE_COURSE = 95f
        private const val DEBUG_NATIVE_CROSS_ARM_THICKNESS_COURSE = 6f
        private const val DEBUG_NATIVE_CROSS_CENTER_RADIUS_COURSE = 9.5f

        private const val DEBUG_NATIVE_SLOPE_WIDTH_COURSE = 65f
        private const val DEBUG_NATIVE_SLOPE_HEIGHT_COURSE = 52f

        private const val BUMPER_PULSE_DURATION_MS = 220L
        private const val BUMPER_PULSE_MAX_SCALE = 1.5f
    }

    private enum class CutCorner {
        TOP_LEFT,
        TOP_RIGHT,
        BOTTOM_LEFT,
        BOTTOM_RIGHT
    }

    private enum class CameraMode {
        FULL_BOARD,
        AIM,
        REPLAY
    }

    private var hasLoggedFirstDraw = false
    private var lastSizeLog = ""
    private var loggedCollisionDebugTruthForKey: String? = null

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var showCollisionDebug = DEFAULT_SHOW_COLLISION_DEBUG
    private var showDebugLabel = DEFAULT_SHOW_DEBUG_LABEL
    private var logVisualAlignmentEnabled = true
    private val traceBallRadiusCourse = IOS_BALL_DRAW_SIZE * 0.5f
    private val bumperPulses = HashMap<String, BumperPulse>()

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.SQUARE
        strokeJoin = Paint.Join.MITER
    }

    private var map: GolfMap? = null
    private var scale = 1f
    private var offsetX = 0f
    private var offsetY = 0f

    private var cameraMode = CameraMode.FULL_BOARD
    private var overviewCameraHeld = false
    private var aimCameraBallCourse: PointF? = null
    private var aimCameraDist = 0f

    private var cameraTransformReady = false
    private var snapCameraOnNextDraw = true
    private var cameraAnimLastMs = 0L

    private var runtimeBallCourse: PointF? = null
    private var opponentBallCourse: PointF? = null
    private var replayCameraBall1Course: PointF? = null
    private var replayCameraBall2Course: PointF? = null

    private var aimDotsVisual: List<PointF> = emptyList()
    private var opponentAimDotsVisual: List<PointF> = emptyList()
    private var aimReadyBallCourse: PointF? = null
    private var aimReadyRingStartMs = 0L
    private var aimReadyRingFadeLastMs = 0L
    private var aimReadyRingAlpha = 0f
    private var aimReadyRingTargetAlpha = 0f

    private var flagPulled = false
    private var ballInHole = false
    private var replayBallHoleStateActive = false
    private var replayPrimaryBallInHole = false
    private var replayOpponentBallInHole = false
    private var flagPullProgress = 0f
    private var flagAnimLastMs = 0L


    private val flagPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private val collisionDebugPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2f
    }

    private val ballBitmap = loadAssetBitmap("golf_ball_Normal@3x.png")
    private val holeBitmap = loadAssetBitmap("golf_hole_Normal@3x.png")
    private val flagBitmap = loadAssetBitmap("golf_flag_Normal@3x.png")

    private val slopeUpBitmap = loadAssetBitmap("golf_slope_up_Normal@3x.png")
    private val slopeDownBitmap = loadAssetBitmap("golf_slope_down_Normal@3x.png")

    private val obstacleSquareBitmap = loadAssetBitmap("golf_obstacle_square_Normal@3x.png")
    private val obstacleSquare2Bitmap = loadAssetBitmap("golf_obstacle_square2_Normal@3x.png")
    private val obstacleBarBitmap = loadAssetBitmap("golf_obstacle_bar_Normal@3x.png")
    private val obstacleBar2Bitmap =
        loadAssetBitmap("golf_obstacle_bar2_Normal@3x.png")
            ?: loadAssetBitmap("golf_obstacles_bar2_Normal@3x.png")
    private val obstacleRoundBitmap = loadAssetBitmap("golf_obstacle_round_Normal@3x.png")
    private val obstacleRound2Bitmap = loadAssetBitmap("golf_obstacle_round2_Normal@3x.png")
    private val obstacleTriangleBitmap = loadAssetBitmap("golf_obstacle_triangle_Normal@3x.png")
    private val obstacleTriangle2Bitmap = loadAssetBitmap("golf_obstacle_triangle2_Normal@3x.png")
    private val obstacleCrossBitmap = loadAssetBitmap("golf_obstacle_cross_Normal@3x.png")

    fun setDebugOverlayEnabled(enabled: Boolean) {
        showCollisionDebug = enabled
        showDebugLabel = enabled
        postInvalidateOnAnimation()
    }

    private data class VisualRectCourse(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float
    ) {
        val width: Float get() = right - left
        val height: Float get() = bottom - top
    }

    private data class BumperPulse(
        val x: Float,
        val y: Float,
        val startMs: Long
    )

    private data class BallRenderSpec(
        val coursePoint: PointF,
        val fallbackColor: Int,
        val sunk: Boolean,
        val tintColor: Int? = null,
        val alpha: Int,
        val screenOffsetX: Float = 0f,
        val screenOffsetY: Float = 0f
    )

    private data class WallSegmentCourse(
        val ax: Float,
        val ay: Float,
        val bx: Float,
        val by: Float,
        val label: String,
        val kind: String = "axis",
        val thicknessCourse: Float = IOS_WALL_DRAW_SIZE
    )

    private fun isCourseOpenForTrace(
        g: GolfMap,
        outerY: Int,
        innerX: Int
    ): Boolean {
        if (outerY !in g.grid.indices) return false
        if (innerX !in g.grid[outerY].indices) return false

        val value = g.grid[outerY][innerX]
        return value == 0 || value == 3
    }

    private fun diagonalCollisionAngleForTrace(
        g: GolfMap,
        row: Int,
        col: Int
    ): Float {
        val topBlocked = !isCourseOpenForTrace(g, row - 1, col)
        val bottomBlocked = !isCourseOpenForTrace(g, row + 1, col)
        val leftBlocked = !isCourseOpenForTrace(g, row, col - 1)
        val rightBlocked = !isCourseOpenForTrace(g, row, col + 1)

        return when {
            topBlocked && rightBlocked -> (Math.PI / 4.0).toFloat()
            bottomBlocked && leftBlocked -> (Math.PI / 4.0).toFloat()
            topBlocked && leftBlocked -> (-Math.PI / 4.0).toFloat()
            bottomBlocked && rightBlocked -> (-Math.PI / 4.0).toFloat()
            else -> (-Math.PI / 4.0).toFloat()
        }
    }

    private fun courseWallSegmentsForTrace(g: GolfMap): List<WallSegmentCourse> {
        val tile = GolfConstants.TILE_SIZE
        val segments = ArrayList<WallSegmentCourse>()

        for (outerY in g.grid.indices) {
            for (innerX in g.grid[outerY].indices) {
                if (!isCourseOpenForTrace(g, outerY, innerX)) continue

                val x0 = innerX * tile
                val y0 = outerY * tile
                val x1 = x0 + tile
                val y1 = y0 + tile

                if (g.grid[outerY][innerX] == 3) {
                    val cx = innerX * tile
                    val cy = outerY * tile
                    val halfLength = tile * 0.5f * kotlin.math.sqrt(2f)
                    val angle = diagonalCollisionAngleForTrace(g, outerY, innerX)
                    val c = kotlin.math.cos(angle)
                    val s = kotlin.math.sin(angle)

                    segments += WallSegmentCourse(
                        ax = cx - halfLength * c,
                        ay = cy - halfLength * s,
                        bx = cx + halfLength * c,
                        by = cy + halfLength * s,
                        label = "diagonal cell=($outerY,$innerX)",
                        kind = "diagonal",
                        thicknessCourse = DEBUG_NATIVE_DIAGONAL_WALL_THICKNESS_COURSE
                    )
                }

                if (!isCourseOpenForTrace(g, outerY, innerX - 1)) {
                    segments += WallSegmentCourse(
                        x0,
                        y0,
                        x0,
                        y1,
                        "left cell=($outerY,$innerX)"
                    )
                }

                if (!isCourseOpenForTrace(g, outerY, innerX + 1)) {
                    segments += WallSegmentCourse(
                        x1,
                        y0,
                        x1,
                        y1,
                        "right cell=($outerY,$innerX)"
                    )
                }

                if (!isCourseOpenForTrace(g, outerY - 1, innerX)) {
                    segments += WallSegmentCourse(
                        x0,
                        y0,
                        x1,
                        y0,
                        "top cell=($outerY,$innerX)"
                    )
                }

                if (!isCourseOpenForTrace(g, outerY + 1, innerX)) {
                    segments += WallSegmentCourse(
                        x0,
                        y1,
                        x1,
                        y1,
                        "bottom cell=($outerY,$innerX)"
                    )
                }
            }
        }

        return segments
    }

    private fun pointToSegmentDistanceCourse(
        px: Float,
        py: Float,
        segment: WallSegmentCourse
    ): Float {
        val vx = segment.bx - segment.ax
        val vy = segment.by - segment.ay
        val wx = px - segment.ax
        val wy = py - segment.ay

        val len2 = vx * vx + vy * vy
        if (len2 <= 0.0001f) {
            val dx = px - segment.ax
            val dy = py - segment.ay
            return kotlin.math.sqrt(dx * dx + dy * dy)
        }

        val t = ((wx * vx + wy * vy) / len2).coerceIn(0f, 1f)
        val cx = segment.ax + t * vx
        val cy = segment.ay + t * vy

        val dx = px - cx
        val dy = py - cy

        return kotlin.math.sqrt(dx * dx + dy * dy)
    }

    private fun rotatedAabbCourse(
        cx: Float,
        cy: Float,
        width: Float,
        height: Float,
        rotationRadians: Float
    ): VisualRectCourse {
        val halfW = width / 2f
        val halfH = height / 2f

        val cos = cos(rotationRadians)
        val sin = kotlin.math.sin(rotationRadians)

        val corners = arrayOf(
            -halfW to -halfH,
            halfW to -halfH,
            halfW to halfH,
            -halfW to halfH
        )

        var minX = Float.POSITIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY
        var maxX = Float.NEGATIVE_INFINITY
        var maxY = Float.NEGATIVE_INFINITY

        for ((x, y) in corners) {
            val rx = cx + x * cos - y * sin
            val ry = cy + x * sin + y * cos

            minX = min(minX, rx)
            minY = min(minY, ry)
            maxX = max(maxX, rx)
            maxY = max(maxY, ry)
        }

        return VisualRectCourse(
            left = minX,
            top = minY,
            right = maxX,
            bottom = maxY
        )
    }

    private fun obstacleTraceImageName(obstacle: GolfObstacle): String {
        return obstacle.image.ifBlank {
            obstacleImageForType(obstacle.type, obstacle.bouncy)
        }
    }

    private fun jsonPoint(x: Float, y: Float): String {
        return "{\"x\":$x,\"y\":$y}"
    }

    private fun jsonRect(r: VisualRectCourse): String {
        return "{" +
                "\"left\":${r.left}," +
                "\"top\":${r.top}," +
                "\"right\":${r.right}," +
                "\"bottom\":${r.bottom}," +
                "\"width\":${r.width}," +
                "\"height\":${r.height}" +
                "}"
    }

    private fun jsonWallSegment(s: WallSegmentCourse): String {
        return "{" +
                "\"ax\":${s.ax}," +
                "\"ay\":${s.ay}," +
                "\"bx\":${s.bx}," +
                "\"by\":${s.by}," +
                "\"label\":\"${s.label.replace("\"", "\\\"")}\"," +
                "\"kind\":\"${s.kind}\"," +
                "\"thicknessCourse\":${s.thicknessCourse}" +
                "}"
    }

    private fun logVisualAlignment(g: GolfMap) {
        if (!logVisualAlignmentEnabled && !GolfConstants.debugToolsEnabled) return

        val wallSegments = courseWallSegmentsForTrace(g)
        val diagonalWallSegments = wallSegments.count { it.kind == "diagonal" }

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_VISUAL=" +
                    "{" +
                    "\"kind\":\"mapVisualTransform\"," +
                    "\"seed\":${g.seed}," +
                    "\"mode\":\"${g.mode}\"," +
                    "\"mapNum\":${g.mapNum}," +
                    "\"xCells\":${g.xCells}," +
                    "\"yCells\":${g.yCells}," +
                    "\"mapSize\":${g.mapSize}," +
                    "\"mapSize2\":${g.mapSize2}," +
                    "\"scale\":$scale," +
                    "\"offsetX\":$offsetX," +
                    "\"offsetY\":$offsetY," +
                    "\"flipY\":$FLIP_BOARD_Y_ONLY," +
                    "\"wallSegments\":${wallSegments.size}," +
                    "\"diagonalWallSegments\":$diagonalWallSegments," +
                    "\"diagonalWallThicknessCourse\":$DEBUG_NATIVE_DIAGONAL_WALL_THICKNESS_COURSE," +
                    "\"diagonalWallHalfThicknessCourse\":$DEBUG_NATIVE_DIAGONAL_WALL_HALF_THICKNESS_COURSE," +
                    "\"ballRadiusCourse\":$traceBallRadiusCourse," +
                    "\"physicsBallRadiusCourse\":$TRACE_PHYSICS_BALL_RADIUS_COURSE," +
                    "\"wallDrawSizeCourse\":$IOS_WALL_DRAW_SIZE," +
                    "\"wallDrawSizeScreen\":${IOS_WALL_DRAW_SIZE * scale}," +
                    "\"wallVisibleHalfCourse\":${IOS_WALL_DRAW_SIZE * 0.5f}," +
                    "\"wallCollisionRadiusCourse\":$TRACE_WALL_COLLISION_RADIUS_COURSE," +
                    "\"wallCollisionDiameterScreen\":${TRACE_WALL_COLLISION_RADIUS_COURSE * 2f * scale}" +
                    "}"
        )

        g.obstacles.forEachIndexed { index, obstacle ->
            val spec = obstacleSpec(obstacle)
            val image = obstacleTraceImageName(obstacle)

            val drawWidthCourse = spec.width * obstacle.scale
            val drawHeightCourse = spec.height * obstacle.scale

            val unrotated = VisualRectCourse(
                left = obstacle.x - drawWidthCourse / 2f,
                top = obstacle.y - drawHeightCourse / 2f,
                right = obstacle.x + drawWidthCourse / 2f,
                bottom = obstacle.y + drawHeightCourse / 2f
            )

            val rotated = rotatedAabbCourse(
                cx = obstacle.x,
                cy = obstacle.y,
                width = drawWidthCourse,
                height = drawHeightCourse,
                rotationRadians = obstacle.rotation
            )

            val centerScreen = courseToScreen(PointF(obstacle.x, obstacle.y))
            val shadowScreen = courseToScreen(
                PointF(
                    obstacle.x,
                    obstacle.y + IOS_SHADOW_COURSE_Y_OFFSET
                )
            )

            val obstacleRadiusApprox = min(
                drawWidthCourse,
                drawHeightCourse
            ) / 2f

            var nearestWallDistance = Float.POSITIVE_INFINITY
            var nearestWall: WallSegmentCourse? = null

            for (segment in wallSegments) {
                val distance = pointToSegmentDistanceCourse(
                    px = obstacle.x,
                    py = obstacle.y,
                    segment = segment
                )

                if (distance < nearestWallDistance) {
                    nearestWallDistance = distance
                    nearestWall = segment
                }
            }

            val wallVisibleHalfCourse = IOS_WALL_DRAW_SIZE * 0.5f

            val visibleWallGapCourse =
                nearestWallDistance - obstacleRadiusApprox - wallVisibleHalfCourse

            val visualBallPassageGapCourse =
                visibleWallGapCourse - IOS_BALL_DRAW_SIZE

            val physicsBallCenterPassageGapCourse =
                nearestWallDistance -
                        obstacleRadiusApprox -
                        TRACE_PHYSICS_BALL_RADIUS_COURSE -
                        TRACE_WALL_COLLISION_RADIUS_COURSE

            OpenPigeonLog.i(
                TAG,
                "GOLF_ANDROID_VISUAL=" +
                        "{" +
                        "\"kind\":\"obstacleVisual\"," +
                        "\"index\":$index," +
                        "\"image\":\"$image\"," +
                        "\"type\":${obstacle.type}," +
                        "\"bouncy\":${obstacle.bouncy}," +
                        "\"courseCenter\":${jsonPoint(obstacle.x, obstacle.y)}," +
                        "\"screenCenter\":${jsonPoint(centerScreen.x, centerScreen.y)}," +
                        "\"shadowScreenCenter\":${jsonPoint(shadowScreen.x, shadowScreen.y)}," +
                        "\"rotationRadians\":${obstacle.rotation}," +
                        "\"rotationDegrees\":${Math.toDegrees(obstacle.rotation.toDouble()).toFloat()}," +
                        "\"scaleValue\":${obstacle.scale}," +
                        "\"baseSizeCourse\":${jsonPoint(spec.width, spec.height)}," +
                        "\"drawSizeCourse\":${jsonPoint(drawWidthCourse, drawHeightCourse)}," +
                        "\"drawSizeScreen\":${jsonPoint(drawWidthCourse * scale, drawHeightCourse * scale)}," +
                        "\"unrotatedRectCourse\":${jsonRect(unrotated)}," +
                        "\"rotatedAabbCourse\":${jsonRect(rotated)}," +
                        "\"nearestWallDistanceCourse\":$nearestWallDistance," +
                        "\"wallVisibleHalfCourse\":$wallVisibleHalfCourse," +
                        "\"wallCollisionRadiusCourse\":$TRACE_WALL_COLLISION_RADIUS_COURSE," +
                        "\"visibleWallGapCourse\":$visibleWallGapCourse," +
                        "\"visualBallPassageGapCourse\":$visualBallPassageGapCourse," +
                        "\"physicsBallCenterPassageGapCourse\":$physicsBallCenterPassageGapCourse," +
                        "\"ballCenterPassageGapCourse\":$physicsBallCenterPassageGapCourse," +
                        "\"nearestWall\":${nearestWall?.let { jsonWallSegment(it) } ?: "null"}" +
                        "}"
            )
        }
    }

    fun setMap(newMap: GolfMap) {
        OpenPigeonLog.i(
            TAG,
            "Renderer.setMap seed=${newMap.seed} mode=${newMap.mode} mapNum=${newMap.mapNum} " +
                    "cells=${newMap.xCells}x${newMap.yCells} mapSize=${newMap.mapSize} mapSize2=${newMap.mapSize2} " +
                    "complete=${newMap.complete} flipY=$FLIP_BOARD_Y_ONLY " +
                    "slopes=${newMap.slopes.size} obstacles=${newMap.obstacles.size}"
        )

        newMap.slopes.forEachIndexed { index, slope ->
            OpenPigeonLog.i(
                TAG,
                "Renderer.slope[$index] image=${slope.image} pos=(${slope.x},${slope.y}) " +
                        "v=(${slope.vx},${slope.vy}) rotation=${slope.rotation}"
            )
        }

        newMap.obstacles.forEachIndexed { index, obstacle ->
            OpenPigeonLog.i(
                TAG,
                "Renderer.obstacle[$index] image=${obstacle.image} type=${obstacle.type} " +
                        "pos=(${obstacle.x},${obstacle.y}) rotation=${obstacle.rotation} " +
                        "scale=${obstacle.scale} bouncy=${obstacle.bouncy}"
            )
        }

        map = newMap
        hasLoggedFirstDraw = false

        flagPulled = false
        ballInHole = false
        replayBallHoleStateActive = false
        replayPrimaryBallInHole = false
        replayOpponentBallInHole = false
        flagPullProgress = 0f
        flagAnimLastMs = 0L
        cameraTransformReady = false
        snapCameraOnNextDraw = true
        cameraAnimLastMs = 0L
        replayCameraBall1Course = null
        replayCameraBall2Course = null
        aimReadyBallCourse = null
        aimReadyRingStartMs = 0L
        aimReadyRingFadeLastMs = 0L
        aimReadyRingAlpha = 0f
        aimReadyRingTargetAlpha = 0f
        bumperPulses.clear()

        invalidate()
    }

    fun courseToScreen(point: PointF): PointF {
        val g = map

        val visual = if (g != null) {
            PointF(
                point.x,
                g.mapSize - point.y
            )
        } else {
            PointF(point.x, point.y)
        }

        return PointF(
            offsetX + visual.x * scale,
            offsetY + visual.y * scale
        )
    }

    fun screenToCourse(x: Float, y: Float): PointF {
        val visualX = (x - offsetX) / scale
        val visualY = (y - offsetY) / scale
        val g = map

        return if (g != null) {
            PointF(
                visualX,
                g.mapSize - visualY
            )
        } else {
            PointF(visualX, visualY)
        }
    }

    fun screenToVisual(x: Float, y: Float): PointF {
        return PointF(
            (x - offsetX) / scale,
            (y - offsetY) / scale
        )
    }

    fun visualToScreen(point: PointF): PointF {
        return PointF(
            offsetX + point.x * scale,
            offsetY + point.y * scale
        )
    }

    fun courseToVisual(point: PointF): PointF {
        val g = map
        return if (g != null) {
            courseToVisualRaw(g, point)
        } else {
            PointF(point.x, point.y)
        }
    }

    private fun courseToVisualRaw(g: GolfMap, point: PointF): PointF {
        return PointF(
            point.x,
            g.mapSize - point.y
        )
    }

    fun visualDeltaToCourseDelta(dxVisual: Float, dyVisual: Float): PointF {
        val c0 = screenToCourse(offsetX, offsetY)
        val c1 = screenToCourse(
            offsetX + dxVisual * scale,
            offsetY + dyVisual * scale
        )

        return PointF(
            c1.x - c0.x,
            c1.y - c0.y
        )
    }

    fun setReplayBallHoleStates(
        primaryInHole: Boolean,
        opponentInHole: Boolean
    ) {
        replayBallHoleStateActive = true
        replayPrimaryBallInHole = primaryInHole
        replayOpponentBallInHole = opponentInHole
        postInvalidateOnAnimation()
    }

    fun clearReplayBallHoleStates() {
        if (
            !replayBallHoleStateActive &&
            !replayPrimaryBallInHole &&
            !replayOpponentBallInHole
        ) {
            return
        }

        replayBallHoleStateActive = false
        replayPrimaryBallInHole = false
        replayOpponentBallInHole = false
        postInvalidateOnAnimation()
    }

    fun setHoleState(flagPulled: Boolean, ballInHole: Boolean) {
        if (this.flagPulled == flagPulled && this.ballInHole == ballInHole) return

        this.flagPulled = flagPulled
        this.ballInHole = ballInHole

        if (flagAnimLastMs == 0L) {
            flagAnimLastMs = SystemClock.elapsedRealtime()
        }

        postInvalidateOnAnimation()
    }

    fun setRuntimeBallCourse(point: PointF?) {
        runtimeBallCourse = point?.let { PointF(it.x, it.y) }
        invalidate()
    }

    fun setOpponentBallCourse(point: PointF?) {
        opponentBallCourse = point?.let { PointF(it.x, it.y) }
        postInvalidateOnAnimation()
    }

    fun clearOpponentBallCourse() {
        opponentBallCourse = null
        opponentAimDotsVisual = emptyList()
        postInvalidateOnAnimation()
    }

    fun getPrimaryBallCourse(): PointF? {
        val g = map ?: return null
        return runtimeBallCourse ?: g.ballStart1
    }

    private fun bumperKey(obstacle: GolfObstacle): String {
        return "${obstacle.x}|${obstacle.y}|${obstacle.rotation}|${obstacle.scale}|${obstacle.image}|${obstacle.type}|${obstacle.bouncy}"
    }

    fun pulseBumperAtCourse(x: Float, y: Float) {
        val g = map ?: return

        var bestObstacle: GolfObstacle? = null
        var bestDist2 = Float.POSITIVE_INFINITY

        for (obstacle in g.obstacles) {
            if (!obstacle.bouncy) continue

            val dx = obstacle.x - x
            val dy = obstacle.y - y
            val d2 = dx * dx + dy * dy

            if (d2 < bestDist2) {
                bestDist2 = d2
                bestObstacle = obstacle
            }
        }

        val obstacle = bestObstacle ?: return

        if (bestDist2 > 40f * 40f) return

        val key = bumperKey(obstacle)
        val now = SystemClock.elapsedRealtime()
        val existing = bumperPulses[key]

        if (existing != null && now - existing.startMs < 90L) {
            return
        }

        bumperPulses[key] = BumperPulse(
            x = obstacle.x,
            y = obstacle.y,
            startMs = now
        )

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_BUMPER_VISUAL_PULSE x=${obstacle.x} y=${obstacle.y} key=$key"
        )

        postInvalidateOnAnimation()
    }

    private fun bumperPulseScale(obstacle: GolfObstacle): Float {
        if (!obstacle.bouncy) return 1f

        val key = bumperKey(obstacle)
        val pulse = bumperPulses[key] ?: return 1f

        val elapsed = SystemClock.elapsedRealtime() - pulse.startMs

        if (elapsed >= BUMPER_PULSE_DURATION_MS) {
            bumperPulses.remove(key)
            return 1f
        }

        val t = (elapsed.toFloat() / BUMPER_PULSE_DURATION_MS.toFloat())
            .coerceIn(0f, 1f)

        val growProgress =
            if (t <= 0.5f) {
                t / 0.5f
            } else {
                1f - ((t - 0.5f) / 0.5f)
            }.coerceIn(0f, 1f)

        val eased = growProgress * growProgress * (3f - 2f * growProgress)

        postInvalidateOnAnimation()

        return 1f + (BUMPER_PULSE_MAX_SCALE - 1f) * eased
    }

    fun setOverviewCameraHeld(held: Boolean) {
        if (overviewCameraHeld == held) return

        overviewCameraHeld = held

        postInvalidateOnAnimation()
    }

    fun setAimingCamera(ballCourse: PointF?, aim: GolfShot.Aim?) {
        cameraMode = CameraMode.AIM
        aimCameraBallCourse = ballCourse?.let { PointF(it.x, it.y) }
        aimCameraDist = aim?.dist ?: 0f
        postInvalidateOnAnimation()
    }

    fun setShotCamera(ballCourse: PointF?, dist: Float) {
        cameraMode = CameraMode.AIM
        aimCameraBallCourse = ballCourse?.let { PointF(it.x, it.y) }
        aimCameraDist = dist.coerceIn(0f, GolfShot.AIM_MAX_DIST)
        postInvalidateOnAnimation()
    }

    fun setReplayCamera(ball1Course: PointF?, ball2Course: PointF?) {
        cameraMode = CameraMode.REPLAY
        replayCameraBall1Course = ball1Course?.let { PointF(it.x, it.y) }
        replayCameraBall2Course = ball2Course?.let { PointF(it.x, it.y) }
        postInvalidateOnAnimation()
    }

    fun clearCameraFocus() {
        cameraMode = CameraMode.FULL_BOARD
        aimCameraBallCourse = null
        aimCameraDist = 0f
        replayCameraBall1Course = null
        replayCameraBall2Course = null
        overviewCameraHeld = false
        snapCameraOnNextDraw = true

        invalidate()
    }

    fun isScreenNearPrimaryBall(screenX: Float, screenY: Float): Boolean {
        val ball = getPrimaryBallCourse() ?: return false
        val p = courseToScreen(ball)

        val hitRadius = 28f * scale
        val dx = screenX - p.x
        val dy = screenY - p.y

        return dx * dx + dy * dy <= hitRadius * hitRadius
    }

    fun setAimPreview(ballCourse: PointF?, aim: GolfShot.Aim?) {
        if (ballCourse == null || aim == null || !aim.active) {
            aimDotsVisual = emptyList()
            invalidate()
            return
        }

        val ballVisual = courseToVisual(ballCourse)
        aimDotsVisual = GolfShot.previewDotsVisual(ballVisual, aim)
        invalidate()
    }

    fun setReplayAimPreviews(
        whiteBallCourse: PointF?,
        whiteAim: GolfShot.Aim?,
        grayBallCourse: PointF?,
        grayAim: GolfShot.Aim?
    ) {
        aimDotsVisual = if (whiteBallCourse != null && whiteAim != null && whiteAim.active) {
            GolfShot.previewDotsVisual(courseToVisual(whiteBallCourse), whiteAim)
        } else {
            emptyList()
        }

        opponentAimDotsVisual = if (grayBallCourse != null && grayAim != null && grayAim.active) {
            GolfShot.previewDotsVisual(courseToVisual(grayBallCourse), grayAim)
        } else {
            emptyList()
        }

        postInvalidateOnAnimation()
    }

    fun clearReplayAimPreview() {
        if (aimDotsVisual.isNotEmpty() || opponentAimDotsVisual.isNotEmpty()) {
            aimDotsVisual = emptyList()
            opponentAimDotsVisual = emptyList()
            postInvalidateOnAnimation()
        }
    }

    fun clearAimPreview() {
        if (aimDotsVisual.isNotEmpty() || opponentAimDotsVisual.isNotEmpty()) {
            aimDotsVisual = emptyList()
            opponentAimDotsVisual = emptyList()
            invalidate()
        }
    }

    fun setAimReadyIndicator(ballCourse: PointF?) {
        val now = SystemClock.elapsedRealtime()
        val next = ballCourse?.let { PointF(it.x, it.y) }

        if (next == null) {
            aimReadyRingTargetAlpha = 0f
            aimReadyRingFadeLastMs = now
            postInvalidateOnAnimation()
            return
        }

        val old = aimReadyBallCourse

        if (old == null || abs(old.x - next.x) > 0.001f || abs(old.y - next.y) > 0.001f) {
            aimReadyRingStartMs = now
        } else if (aimReadyRingStartMs == 0L) {
            aimReadyRingStartMs = now
        }

        aimReadyBallCourse = next
        aimReadyRingTargetAlpha = 1f
        aimReadyRingFadeLastMs = now

        postInvalidateOnAnimation()
    }

    private fun logRendererScreenCoordinates(g: GolfMap) {
        fun visualCoursePoint(point: PointF): PointF {
            return PointF(
                point.x,
                g.mapSize - point.y
            )
        }

        fun logPoint(label: String, point: PointF) {
            val visual = visualCoursePoint(point)
            val screen = courseToScreen(point)

            OpenPigeonLog.i(
                TAG,
                "Renderer.screen.$label course=(${point.x},${point.y}) " +
                        "visual=(${visual.x},${visual.y}) screen=(${screen.x},${screen.y})"
            )
        }

        logPoint("ball1", g.ballStart1)
        logPoint("ball2", g.ballStart2)
        logPoint("hole", g.hole)
        logPoint("flagExpected", PointF(g.hole.x, g.hole.y + 18f))

        g.slopes.forEachIndexed { index, slope ->
            val course = PointF(slope.x, slope.y)
            val visual = visualCoursePoint(course)
            val screen = courseToScreen(course)
            val drawDeg = Math.toDegrees(slopeRotationForRenderer(slope).toDouble()).toFloat()

            OpenPigeonLog.i(
                TAG,
                "Renderer.slopeScreen[$index] image=${slope.image} " +
                        "course=(${course.x},${course.y}) visual=(${visual.x},${visual.y}) " +
                        "screen=(${screen.x},${screen.y}) v=(${slope.vx},${slope.vy}) " +
                        "drawDeg=$drawDeg rawRotation=${slope.rotation}"
            )
        }

        g.obstacles.forEachIndexed { index, obstacle ->
            val spec = obstacleSpec(obstacle)
            val course = PointF(obstacle.x, obstacle.y)
            val visual = visualCoursePoint(course)
            val screen = courseToScreen(course)
            val shadowScreen = courseToScreen(
                PointF(
                    obstacle.x,
                    obstacle.y + IOS_SHADOW_COURSE_Y_OFFSET
                )
            )

            val rawDeg = Math.toDegrees(obstacle.rotation.toDouble()).toFloat()
            val drawDeg = -rawDeg

            OpenPigeonLog.i(
                TAG,
                "Renderer.obstacleScreen[$index] image=${obstacle.image} type=${obstacle.type} " +
                        "course=(${course.x},${course.y}) visual=(${visual.x},${visual.y}) " +
                        "screen=(${screen.x},${screen.y}) shadowScreen=(${shadowScreen.x},${shadowScreen.y}) " +
                        "rawDeg=$rawDeg drawDeg=$drawDeg inverted=${-rawDeg} flipY=$FLIP_BOARD_Y_ONLY " +
                        "scale=${obstacle.scale} sizeCourse=(${spec.width * obstacle.scale},${spec.height * obstacle.scale}) " +
                        "bouncy=${obstacle.bouncy}"
            )
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val sizeKey = "${width}x${height}"
        if (sizeKey != lastSizeLog) {
            lastSizeLog = sizeKey
            OpenPigeonLog.i(TAG, "Renderer.onDraw size=$sizeKey mapNull=${map == null}")
        }

        drawBackground(canvas)

        val g = map ?: return

        computeTransform(g)

        if (!hasLoggedFirstDraw) {
            hasLoggedFirstDraw = true
            val rb = renderBounds(g)

            OpenPigeonLog.i(
                TAG,
                "Renderer.firstDraw mapNum=${g.mapNum} scale=$scale offset=($offsetX,$offsetY) " +
                        "view=${width}x${height} cells=${g.xCells}x${g.yCells} " +
                        "visual=${visualMapWidth(g)}x${visualMapHeight(g)} " +
                        "bounds=(${rb.left},${rb.top},${rb.right},${rb.bottom}) " +
                        "flipY=$FLIP_BOARD_Y_ONLY " +
                        "slopes=${g.slopes.size} obstacles=${g.obstacles.size}"
            )

            if (logRenderScreenCoords || GolfConstants.debugToolsEnabled) {
                logRendererScreenCoordinates(g)
            }

            logVisualAlignment(g)
        }

        val fillPath = buildCoursePath(g, IOS_TILE_DRAW_SIZE)
        val wallPath = buildCoursePath(g, IOS_WALL_PATH_TILE_SIZE)

        drawCourseVisualWallBandShadowBehindFill(canvas, wallPath)
        drawCourseVisualWallBandBehindFill(canvas, wallPath)

        drawCourseFill(canvas, fillPath)

        if (showPathPreview) {
            drawPathPreview(canvas, g)
        }

        drawSlopes(canvas, g)
        drawObjectShadows(canvas, g)
        drawBallShadows(canvas, g)
        drawObstacleSprites(canvas, g)
        drawCourseOutline(canvas, wallPath)

        if (showObjectDebugDots) {
            drawObjectDebugDots(canvas, g)
        }

        drawHoleCup(canvas, g)

        drawAimPreview(canvas)
        drawBalls(canvas, g)
        drawAimReadyRing(canvas)

        drawHoleFlag(canvas, g)

        drawCollisionDebug(canvas, g)

        if (showDebugLabel) {
            drawDebugLabel(canvas, g)
        }
    }

    private fun drawObjectShadows(canvas: Canvas, g: GolfMap) {
        for (obstacle in g.obstacles) {
            val spec = obstacleSpec(obstacle)
            val pulseScale = bumperPulseScale(obstacle)

            val shadow = courseToScreen(
                PointF(
                    obstacle.x,
                    obstacle.y + IOS_SHADOW_COURSE_Y_OFFSET
                )
            )

            drawCourseBitmap(
                canvas = canvas,
                bitmap = spec.bitmap,
                cx = shadow.x,
                cy = shadow.y,
                widthCourse = spec.width * obstacle.scale * pulseScale,
                heightCourse = spec.height * obstacle.scale * pulseScale,
                rotationRadians = obstacle.rotation,
                fallbackColor = Color.argb(80, 0, 0, 0),
                drawShadow = true,
                fallbackShape = spec.fallbackShape
            )
        }
    }

    private fun drawObstacleSprites(canvas: Canvas, g: GolfMap) {
        for (obstacle in g.obstacles) {
            val spec = obstacleSpec(obstacle)
            val pulseScale = bumperPulseScale(obstacle)
            val p = courseToScreen(PointF(obstacle.x, obstacle.y))

            drawCourseBitmap(
                canvas = canvas,
                bitmap = spec.bitmap,
                cx = p.x,
                cy = p.y,
                widthCourse = spec.width * obstacle.scale * pulseScale,
                heightCourse = spec.height * obstacle.scale * pulseScale,
                rotationRadians = obstacle.rotation,
                fallbackColor = Color.WHITE,
                drawShadow = false,
                fallbackShape = spec.fallbackShape
            )
        }
    }

    private fun drawCourseVisualWallBandShadowBehindFill(canvas: Canvas, coursePath: Path) {
        strokePaint.style = Paint.Style.STROKE
        strokePaint.color = Color.argb(58, 0, 0, 0)
        strokePaint.strokeWidth = IOS_WALL_VISUAL_BAND_SHADOW_SIZE
        strokePaint.strokeCap = Paint.Cap.SQUARE
        strokePaint.strokeJoin = Paint.Join.MITER

        canvas.withTranslation(offsetX, offsetY) {
            scale(scale, scale)

            translate(0f, -IOS_SHADOW_COURSE_Y_OFFSET)
            drawPath(coursePath, strokePaint)
        }
    }

    private fun drawCourseVisualWallBandBehindFill(canvas: Canvas, coursePath: Path) {
        strokePaint.style = Paint.Style.STROKE
        strokePaint.color = Color.rgb(232, 232, 226)
        strokePaint.strokeWidth = IOS_WALL_VISUAL_BAND_DRAW_SIZE
        strokePaint.strokeCap = Paint.Cap.SQUARE
        strokePaint.strokeJoin = Paint.Join.MITER

        canvas.withTranslation(offsetX, offsetY) {
            scale(scale, scale)
            drawPath(coursePath, strokePaint)
        }
    }

    private fun drawBackground(canvas: Canvas) {
        canvas.drawColor(Color.rgb(174, 171, 162))
    }

    private data class BoardTransform(
        val scale: Float,
        val offsetX: Float,
        val offsetY: Float
    )

    private fun computeTransform(g: GolfMap) {
        val full = computeFullBoardTransform(g)

        val target = when {
            overviewCameraHeld || cameraMode == CameraMode.FULL_BOARD -> full
            cameraMode == CameraMode.REPLAY -> computeReplayBoardTransform(g, full)
            else -> computeAimBoardTransform(g, full)
        }

        applyAnimatedTransform(target)
    }

    private fun applyAnimatedTransform(target: BoardTransform) {
        val now = SystemClock.elapsedRealtime()

        if (!cameraTransformReady || snapCameraOnNextDraw || width <= 0 || height <= 0) {
            scale = target.scale
            offsetX = target.offsetX
            offsetY = target.offsetY

            cameraTransformReady = true
            snapCameraOnNextDraw = false
            cameraAnimLastMs = now
            return
        }

        val dt = ((now - cameraAnimLastMs).coerceIn(1L, 34L)).toFloat() / 1000f
        cameraAnimLastMs = now

        val t = (1f - CAMERA_ANIMATION_DAMPING_PER_60FPS_FRAME.pow(dt * 60f))
            .coerceIn(0.06f, 0.38f)

        scale += (target.scale - scale) * t
        offsetX += (target.offsetX - offsetX) * t
        offsetY += (target.offsetY - offsetY) * t

        val close =
            abs(target.scale - scale) < 0.001f &&
                    abs(target.offsetX - offsetX) < CAMERA_ANIMATION_EPSILON &&
                    abs(target.offsetY - offsetY) < CAMERA_ANIMATION_EPSILON

        if (close) {
            scale = target.scale
            offsetX = target.offsetX
            offsetY = target.offsetY
        } else {
            postInvalidateOnAnimation()
        }
    }

    private fun computeFullBoardTransform(g: GolfMap): BoardTransform {
        val safeW = width.coerceAtLeast(1).toFloat()
        val safeH = height.coerceAtLeast(1).toFloat()

        val topUiPad = safeH * 0.06f
        val bottomUiPad = safeH * 0.18f

        val usableBottom = safeH - bottomUiPad
        val usableHeight = usableBottom - topUiPad

        val bounds = renderBounds(g)

        val availableW = safeW * 0.82f
        val availableH = usableHeight * 0.92f

        val fullScale = min(availableW / bounds.width, availableH / bounds.height)

        val fullOffsetX = (safeW - bounds.width * fullScale) * 0.5f - bounds.left * fullScale

        val centeredTop = topUiPad + (usableHeight - bounds.height * fullScale) * 0.5f
        val fullOffsetY = centeredTop - bounds.top * fullScale

        return BoardTransform(
            scale = fullScale,
            offsetX = fullOffsetX,
            offsetY = fullOffsetY
        )
    }

    private fun computeAimBoardTransform(
        g: GolfMap,
        full: BoardTransform
    ): BoardTransform {
        val safeW = width.coerceAtLeast(1).toFloat()
        val safeH = height.coerceAtLeast(1).toFloat()
        val bounds = renderBounds(g)

        val ballCourse =
            runtimeBallCourse
                ?: aimCameraBallCourse
                ?: g.ballStart1

        val ballVisual = courseToVisualRaw(g, ballCourse)

        val powerT = (aimCameraDist / GolfShot.AIM_MAX_DIST).coerceIn(0f, 1f)

        val zoomMultiplier =
            AIM_CAMERA_MAX_ZOOM_MULTIPLIER -
                    (AIM_CAMERA_MAX_ZOOM_MULTIPLIER - AIM_CAMERA_MIN_ZOOM_MULTIPLIER) * powerT

        val aimScale = max(full.scale, full.scale * zoomMultiplier)

        val aimOffsetX = safeW * 0.5f - ballVisual.x * aimScale

        val safeTopY = safeH * AIM_CAMERA_VERTICAL_MIN_SCREEN_FRACTION
        val safeBottomY = safeH * AIM_CAMERA_VERTICAL_MAX_SCREEN_FRACTION

        val currentBallScreenY = if (cameraTransformReady) {
            offsetY + ballVisual.y * scale
        } else {
            full.offsetY + ballVisual.y * full.scale
        }

        val preferredBallScreenY = currentBallScreenY.coerceIn(
            safeTopY,
            safeBottomY
        )

        val preferredOffsetY = preferredBallScreenY - ballVisual.y * aimScale

        val aimOffsetY = clampAimOffsetY(
            bounds = bounds,
            scaleValue = aimScale,
            preferredOffsetY = preferredOffsetY
        )

        return BoardTransform(
            scale = aimScale,
            offsetX = aimOffsetX,
            offsetY = aimOffsetY
        )
    }

    private fun computeReplayBoardTransform(
        g: GolfMap,
        full: BoardTransform
    ): BoardTransform {
        val safeW = width.coerceAtLeast(1).toFloat()
        val safeH = height.coerceAtLeast(1).toFloat()

        val ball1Course =
            replayCameraBall1Course
                ?: runtimeBallCourse
                ?: g.ballStart1

        val ball2Course =
            replayCameraBall2Course
                ?: opponentBallCourse
                ?: ball1Course

        val b1 = courseToVisualRaw(g, ball1Course)
        val b2 = courseToVisualRaw(g, ball2Course)

        val minX = min(b1.x, b2.x)
        val maxX = max(b1.x, b2.x)
        val minY = min(b1.y, b2.y)
        val maxY = max(b1.y, b2.y)

        val centerX = (minX + maxX) * 0.5f
        val centerY = (minY + maxY) * 0.5f

        val contentW = (maxX - minX).coerceAtLeast(110f)
        val contentH = (maxY - minY).coerceAtLeast(110f)

        val availableW = safeW * 0.72f
        val availableH = safeH * 0.52f

        val replayScale = min(
            availableW / contentW,
            availableH / contentH
        ).coerceIn(
            full.scale,
            full.scale * 1.85f
        )

        val replayOffsetX = safeW * 0.5f - centerX * replayScale
        val replayOffsetY = safeH * 0.48f - centerY * replayScale

        return BoardTransform(
            scale = replayScale,
            offsetX = replayOffsetX,
            offsetY = replayOffsetY
        )
    }

    private fun clampAimOffsetY(
        bounds: RenderBounds,
        scaleValue: Float,
        preferredOffsetY: Float
    ): Float {
        val safeH = height.coerceAtLeast(1).toFloat()
        val topLimit = safeH * 0.25f
        val bottomLimit = safeH * 0.75f

        val minOffsetY = bottomLimit - bounds.bottom * scaleValue
        val maxOffsetY = topLimit - bounds.top * scaleValue

        return if (minOffsetY <= maxOffsetY) {
            preferredOffsetY.coerceIn(minOffsetY, maxOffsetY)
        } else {
            preferredOffsetY
        }
    }

    private fun visualMapWidth(g: GolfMap): Float {
        return g.mapSize2
    }

    private fun visualMapHeight(g: GolfMap): Float {
        return g.mapSize
    }

    private data class RenderBounds(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float
    ) {
        val width: Float get() = right - left
        val height: Float get() = bottom - top
    }

    private fun renderBounds(g: GolfMap): RenderBounds {
        val halfTile = IOS_TILE_DRAW_SIZE * 0.5f

        val left = -halfTile
        val right = (g.yCells - 1) * GolfConstants.TILE_SIZE + halfTile

        val top = GolfConstants.TILE_SIZE - halfTile
        val bottom = g.mapSize + halfTile

        return RenderBounds(left, top, right, bottom)
    }

    private fun drawCourseFill(canvas: Canvas, coursePath: Path) {
        paint.style = Paint.Style.FILL
        paint.color = Color.rgb(0, 142, 43)
        paint.alpha = 255
        paint.colorFilter = null

        canvas.withTranslation(offsetX, offsetY) {
            scale(scale, scale)
            drawPath(coursePath, paint)
        }
    }

    private fun drawCourseOutline(canvas: Canvas, coursePath: Path) {
        strokePaint.style = Paint.Style.STROKE
        strokePaint.color = Color.rgb(232, 232, 226)
        strokePaint.strokeWidth = IOS_WALL_DRAW_SIZE
        strokePaint.strokeCap = Paint.Cap.SQUARE
        strokePaint.strokeJoin = Paint.Join.MITER

        canvas.withTranslation(offsetX, offsetY) {
            scale(scale, scale)
            drawPath(coursePath, strokePaint)
        }
    }

    private fun buildCoursePath(g: GolfMap, tileDrawSize: Float): Path {
        val unionPath = Path()
        var hasAnyCell = false

        for (visualRow in 0 until visualRows(g)) {
            for (visualCol in 0 until visualCols(g)) {
                if (!visualIsOpen(g, visualCol, visualRow)) continue

                val rect = visualCellRect(visualCol, visualRow, tileDrawSize)
                val cellPath = Path().apply {
                    addRect(rect, Path.Direction.CW)
                }

                if (!hasAnyCell) {
                    unionPath.set(cellPath)
                    hasAnyCell = true
                } else {
                    unionPath.op(cellPath, Path.Op.UNION)
                }
            }
        }

        applySpecialValue3Cuts(g, unionPath, tileDrawSize)
        applyDiagonalCornerCuts(g, unionPath, tileDrawSize)

        return unionPath
    }

    private fun applySpecialValue3Cuts(g: GolfMap, coursePath: Path, tileDrawSize: Float) {
        for (visualRow in 0 until visualRows(g)) {
            for (visualCol in 0 until visualCols(g)) {
                if (visualCellValue(g, visualCol, visualRow) != 3) continue

                val corner = specialValue3CutCorner(g, visualCol, visualRow)
                val rect = visualCellRect(visualCol, visualRow, tileDrawSize)

                subtractCornerTriangle(coursePath, rect, corner)
            }
        }
    }

    private fun specialValue3CutCorner(g: GolfMap, visualCol: Int, visualRow: Int): CutCorner {
        val topBlocked = !visualIsOpen(g, visualCol, visualRow - 1)
        val bottomBlocked = !visualIsOpen(g, visualCol, visualRow + 1)
        val leftBlocked = !visualIsOpen(g, visualCol - 1, visualRow)
        val rightBlocked = !visualIsOpen(g, visualCol + 1, visualRow)

        return when {
            topBlocked && leftBlocked -> CutCorner.TOP_LEFT
            topBlocked && rightBlocked -> CutCorner.TOP_RIGHT
            bottomBlocked && leftBlocked -> CutCorner.BOTTOM_LEFT
            bottomBlocked && rightBlocked -> CutCorner.BOTTOM_RIGHT

            else -> {
                CutCorner.BOTTOM_LEFT
            }
        }
    }

    private fun subtractCornerTriangle(coursePath: Path, rect: RectF, corner: CutCorner) {
        val cut = Path()

        when (corner) {
            CutCorner.TOP_LEFT -> {
                cut.moveTo(rect.left, rect.top)
                cut.lineTo(rect.right, rect.top)
                cut.lineTo(rect.left, rect.bottom)
                cut.close()
            }

            CutCorner.TOP_RIGHT -> {
                cut.moveTo(rect.left, rect.top)
                cut.lineTo(rect.right, rect.top)
                cut.lineTo(rect.right, rect.bottom)
                cut.close()
            }

            CutCorner.BOTTOM_LEFT -> {
                cut.moveTo(rect.left, rect.top)
                cut.lineTo(rect.left, rect.bottom)
                cut.lineTo(rect.right, rect.bottom)
                cut.close()
            }

            CutCorner.BOTTOM_RIGHT -> {
                cut.moveTo(rect.right, rect.top)
                cut.lineTo(rect.right, rect.bottom)
                cut.lineTo(rect.left, rect.bottom)
                cut.close()
            }
        }

        coursePath.op(cut, Path.Op.DIFFERENCE)
    }

    private fun applyDiagonalCornerCuts(g: GolfMap, coursePath: Path, tileDrawSize: Float) {
        val rows = visualRows(g)
        val cols = visualCols(g)

        for (row in 0 until rows - 1) {
            for (col in 0 until cols - 1) {
                if (
                    visualCellValue(g, col, row) == 3 ||
                    visualCellValue(g, col + 1, row) == 3 ||
                    visualCellValue(g, col, row + 1) == 3 ||
                    visualCellValue(g, col + 1, row + 1) == 3
                ) {
                    continue
                }

                val tl = visualIsOpen(g, col, row)
                val tr = visualIsOpen(g, col + 1, row)
                val bl = visualIsOpen(g, col, row + 1)
                val br = visualIsOpen(g, col + 1, row + 1)

                val openCount = listOf(tl, tr, bl, br).count { it }
                if (openCount != 3) continue

                val tlCenter = visualCellCenter(col, row, tileDrawSize)
                val trCenter = visualCellCenter(col + 1, row, tileDrawSize)
                val blCenter = visualCellCenter(col, row + 1, tileDrawSize)
                val brCenter = visualCellCenter(col + 1, row + 1, tileDrawSize)
                val sharedX = (tlCenter.x + trCenter.x + blCenter.x + brCenter.x) * 0.25f
                val sharedY = (tlCenter.y + trCenter.y + blCenter.y + brCenter.y) * 0.25f

                val cutPath = Path()

                when {
                    !tl -> {
                        cutPath.moveTo(trCenter.x, trCenter.y)
                        cutPath.lineTo(sharedX, sharedY)
                        cutPath.lineTo(blCenter.x, blCenter.y)
                        cutPath.close()
                    }

                    !tr -> {
                        cutPath.moveTo(tlCenter.x, tlCenter.y)
                        cutPath.lineTo(sharedX, sharedY)
                        cutPath.lineTo(brCenter.x, brCenter.y)
                        cutPath.close()
                    }

                    !bl -> {
                        cutPath.moveTo(tlCenter.x, tlCenter.y)
                        cutPath.lineTo(sharedX, sharedY)
                        cutPath.lineTo(brCenter.x, brCenter.y)
                        cutPath.close()
                    }

                    !br -> {
                        cutPath.moveTo(trCenter.x, trCenter.y)
                        cutPath.lineTo(sharedX, sharedY)
                        cutPath.lineTo(blCenter.x, blCenter.y)
                        cutPath.close()
                    }
                }

                coursePath.op(cutPath, Path.Op.DIFFERENCE)
            }
        }
    }

    private fun visualCols(g: GolfMap): Int {
        return g.yCells
    }

    private fun visualRows(g: GolfMap): Int {
        return g.xCells
    }

    private fun visualIsOpen(g: GolfMap, visualCol: Int, visualRow: Int): Boolean {
        val original = visualToOriginalCell(g, visualCol, visualRow) ?: return false
        return g.isOpen(original.x, original.y)
    }

    private fun visualCellValue(g: GolfMap, visualCol: Int, visualRow: Int): Int {
        val original = visualToOriginalCell(g, visualCol, visualRow) ?: return 1
        return g.grid[original.x][original.y]
    }

    private fun visualToOriginalCell(g: GolfMap, visualCol: Int, visualRow: Int): Cell? {
        val outerRow = g.xCells - 1 - visualRow

        if (outerRow !in 0 until g.xCells || visualCol !in 0 until g.yCells) {
            return null
        }

        return Cell(outerRow, visualCol)
    }

    private fun visualCellRect(
        visualCol: Int,
        visualRow: Int,
        tileDrawSize: Float = IOS_TILE_DRAW_SIZE
    ): RectF {
        val centerVisualX = visualCol * GolfConstants.TILE_SIZE
        val centerVisualY = (visualRow + 1) * GolfConstants.TILE_SIZE

        val half = tileDrawSize * 0.5f

        return RectF(
            centerVisualX - half,
            centerVisualY - half,
            centerVisualX + half,
            centerVisualY + half
        )
    }

    private fun visualCellCenter(
        visualCol: Int,
        visualRow: Int,
        tileDrawSize: Float = IOS_TILE_DRAW_SIZE
    ): PointF {
        val r = visualCellRect(visualCol, visualRow, tileDrawSize)
        return PointF(r.centerX(), r.centerY())
    }

    private fun drawPathPreview(canvas: Canvas, g: GolfMap) {
        if (g.longestPath.size < 2) return

        val path = Path()

        g.longestPath.forEachIndexed { index, cell ->
            val p = courseToScreen(
                PointF(
                    cell.y * GolfConstants.TILE_SIZE,
                    cell.x * GolfConstants.TILE_SIZE
                )
            )

            if (index == 0) {
                path.moveTo(p.x, p.y)
            } else {
                path.lineTo(p.x, p.y)
            }
        }

        strokePaint.color = Color.argb(110, 255, 255, 255)
        strokePaint.strokeWidth = 3f * scale
        strokePaint.strokeCap = Paint.Cap.ROUND
        strokePaint.strokeJoin = Paint.Join.ROUND
        canvas.drawPath(path, strokePaint)

        strokePaint.strokeCap = Paint.Cap.SQUARE
        strokePaint.strokeJoin = Paint.Join.MITER
    }

    private fun drawSlopes(canvas: Canvas, g: GolfMap) {
        for (slope in g.slopes) {
            val bitmap = when (slope.image) {
                "golf_slope_down" -> slopeDownBitmap
                else -> slopeUpBitmap
            }

            val p = courseToScreen(PointF(slope.x, slope.y))

            drawCourseBitmap(
                canvas = canvas,
                bitmap = bitmap,
                cx = p.x,
                cy = p.y,
                widthCourse = IOS_SLOPE_WIDTH,
                heightCourse = IOS_SLOPE_HEIGHT,
                rotationRadians = slopeRotationForRenderer(slope),
                fallbackColor = Color.argb(180, 125, 230, 110),
                drawShadow = false
            )
        }
    }

    private fun drawObjectDebugDots(canvas: Canvas, g: GolfMap) {
        paint.style = Paint.Style.FILL
        paint.color = Color.MAGENTA

        for (slope in g.slopes) {
            val p = courseToScreen(PointF(slope.x, slope.y))
            canvas.drawCircle(p.x, p.y, 8f, paint)
        }

        paint.color = Color.CYAN

        for (obstacle in g.obstacles) {
            val p = courseToScreen(PointF(obstacle.x, obstacle.y))
            canvas.drawCircle(p.x, p.y, 8f, paint)
        }
    }

    private fun slopeRotationForRenderer(slope: GolfSlope): Float {
        if (!slope.rotation.isNaN()) {
            return slope.rotation
        }

        return when {
            abs(slope.vx) > 0.001f && abs(slope.vy) <= 0.001f -> (Math.PI / 2.0).toFloat()
            else -> 0f
        }
    }

    private enum class ObstacleVisualFallbackShape {
        RECT,
        CIRCLE,
        TRIANGLE,
        CROSS
    }

    private data class ObstacleDrawSpec(
        val bitmap: Bitmap?,
        val width: Float,
        val height: Float,
        val fallbackShape: ObstacleVisualFallbackShape = ObstacleVisualFallbackShape.RECT
    )

    private enum class CollisionDebugShape {
        BOX,
        CIRCLE,
        TRIANGLE,
        CROSS
    }

    private data class ObstacleCollisionDrawSpec(
        val image: String,
        val width: Float,
        val height: Float,
        val shape: CollisionDebugShape
    )

    private fun obstacleCollisionSpecForDebug(obstacle: GolfObstacle): ObstacleCollisionDrawSpec {
        val image = obstacle.image.ifBlank {
            obstacleImageForType(obstacle.type, obstacle.bouncy)
        }

        return when (image) {
            "golf_obstacle_square" -> ObstacleCollisionDrawSpec(
                image,
                30f,
                30f,
                CollisionDebugShape.BOX
            )

            "golf_obstacle_square2" -> ObstacleCollisionDrawSpec(
                image,
                70f,
                70f,
                CollisionDebugShape.BOX
            )

            "golf_obstacle_bar" -> ObstacleCollisionDrawSpec(
                image,
                DEBUG_NATIVE_SMALL_BAR_WIDTH_COURSE,
                DEBUG_NATIVE_SMALL_BAR_HEIGHT_COURSE,
                CollisionDebugShape.BOX
            )

            "golf_obstacle_bar2",
            "golf_obstacles_bar2" -> ObstacleCollisionDrawSpec(
                image,
                DEBUG_NATIVE_LARGE_BAR_WIDTH_COURSE,
                DEBUG_NATIVE_LARGE_BAR_HEIGHT_COURSE,
                CollisionDebugShape.BOX
            )

            "golf_obstacle_round" -> ObstacleCollisionDrawSpec(
                image,
                37f,
                37f,
                CollisionDebugShape.CIRCLE
            )

            "golf_obstacle_round2",
            "golf_obstacles_round2" -> ObstacleCollisionDrawSpec(
                image,
                72f,
                72f,
                CollisionDebugShape.CIRCLE
            )

            "golf_obstacle_triangle" -> ObstacleCollisionDrawSpec(
                image,
                30f,
                30f,
                CollisionDebugShape.TRIANGLE
            )

            "golf_obstacle_triangle2" -> ObstacleCollisionDrawSpec(
                image,
                70f,
                70f,
                CollisionDebugShape.TRIANGLE
            )

            "golf_obstacle_cross" -> ObstacleCollisionDrawSpec(
                image,
                95f,
                95f,
                CollisionDebugShape.CROSS
            )

            else -> ObstacleCollisionDrawSpec(
                image,
                30f,
                30f,
                CollisionDebugShape.BOX
            )
        }
    }

    private fun collisionDebugCellValue(
        g: GolfMap,
        row: Int,
        col: Int
    ): Int {
        if (row !in g.grid.indices) return 1
        if (col !in g.grid[row].indices) return 1
        return g.grid[row][col]
    }

    private fun collisionDebugCellOpen(
        g: GolfMap,
        row: Int,
        col: Int
    ): Boolean {
        val value = collisionDebugCellValue(g, row, col)
        return value == 0 || value == 3
    }

    private fun drawDebugPath(
        canvas: Canvas,
        path: Path,
        fillColor: Int,
        strokeColor: Int = Color.argb(230, 255, 255, 255)
    ) {
        collisionDebugPaint.style = Paint.Style.FILL
        collisionDebugPaint.color = fillColor
        canvas.drawPath(path, collisionDebugPaint)

        collisionDebugPaint.style = Paint.Style.STROKE
        collisionDebugPaint.strokeWidth = 1.5f * scale
        collisionDebugPaint.color = strokeColor
        canvas.drawPath(path, collisionDebugPaint)
    }

    private fun rotatedBoxPathScreen(
        cx: Float,
        cy: Float,
        halfW: Float,
        halfH: Float,
        rotationRadians: Float
    ): Path {
        val c = cos(rotationRadians)
        val s = kotlin.math.sin(rotationRadians)

        val local = arrayOf(
            -halfW to -halfH,
            halfW to -halfH,
            halfW to halfH,
            -halfW to halfH
        )

        val path = Path()

        local.forEachIndexed { index, pair ->
            val lx = pair.first
            val ly = pair.second

            val courseX = cx + lx * c - ly * s
            val courseY = cy + lx * s + ly * c
            val screen = courseToScreen(PointF(courseX, courseY))

            if (index == 0) {
                path.moveTo(screen.x, screen.y)
            } else {
                path.lineTo(screen.x, screen.y)
            }
        }

        path.close()
        return path
    }

    private fun trianglePathScreen(
        cx: Float,
        cy: Float,
        width: Float,
        height: Float,
        rotationRadians: Float
    ): Path {
        val halfW = width * 0.5f
        val halfH = height * 0.5f

        val local = arrayOf(
            -halfW to -halfH,
            halfW to halfH,
            halfW to -halfH
        )

        val c = cos(rotationRadians)
        val s = kotlin.math.sin(rotationRadians)

        val path = Path()

        local.forEachIndexed { index, pair ->
            val lx = pair.first
            val ly = pair.second

            val courseX = cx + lx * c - ly * s
            val courseY = cy + lx * s + ly * c
            val screen = courseToScreen(PointF(courseX, courseY))

            if (index == 0) {
                path.moveTo(screen.x, screen.y)
            } else {
                path.lineTo(screen.x, screen.y)
            }
        }

        path.close()
        return path
    }

    private fun drawCollisionBoxCourse(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        width: Float,
        height: Float,
        rotationRadians: Float,
        fillColor: Int
    ) {
        val path = rotatedBoxPathScreen(
            cx = cx,
            cy = cy,
            halfW = width * 0.5f,
            halfH = height * 0.5f,
            rotationRadians = rotationRadians
        )

        drawDebugPath(canvas, path, fillColor)
    }

    private fun drawCollisionCircleCourse(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        radius: Float,
        fillColor: Int
    ) {
        val center = courseToScreen(PointF(cx, cy))
        val screenRadius = radius * scale

        collisionDebugPaint.style = Paint.Style.FILL
        collisionDebugPaint.color = fillColor
        canvas.drawCircle(center.x, center.y, screenRadius, collisionDebugPaint)

        collisionDebugPaint.style = Paint.Style.STROKE
        collisionDebugPaint.strokeWidth = 1.5f * scale
        collisionDebugPaint.color = Color.argb(230, 255, 255, 255)
        canvas.drawCircle(center.x, center.y, screenRadius, collisionDebugPaint)
    }

    private fun diagonalCollisionAngleForDebug(
        g: GolfMap,
        row: Int,
        col: Int
    ): Float {
        val topBlocked = !collisionDebugCellOpen(g, row - 1, col)
        val bottomBlocked = !collisionDebugCellOpen(g, row + 1, col)
        val leftBlocked = !collisionDebugCellOpen(g, row, col - 1)
        val rightBlocked = !collisionDebugCellOpen(g, row, col + 1)

        return when {
            topBlocked && rightBlocked -> (Math.PI / 4.0).toFloat()
            bottomBlocked && leftBlocked -> (Math.PI / 4.0).toFloat()
            topBlocked && leftBlocked -> (-Math.PI / 4.0).toFloat()
            bottomBlocked && rightBlocked -> (-Math.PI / 4.0).toFloat()
            else -> (-Math.PI / 4.0).toFloat()
        }
    }

    private fun drawNativeWallCollisionDebug(canvas: Canvas, g: GolfMap) {
        val tile = GolfConstants.TILE_SIZE
        val wallFill = Color.argb(70, 255, 0, 0)
        val diagonalFill = Color.argb(120, 255, 180, 0)

        for (row in g.grid.indices) {
            for (col in g.grid[row].indices) {
                val value = g.grid[row][col]
                val cx = col * tile
                val cy = row * tile

                when (value) {
                    1 -> {
                        drawCollisionBoxCourse(
                            canvas = canvas,
                            cx = cx,
                            cy = cy,
                            width = tile,
                            height = tile,
                            rotationRadians = 0f,
                            fillColor = wallFill
                        )
                    }

                    3 -> {
                        val halfLength = tile * 0.5f * kotlin.math.sqrt(2f)
                        val angle = diagonalCollisionAngleForDebug(g, row, col)

                        drawCollisionBoxCourse(
                            canvas = canvas,
                            cx = cx,
                            cy = cy,
                            width = halfLength * 2f,
                            height = DEBUG_NATIVE_DIAGONAL_WALL_THICKNESS_COURSE,
                            rotationRadians = angle,
                            fillColor = diagonalFill
                        )
                    }
                }
            }
        }

        val halfTile = tile * 0.5f

        val minX = -halfTile
        val maxX =
            if (g.yCells > 0) {
                ((g.yCells - 1).toFloat() * tile) + halfTile
            } else {
                g.mapSize + halfTile
            }

        val minY = -halfTile
        val maxY =
            if (g.xCells > 0) {
                ((g.xCells - 1).toFloat() * tile) + halfTile
            } else {
                g.mapSize + halfTile
            }

        val centerX = (minX + maxX) * 0.5f
        val centerY = (minY + maxY) * 0.5f

        val halfW = (maxX - minX) * 0.5f
        val halfH = (maxY - minY) * 0.5f
        val t = DEBUG_NATIVE_OUTER_WALL_THICKNESS_COURSE

        drawCollisionBoxCourse(
            canvas = canvas,
            cx = centerX,
            cy = minY - t,
            width = (halfW + t * 2f) * 2f,
            height = t * 2f,
            rotationRadians = 0f,
            fillColor = Color.argb(45, 255, 0, 0)
        )

        drawCollisionBoxCourse(
            canvas = canvas,
            cx = centerX,
            cy = maxY + t,
            width = (halfW + t * 2f) * 2f,
            height = t * 2f,
            rotationRadians = 0f,
            fillColor = Color.argb(45, 255, 0, 0)
        )

        drawCollisionBoxCourse(
            canvas = canvas,
            cx = minX - t,
            cy = centerY,
            width = t * 2f,
            height = (halfH + t * 2f) * 2f,
            rotationRadians = 0f,
            fillColor = Color.argb(45, 255, 0, 0)
        )

        drawCollisionBoxCourse(
            canvas = canvas,
            cx = maxX + t,
            cy = centerY,
            width = t * 2f,
            height = (halfH + t * 2f) * 2f,
            rotationRadians = 0f,
            fillColor = Color.argb(45, 255, 0, 0)
        )
    }

    private fun drawNativeObstacleCollisionDebug(canvas: Canvas, g: GolfMap) {
        val obstacleFill = Color.argb(95, 255, 0, 255)

        for (obstacle in g.obstacles) {
            val spec = obstacleCollisionSpecForDebug(obstacle)

            val widthCourse = spec.width * obstacle.scale
            val heightCourse = spec.height * obstacle.scale

            when (spec.shape) {
                CollisionDebugShape.CIRCLE -> {
                    drawCollisionCircleCourse(
                        canvas = canvas,
                        cx = obstacle.x,
                        cy = obstacle.y,
                        radius = min(widthCourse, heightCourse) * 0.5f,
                        fillColor = obstacleFill
                    )
                }

                CollisionDebugShape.TRIANGLE -> {
                    val path = trianglePathScreen(
                        cx = obstacle.x,
                        cy = obstacle.y,
                        width = widthCourse,
                        height = heightCourse,
                        rotationRadians = obstacle.rotation
                    )

                    drawDebugPath(canvas, path, obstacleFill)
                }

                CollisionDebugShape.CROSS -> {
                    val minSide = min(widthCourse, heightCourse)
                    val scaleValue =
                        if (minSide > 0f) {
                            minSide / DEBUG_NATIVE_CROSS_BASE_SIZE_COURSE
                        } else {
                            1f
                        }

                    val armThickness =
                        DEBUG_NATIVE_CROSS_ARM_THICKNESS_COURSE * scaleValue

                    val centerRadius =
                        DEBUG_NATIVE_CROSS_CENTER_RADIUS_COURSE * scaleValue

                    drawCollisionBoxCourse(
                        canvas = canvas,
                        cx = obstacle.x,
                        cy = obstacle.y,
                        width = widthCourse,
                        height = armThickness,
                        rotationRadians = obstacle.rotation,
                        fillColor = obstacleFill
                    )

                    drawCollisionBoxCourse(
                        canvas = canvas,
                        cx = obstacle.x,
                        cy = obstacle.y,
                        width = armThickness,
                        height = heightCourse,
                        rotationRadians = obstacle.rotation,
                        fillColor = obstacleFill
                    )

                    drawCollisionCircleCourse(
                        canvas = canvas,
                        cx = obstacle.x,
                        cy = obstacle.y,
                        radius = centerRadius,
                        fillColor = obstacleFill
                    )
                }

                CollisionDebugShape.BOX -> {
                    drawCollisionBoxCourse(
                        canvas = canvas,
                        cx = obstacle.x,
                        cy = obstacle.y,
                        width = widthCourse,
                        height = heightCourse,
                        rotationRadians = obstacle.rotation,
                        fillColor = obstacleFill
                    )
                }
            }
        }
    }

    private fun drawSlopeCollisionDebug(canvas: Canvas, g: GolfMap) {
        val slopeFill = Color.argb(75, 0, 255, 80)

        for (slope in g.slopes) {
            drawCollisionBoxCourse(
                canvas = canvas,
                cx = slope.x,
                cy = slope.y,
                width = DEBUG_NATIVE_SLOPE_WIDTH_COURSE,
                height = DEBUG_NATIVE_SLOPE_HEIGHT_COURSE,
                rotationRadians = slopeRotationForRenderer(slope),
                fillColor = slopeFill
            )
        }
    }

    private fun drawBallCollisionDebug(canvas: Canvas, g: GolfMap) {
        val ball = runtimeBallCourse ?: g.ballStart1

        drawCollisionCircleCourse(
            canvas = canvas,
            cx = ball.x,
            cy = ball.y,
            radius = DEBUG_NATIVE_BALL_RADIUS_COURSE,
            fillColor = Color.argb(140, 255, 255, 0)
        )
    }

    private fun logCollisionDebugTruthOnce(g: GolfMap) {
        if (!showCollisionDebug) return

        val key =
            "${g.seed}|${g.mode}|${g.mapNum}|" +
                    "$DEBUG_NATIVE_DIAGONAL_WALL_THICKNESS_COURSE|" +
                    "$DEBUG_NATIVE_CROSS_ARM_THICKNESS_COURSE|" +
                    "$DEBUG_NATIVE_CROSS_CENTER_RADIUS_COURSE"

        if (loggedCollisionDebugTruthForKey == key) return
        loggedCollisionDebugTruthForKey = key

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_VISUAL_COLLISION_DEBUG=" +
                    "{" +
                    "\"seed\":${g.seed}," +
                    "\"mode\":\"${g.mode}\"," +
                    "\"mapNum\":${g.mapNum}," +
                    "\"ballRadius\":$DEBUG_NATIVE_BALL_RADIUS_COURSE," +
                    "\"diagonalThickness\":$DEBUG_NATIVE_DIAGONAL_WALL_THICKNESS_COURSE," +
                    "\"diagonalHalfThickness\":$DEBUG_NATIVE_DIAGONAL_WALL_HALF_THICKNESS_COURSE," +
                    "\"outerWallThickness\":$DEBUG_NATIVE_OUTER_WALL_THICKNESS_COURSE," +
                    "\"crossBaseSize\":$DEBUG_NATIVE_CROSS_BASE_SIZE_COURSE," +
                    "\"crossArmThickness\":$DEBUG_NATIVE_CROSS_ARM_THICKNESS_COURSE," +
                    "\"crossCenterRadius\":$DEBUG_NATIVE_CROSS_CENTER_RADIUS_COURSE," +
                    "\"smallBar\":{\"width\":$DEBUG_NATIVE_SMALL_BAR_WIDTH_COURSE,\"height\":$DEBUG_NATIVE_SMALL_BAR_HEIGHT_COURSE}," +
                    "\"largeBar\":{\"width\":$DEBUG_NATIVE_LARGE_BAR_WIDTH_COURSE,\"height\":$DEBUG_NATIVE_LARGE_BAR_HEIGHT_COURSE}," +
                    "\"slope\":{\"width\":$DEBUG_NATIVE_SLOPE_WIDTH_COURSE,\"height\":$DEBUG_NATIVE_SLOPE_HEIGHT_COURSE}" +
                    "}"
        )
    }

    private fun drawCollisionDebug(canvas: Canvas, g: GolfMap) {
        if (!showCollisionDebug) return

        logCollisionDebugTruthOnce(g)

        drawNativeWallCollisionDebug(canvas, g)
        drawSlopeCollisionDebug(canvas, g)
        drawNativeObstacleCollisionDebug(canvas, g)
        drawBallCollisionDebug(canvas, g)

        collisionDebugPaint.style = Paint.Style.STROKE
    }

    private fun obstacleSpec(obstacle: GolfObstacle): ObstacleDrawSpec {
        val image = obstacle.image.ifBlank {
            obstacleImageForType(obstacle.type, obstacle.bouncy)
        }

        return when (image) {
            "golf_obstacle_square" -> ObstacleDrawSpec(
                obstacleSquareBitmap,
                IOS_OBSTACLE_BASE_SIZE,
                IOS_OBSTACLE_BASE_SIZE,
                ObstacleVisualFallbackShape.RECT
            )

            "golf_obstacle_square2" -> ObstacleDrawSpec(
                obstacleSquare2Bitmap,
                70f,
                70f,
                ObstacleVisualFallbackShape.RECT
            )

            "golf_obstacle_bar" -> ObstacleDrawSpec(
                obstacleBarBitmap,
                46f,
                8f,
                ObstacleVisualFallbackShape.RECT
            )

            "golf_obstacle_bar2",
            "golf_obstacles_bar2" -> ObstacleDrawSpec(
                obstacleBar2Bitmap,
                95f,
                6f,
                ObstacleVisualFallbackShape.RECT
            )

            "golf_obstacle_round" -> ObstacleDrawSpec(
                obstacleRoundBitmap,
                37f,
                37f,
                ObstacleVisualFallbackShape.CIRCLE
            )

            "golf_obstacle_round2",
            "golf_obstacles_round2" -> ObstacleDrawSpec(
                obstacleRound2Bitmap,
                72f,
                72f,
                ObstacleVisualFallbackShape.CIRCLE
            )

            "golf_obstacle_triangle" -> ObstacleDrawSpec(
                obstacleTriangleBitmap,
                IOS_OBSTACLE_BASE_SIZE,
                IOS_OBSTACLE_BASE_SIZE,
                ObstacleVisualFallbackShape.TRIANGLE
            )

            "golf_obstacle_triangle2" -> ObstacleDrawSpec(
                obstacleTriangle2Bitmap,
                70f,
                70f,
                ObstacleVisualFallbackShape.TRIANGLE
            )

            "golf_obstacle_cross" -> ObstacleDrawSpec(
                obstacleCrossBitmap,
                95f,
                95f,
                ObstacleVisualFallbackShape.CROSS
            )

            else -> ObstacleDrawSpec(
                obstacleSquareBitmap,
                30f,
                30f,
                ObstacleVisualFallbackShape.RECT
            )
        }
    }

    private fun obstacleImageForType(type: Int, bouncy: Boolean): String {
        return when {
            bouncy -> "golf_obstacle_round"
            type == 2 -> "golf_obstacle_bar"
            type == 3 -> "golf_obstacle_triangle"
            type == 4 -> "golf_obstacle_round"
            type == 5 -> "golf_obstacle_cross"
            else -> "golf_obstacle_square"
        }
    }

    private fun drawCourseBitmap(
        canvas: Canvas,
        bitmap: Bitmap?,
        cx: Float,
        cy: Float,
        widthCourse: Float,
        heightCourse: Float,
        rotationRadians: Float,
        fallbackColor: Int,
        drawShadow: Boolean,
        fallbackShape: ObstacleVisualFallbackShape = ObstacleVisualFallbackShape.RECT
    ) {
        val w = widthCourse * scale
        val h = heightCourse * scale

        val baseRotationDegrees = Math.toDegrees(rotationRadians.toDouble()).toFloat()
        val rotationDegrees = -baseRotationDegrees

        canvas.withRotation(rotationDegrees, cx, cy) {
            val dst = RectF(
                cx - w / 2f,
                cy - h / 2f,
                cx + w / 2f,
                cy + h / 2f
            )

            if (bitmap != null) {
                if (drawShadow) {
                    paint.alpha = 64
                    paint.colorFilter = PorterDuffColorFilter(Color.BLACK, PorterDuff.Mode.SRC_IN)
                    drawBitmap(bitmap, null, dst, paint)
                    paint.colorFilter = null
                    paint.alpha = 255
                } else {
                    paint.alpha = 255
                    paint.colorFilter = null
                    drawBitmap(bitmap, null, dst, paint)
                }
            } else {
                paint.style = Paint.Style.FILL
                paint.color = fallbackColor

                when (fallbackShape) {
                    ObstacleVisualFallbackShape.CIRCLE -> {
                        drawOval(dst, paint)
                    }

                    ObstacleVisualFallbackShape.TRIANGLE -> {
                        val path = Path()
                        path.moveTo(dst.centerX(), dst.top)
                        path.lineTo(dst.right, dst.bottom)
                        path.lineTo(dst.left, dst.bottom)
                        path.close()
                        drawPath(path, paint)
                    }

                    ObstacleVisualFallbackShape.CROSS -> {
                        val arm = min(dst.width(), dst.height()) * 0.26f
                        val hRect = RectF(
                            dst.left,
                            dst.centerY() - arm * 0.5f,
                            dst.right,
                            dst.centerY() + arm * 0.5f
                        )
                        val vRect = RectF(
                            dst.centerX() - arm * 0.5f,
                            dst.top,
                            dst.centerX() + arm * 0.5f,
                            dst.bottom
                        )
                        drawRoundRect(hRect, 2f * scale, 2f * scale, paint)
                        drawRoundRect(vRect, 2f * scale, 2f * scale, paint)
                    }

                    ObstacleVisualFallbackShape.RECT -> {
                        drawRoundRect(dst, 3f * scale, 3f * scale, paint)
                    }
                }
            }
        }
    }

    private fun updateFlagAnimation() {
        val now = SystemClock.elapsedRealtime()

        if (flagAnimLastMs == 0L) {
            flagAnimLastMs = now
            return
        }

        val dt = ((now - flagAnimLastMs).coerceIn(0L, 34L)).toFloat() / 1000f
        flagAnimLastMs = now

        val target = if (flagPulled || ballInHole) 1f else 0f
        val speed = if (target > flagPullProgress) 2.6f else 2.2f
        val delta = speed * dt

        flagPullProgress = if (target > flagPullProgress) {
            (flagPullProgress + delta).coerceAtMost(target)
        } else {
            (flagPullProgress - delta).coerceAtLeast(target)
        }

        if (abs(flagPullProgress - target) > 0.001f) {
            postInvalidateOnAnimation()
        }
    }

    private fun easedFlagProgress(): Float {
        val t = flagPullProgress.coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
    }

    private fun drawHoleCup(canvas: Canvas, g: GolfMap) {
        val p = courseToScreen(g.hole)
        val holeSize = 11f * scale

        if (holeBitmap != null) {
            drawBitmapCentered(canvas, holeBitmap, p.x, p.y, holeSize, holeSize)
        } else {
            paint.style = Paint.Style.FILL
            paint.color = Color.rgb(16, 25, 18)
            canvas.drawCircle(p.x, p.y, holeSize * 0.5f, paint)
        }
    }

    private fun drawHoleFlag(canvas: Canvas, g: GolfMap) {
        updateFlagAnimation()

        val flag = flagBitmap ?: return
        val progress = easedFlagProgress()

        val maxFlagLiftCourse = 24f
        val flagLiftCourse = maxFlagLiftCourse * progress

        val fadeByMovement = flagLiftCourse / maxFlagLiftCourse
        val flagAlpha = ((1f - fadeByMovement) * 255f).toInt().coerceIn(0, 255)

        if (flagAlpha <= 2) return

        val flagCenter = courseToScreen(
            PointF(
                g.hole.x,
                g.hole.y + 18f + flagLiftCourse
            )
        )

        val size = 42f * scale
        val dst = RectF(
            flagCenter.x - size / 2f,
            flagCenter.y - size / 2f,
            flagCenter.x + size / 2f,
            flagCenter.y + size / 2f
        )

        flagPaint.reset()
        flagPaint.isAntiAlias = true
        flagPaint.alpha = flagAlpha

        canvas.drawBitmap(flag, null, dst, flagPaint)
    }

    private fun ballRenderSpecs(g: GolfMap): List<BallRenderSpec> {
        val specs = ArrayList<BallRenderSpec>()

        val primaryBall = runtimeBallCourse ?: g.ballStart1
        val opponentBall = opponentBallCourse

        val primarySunk =
            if (replayBallHoleStateActive) {
                replayPrimaryBallInHole
            } else {
                ballInHole
            }

        val opponentSunk =
            replayBallHoleStateActive && replayOpponentBallInHole

        opponentBall?.let { opponent ->
            specs += BallRenderSpec(
                coursePoint = opponent,
                fallbackColor = Color.rgb(92, 92, 92),
                sunk = opponentSunk,
                tintColor = Color.rgb(92, 92, 92),
                alpha = if (opponentSunk) 210 else 255,
                screenOffsetX = 0f,
                screenOffsetY = 0f
            )
        }

        specs += BallRenderSpec(
            coursePoint = primaryBall,
            fallbackColor = Color.WHITE,
            sunk = primarySunk,
            tintColor = null,
            alpha = if (primarySunk) 210 else 255,
            screenOffsetX = 0f,
            screenOffsetY = 0f
        )

        if (
            opponentBall == null &&
            !primarySunk &&
            (abs(g.ballStart2.x - g.ballStart1.x) > 0.001f ||
                    abs(g.ballStart2.y - g.ballStart1.y) > 0.001f)
        ) {
            specs += BallRenderSpec(
                coursePoint = g.ballStart2,
                fallbackColor = Color.rgb(230, 230, 230),
                sunk = false,
                tintColor = null,
                alpha = 255
            )
        }

        return specs
    }

    private fun drawBallShadows(canvas: Canvas, g: GolfMap) {
        for (spec in ballRenderSpecs(g)) {
            val ballSizeCourse =
                if (spec.sunk) IOS_BALL_SUNK_DRAW_SIZE else IOS_BALL_DRAW_SIZE

            drawBallShadow(
                canvas = canvas,
                coursePoint = spec.coursePoint,
                alpha = spec.alpha,
                sunk = spec.sunk,
                ballSizeScreen = ballSizeCourse * scale,
                screenOffsetX = spec.screenOffsetX,
                screenOffsetY = spec.screenOffsetY
            )
        }
    }

    private fun drawBalls(canvas: Canvas, g: GolfMap) {
        for (spec in ballRenderSpecs(g)) {
            drawBall(
                canvas = canvas,
                coursePoint = spec.coursePoint,
                fallbackColor = spec.fallbackColor,
                sunk = spec.sunk,
                tintColor = spec.tintColor,
                alphaOverride = spec.alpha,
                screenOffsetX = spec.screenOffsetX,
                screenOffsetY = spec.screenOffsetY
            )
        }
    }

    private fun drawBallShadow(
        canvas: Canvas,
        coursePoint: PointF,
        alpha: Int,
        sunk: Boolean,
        ballSizeScreen: Float,
        screenOffsetX: Float = 0f,
        screenOffsetY: Float = 0f
    ) {
        if (sunk) return

        val p = courseToScreen(coursePoint)

        val drawX = p.x + screenOffsetX
        val drawY = p.y + screenOffsetY

        val shadowAlpha = ((BALL_SHADOW_ALPHA.toFloat() * (alpha / 255f)))
            .toInt()
            .coerceIn(0, BALL_SHADOW_ALPHA)

        if (shadowAlpha <= 0) return

        val shadowOffsetY = 1.5f * scale

        paint.alpha = shadowAlpha
        paint.colorFilter = PorterDuffColorFilter(Color.BLACK, PorterDuff.Mode.SRC_IN)

        if (ballBitmap != null) {
            drawBitmapCentered(
                canvas = canvas,
                bitmap = ballBitmap,
                cx = drawX,
                cy = drawY + shadowOffsetY,
                w = ballSizeScreen,
                h = ballSizeScreen
            )
        } else {
            paint.style = Paint.Style.FILL
            paint.color = Color.BLACK

            canvas.drawCircle(
                drawX,
                drawY + shadowOffsetY,
                ballSizeScreen * 0.5f,
                paint
            )
        }

        paint.alpha = 255
        paint.colorFilter = null
    }

    private fun drawBall(
        canvas: Canvas,
        coursePoint: PointF,
        fallbackColor: Int,
        sunk: Boolean = false,
        tintColor: Int? = null,
        alphaOverride: Int? = null,
        screenOffsetX: Float = 0f,
        screenOffsetY: Float = 0f
    ) {
        val p = courseToScreen(coursePoint)

        val drawX = p.x + screenOffsetX
        val drawY = p.y + screenOffsetY

        val ballSizeCourse = if (sunk) IOS_BALL_SUNK_DRAW_SIZE else IOS_BALL_DRAW_SIZE
        val size = ballSizeCourse * scale
        val alpha = alphaOverride ?: if (sunk) 210 else 255

        paint.alpha = alpha
        paint.colorFilter = tintColor?.let {
            PorterDuffColorFilter(it, PorterDuff.Mode.SRC_IN)
        }

        if (ballBitmap != null) {
            drawBitmapCentered(canvas, ballBitmap, drawX, drawY, size, size)
        } else {
            paint.style = Paint.Style.FILL
            paint.color = fallbackColor
            canvas.drawCircle(drawX, drawY, size * 0.5f, paint)

            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 1.5f * scale
            paint.color = if (tintColor != null) {
                Color.rgb(105, 105, 105)
            } else {
                Color.rgb(210, 210, 210)
            }
            canvas.drawCircle(drawX, drawY, size * 0.5f, paint)
        }

        paint.alpha = 255
        paint.colorFilter = null
    }

    private fun drawAimPreview(canvas: Canvas) {
        val radius = 1.8f * scale

        if (opponentAimDotsVisual.isNotEmpty()) {
            paint.style = Paint.Style.FILL
            paint.color = Color.argb(145, 185, 185, 185)
            paint.alpha = 145
            paint.colorFilter = null

            for (dotVisual in opponentAimDotsVisual) {
                val p = visualToScreen(dotVisual)
                canvas.drawCircle(p.x, p.y, radius, paint)
            }
        }

        if (aimDotsVisual.isNotEmpty()) {
            paint.style = Paint.Style.FILL
            paint.color = Color.argb(175, 255, 255, 255)
            paint.alpha = 175
            paint.colorFilter = null

            for (dotVisual in aimDotsVisual) {
                val p = visualToScreen(dotVisual)
                canvas.drawCircle(p.x, p.y, radius, paint)
            }
        }

        paint.alpha = 255
    }

    private fun drawAimReadyRing(canvas: Canvas) {
        val ball = aimReadyBallCourse ?: return

        val now = SystemClock.elapsedRealtime()

        if (aimReadyRingStartMs == 0L) {
            aimReadyRingStartMs = now
        }

        if (aimReadyRingFadeLastMs == 0L) {
            aimReadyRingFadeLastMs = now
        }

        val dt = ((now - aimReadyRingFadeLastMs).coerceIn(0L, 34L)).toFloat() / 1000f
        aimReadyRingFadeLastMs = now

        val fadeSpeed = if (aimReadyRingTargetAlpha > aimReadyRingAlpha) 8.5f else 12.5f
        val delta = fadeSpeed * dt

        aimReadyRingAlpha = if (aimReadyRingTargetAlpha > aimReadyRingAlpha) {
            (aimReadyRingAlpha + delta).coerceAtMost(aimReadyRingTargetAlpha)
        } else {
            (aimReadyRingAlpha - delta).coerceAtLeast(aimReadyRingTargetAlpha)
        }

        if (aimReadyRingAlpha <= 0.001f && aimReadyRingTargetAlpha <= 0f) {
            aimReadyBallCourse = null
            aimReadyRingStartMs = 0L
            aimReadyRingFadeLastMs = 0L
            return
        }

        val phase = ((now - aimReadyRingStartMs) % 1100L).toFloat() / 1100f
        val wave = ((1f - cos((phase * Math.PI * 2.0)).toFloat()) * 0.5f)

        val p = courseToScreen(ball)
        val ballRadius = 5f * scale
        val radius = ballRadius * (3f + wave)

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = (0.9f * scale).coerceAtLeast(1f)
        paint.color = Color.WHITE
        paint.alpha = (128f * aimReadyRingAlpha).toInt().coerceIn(0, 128)
        paint.colorFilter = null

        canvas.drawCircle(p.x, p.y, radius, paint)

        paint.alpha = 255
        paint.style = Paint.Style.FILL

        if (
            aimReadyRingTargetAlpha > 0f ||
            aimReadyRingAlpha > 0.001f
        ) {
            postInvalidateOnAnimation()
        }
    }

    private fun drawDebugLabel(canvas: Canvas, g: GolfMap) {
        paint.style = Paint.Style.FILL
        paint.color = Color.argb(150, 0, 0, 0)

        val r = RectF(12f, height - 78f, width - 12f, height - 18f)
        canvas.drawRoundRect(r, 12f, 12f, paint)

        paint.color = Color.WHITE
        paint.textAlign = Paint.Align.CENTER
        paint.textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            14f,
            resources.displayMetrics
        )

        val source = if (g.complete) {
            "captured parity grid"
        } else {
            "seed-generated visual grid"
        }

        val visualCells = "${g.yCells}x${g.xCells}"

        canvas.drawText(
            "Hole ${g.holeNumber}/${g.holeCount}  visual=$visualCells  seed=${g.seed}  $source",
            width / 2f,
            height - 42f,
            paint
        )
    }

    private fun drawBitmapCentered(canvas: Canvas, bitmap: Bitmap, cx: Float, cy: Float, w: Float, h: Float) {
        val dst = RectF(cx - w / 2f, cy - h / 2f, cx + w / 2f, cy + h / 2f)
        canvas.drawBitmap(bitmap, null, dst, paint)
    }

    private fun loadAssetBitmap(fileName: String): Bitmap? {
        val paths = listOf(
            "golf/$fileName",
            "golf/reference_original/$fileName",
            fileName
        )

        for (path in paths) {
            try {
                context.assets.open(path).use {
                    val bitmap = BitmapFactory.decodeStream(it)
                    if (bitmap != null) {
                        OpenPigeonLog.i(TAG, "Renderer.asset loaded $path ${bitmap.width}x${bitmap.height}")
                    }
                    return bitmap
                }
            } catch (_: Throwable) {
                OpenPigeonLog.w(TAG, "Renderer.asset missing path=$path")
            }
        }

        OpenPigeonLog.w(TAG, "Renderer.asset failed fileName=$fileName")
        return null
    }
}