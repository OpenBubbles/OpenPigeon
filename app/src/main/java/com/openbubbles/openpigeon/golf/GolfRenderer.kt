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
        private const val SHOW_PATH_PREVIEW = false
        private const val SHOW_OBJECT_DEBUG_DOTS = false
        private const val LOG_RENDER_SCREEN_COORDS = true
        private const val IOS_TILE_DRAW_SIZE = 66f
        private const val IOS_BALL_DRAW_SIZE = 10f
        private const val IOS_BALL_SUNK_DRAW_SIZE = 7f
        private const val BALL_SHADOW_ALPHA = 128
        private const val IOS_WALL_PATH_TILE_SIZE = 65f
        private const val IOS_WALL_DRAW_SIZE = 6f
        private const val IOS_SLOPE_WIDTH = 65f
        private const val IOS_SLOPE_HEIGHT = 52f
        private const val IOS_OBSTACLE_BASE_SIZE = 30f
        private const val IOS_SHADOW_COURSE_Y_OFFSET = -2f
        private const val AIM_CAMERA_MAX_ZOOM_MULTIPLIER = 1.62f
        private const val AIM_CAMERA_MIN_ZOOM_MULTIPLIER = 1.06f
        private const val AIM_CAMERA_VERTICAL_MIN_SCREEN_FRACTION = 0.25f
        private const val AIM_CAMERA_VERTICAL_MAX_SCREEN_FRACTION = 0.75f
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
        AIM,
        REPLAY
    }

    private var hasLoggedFirstDraw = false
    private var lastSizeLog = ""

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var showCollisionDebug = DEFAULT_SHOW_COLLISION_DEBUG
    private var showDebugLabel = DEFAULT_SHOW_DEBUG_LABEL

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
        replayCameraBall1Course = null
        replayCameraBall2Course = null
        aimReadyBallCourse = null
        aimReadyRingStartMs = 0L
        aimReadyRingFadeLastMs = 0L
        aimReadyRingAlpha = 0f
        aimReadyRingTargetAlpha = 0f

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
        overviewCameraHeld = false
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

        drawCourseOutlineShadow(canvas, wallPath)

        drawObjectShadows(canvas, g)
        drawObstacleSprites(canvas, g)
        drawCourseOutline(canvas, wallPath)

        if (SHOW_OBJECT_DEBUG_DOTS) {
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

    private fun drawCourseOutlineShadow(canvas: Canvas, coursePath: Path) {
        strokePaint.style = Paint.Style.STROKE
        strokePaint.color = Color.argb(64, 0, 0, 0)
        strokePaint.strokeWidth = IOS_WALL_DRAW_SIZE
        strokePaint.strokeCap = Paint.Cap.SQUARE
        strokePaint.strokeJoin = Paint.Join.MITER

        canvas.withTranslation(offsetX, offsetY) {
            scale(scale, scale)
            translate(0f, -IOS_SHADOW_COURSE_Y_OFFSET)
            drawPath(coursePath, strokePaint)
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

    private data class ObstacleDrawSpec(
        val bitmap: Bitmap?,
        val width: Float,
        val height: Float
    )

    private data class ObstacleCollisionDrawSpec(
        val image: String,
        val width: Float,
        val height: Float,
        val circular: Boolean,
        val cross: Boolean = false
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

            "golf_obstacle_cross" -> ObstacleCollisionDrawSpec(
                image,
                95f,
                95f,
                circular = false,
                cross = true
            )

            else -> ObstacleCollisionDrawSpec(image, 30f, 30f, circular = false)
        }
    }

    private fun drawCollisionDebug(canvas: Canvas, g: GolfMap) {
        if (!showCollisionDebug) return

        val ball = runtimeBallCourse ?: g.ballStart1
        val ballScreen = courseToScreen(ball)

        collisionDebugPaint.color = Color.argb(220, 255, 255, 0)
        collisionDebugPaint.strokeWidth = 2f * scale
        canvas.drawCircle(ballScreen.x, ballScreen.y, 4f * scale, collisionDebugPaint)

        collisionDebugPaint.color = Color.argb(220, 255, 0, 255)

        for (obstacle in g.obstacles) {
            val spec = obstacleCollisionSpecForDebug(obstacle)
            val center = courseToScreen(PointF(obstacle.x, obstacle.y))

            val width = spec.width * obstacle.scale * scale
            val height = spec.height * obstacle.scale * scale

            if (spec.cross) {
                val armThickness = (min(width, height) * 0.17f).coerceIn(
                    12f * scale,
                    18f * scale
                )

                val rawDeg = Math.toDegrees(obstacle.rotation.toDouble()).toFloat()
                val drawDeg = -rawDeg

                canvas.withRotation(drawDeg, center.x, center.y) {
                    val horizontal = RectF(
                        center.x - width / 2f,
                        center.y - armThickness / 2f,
                        center.x + width / 2f,
                        center.y + armThickness / 2f
                    )

                    val vertical = RectF(
                        center.x - armThickness / 2f,
                        center.y - height / 2f,
                        center.x + armThickness / 2f,
                        center.y + height / 2f
                    )

                    drawRect(horizontal, collisionDebugPaint)
                    drawRect(vertical, collisionDebugPaint)
                }
            } else if (spec.circular) {
                val radius = min(width, height) * 0.5f
                canvas.drawCircle(center.x, center.y, radius, collisionDebugPaint)
            } else {
                val rawDeg = Math.toDegrees(obstacle.rotation.toDouble()).toFloat()
                val drawDeg = -rawDeg

                canvas.withRotation(drawDeg, center.x, center.y) {
                    val r = RectF(
                        center.x - width / 2f,
                        center.y - height / 2f,
                        center.x + width / 2f,
                        center.y + height / 2f
                    )

                    drawRect(r, collisionDebugPaint)
                }
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
                drawRoundRect(dst, 3f * scale, 3f * scale, paint)
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

    private fun drawBalls(canvas: Canvas, g: GolfMap) {
        opponentBallCourse?.let { opponent ->
            drawBall(
                canvas = canvas,
                coursePoint = opponent,
                fallbackColor = Color.rgb(92, 92, 92),
                sunk = false,
                tintColor = Color.rgb(92, 92, 92),
                alphaOverride = 255
            )
        }

        val primaryBall = runtimeBallCourse ?: g.ballStart1

        drawBall(
            canvas = canvas,
            coursePoint = primaryBall,
            fallbackColor = Color.WHITE,
            sunk = ballInHole
        )

        if (
            opponentBallCourse == null &&
            !ballInHole &&
            (abs(g.ballStart2.x - g.ballStart1.x) > 0.001f ||
                    abs(g.ballStart2.y - g.ballStart1.y) > 0.001f)
        ) {
            drawBall(
                canvas = canvas,
                coursePoint = g.ballStart2,
                fallbackColor = Color.rgb(230, 230, 230),
                sunk = false
            )
        }
    }

    private fun drawBallShadow(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        alpha: Int,
        sunk: Boolean
    ) {
        if (sunk) return
        val shadowRadius = GolfConstants.BALL_RADIUS * scale

        val shadowAlpha = ((BALL_SHADOW_ALPHA.toFloat() * (alpha / 255f)))
            .toInt()
            .coerceIn(0, BALL_SHADOW_ALPHA)

        if (shadowAlpha <= 0) return

        val shadowOffsetY = 1.4f * scale

        paint.style = Paint.Style.FILL
        paint.color = Color.BLACK
        paint.alpha = shadowAlpha
        paint.colorFilter = null

        canvas.drawCircle(
            cx,
            cy + shadowOffsetY,
            shadowRadius,
            paint
        )

        paint.alpha = 255
    }

    private fun drawBall(
        canvas: Canvas,
        coursePoint: PointF,
        fallbackColor: Int,
        sunk: Boolean = false,
        tintColor: Int? = null,
        alphaOverride: Int? = null
    ) {
        val p = courseToScreen(coursePoint)

        val ballSizeCourse = if (sunk) IOS_BALL_SUNK_DRAW_SIZE else IOS_BALL_DRAW_SIZE
        val size = ballSizeCourse * scale
        val alpha = alphaOverride ?: if (sunk) 210 else 255

        drawBallShadow(
            canvas = canvas,
            cx = p.x,
            cy = p.y,
            alpha = alpha,
            sunk = sunk
        )

        paint.alpha = alpha
        paint.colorFilter = tintColor?.let {
            PorterDuffColorFilter(it, PorterDuff.Mode.SRC_IN)
        }

        if (ballBitmap != null) {
            drawBitmapCentered(canvas, ballBitmap, p.x, p.y, size, size)
        } else {
            paint.style = Paint.Style.FILL
            paint.color = fallbackColor
            canvas.drawCircle(p.x, p.y, size * 0.5f, paint)

            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 1.5f * scale
            paint.color = if (tintColor != null) {
                Color.rgb(105, 105, 105)
            } else {
                Color.rgb(210, 210, 210)
            }
            canvas.drawCircle(p.x, p.y, size * 0.5f, paint)
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