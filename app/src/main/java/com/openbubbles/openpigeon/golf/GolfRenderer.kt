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

/**
 * Canvas renderer for Mini Golf.
 *
 * This version renders the course closer to iOS:
 * - no visible dark blocked tiles
 * - no internal square grid lines
 * - no debug path preview
 * - one continuous filled course body
 * - white exterior outline
 * - diagonal 2x2 corner cuts based on the same kind of geometry seen in iOS fixture probes
 */
class GolfRenderer @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    companion object {
        private const val TAG = "GolfNative"
        private const val SHOW_COLLISION_DEBUG = true

        private const val FLIP_BOARD_Y_ONLY = true

        /*
         * Keep this false for visual parity. Set true only while debugging.
         */
        private const val SHOW_DEBUG_LABEL = false

        /*
         * Keep this false for visual parity. The old line made the Android version
         * visibly different from the iOS board.
         */
        private const val SHOW_PATH_PREVIEW = false

        /*
 * Keep false for screenshots/parity. Turn on only when we want center dots.
 */
        private const val SHOW_OBJECT_DEBUG_DOTS = false

        /*
         * Logs transformed screen positions once on first draw.
         * This is what we need for the next comparison.
         */
        private const val LOG_RENDER_SCREEN_COORDS = true
        private const val IOS_TILE_DRAW_SIZE = 66f
        private const val IOS_WALL_PATH_TILE_SIZE = 65f
        private const val IOS_WALL_DRAW_SIZE = 6f
        private const val IOS_SLOPE_WIDTH = 65f
        private const val IOS_SLOPE_HEIGHT = 52f
        private const val IOS_OBSTACLE_BASE_SIZE = 30f
        private const val IOS_SHADOW_COURSE_Y_OFFSET = -2f
        private const val AIM_CAMERA_MAX_ZOOM_MULTIPLIER = 2.10f
        private const val AIM_CAMERA_MIN_ZOOM_MULTIPLIER = 1.18f
        private const val AIM_CAMERA_VERTICAL_MIN_SCREEN_FRACTION = 0.20f
        private const val AIM_CAMERA_VERTICAL_MAX_SCREEN_FRACTION = 0.78f
        private const val CAMERA_ANIMATION_DAMPING_PER_60FPS_FRAME = 0.72f
        private const val CAMERA_ANIMATION_EPSILON = 0.35f
    }

    private enum class CutCorner {
        TOP_LEFT,
        TOP_RIGHT,
        BOTTOM_LEFT,
        BOTTOM_RIGHT
    }

    private enum class CameraMode {
        FULL_BOARD,
        AIM
    }

    private var hasLoggedFirstDraw = false
    private var lastSizeLog = ""

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

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
    private var aimDotsVisual: List<PointF> = emptyList()

    private var flagPulled = false
    private var ballInHole = false
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
        flagPullProgress = 0f
        flagAnimLastMs = 0L
        cameraTransformReady = false
        snapCameraOnNextDraw = true
        cameraAnimLastMs = 0L

        invalidate()
    }

    fun courseToScreen(point: PointF): PointF {
        val g = map

        val visual = if (g != null && FLIP_BOARD_Y_ONLY) {
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

        return if (g != null && FLIP_BOARD_Y_ONLY) {
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

    /**
     * Converts a course-space point into the same visual coordinate space used by touch aiming.
     * This avoids hardcoding whether the current renderer is Y-flipped or rotated.
     */
    fun courseToVisual(point: PointF): PointF {
        val g = map
        return if (g != null) {
            courseToVisualRaw(g, point)
        } else {
            PointF(point.x, point.y)
        }
    }

    private fun courseToVisualRaw(g: GolfMap, point: PointF): PointF {
        return if (FLIP_BOARD_Y_ONLY) {
            PointF(
                point.x,
                g.mapSize - point.y
            )
        } else {
            PointF(point.x, point.y)
        }
    }

    /**
     * Converts a velocity/delta expressed in visual board units into course-space units.
     * Use this before adding velocity to ballStart/course positions.
     */
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

    fun getPrimaryBallCourse(): PointF? {
        val g = map ?: return null
        return runtimeBallCourse ?: g.ballStart1
    }

    fun setOverviewCameraHeld(held: Boolean) {
        if (overviewCameraHeld == held) return

        overviewCameraHeld = held

        /*
         * This is a toggle target, not a press/hold state.
         * Do not snap. Let applyAnimatedTransform ease between overview and aim camera.
         */
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

    fun clearCameraFocus() {
        cameraMode = CameraMode.FULL_BOARD
        aimCameraBallCourse = null
        aimCameraDist = 0f
        overviewCameraHeld = false
        snapCameraOnNextDraw = true

        invalidate()
    }

    fun isScreenNearPrimaryBall(screenX: Float, screenY: Float): Boolean {
        val ball = getPrimaryBallCourse() ?: return false
        val p = courseToScreen(ball)

        /*
         * iOS GolfBall visual frame is much larger than the physical ball.
         * Use a generous hit radius so dragging feels like iOS.
         */
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

    fun clearAimPreview() {
        if (aimDotsVisual.isNotEmpty()) {
            aimDotsVisual = emptyList()
            invalidate()
        }
    }

    private fun logRendererScreenCoordinates(g: GolfMap) {
        fun visualCoursePoint(point: PointF): PointF {
            return if (FLIP_BOARD_Y_ONLY) {
                PointF(
                    point.x,
                    g.mapSize - point.y
                )
            } else {
                PointF(point.x, point.y)
            }
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

        val g = map
        if (g == null) {
            drawCenteredText(canvas, "Mini Golf", "Waiting for board...")
            return
        }

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

            if (LOG_RENDER_SCREEN_COORDS) {
                logRendererScreenCoordinates(g)
            }
        }

        val fillPath = buildCoursePath(g, IOS_TILE_DRAW_SIZE)
        val wallPath = buildCoursePath(g, IOS_WALL_PATH_TILE_SIZE)

        drawCourseFill(canvas, fillPath)

        if (SHOW_PATH_PREVIEW) {
            drawPathPreview(canvas, g)
        }

        drawSlopes(canvas, g)

        /*
         * iOS has a dark/shadow wall layer behind the real wall layer.
         * Draw this before obstacle sprites.
         */
        drawCourseOutlineShadow(canvas, wallPath)

        drawObjectShadows(canvas, g)
        drawObstacleSprites(canvas, g)

        /*
         * Real white barriers go on top of obstacles.
         */
        drawCourseOutline(canvas, wallPath)

        if (SHOW_OBJECT_DEBUG_DOTS) {
            drawObjectDebugDots(canvas, g)
        }

        drawHoleCup(canvas, g)

        drawAimPreview(canvas)
        drawBalls(canvas, g)

        drawHoleFlag(canvas, g)

        drawCollisionDebug(canvas, g)

        if (SHOW_DEBUG_LABEL) {
            drawDebugLabel(canvas, g)
        }
    }

    private fun drawObjectShadows(canvas: Canvas, g: GolfMap) {
        for (obstacle in g.obstacles) {
            val spec = obstacleSpec(obstacle)
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
                widthCourse = spec.width * obstacle.scale,
                heightCourse = spec.height * obstacle.scale,
                rotationRadians = obstacle.rotation,
                fallbackColor = Color.argb(80, 0, 0, 0),
                drawShadow = true
            )
        }
    }

    private fun drawObstacleSprites(canvas: Canvas, g: GolfMap) {
        for (obstacle in g.obstacles) {
            val spec = obstacleSpec(obstacle)
            val p = courseToScreen(PointF(obstacle.x, obstacle.y))

            drawCourseBitmap(
                canvas = canvas,
                bitmap = spec.bitmap,
                cx = p.x,
                cy = p.y,
                widthCourse = spec.width * obstacle.scale,
                heightCourse = spec.height * obstacle.scale,
                rotationRadians = obstacle.rotation,
                fallbackColor = Color.WHITE,
                drawShadow = false
            )
        }
    }

    private fun drawBackground(canvas: Canvas) {
        /*
         * iOS screenshot background is a warm gray, not the earlier blue-gray.
         */
        canvas.drawColor(Color.rgb(174, 171, 162))
    }

    private data class BoardTransform(
        val scale: Float,
        val offsetX: Float,
        val offsetY: Float
    )

    private fun computeTransform(g: GolfMap) {
        val full = computeFullBoardTransform(g)

        val target = if (overviewCameraHeld || cameraMode == CameraMode.FULL_BOARD) {
            full
        } else {
            computeAimBoardTransform(g, full)
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
            .coerceIn(0.08f, 0.55f)

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

        /*
         * Leave room for the top avatars/header and bottom buttons.
         * This keeps the playable board centered in the usable game area.
         */
        val topUiPad = safeH * 0.06f
        val bottomUiPad = safeH * 0.18f

        val usableTop = topUiPad
        val usableBottom = safeH - bottomUiPad
        val usableHeight = usableBottom - usableTop

        val bounds = renderBounds(g)

        val availableW = safeW * 0.82f
        val availableH = usableHeight * 0.92f

        val fullScale = min(availableW / bounds.width, availableH / bounds.height)

        val fullOffsetX = (safeW - bounds.width * fullScale) * 0.5f - bounds.left * fullScale

        val centeredTop = usableTop + (usableHeight - bounds.height * fullScale) * 0.5f
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

        /*
         * More power means zoom out more.
         * dist=0   -> largest zoom
         * dist=300 -> closest to full-board zoom
         */
        val powerT = (aimCameraDist / GolfShot.AIM_MAX_DIST).coerceIn(0f, 1f)

        val zoomMultiplier =
            AIM_CAMERA_MAX_ZOOM_MULTIPLIER -
                    (AIM_CAMERA_MAX_ZOOM_MULTIPLIER - AIM_CAMERA_MIN_ZOOM_MULTIPLIER) * powerT

        val aimScale = max(full.scale, full.scale * zoomMultiplier)

        /*
         * iOS feel: snap horizontally to the ball.
         */
        val aimOffsetX = safeW * 0.5f - ballVisual.x * aimScale

        /*
         * Do not force vertical centering. Preserve the ball's full-board vertical
         * position where possible, then clamp only enough to avoid losing the board.
         */
        val fullBallScreenY = full.offsetY + ballVisual.y * full.scale

        val preferredBallScreenY = fullBallScreenY.coerceIn(
            safeH * AIM_CAMERA_VERTICAL_MIN_SCREEN_FRACTION,
            safeH * AIM_CAMERA_VERTICAL_MAX_SCREEN_FRACTION
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

    private fun clampAimOffsetY(
        bounds: RenderBounds,
        scaleValue: Float,
        preferredOffsetY: Float
    ): Float {
        val safeH = height.coerceAtLeast(1).toFloat()

        val topLimit = safeH * 0.06f
        val bottomLimit = safeH * 0.82f

        val minOffsetY = bottomLimit - bounds.bottom * scaleValue
        val maxOffsetY = topLimit - bounds.top * scaleValue

        return if (minOffsetY <= maxOffsetY) {
            preferredOffsetY.coerceIn(minOffsetY, maxOffsetY)
        } else {
            /*
             * Board is smaller than the usable vertical area at this zoom.
             */
            (minOffsetY + maxOffsetY) * 0.5f
        }
    }

    private fun visualMapWidth(g: GolfMap): Float {
        // Raw iOS course width = inner columns * TILE_SIZE
        return g.mapSize2
    }

    private fun visualMapHeight(g: GolfMap): Float {
        // Raw iOS course height = outer rows * TILE_SIZE
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
        /*
         * iOS tiles are centered at col*65,row*65 and drawn 66x66.
         * So the visible board extends half a tile outside the logical centers.
         *
         * With FLIP_BOARD_Y_ONLY, visual row centers are:
         *   65, 130, 195, ... mapSize
         */
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

        canvas.save()
        canvas.translate(offsetX, offsetY)
        canvas.scale(scale, scale)
        canvas.drawPath(coursePath, paint)
        canvas.restore()
    }

    private fun drawCourseOutlineShadow(canvas: Canvas, coursePath: Path) {
        strokePaint.style = Paint.Style.STROKE
        strokePaint.color = Color.argb(64, 0, 0, 0)
        strokePaint.strokeWidth = IOS_WALL_DRAW_SIZE
        strokePaint.strokeCap = Paint.Cap.SQUARE
        strokePaint.strokeJoin = Paint.Join.MITER

        canvas.save()
        canvas.translate(offsetX, offsetY)
        canvas.scale(scale, scale)

        /*
         * iOS shadow nodes are course y - 2.
         * With our Y-flip, that becomes visual y + 2.
         */
        canvas.translate(0f, -IOS_SHADOW_COURSE_Y_OFFSET)
        canvas.drawPath(coursePath, strokePaint)

        canvas.restore()
    }

    private fun drawCourseOutline(canvas: Canvas, coursePath: Path) {
        strokePaint.style = Paint.Style.STROKE
        strokePaint.color = Color.rgb(232, 232, 226)
        strokePaint.strokeWidth = IOS_WALL_DRAW_SIZE
        strokePaint.strokeCap = Paint.Cap.SQUARE
        strokePaint.strokeJoin = Paint.Join.MITER

        canvas.save()
        canvas.translate(offsetX, offsetY)
        canvas.scale(scale, scale)
        canvas.drawPath(coursePath, strokePaint)
        canvas.restore()
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

            /*
             * For seed=128780070 map 0, the captured 3 cell is the upper-left
             * diagonal transition in the right-side section after the 90° visual rotation.
             */
            else -> {
                CutCorner.BOTTOM_LEFT
            }
        }
    }

    private fun subtractCornerTriangle(coursePath: Path, rect: RectF, corner: CutCorner) {
        val cut = Path()

        when (corner) {
            CutCorner.TOP_LEFT -> {
                /*
                 * Removes the upper-left half of the square.
                 * Leaves a diagonal from bottom-left to top-right.
                 */
                cut.moveTo(rect.left, rect.top)
                cut.lineTo(rect.right, rect.top)
                cut.lineTo(rect.left, rect.bottom)
                cut.close()
            }

            CutCorner.TOP_RIGHT -> {
                /*
                 * Removes the upper-right half of the square.
                 * Leaves a diagonal from top-left to bottom-right.
                 */
                cut.moveTo(rect.left, rect.top)
                cut.lineTo(rect.right, rect.top)
                cut.lineTo(rect.right, rect.bottom)
                cut.close()
            }

            CutCorner.BOTTOM_LEFT -> {
                /*
                 * Removes the lower-left half of the square.
                 * Leaves a diagonal from top-left to bottom-right.
                 */
                cut.moveTo(rect.left, rect.top)
                cut.lineTo(rect.left, rect.bottom)
                cut.lineTo(rect.right, rect.bottom)
                cut.close()
            }

            CutCorner.BOTTOM_RIGHT -> {
                /*
                 * Removes the lower-right half of the square.
                 * Leaves a diagonal from bottom-left to top-right.
                 */
                cut.moveTo(rect.right, rect.top)
                cut.lineTo(rect.right, rect.bottom)
                cut.lineTo(rect.left, rect.bottom)
                cut.close()
            }
        }

        coursePath.op(cut, Path.Op.DIFFERENCE)
    }

    /**
     * iOS creates diagonal wall fixtures for certain 2x2 patterns. The probe showed
     * diagonal makeFixture geometry on this exact board. This approximates that rule
     * from the visual grid:
     *
     * In a 2x2 block with exactly one blocked cell and three open cells, cut the
     * shared interior corner diagonally.
     */
    private fun applyDiagonalCornerCuts(g: GolfMap, coursePath: Path, tileDrawSize: Float) {
        val rows = visualRows(g)
        val cols = visualCols(g)

        for (row in 0 until rows - 1) {
            for (col in 0 until cols - 1) {
                /*
                 * Value 3 cells have their own exact-style diagonal handling.
                 * Do not apply the generic 2x2 approximation to any 2x2 group
                 * containing a value 3.
                 */
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

                /*
                 * visualCellRect() now uses iOS-style centered tiles.
                 * The shared interior point must be derived from the current centers,
                 * not from old top-left grid math.
                 */
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
        // Screen columns are inner columns.
        return g.yCells
    }

    private fun visualRows(g: GolfMap): Int {
        // Screen rows are outer rows.
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
        val outerRow: Int
        val innerCol: Int

        if (FLIP_BOARD_Y_ONLY) {
            /*
             * Board is flipped vertically only:
             * visual row 0 maps to original bottom row.
             * visual col stays the same.
             */
            outerRow = g.xCells - 1 - visualRow
            innerCol = visualCol
        } else {
            outerRow = visualRow
            innerCol = visualCol
        }

        if (outerRow !in 0 until g.xCells || innerCol !in 0 until g.yCells) {
            return null
        }

        return Cell(outerRow, innerCol)
    }

    private fun visualCellRect(
        visualCol: Int,
        visualRow: Int,
        tileDrawSize: Float = IOS_TILE_DRAW_SIZE
    ): RectF {
        /*
         * Build board geometry in stable visual/course units.
         * Do NOT include offsetX/offsetY/scale here.
         *
         * The canvas transform applies camera scale/offset later.
         * This avoids Path.Op artifacts while zoom changes during aiming.
         */
        val centerVisualX = visualCol * GolfConstants.TILE_SIZE

        val centerVisualY = if (FLIP_BOARD_Y_ONLY) {
            (visualRow + 1) * GolfConstants.TILE_SIZE
        } else {
            visualRow * GolfConstants.TILE_SIZE
        }

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

        /*
         * From the binary:
         * - vertical slope corridors use rotation 0
         * - horizontal slope corridors use rotation pi/2
         */
        return when {
            abs(slope.vx) > 0.001f && abs(slope.vy) <= 0.001f -> (Math.PI / 2.0).toFloat()
            else -> 0f
        }
    }

    private data class ObstacleDrawSpec(
        val bitmap: Bitmap?,
        val width: Float,
        val height: Float
    )

    private data class ObstacleCollisionDrawSpec(
        val image: String,
        val width: Float,
        val height: Float,
        val circular: Boolean
    )

    private fun obstacleCollisionSpecForDebug(obstacle: GolfObstacle): ObstacleCollisionDrawSpec {
        val image = obstacle.image.ifBlank {
            obstacleImageForType(obstacle.type, obstacle.bouncy)
        }

        return when (image) {
            "golf_obstacle_square" -> ObstacleCollisionDrawSpec(image, 30f, 30f, circular = false)
            "golf_obstacle_square2" -> ObstacleCollisionDrawSpec(image, 70f, 70f, circular = false)

            "golf_obstacle_bar" -> ObstacleCollisionDrawSpec(image, 46f, 8f, circular = false)

            "golf_obstacle_bar2",
            "golf_obstacles_bar2" -> ObstacleCollisionDrawSpec(image, 95f, 16f, circular = false)

            "golf_obstacle_round" -> ObstacleCollisionDrawSpec(image, 37f, 37f, circular = true)
            "golf_obstacle_round2" -> ObstacleCollisionDrawSpec(image, 72f, 72f, circular = true)

            "golf_obstacle_triangle" -> ObstacleCollisionDrawSpec(image, 30f, 30f, circular = false)
            "golf_obstacle_triangle2" -> ObstacleCollisionDrawSpec(image, 70f, 70f, circular = false)

            "golf_obstacle_cross" -> ObstacleCollisionDrawSpec(image, 95f, 95f, circular = false)

            else -> ObstacleCollisionDrawSpec(image, 30f, 30f, circular = false)
        }
    }

    private fun drawCollisionDebug(canvas: Canvas, g: GolfMap) {
        if (!SHOW_COLLISION_DEBUG) return

        /*
         * Ball physics circle.
         * Visual ball is 12 course units, so the physics radius should be 6.
         */
        val ball = runtimeBallCourse ?: g.ballStart1
        val ballScreen = courseToScreen(ball)

        collisionDebugPaint.color = Color.argb(220, 255, 255, 0)
        collisionDebugPaint.strokeWidth = 2f * scale
        canvas.drawCircle(ballScreen.x, ballScreen.y, 4f * scale, collisionDebugPaint)

        /*
         * Obstacle physics shapes.
         * These should line up with the visible sprites. If they do not,
         * the collision shape is wrong, not the ball size.
         */
        collisionDebugPaint.color = Color.argb(220, 255, 0, 255)

        for (obstacle in g.obstacles) {
            val spec = obstacleCollisionSpecForDebug(obstacle)
            val center = courseToScreen(PointF(obstacle.x, obstacle.y))

            val width = spec.width * obstacle.scale * scale
            val height = spec.height * obstacle.scale * scale

            if (spec.circular) {
                val radius = kotlin.math.min(width, height) * 0.5f
                canvas.drawCircle(center.x, center.y, radius, collisionDebugPaint)
            } else {
                canvas.save()

                val rawDeg = Math.toDegrees(obstacle.rotation.toDouble()).toFloat()
                val drawDeg = -rawDeg

                canvas.rotate(drawDeg, center.x, center.y)

                val r = RectF(
                    center.x - width / 2f,
                    center.y - height / 2f,
                    center.x + width / 2f,
                    center.y + height / 2f
                )

                canvas.drawRect(r, collisionDebugPaint)
                canvas.restore()
            }
        }
    }

    private fun obstacleSpec(obstacle: GolfObstacle): ObstacleDrawSpec {
        val image = obstacle.image.ifBlank {
            obstacleImageForType(obstacle.type, obstacle.bouncy)
        }

        return when (image) {
            "golf_obstacle_square" -> ObstacleDrawSpec(
                obstacleSquareBitmap,
                IOS_OBSTACLE_BASE_SIZE,
                IOS_OBSTACLE_BASE_SIZE
            )
            "golf_obstacle_square2" -> ObstacleDrawSpec(obstacleSquare2Bitmap, 70f, 70f)

            "golf_obstacle_bar" -> ObstacleDrawSpec(obstacleBarBitmap, 46f, 8f)
            "golf_obstacle_bar2",
            "golf_obstacles_bar2" -> ObstacleDrawSpec(obstacleBar2Bitmap, 95f, 16f)

            "golf_obstacle_round" -> ObstacleDrawSpec(obstacleRoundBitmap, 37f, 37f)
            "golf_obstacle_round2" -> ObstacleDrawSpec(obstacleRound2Bitmap, 72f, 72f)

            "golf_obstacle_triangle" -> ObstacleDrawSpec(
                obstacleTriangleBitmap,
                IOS_OBSTACLE_BASE_SIZE,
                IOS_OBSTACLE_BASE_SIZE
            )
            "golf_obstacle_triangle2" -> ObstacleDrawSpec(obstacleTriangle2Bitmap, 70f, 70f)

            "golf_obstacle_cross" -> ObstacleDrawSpec(obstacleCrossBitmap, 95f, 95f)

            else -> ObstacleDrawSpec(obstacleSquareBitmap, 30f, 30f)
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
        drawShadow: Boolean
    ) {
        val w = widthCourse * scale
        val h = heightCourse * scale

        val baseRotationDegrees = Math.toDegrees(rotationRadians.toDouble()).toFloat()

        /*
         * SpriteKit and Android Canvas rotation have opposite handedness.
         * Board orientation is handled by courseToScreen()/visualToOriginalCell(),
         * so do not add 180 degrees here.
         */
        val rotationDegrees = -baseRotationDegrees

        canvas.save()
        canvas.rotate(rotationDegrees, cx, cy)

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
                canvas.drawBitmap(bitmap, null, dst, paint)
                paint.colorFilter = null
                paint.alpha = 255
            } else {
                paint.alpha = 255
                paint.colorFilter = null
                canvas.drawBitmap(bitmap, null, dst, paint)
            }
        } else {
            paint.style = Paint.Style.FILL
            paint.color = fallbackColor
            canvas.drawRoundRect(dst, 3f * scale, 3f * scale, paint)
        }

        canvas.restore()
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

        /*
         * Slower than before. This controls movement only.
         * Opacity is derived from movement position in drawHole().
         */
        val speed = if (target > flagPullProgress) 2.6f else 2.2f
        val delta = speed * dt

        flagPullProgress = if (target > flagPullProgress) {
            (flagPullProgress + delta).coerceAtMost(target)
        } else {
            (flagPullProgress - delta).coerceAtLeast(target)
        }

        if (kotlin.math.abs(flagPullProgress - target) > 0.001f) {
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

        /*
         * Higher lift. Alpha is based on movement distance.
         */
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

    private fun drawBalls(canvas: Canvas, g: GolfMap) {
        val primaryBall = runtimeBallCourse ?: g.ballStart1

        /*
         * Keep drawing the ball after it enters the cup.
         * The sunk variant is smaller/fainter so the hole remains visible.
         */
        drawBall(
            canvas = canvas,
            coursePoint = primaryBall,
            fallbackColor = Color.WHITE,
            sunk = ballInHole
        )

        /*
         * Avoid drawing a duplicate second ball when both starts are identical.
         * Race/two-ball behavior can be wired separately after parseReplay/update.
         */
        if (
            !ballInHole &&
            (kotlin.math.abs(g.ballStart2.x - g.ballStart1.x) > 0.001f ||
                    kotlin.math.abs(g.ballStart2.y - g.ballStart1.y) > 0.001f)
        ) {
            drawBall(
                canvas = canvas,
                coursePoint = g.ballStart2,
                fallbackColor = Color.rgb(230, 230, 230),
                sunk = false
            )
        }
    }

    private fun drawBall(
        canvas: Canvas,
        coursePoint: PointF,
        fallbackColor: Int,
        sunk: Boolean = false
    ) {
        val p = courseToScreen(coursePoint)

        /*
         * iOS visual ball is 10 x 10. Once inside the cup, draw it smaller and
         * slightly faded so it reads as falling into the hole instead of sitting
         * on top of it.
         */
        val baseSize = if (sunk) 7f else 10f
        val size = baseSize * scale
        val alpha = if (sunk) 210 else 255

        paint.alpha = alpha
        paint.colorFilter = null

        if (ballBitmap != null) {
            drawBitmapCentered(canvas, ballBitmap, p.x, p.y, size, size)
        } else {
            paint.style = Paint.Style.FILL
            paint.color = fallbackColor
            canvas.drawCircle(p.x, p.y, size * 0.5f, paint)

            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 1.5f * scale
            paint.color = Color.rgb(210, 210, 210)
            canvas.drawCircle(p.x, p.y, size * 0.5f, paint)
        }

        paint.alpha = 255
    }

    private fun drawAimPreview(canvas: Canvas) {
        if (aimDotsVisual.isEmpty()) return

        paint.style = Paint.Style.FILL
        paint.color = Color.argb(175, 255, 255, 255)
        paint.alpha = 175
        paint.colorFilter = null

        val radius = 1.8f * scale

        for (dotVisual in aimDotsVisual) {
            val p = visualToScreen(dotVisual)
            canvas.drawCircle(p.x, p.y, radius, paint)
        }

        paint.alpha = 255
    }

    private fun drawDebugLabel(canvas: Canvas, g: GolfMap) {
        paint.style = Paint.Style.FILL
        paint.color = Color.argb(150, 0, 0, 0)

        val r = RectF(12f, height - 78f, width - 12f, height - 18f)
        canvas.drawRoundRect(r, 12f, 12f, paint)

        paint.color = Color.WHITE
        paint.textAlign = Paint.Align.CENTER
        paint.textSize = 14f * resources.displayMetrics.scaledDensity

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

    private fun drawCenteredText(canvas: Canvas, title: String, subtitle: String) {
        paint.textAlign = Paint.Align.CENTER
        paint.style = Paint.Style.FILL
        paint.color = Color.WHITE
        paint.textSize = 34f * resources.displayMetrics.scaledDensity
        canvas.drawText(title, width / 2f, height / 2f - 16f, paint)

        paint.textSize = 17f * resources.displayMetrics.scaledDensity
        canvas.drawText(subtitle, width / 2f, height / 2f + 20f, paint)
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