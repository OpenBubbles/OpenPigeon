package com.openbubbles.openpigeon.shuffle

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.abs
import androidx.core.graphics.withRotation
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

class ShuffleRenderer @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {
    private data class ShufflePuck(
        val x: Float,
        val y: Float,
        val player: Int,
        val bodyAngle: Float,
        val shotAngle: Float,
        val shotDistance: Float,
        val velocityX: Float = 0f,
        val velocityY: Float = 0f
    )

    private data class NativePuckSlot(
        val traceId: Int,
        val byteBuffer: ByteBuffer,
        val floatBuffer: FloatBuffer
    )

    private enum class ShuffleUiMode {
        Aiming,
        Waiting,
        Playing,
        SentWaiting
    }

    private val density = resources.displayMetrics.density

    private var mode: Int = 1
    private var layoutMode: Int = 1
    private var replay: String = DEFAULT_REPLAY
    private var currentPlayer: Int = 1
    private var score1: Int = 0
    private var score2: Int = 0
    private val pucks = mutableListOf<ShufflePuck>()
    private var mapScores: List<Int> = defaultMapScoresForMode(1)

    private var draggingCuePuck = false
    private var draggingArrowHead = false
    private var cuePuckXNorm = 0.0f

    private var hasCueAim = false
    private var cueAimAngleRad = (-90.0).toRadiansFloat()
    private var cueAimDist = 0.0f

    private var nativeTablePtr: Long = 0L
    private var nativeRunning = false
    private val nativeSlots = mutableListOf<NativePuckSlot>()

    var onLaunchReplayReady: ((String) -> Unit)? = null

    private var uiMode = ShuffleUiMode.Aiming
    private var localPlayer = 1
    private var nativeRoundFinished: (() -> Unit)? = null
    private var sentWaitingStartMs = 0L

    private var showReplayArrows = false
    private var replayArrowAlpha = 0f
    private var pendingRoundStartRunnable: Runnable? = null

    private var wallIntroStartMs = 0L
    private var wallIntroActive = false

    private val launchButtonRect = RectF()
    private var launchButtonProgress = 0f
    private var launchButtonPressed = false

    private var puck1Bitmap: Bitmap? = null
    private var puck2Bitmap: Bitmap? = null
    private var puckShadowBitmap: Bitmap? = null
    private var bumperBitmap: Bitmap? = null
    private var bumperShadowBitmap: Bitmap? = null

    private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isDither = true
    }

    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isDither = true
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isDither = true
        textAlign = Paint.Align.CENTER
        typeface = android.graphics.Typeface.DEFAULT_BOLD
    }

    init {
        loadAssets()
        parseReplay(DEFAULT_REPLAY)
    }

    fun setGameData(data: Map<String, String>) {
        mode = data["mode"]?.toIntOrNull()?.coerceIn(1, 3) ?: 1
        currentPlayer = data["player"]?.toIntOrNull()?.coerceIn(1, 2) ?: 1
        replay = data["replay"] ?: DEFAULT_REPLAY

        // iOS uses mode as the board selector.
        // mode 1 = shuffle_board
        // mode 2 = shuffle_board3 + bumper
        // mode 3 = shuffle_board4
        layoutMode = mode

        if (nativeTablePtr != 0L) {
            ShuffleNativePhysics.setShuffleMode(nativeTablePtr, layoutMode)
        }

        val parsedScores = parseMapScores(data["map"])
        val expectedCount = expectedMapCountForMode(layoutMode)

        mapScores = if (parsedScores.size == expectedCount) {
            parsedScores
        } else {
            OpenPigeonLog.w(
                "ShuffleRenderer",
                "Map count mismatch for shuffle layout. dataMode=$mode layoutMode=$layoutMode " +
                        "rawMap=${data["map"]} parsed=${parsedScores.size} expected=$expectedCount; using default"
            )

            defaultMapScoresForMode(layoutMode)
        }

        parseReplay(replay)

        nativeRunning = false
        nativeSlots.clear()
        hasCueAim = false
        launchButtonPressed = false
        launchButtonProgress = 0f

        pendingRoundStartRunnable?.let { removeCallbacks(it) }
        pendingRoundStartRunnable = null

        showReplayArrows = false
        replayArrowAlpha = 0f

        wallIntroActive = false
        wallIntroStartMs = 0L

        OpenPigeonLog.i(
            "ShuffleRenderer",
            "setGameData dataMode=$mode layoutMode=$layoutMode currentPlayer=$currentPlayer " +
                    "mapRaw=${data["map"]} mapCount=${mapScores.size} mapScores=$mapScores " +
                    "pucks=${pucks.size} score=$score1,$score2"
        )

        invalidate()
    }

    private fun Double.toRadiansFloat(): Float {
        return Math.toRadians(this).toFloat()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        updateNativeSimulationFrame()

        val w = width.toFloat()
        val h = height.toFloat()

        drawBackground(canvas, w, h)
        drawTopHud(canvas, w)
        drawBoardAndPucks(canvas, w, h)
        drawBottomHud(canvas, w, h)
        drawStatusOverlay(canvas, w, h)
    }

    fun setLocalPlayer(player: Int) {
        localPlayer = player.coerceIn(1, 2)
    }

    fun showAiming() {
        uiMode = ShuffleUiMode.Aiming
        nativeRoundFinished = null

        pendingRoundStartRunnable?.let { removeCallbacks(it) }
        pendingRoundStartRunnable = null

        showReplayArrows = false
        replayArrowAlpha = 0f

        wallIntroActive = false
        wallIntroStartMs = 0L

        launchButtonPressed = false
        invalidate()
    }

    fun showWaitingForOpponent() {
        uiMode = ShuffleUiMode.Waiting
        hasCueAim = false
        draggingCuePuck = false
        draggingArrowHead = false
        launchButtonPressed = false
        launchButtonProgress = 0f
        launchButtonRect.set(0f, 0f, 0f, 0f)

        wallIntroActive = false
        wallIntroStartMs = 0L

        showReplayArrows = pucks.any { it.shotDistance > SHOT_DISTANCE_EPS }
        replayArrowAlpha = if (showReplayArrows) ARROW_MAX_ALPHA else 0f

        invalidate()
    }

    fun showPlaying() {
        uiMode = ShuffleUiMode.Playing
        hasCueAim = false
        draggingCuePuck = false
        draggingArrowHead = false
        launchButtonPressed = false
        launchButtonProgress = 0f
        launchButtonRect.set(0f, 0f, 0f, 0f)

        showReplayArrows = pucks.any { it.shotDistance > SHOT_DISTANCE_EPS }
        replayArrowAlpha = if (showReplayArrows) ARROW_MAX_ALPHA else 0f

        invalidate()
    }

    fun showSentThenWaiting() {
        uiMode = ShuffleUiMode.SentWaiting
        sentWaitingStartMs = System.currentTimeMillis()

        hasCueAim = false
        draggingCuePuck = false
        draggingArrowHead = false
        launchButtonPressed = false
        launchButtonProgress = 0f
        launchButtonRect.set(0f, 0f, 0f, 0f)

        wallIntroActive = false
        wallIntroStartMs = 0L

        showReplayArrows = pucks.any { it.shotDistance > SHOT_DISTANCE_EPS }
        replayArrowAlpha = if (showReplayArrows) ARROW_MAX_ALPHA else 0f

        invalidate()
    }

    fun isPlayingRound(): Boolean {
        return nativeRunning || uiMode == ShuffleUiMode.Playing
    }

    fun hasShotForPlayer(player: Int): Boolean {
        return pucks.any {
            it.player == player.coerceIn(1, 2) &&
                    it.shotDistance > SHOT_DISTANCE_EPS
        }
    }

    fun hasBothPlayerShots(): Boolean {
        return hasShotForPlayer(1) && hasShotForPlayer(2)
    }

    fun currentZeroShotReplay(): String {
        return buildZeroShotBoardReplay()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (uiMode != ShuffleUiMode.Aiming || nativeRunning) {
            return true
        }
        val boardRect = calculateBoardRect(width.toFloat(), height.toFloat())
        val cueX = cuePuckScreenX(boardRect)
        val cueY = bottomOutOfPlayPuckY(boardRect)

        val puckTouchRadius = iosSize(READY_PUCK_PICK_RADIUS, boardRect)
        val arrowHeadTouchRadius = iosSize(26f, boardRect)

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (launchButtonProgress > 0.85f && launchButtonRect.contains(event.x, event.y)) {
                    launchButtonPressed = true
                    invalidate()
                    return true
                }

                if (hasCueAim) {
                    val arrowHead = arrowHeadScreenPosition(
                        boardRect = boardRect,
                        cueX = cueX,
                        cueY = cueY
                    )

                    val arrowDx = event.x - arrowHead.first
                    val arrowDy = event.y - arrowHead.second

                    if (arrowDx * arrowDx + arrowDy * arrowDy <= arrowHeadTouchRadius * arrowHeadTouchRadius) {
                        draggingArrowHead = true
                        parent?.requestDisallowInterceptTouchEvent(true)

                        updateCueAimFromScreenTouch(
                            touchX = event.x,
                            touchY = event.y,
                            boardRect = boardRect
                        )

                        invalidate()
                        return true
                    }
                }

                val puckDx = event.x - cueX
                val puckDy = event.y - cueY

                if (puckDx * puckDx + puckDy * puckDy <= puckTouchRadius * puckTouchRadius) {
                    draggingCuePuck = true
                    parent?.requestDisallowInterceptTouchEvent(true)

                    updateCueDragFromTouch(
                        touchX = event.x,
                        touchY = event.y,
                        boardRect = boardRect
                    )

                    invalidate()
                    return true
                }
            }

            MotionEvent.ACTION_MOVE -> {
                if (launchButtonPressed) {
                    launchButtonPressed = launchButtonRect.contains(event.x, event.y)
                    invalidate()
                    return true
                }

                if (draggingArrowHead) {
                    updateCueAimFromScreenTouch(
                        touchX = event.x,
                        touchY = event.y,
                        boardRect = boardRect
                    )

                    invalidate()
                    return true
                }

                if (draggingCuePuck) {
                    updateCueDragFromTouch(
                        touchX = event.x,
                        touchY = event.y,
                        boardRect = boardRect
                    )

                    invalidate()
                    return true
                }
            }

            MotionEvent.ACTION_UP -> {
                if (launchButtonPressed) {
                    val wasInside = launchButtonRect.contains(event.x, event.y)
                    launchButtonPressed = false

                    if (wasInside) {
                        onLaunchPressed()
                        performClick()
                    }

                    invalidate()
                    return true
                }

                if (draggingArrowHead) {
                    updateCueAimFromScreenTouch(
                        touchX = event.x,
                        touchY = event.y,
                        boardRect = boardRect
                    )

                    draggingArrowHead = false
                    parent?.requestDisallowInterceptTouchEvent(false)
                    performClick()
                    invalidate()
                    return true
                }

                if (draggingCuePuck) {
                    updateCueDragFromTouch(
                        touchX = event.x,
                        touchY = event.y,
                        boardRect = boardRect
                    )

                    draggingCuePuck = false
                    parent?.requestDisallowInterceptTouchEvent(false)
                    performClick()
                    invalidate()
                    return true
                }
            }

            MotionEvent.ACTION_CANCEL -> {
                launchButtonPressed = false
                draggingCuePuck = false
                draggingArrowHead = false
                parent?.requestDisallowInterceptTouchEvent(false)
                invalidate()
                return true
            }
        }

        return true
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        ensureNativeTable()
    }

    override fun onDetachedFromWindow() {
        destroyNativeTable()
        super.onDetachedFromWindow()
    }

    private fun ensureNativeTable(): Long {
        if (nativeTablePtr == 0L) {
            nativeTablePtr = ShuffleNativePhysics.createShuffleTable()
            ShuffleNativePhysics.setShuffleMode(nativeTablePtr, layoutMode)
        }

        return nativeTablePtr
    }

    private fun destroyNativeTable() {
        if (nativeTablePtr != 0L) {
            ShuffleNativePhysics.destroyShuffleTable(nativeTablePtr)
            nativeTablePtr = 0L
        }

        nativeSlots.clear()
        nativeRunning = false
    }

    private fun drawBackground(
        canvas: Canvas,
        w: Float,
        h: Float
    ) {
        val gradient = LinearGradient(
            0f,
            0f,
            0f,
            h,
            Color.rgb(197, 207, 214),
            Color.rgb(176, 187, 193),
            Shader.TileMode.CLAMP
        )

        fillPaint.shader = gradient
        canvas.drawRect(0f, 0f, w, h, fillPaint)
        fillPaint.shader = null

        // Top rounded card area.
        fillPaint.color = Color.argb(95, 240, 245, 248)
        canvas.drawRoundRect(
            RectF(
                dp(4f),
                dp(6f),
                w - dp(4f),
                h - dp(6f)
            ),
            dp(10f),
            dp(10f),
            fillPaint
        )

        // iOS-style handle.
        fillPaint.color = Color.argb(90, 68, 79, 86)
        canvas.drawRoundRect(
            RectF(
                w * 0.43f,
                dp(9f),
                w * 0.57f,
                dp(13f)
            ),
            dp(2f),
            dp(2f),
            fillPaint
        )
    }

    private fun drawTopHud(
        canvas: Canvas,
        w: Float
    ) {
        val leftAvatarLeft = dp(10f)
        val rightAvatarRight = w - dp(10f)
        val avatarSize = dp(46f)
        val avatarTop = dp(40f)

        val avatarCenterY = avatarTop + avatarSize / 2f
        val leftTextX = leftAvatarLeft + avatarSize + dp(8f)
        val rightTextX = rightAvatarRight - avatarSize - dp(8f)

        textPaint.typeface = android.graphics.Typeface.DEFAULT_BOLD

        // --- Left side: "You" above score ---
        textPaint.textAlign = Paint.Align.LEFT
        textPaint.color = Color.rgb(255, 226, 0)

        textPaint.textSize = dp(12f)
        val youBaseline = avatarCenterY - dp(6f) - (textPaint.descent() + textPaint.ascent()) / 2f
        canvas.drawText(
            "You",
            leftTextX,
            youBaseline,
            textPaint
        )

        textPaint.textSize = dp(14f)
        val myScoreBaseline = avatarCenterY + dp(7f) - (textPaint.descent() + textPaint.ascent()) / 2f
        canvas.drawText(
            "$score1/50",
            leftTextX,
            myScoreBaseline,
            textPaint
        )

        // --- Right side: opponent score aligned with our score row ---
        textPaint.textAlign = Paint.Align.RIGHT
        textPaint.textSize = dp(14f)
        textPaint.color = Color.rgb(74, 79, 83)

        canvas.drawText(
            "$score2/50",
            rightTextX,
            myScoreBaseline,
            textPaint
        )
    }

    private fun drawBoardAndPucks(
        canvas: Canvas,
        w: Float,
        h: Float
    ) {
        val boardRect = calculateBoardRect(w, h)

        drawOpponentReadyPuck(canvas, boardRect)
        drawBoard(canvas, boardRect)

        if (layoutMode == 2) {
            drawMode2Bumper(canvas, boardRect)
        }

        for (puck in pucks) {
            drawReplayPuck(canvas, boardRect, puck)
        }

        drawReplayShotArrows(canvas, boardRect)
        drawIncomingWalls(canvas, boardRect)

        drawCueLineAndPuck(canvas, boardRect, w)
    }

    private fun drawReplayShotArrows(
        canvas: Canvas,
        boardRect: RectF
    ) {
        if (!showReplayArrows || replayArrowAlpha <= 0.001f) {
            return
        }

        for (puck in pucks) {
            if (puck.shotDistance <= SHOT_DISTANCE_EPS) {
                continue
            }

            val originX = puckScreenX(puck.x, boardRect)
            val originY = puckVisualScreenY(puck, boardRect)

            drawCueAimArrow(
                canvas = canvas,
                boardRect = boardRect,
                cueX = originX,
                cueY = originY,
                angle = replayArrowDrawAngle(puck),
                distance = puck.shotDistance,
                alpha = replayArrowAlpha
            )
        }
    }

    private fun puckVisualScreenY(
        puck: ShufflePuck,
        boardRect: RectF
    ): Float {
        return when {
            puck.player == 1 && puck.y <= -200f -> bottomOutOfPlayPuckY(boardRect)
            puck.player == 2 && puck.y >= 200f -> topOutOfPlayPuckY(boardRect)
            else -> puckScreenY(puck.y, boardRect)
        }
    }

    private fun replayArrowDrawAngle(puck: ShufflePuck): Float {
        val normalScreenAngle = -puck.shotAngle

        // Native movement already uses the correct unflipped iOS game-space angle.
        // When localPlayer == 2, the board is visually flipped, so only the
        // screen-space arrow preview needs to rotate 180 degrees.
        return if (localPlayer == 2) {
            normalScreenAngle + Math.PI.toFloat()
        } else {
            normalScreenAngle
        }
    }

    private fun drawIncomingWalls(
        canvas: Canvas,
        boardRect: RectF
    ) {
        if (!wallIntroActive && !nativeRunning) {
            return
        }

        val now = System.currentTimeMillis()

        if (wallIntroStartMs == 0L || now < wallIntroStartMs) {
            if (wallIntroActive || nativeRunning) {
                postInvalidateOnAnimation()
            }

            return
        }

        val elapsed = now - wallIntroStartMs

        val t = (elapsed / WALL_INTRO_DURATION_MS.toFloat())
            .coerceIn(0f, 1f)

        val eased = 1f - ((1f - t) * (1f - t))
        val scale = WALL_INTRO_START_SCALE + (1f - WALL_INTRO_START_SCALE) * eased

        val cx = boardRect.centerX()
        val cy = boardRect.centerY()

        val innerBase = RectF(
            boardRect.left,
            boardRect.top,
            boardRect.right,
            boardRect.bottom
        )

        val scaledInner = scaleRectAboutCenter(
            rect = innerBase,
            cx = cx,
            cy = cy,
            scale = scale
        )

        val thickness = iosSize(WALL_INTRO_THICKNESS, boardRect)

        val outer = RectF(
            scaledInner.left - thickness,
            scaledInner.top - thickness,
            scaledInner.right + thickness,
            scaledInner.bottom + thickness
        )

        val path = Path().apply {
            fillType = Path.FillType.EVEN_ODD

            addRoundRect(
                outer,
                iosSize(6f, boardRect),
                iosSize(6f, boardRect),
                Path.Direction.CW
            )

            addRoundRect(
                scaledInner,
                iosSize(2f, boardRect),
                iosSize(2f, boardRect),
                Path.Direction.CCW
            )
        }

        fillPaint.style = Paint.Style.FILL
        fillPaint.color = Color.rgb(238, 242, 245)
        canvas.drawPath(path, fillPaint)

        linePaint.style = Paint.Style.STROKE
        linePaint.strokeWidth = iosSize(1.4f, boardRect)
        linePaint.color = Color.WHITE

        canvas.drawRoundRect(
            scaledInner,
            iosSize(2f, boardRect),
            iosSize(2f, boardRect),
            linePaint
        )

        if (t < 1f) {
            postInvalidateOnAnimation()
        }
    }

    private fun scaleRectAboutCenter(
        rect: RectF,
        cx: Float,
        cy: Float,
        scale: Float
    ): RectF {
        val halfW = rect.width() * 0.5f * scale
        val halfH = rect.height() * 0.5f * scale

        return RectF(
            cx - halfW,
            cy - halfH,
            cx + halfW,
            cy + halfH
        )
    }

    private fun drawMode2Bumper(
        canvas: Canvas,
        boardRect: RectF
    ) {
        val cx = boardRect.centerX()
        val cy = boardRect.centerY()

        val bumperSize = iosSize(53f, boardRect)
        val shadowSize = iosSize(56f, boardRect)

        val shadowRect = RectF(
            cx - shadowSize / 2f,
            cy - shadowSize / 2f + iosSize(1.5f, boardRect),
            cx + shadowSize / 2f,
            cy + shadowSize / 2f + iosSize(1.5f, boardRect)
        )

        val bumperRect = RectF(
            cx - bumperSize / 2f,
            cy - bumperSize / 2f,
            cx + bumperSize / 2f,
            cy + bumperSize / 2f
        )

        val shadow = bumperShadowBitmap
        val bumper = bumperBitmap

        if (shadow != null) {
            canvas.drawBitmap(shadow, null, shadowRect, imagePaint)
        } else {
            fillPaint.style = Paint.Style.FILL
            fillPaint.color = Color.argb(65, 0, 0, 0)
            canvas.drawCircle(cx, cy + iosSize(1.5f, boardRect), shadowSize / 2f, fillPaint)
        }

        if (bumper != null) {
            canvas.drawBitmap(bumper, null, bumperRect, imagePaint)
        } else {
            fillPaint.style = Paint.Style.FILL
            fillPaint.color = Color.rgb(215, 215, 215)
            canvas.drawCircle(cx, cy, bumperSize / 2f, fillPaint)
        }
    }

    private fun drawOpponentReadyPuck(
        canvas: Canvas,
        boardRect: RectF
    ) {
        val topPuck = pucks.lastOrNull { it.player == 2 && it.y >= 200f }

        val x = if (topPuck != null) {
            puckScreenX(topPuck.x, boardRect)
        } else {
            boardRect.centerX()
        }

        val y = if (topPuck != null && topPuck.y < 205f) {
            puckScreenY(topPuck.y, boardRect)
        } else {
            topOutOfPlayPuckY(boardRect)
        }

        drawPuck(
            canvas = canvas,
            cx = x,
            cy = y,
            player = 2,
            rotation = topPuck?.bodyAngle ?: 0f,
            size = puckSize(boardRect)
        )
    }

    private fun drawCueLineAndPuck(
        canvas: Canvas,
        boardRect: RectF,
        w: Float
    ) {
        val cueY = bottomOutOfPlayPuckY(boardRect)

        linePaint.style = Paint.Style.STROKE
        linePaint.strokeWidth = dp(1.2f)
        linePaint.color = Color.argb(170, 255, 232, 72)

        canvas.drawLine(
            dp(14f),
            cueY,
            w - dp(14f),
            cueY,
            linePaint
        )

        val bottomPuck = pucks.lastOrNull { it.player == 1 && it.y <= -200f }

        val cueX = if (draggingCuePuck || draggingArrowHead || hasCueAim) {
            cuePuckScreenX(boardRect)
        } else if (bottomPuck != null) {
            puckScreenX(bottomPuck.x, boardRect)
        } else {
            cuePuckScreenX(boardRect)
        }

        if (!draggingCuePuck && !draggingArrowHead && !hasCueAim && bottomPuck != null) {
            cuePuckXNorm = (bottomPuck.x / READY_PUCK_X_LIMIT)
                .coerceIn(-1f, 1f)
        }

        if (uiMode == ShuffleUiMode.Aiming && hasCueAim) {
            drawCueAimArrow(
                canvas = canvas,
                boardRect = boardRect,
                cueX = cueX,
                cueY = cueY,
                angle = cueAimAngleRad,
                distance = cueAimDist,
                alpha = ARROW_MAX_ALPHA
            )
        }

        drawPuck(
            canvas = canvas,
            cx = cueX,
            cy = cueY,
            player = 1,
            rotation = bottomPuck?.bodyAngle ?: 0f,
            size = puckSize(boardRect)
        )
    }

    private fun updateCueAimFromScreenTouch(
        touchX: Float,
        touchY: Float,
        boardRect: RectF
    ) {
        val gameX = screenToGameX(touchX, boardRect)
            .coerceIn(-TABLE_AIM_X_LIMIT, TABLE_AIM_X_LIMIT)

        val minGameY = READY_PUCK_PLAYER1_Y + MIN_AIM_DISTANCE

        val gameY = screenToGameY(touchY, boardRect)
            .coerceIn(minGameY, TABLE_AIM_Y_LIMIT)

        updateCueAimFromGameTouch(
            touchGameX = gameX,
            touchGameY = gameY
        )
    }

    private fun drawCueAimArrow(
        canvas: Canvas,
        boardRect: RectF,
        cueX: Float,
        cueY: Float,
        angle: Float = cueAimAngleRad,
        distance: Float = cueAimDist,
        alpha: Float = ARROW_MAX_ALPHA
    ) {
        if (distance <= MIN_AIM_DISTANCE) {
            return
        }

        val visualAlpha = (255f * alpha).toInt().coerceIn(0, 255)
        val shadowAlpha = (80f * alpha).toInt().coerceIn(0, 255)

        val length = iosSize(
            distance.coerceIn(MIN_AIM_VISUAL_LENGTH, MAX_AIM_DISTANCE),
            boardRect
        )

        val startOffset = puckSize(boardRect) * 0.68f
        val headLength = iosSize(24f, boardRect)
        val headWidth = iosSize(20f, boardRect)

        val cosA = cos(angle)
        val sinA = sin(angle)

        val startX = cueX + cosA * startOffset
        val startY = cueY + sinA * startOffset

        val tipX = cueX + cosA * length
        val tipY = cueY + sinA * length

        val shaftEndX = tipX - cosA * headLength * 0.78f
        val shaftEndY = tipY - sinA * headLength * 0.78f

        val normalX = -sinA
        val normalY = cosA

        linePaint.style = Paint.Style.STROKE
        linePaint.strokeCap = Paint.Cap.ROUND
        linePaint.strokeWidth = iosSize(8.5f, boardRect)
        linePaint.color = Color.argb(shadowAlpha, 0, 0, 0)

        canvas.drawLine(
            startX + iosSize(1.5f, boardRect),
            startY + iosSize(1.5f, boardRect),
            shaftEndX + iosSize(1.5f, boardRect),
            shaftEndY + iosSize(1.5f, boardRect),
            linePaint
        )

        linePaint.strokeWidth = iosSize(5.6f, boardRect)
        linePaint.color = Color.argb(visualAlpha, 255, 220, 0)

        canvas.drawLine(
            startX,
            startY,
            shaftEndX,
            shaftEndY,
            linePaint
        )

        val headBackX = tipX - cosA * headLength
        val headBackY = tipY - sinA * headLength

        val shadowOffset = iosSize(1.5f, boardRect)

        val headPathShadow = Path().apply {
            moveTo(tipX + shadowOffset, tipY + shadowOffset)
            lineTo(
                headBackX + normalX * (headWidth * 0.5f) + shadowOffset,
                headBackY + normalY * (headWidth * 0.5f) + shadowOffset
            )
            lineTo(
                headBackX - normalX * (headWidth * 0.5f) + shadowOffset,
                headBackY - normalY * (headWidth * 0.5f) + shadowOffset
            )
            close()
        }

        fillPaint.style = Paint.Style.FILL
        fillPaint.color = Color.argb(shadowAlpha, 0, 0, 0)
        canvas.drawPath(headPathShadow, fillPaint)

        val headPath = Path().apply {
            moveTo(tipX, tipY)
            lineTo(
                headBackX + normalX * (headWidth * 0.5f),
                headBackY + normalY * (headWidth * 0.5f)
            )
            lineTo(
                headBackX - normalX * (headWidth * 0.5f),
                headBackY - normalY * (headWidth * 0.5f)
            )
            close()
        }

        fillPaint.color = Color.argb(visualAlpha, 255, 220, 0)
        canvas.drawPath(headPath, fillPaint)
    }

    private fun drawBoard(
        canvas: Canvas,
        rect: RectF
    ) {
        // Shadow.
        fillPaint.style = Paint.Style.FILL
        fillPaint.color = Color.argb(70, 0, 0, 0)

        canvas.drawRoundRect(
            RectF(
                rect.left + dp(2f),
                rect.top + dp(3f),
                rect.right + dp(2f),
                rect.bottom + dp(3f)
            ),
            dp(3f),
            dp(3f),
            fillPaint
        )

        drawGeneratedShuffleBoard(
            canvas = canvas,
            rect = rect,
            mode = layoutMode,
            scores = mapScores
        )
    }

    private data class ShuffleSegmentSpec(
        val points: List<Pair<Float, Float>>
    )

    private fun seg(
        vararg points: Pair<Float, Float>
    ): ShuffleSegmentSpec {
        return ShuffleSegmentSpec(points.toList())
    }

    private fun drawGeneratedShuffleBoard(
        canvas: Canvas,
        rect: RectF,
        mode: Int,
        scores: List<Int>
    ) {
        val segments = shuffleSegmentSpecs(mode)
        val defaults = defaultMapScoresForMode(mode)

        fillPaint.style = Paint.Style.FILL
        fillPaint.color = baseBoardColor(mode)

        canvas.drawRoundRect(
            rect,
            dp(2f),
            dp(2f),
            fillPaint
        )

        for (i in segments.indices) {
            val score = scores.getOrNull(i) ?: defaults.getOrNull(i) ?: 0

            fillPaint.style = Paint.Style.FILL
            val segmentColor = segmentFillColor(
                mode = mode,
                score = score
            )

            fillPaint.color = segmentColor

            drawShuffleSegmentPolygon(
                canvas = canvas,
                boardRect = rect,
                points = segments[i].points,
                paint = fillPaint
            )
        }

        linePaint.style = Paint.Style.STROKE
        linePaint.strokeWidth = dp(1.25f)
        linePaint.color = Color.argb(235, 255, 255, 255)

        for (segment in segments) {
            drawShuffleSegmentPolygonStroke(
                canvas = canvas,
                boardRect = rect,
                points = segment.points,
                paint = linePaint
            )
        }

        linePaint.style = Paint.Style.STROKE
        linePaint.strokeWidth = dp(2.0f)
        linePaint.color = Color.WHITE
        canvas.drawRect(rect, linePaint)

        drawGeneratedBoardLabels(
            canvas = canvas,
            rect = rect,
            mode = mode,
            scores = scores
        )
    }

    private fun shuffleSegmentSpecs(mode: Int): List<ShuffleSegmentSpec> {
        return when (mode) {
            1 -> shuffleMode1SegmentSpecs()
            2 -> shuffleMode2SegmentSpecs()
            3 -> shuffleMode3SegmentSpecs()
            else -> shuffleMode1SegmentSpecs()
        }
    }

    private fun shuffleMode1SegmentSpecs(): List<ShuffleSegmentSpec> {
        return listOf(
            // iOS mode 1: shuffle_board, 12 segments

            // 0 shuffle_s3
            seg(-125f to 135f, -125f to -135f, -178f to -193f, -178f to 193f),

            // 1 shuffle_s2
            seg(-70f to -76f, -70f to 76f, -125f to 135f, -125f to -135f),

            // 2 shuffle_s1
            seg(-70f to -76f, 0f to 0f, -70f to 76f),

            // 3 shuffle_s1
            seg(70f to -76f, 0f to 0f, 70f to 76f),

            // 4 shuffle_s2
            seg(70f to -76f, 70f to 76f, 125f to 135f, 125f to -135f),

            // 5 shuffle_s3
            seg(125f to 135f, 125f to -135f, 178f to -193f, 178f to 193f),

            // 6 shuffle_s6
            seg(125f to 135f, -125f to 135f, -178f to 193f, 178f to 193f),

            // 7 shuffle_s5
            seg(-70f to 76f, 70f to 76f, 125f to 135f, -125f to 135f),

            // 8 shuffle_s4
            seg(-70f to 76f, 0f to 0f, 70f to 76f),

            // 9 shuffle_s4
            seg(-70f to -76f, 0f to 0f, 70f to -76f),

            // 10 shuffle_s5
            seg(-70f to -76f, 70f to -76f, 125f to -135f, -125f to -135f),

            // 11 shuffle_s6
            seg(125f to -135f, -125f to -135f, -178f to -193f, 178f to -193f)
        )
    }

    private fun shuffleMode2SegmentSpecs(): List<ShuffleSegmentSpec> {
        return listOf(
            // iOS mode 2: shuffle_board3, 16 segments

            // 0 shuffle_b1
            seg(0f to 0f, -64.5f to 69.5f, -129f to 0f, -64.5f to -69.5f),

            // 1 shuffle_b1
            seg(0f to 0f, -64.5f to 69.5f, 0f to 139f, 64.5f to 69.5f),

            // 2 shuffle_b1
            seg(0f to 0f, 64.5f to 69.5f, 129f to 0f, 64.5f to -69.5f),

            // 3 shuffle_b1
            seg(0f to 0f, 64.5f to -69.5f, 0f to -139f, -64.5f to -69.5f),

            // 4 shuffle_b2
            seg(-129f to 0f, -178f to 0f, -178f to 68f, -120f to 131f, -64.5f to 69.5f),

            // 5 shuffle_b3
            seg(-120f to 131f, -64.5f to 69.5f, 0f to 139f, 0f to 193f, -63f to 193f),

            // 6 shuffle_b2
            seg(129f to 0f, 178f to 0f, 178f to 68f, 120f to 131f, 64.5f to 69.5f),

            // 7 shuffle_b3
            seg(120f to 131f, 64.5f to 69.5f, 0f to 139f, 0f to 193f, 63f to 193f),

            // 8 shuffle_b2
            seg(129f to 0f, 178f to 0f, 178f to -68f, 120f to -131f, 64.5f to -69.5f),

            // 9 shuffle_b3
            seg(120f to -131f, 64.5f to -69.5f, 0f to -139f, 0f to -193f, 63f to -193f),

            // 10 shuffle_b2
            seg(-129f to 0f, -178f to 0f, -178f to -68f, -120f to -131f, -64.5f to -69.5f),

            // 11 shuffle_b3
            seg(-120f to -131f, -64.5f to -69.5f, 0f to -139f, 0f to -193f, -63f to -193f),

            // 12 shuffle_b4
            seg(-178f to 68f, -178f to 193f, -63f to 193f),

            // 13 shuffle_b4
            seg(178f to 68f, 178f to 193f, 63f to 193f),

            // 14 shuffle_b4
            seg(178f to -68f, 178f to -193f, 63f to -193f),

            // 15 shuffle_b4
            seg(-178f to -68f, -178f to -193f, -63f to -193f)
        )
    }

    private fun shuffleMode3SegmentSpecs(): List<ShuffleSegmentSpec> {
        return listOf(
            // iOS mode 3: shuffle_board4, 21 segments

            // 0 shuffle_c1
            seg(-35.5f to -38.5f, -35.5f to 38.5f, 35.5f to 38.5f, 35.5f to -38.5f),

            // 1 shuffle_c1
            seg(-106.5f to -38.5f, -106.5f to 38.5f, -35.5f to 38.5f, -35.5f to -38.5f),

            // 2 shuffle_c1
            seg(-106.5f to 38.5f, -106.5f to 115.5f, -35.5f to 115.5f, -35.5f to 38.5f),

            // 3 shuffle_c1
            seg(-35.5f to 38.5f, -35.5f to 115.5f, 35.5f to 115.5f, 35.5f to 38.5f),

            // 4 shuffle_c1
            seg(35.5f to 38.5f, 35.5f to 115.5f, 106.5f to 115.5f, 106.5f to 38.5f),

            // 5 shuffle_c1
            seg(35.5f to -38.5f, 35.5f to 38.5f, 106.5f to 38.5f, 106.5f to -38.5f),

            // 6 shuffle_c1
            seg(35.5f to -115.5f, 35.5f to -38.5f, 106.5f to -38.5f, 106.5f to -115.5f),

            // 7 shuffle_c1
            seg(-35.5f to -115.5f, -35.5f to -38.5f, 35.5f to -38.5f, 35.5f to -115.5f),

            // 8 shuffle_c1
            seg(-106.5f to -115.5f, -106.5f to -38.5f, -35.5f to -38.5f, -35.5f to -115.5f),

            // 9 shuffle_c1
            seg(-177.5f to -115.5f, -177.5f to -38.5f, -106.5f to -38.5f, -106.5f to -115.5f),

            // 10 shuffle_c1
            seg(-177.5f to -38.5f, -177.5f to 38.5f, -106.5f to 38.5f, -106.5f to -38.5f),

            // 11 shuffle_c1
            seg(-177.5f to 38.5f, -177.5f to 115.5f, -106.5f to 115.5f, -106.5f to 38.5f),

            // 12 shuffle_c1
            seg(106.5f to -115.5f, 106.5f to -38.5f, 177.5f to -38.5f, 177.5f to -115.5f),

            // 13 shuffle_c1
            seg(106.5f to -38.5f, 106.5f to 38.5f, 177.5f to 38.5f, 177.5f to -38.5f),

            // 14 shuffle_c1
            seg(106.5f to 38.5f, 106.5f to 115.5f, 177.5f to 115.5f, 177.5f to 38.5f),

            // 15 shuffle_c1
            seg(-35.5f to -192.5f, -35.5f to -115.5f, 35.5f to -115.5f, 35.5f to -192.5f),

            // 16 shuffle_c1
            seg(-35.5f to 115.5f, -35.5f to 192.5f, 35.5f to 192.5f, 35.5f to 115.5f),

            // 17 shuffle_c2
            seg(-177.5f to -192.5f, -177.5f to -115.5f, -35.5f to -115.5f, -35.5f to -192.5f),

            // 18 shuffle_c2
            seg(-177.5f to 115.5f, -177.5f to 192.5f, -35.5f to 192.5f, -35.5f to 115.5f),

            // 19 shuffle_c2
            seg(35.5f to -192.5f, 35.5f to -115.5f, 177.5f to -115.5f, 177.5f to -192.5f),

            // 20 shuffle_c2
            seg(35.5f to 115.5f, 35.5f to 192.5f, 177.5f to 192.5f, 177.5f to 115.5f)
        )
    }

    private fun drawShuffleSegmentPolygon(
        canvas: Canvas,
        boardRect: RectF,
        points: List<Pair<Float, Float>>,
        paint: Paint
    ) {
        if (points.isEmpty()) return

        val path = Path()

        points.forEachIndexed { index, point ->
            val sx = shuffleBoardX(point.first, boardRect)
            val sy = shuffleBoardY(point.second, boardRect)

            if (index == 0) {
                path.moveTo(sx, sy)
            } else {
                path.lineTo(sx, sy)
            }
        }

        path.close()
        canvas.drawPath(path, paint)
    }

    private fun drawShuffleSegmentPolygonStroke(
        canvas: Canvas,
        boardRect: RectF,
        points: List<Pair<Float, Float>>,
        paint: Paint
    ) {
        if (points.isEmpty()) return

        val path = Path()

        points.forEachIndexed { index, point ->
            val sx = shuffleBoardX(point.first, boardRect)
            val sy = shuffleBoardY(point.second, boardRect)

            if (index == 0) {
                path.moveTo(sx, sy)
            } else {
                path.lineTo(sx, sy)
            }
        }

        path.close()
        canvas.drawPath(path, paint)
    }

    private fun drawGeneratedBoardLabels(
        canvas: Canvas,
        rect: RectF,
        mode: Int,
        scores: List<Int>
    ) {
        val segments = shuffleSegmentSpecs(mode)
        val defaults = defaultMapScoresForMode(mode)

        textPaint.textAlign = Paint.Align.CENTER
        textPaint.typeface = android.graphics.Typeface.DEFAULT_BOLD
        textPaint.textSize = when (mode) {
            1 -> dp(12.5f)
            2 -> dp(11.5f)
            3 -> dp(10.5f)
            else -> dp(12.5f)
        }
        textPaint.color = Color.WHITE

        for (i in segments.indices) {
            val score = scores.getOrNull(i) ?: defaults.getOrNull(i) ?: 0
            val center = segmentCentroid(segments[i].points, rect)

            canvas.drawText(
                score.toString(),
                center.first,
                center.second - (textPaint.descent() + textPaint.ascent()) / 2f,
                textPaint
            )
        }
    }

    private fun segmentCentroid(
        points: List<Pair<Float, Float>>,
        rect: RectF
    ): Pair<Float, Float> {
        if (points.isEmpty()) {
            return rect.centerX() to rect.centerY()
        }

        var x = 0f
        var y = 0f

        for (point in points) {
            x += shuffleBoardX(point.first, rect)
            y += shuffleBoardY(point.second, rect)
        }

        return (x / points.size.toFloat()) to (y / points.size.toFloat())
    }

    private fun iosSceneScale(boardRect: RectF): Float {
        return boardRect.width() / IOS_BOARD_WIDTH
    }

    private fun shuffleBoardX(
        gameX: Float,
        boardRect: RectF
    ): Float {
        return boardRect.centerX() + gameX * iosSceneScale(boardRect)
    }

    private fun shuffleBoardY(
        gameY: Float,
        boardRect: RectF
    ): Float {
        return boardRect.centerY() - gameY * iosSceneScale(boardRect)
    }

    private fun baseBoardColor(mode: Int): Int {
        return when (mode) {
            // Mode 1: normal blue board.
            1 -> Color.rgb(68, 139, 196)

            // Mode 2: purple/green board.
            2 -> Color.rgb(126, 118, 199)

            // Mode 3: green/red board.
            3 -> Color.rgb(65, 178, 102)

            else -> Color.rgb(68, 139, 196)
        }
    }

    private fun segmentFillColor(
        mode: Int,
        score: Int
    ): Int {
        return when (mode) {
            1 -> {
                // Mode 1: blue with green 10 cells.
                if (score == 10) {
                    Color.rgb(56, 196, 97)
                } else {
                    Color.rgb(68, 139, 196)
                }
            }

            2 -> {
                // Mode 2: purple with green high cells.
                // No red in this mode.
                if (score == 10) {
                    Color.rgb(56, 196, 97)
                } else {
                    Color.rgb(126, 118, 199)
                }
            }

            3 -> {
                // Mode 3: green with red high/danger cells.
                // No purple in this mode.
                if (score == 10) {
                    Color.rgb(195, 72, 76)
                } else {
                    Color.rgb(65, 178, 102)
                }
            }

            else -> Color.rgb(68, 139, 196)
        }
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    private fun parseMapScores(mapValue: String?): List<Int> {
        val cleaned = mapValue
            ?.trim()
            ?.removePrefix("[")
            ?.removeSuffix("]")
            ?.replace(" ", "")
            .orEmpty()

        if (cleaned.isBlank()) {
            return emptyList()
        }

        return cleaned
            .split(",")
            .mapNotNull { it.trim().toIntOrNull() }
    }

    private fun expectedMapCountForMode(mode: Int): Int {
        return when (mode) {
            1 -> 12
            2 -> 16
            3 -> 21
            else -> 12
        }
    }

    private fun defaultMapScoresForMode(mode: Int): List<Int> {
        return when (mode) {
            1 -> DEFAULT_MAP_SCORES_MODE_1
            2 -> DEFAULT_MAP_SCORES_MODE_2
            3 -> DEFAULT_MAP_SCORES_MODE_3
            else -> DEFAULT_MAP_SCORES_MODE_1
        }
    }

    private fun drawReplayPuck(
        canvas: Canvas,
        boardRect: RectF,
        puck: ShufflePuck
    ) {
        // The top and bottom ready pucks are drawn separately, so avoid double-drawing them.
        if (puck.player == 1 && puck.y <= -205f) return
        if (puck.player == 2 && puck.y >= 205f) return

        drawPuck(
            canvas = canvas,
            cx = puckScreenX(puck.x, boardRect),
            cy = puckScreenY(puck.y, boardRect),
            player = puck.player,
            rotation = puck.bodyAngle,
            size = puckSize(boardRect)
        )
    }

    private fun drawPuck(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        player: Int,
        rotation: Float,
        size: Float
    ) {
        val shadowSize = size * 1.25f
        val shadow = puckShadowBitmap

        val shadowRect = RectF(
            cx - shadowSize / 2f,
            cy - shadowSize / 2f + dp(2f),
            cx + shadowSize / 2f,
            cy + shadowSize / 2f + dp(2f)
        )

        if (shadow != null) {
            canvas.drawBitmap(shadow, null, shadowRect, imagePaint)
        } else {
            fillPaint.style = Paint.Style.FILL
            fillPaint.color = Color.argb(65, 0, 0, 0)
            canvas.drawCircle(cx + dp(1f), cy + dp(2f), shadowSize / 2f, fillPaint)
        }

        val bitmap = if (player == 1) {
            puck1Bitmap
        } else {
            puck2Bitmap
        }

        val rect = RectF(
            cx - size / 2f,
            cy - size / 2f,
            cx + size / 2f,
            cy + size / 2f
        )

        if (bitmap != null) {
            canvas.withRotation(
                degrees = Math.toDegrees(rotation.toDouble()).toFloat(),
                pivotX = cx,
                pivotY = cy
            ) {
                drawBitmap(bitmap, null, rect, imagePaint)
            }
        } else {
            fillPaint.color = if (player == 1) {
                Color.rgb(255, 215, 0)
            } else {
                Color.rgb(35, 35, 35)
            }
            canvas.drawCircle(cx, cy, size / 2f, fillPaint)
        }
    }

    private fun drawBottomHud(
        canvas: Canvas,
        w: Float,
        h: Float
    ) {
        updateLaunchButtonAnimation()

        val bottomY = h - dp(28f)

        if (uiMode == ShuffleUiMode.Aiming) {
            val textAlpha = ((1f - launchButtonProgress) * 255f).toInt().coerceIn(0, 255)

            if (textAlpha > 0) {
                textPaint.textAlign = Paint.Align.CENTER
                textPaint.typeface = android.graphics.Typeface.DEFAULT_BOLD
                textPaint.textSize = dp(16f)
                textPaint.color = Color.argb(
                    textAlpha,
                    105,
                    111,
                    115
                )

                canvas.drawText(
                    "Adjust position and trajectory.",
                    w * 0.50f,
                    bottomY + dp(12f),
                    textPaint
                )
            }

            drawLaunchButton(canvas, w, h, bottomY)
        } else {
            launchButtonProgress = 0f
            launchButtonRect.set(0f, 0f, 0f, 0f)
        }

        drawReservePucks(canvas, w - dp(23f), bottomY - dp(3f))
    }

    private fun drawStatusOverlay(
        canvas: Canvas,
        w: Float,
        h: Float
    ) {
        if (uiMode != ShuffleUiMode.Playing) {
            return
        }

        textPaint.textAlign = Paint.Align.CENTER
        textPaint.typeface = android.graphics.Typeface.DEFAULT_BOLD
        textPaint.textSize = dp(11f)
        textPaint.color = Color.argb(145, 74, 79, 83)

        canvas.drawText(
            "PLAYING ROUND",
            w * 0.5f,
            dp(29f),
            textPaint
        )
    }

    private fun arrowHeadScreenPosition(
        boardRect: RectF,
        cueX: Float,
        cueY: Float
    ): Pair<Float, Float> {
        val length = cueAimLengthPx(boardRect)
        val x = cueX + cos(cueAimAngleRad) * length
        val y = cueY + sin(cueAimAngleRad) * length
        return x to y
    }

    private fun updateLaunchButtonAnimation() {
        val target = if (uiMode == ShuffleUiMode.Aiming && hasCueAim) {
            1f
        } else {
            0f
        }

        if (abs(launchButtonProgress - target) < 0.01f) {
            launchButtonProgress = target
            return
        }

        launchButtonProgress += (target - launchButtonProgress) * 0.22f
        postInvalidateOnAnimation()
    }

    private fun drawLaunchButton(
        canvas: Canvas,
        w: Float,
        h: Float,
        bottomY: Float
    ) {
        if (launchButtonProgress <= 0.001f) {
            launchButtonRect.set(0f, 0f, 0f, 0f)
            return
        }

        val buttonWidth = dp(148f)
        val buttonHeight = dp(42f)

        val targetCenterY = bottomY - dp(13f)
        val hiddenCenterY = h + buttonHeight

        val currentCenterY = hiddenCenterY + (targetCenterY - hiddenCenterY) * launchButtonProgress

        val left = (w - buttonWidth) * 0.5f
        val top = currentCenterY - buttonHeight / 2f
        val right = left + buttonWidth
        val bottom = top + buttonHeight

        launchButtonRect.set(left, top, right, bottom)

        // Shadow
        fillPaint.style = Paint.Style.FILL
        fillPaint.color = Color.argb(65, 0, 0, 0)
        canvas.drawRoundRect(
            RectF(
                left,
                top + dp(2f),
                right,
                bottom + dp(2f)
            ),
            dp(21f),
            dp(21f),
            fillPaint
        )

        // Button
        fillPaint.color = if (launchButtonPressed) {
            Color.rgb(232, 196, 0)
        } else {
            Color.rgb(255, 220, 0)
        }

        canvas.drawRoundRect(
            launchButtonRect,
            dp(21f),
            dp(21f),
            fillPaint
        )

        // Border
        linePaint.style = Paint.Style.STROKE
        linePaint.strokeWidth = dp(1.2f)
        linePaint.color = Color.argb(80, 120, 95, 0)
        canvas.drawRoundRect(
            launchButtonRect,
            dp(21f),
            dp(21f),
            linePaint
        )

        // Text
        textPaint.textAlign = Paint.Align.CENTER
        textPaint.typeface = android.graphics.Typeface.DEFAULT_BOLD
        textPaint.textSize = dp(18f)
        textPaint.color = Color.rgb(70, 62, 0)

        val baseline = launchButtonRect.centerY() - (textPaint.descent() + textPaint.ascent()) / 2f
        canvas.drawText(
            "Launch",
            launchButtonRect.centerX(),
            baseline,
            textPaint
        )
    }

    private fun onLaunchPressed() {
        if (!hasCueAim || uiMode != ShuffleUiMode.Aiming) {
            return
        }

        val shotAngleRad = -cueAimAngleRad
        val shotDistance = cueAimDist

        val stagedReplay = buildLaunchBoardReplay(
            shotAngleRad = shotAngleRad,
            shotDistance = shotDistance
        )

        replay = stagedReplay
        parseReplay(stagedReplay)

        hasCueAim = false
        draggingCuePuck = false
        draggingArrowHead = false
        launchButtonPressed = false
        launchButtonProgress = 0f
        launchButtonRect.set(0f, 0f, 0f, 0f)

        showReplayArrows = true
        replayArrowAlpha = ARROW_MAX_ALPHA

        OpenPigeonLog.i(
            "ShuffleRenderer",
            "Launch staged localPlayer=$localPlayer angle=$shotAngleRad dist=$shotDistance replay=${stagedReplay.take(260)}"
        )

        val callback = onLaunchReplayReady

        if (callback != null) {
            callback.invoke(stagedReplay)
        } else {
            playRoundFromReplay(stagedReplay) {}
        }

        invalidate()
    }

    fun playRoundFromReplay(
        roundReplay: String,
        onFinished: () -> Unit
    ) {
        pendingRoundStartRunnable?.let { removeCallbacks(it) }
        pendingRoundStartRunnable = null

        replay = roundReplay
        parseReplay(roundReplay)

        uiMode = ShuffleUiMode.Playing
        nativeRoundFinished = onFinished

        hasCueAim = false
        draggingCuePuck = false
        draggingArrowHead = false
        launchButtonPressed = false
        launchButtonProgress = 0f
        launchButtonRect.set(0f, 0f, 0f, 0f)

        showReplayArrows = pucks.any { it.shotDistance > SHOT_DISTANCE_EPS }
        replayArrowAlpha = if (showReplayArrows) ARROW_MAX_ALPHA else 0f

        wallIntroActive = false
        wallIntroStartMs = 0L

        val startRunnable = Runnable {
            pendingRoundStartRunnable = null
            startNativeRoundFromCurrentPucks()
        }

        pendingRoundStartRunnable = startRunnable

        invalidate()
        postDelayed(startRunnable, PREPLAY_ARROW_HOLD_MS)
    }

    private fun startNativeRoundFromCurrentPucks() {
        showReplayArrows = false
        replayArrowAlpha = 0f

        wallIntroActive = true
        wallIntroStartMs = System.currentTimeMillis() + WALL_INTRO_DELAY_MS

        val tablePtr = ensureNativeTable()

        ShuffleNativePhysics.setShuffleMode(tablePtr, layoutMode)
        ShuffleNativePhysics.clearShufflePucks(tablePtr)

        nativeSlots.clear()

        var firedCount = 0

        for ((index, puck) in pucks.withIndex()) {
            val byteBuffer = ByteBuffer
                .allocateDirect(8 * 4)
                .order(ByteOrder.nativeOrder())

            val floatBuffer = byteBuffer.asFloatBuffer()

            nativeSlots.add(
                NativePuckSlot(
                    traceId = index,
                    byteBuffer = byteBuffer,
                    floatBuffer = floatBuffer
                )
            )

            ShuffleNativePhysics.makeShufflePuck(
                tablePtr = tablePtr,
                x = puck.x,
                y = puck.y,
                angle = puck.bodyAngle,
                traceId = index,
                player = puck.player,
                outputsBuffer = byteBuffer
            )
        }

        for ((index, puck) in pucks.withIndex()) {
            if (puck.shotDistance > SHOT_DISTANCE_EPS) {
                ShuffleNativePhysics.fireShufflePuck(
                    tablePtr = tablePtr,
                    traceId = index,
                    shootDirRadians = puck.shotAngle,
                    dist = puck.shotDistance
                )

                firedCount++
            }
        }

        if (firedCount == 0) {
            nativeRunning = false
            uiMode = ShuffleUiMode.Aiming

            val callback = nativeRoundFinished
            nativeRoundFinished = null
            callback?.invoke()

            invalidate()
            return
        }

        ShuffleNativePhysics.refreshShuffleOutputs(tablePtr)
        syncNativePucksFromOutputs()

        nativeRunning = true

        OpenPigeonLog.i(
            "ShuffleRenderer",
            "Native round started firedCount=$firedCount pucks=${pucks.size}"
        )

        postInvalidateOnAnimation()
    }

    private fun buildNativeLaunchPucks(): List<ShufflePuck> {
        val out = mutableListOf<ShufflePuck>()

        var replacedReadyPuck = false
        val readyX = cuePuckXNorm * READY_PUCK_X_LIMIT

        for (puck in pucks) {
            if (puck.player == 1 && puck.y <= -200f) {
                out.add(
                    puck.copy(
                        x = readyX,
                        y = READY_PUCK_PLAYER1_Y,
                        bodyAngle = 0f,
                        shotAngle = 0f,
                        shotDistance = 0f,
                        velocityX = 0f,
                        velocityY = 0f
                    )
                )
                replacedReadyPuck = true
            } else {
                out.add(puck)
            }
        }

        if (!replacedReadyPuck) {
            out.add(
                ShufflePuck(
                    x = readyX,
                    y = READY_PUCK_PLAYER1_Y,
                    player = 1,
                    bodyAngle = 0f,
                    shotAngle = 0f,
                    shotDistance = 0f
                )
            )
        }

        return out
    }

    private fun updateNativeSimulationFrame() {
        if (!nativeRunning || nativeTablePtr == 0L) {
            return
        }

        val moving = ShuffleNativePhysics.updateShuffle(nativeTablePtr)
        syncNativePucksFromOutputs()

        if (moving) {
            postInvalidateOnAnimation()
        } else {
            nativeRunning = false
            wallIntroActive = false

            snapFinalPucksToBoardEnvelope()

            replay = buildZeroShotBoardReplay()

            OpenPigeonLog.i(
                "ShuffleRenderer",
                "Native shuffle stopped zeroReplay=${replay.take(300)}"
            )

            val callback = nativeRoundFinished
            nativeRoundFinished = null
            uiMode = ShuffleUiMode.Aiming
            showReplayArrows = false
            replayArrowAlpha = 0f

            callback?.invoke()
            invalidate()
        }
    }

    private fun snapFinalPucksToBoardEnvelope() {
        for (i in pucks.indices) {
            val puck = pucks[i]

            if (puck.y <= -200f || puck.y >= 200f) {
                continue
            }

            pucks[i] = puck.copy(
                x = puck.x.coerceIn(-FINAL_BOARD_X_LIMIT, FINAL_BOARD_X_LIMIT),
                y = puck.y.coerceIn(-FINAL_BOARD_Y_LIMIT, FINAL_BOARD_Y_LIMIT),
                shotAngle = 0f,
                shotDistance = 0f,
                velocityX = 0f,
                velocityY = 0f
            )
        }
    }

    private fun syncNativePucksFromOutputs() {
        if (nativeSlots.isEmpty()) {
            return
        }

        val updated = mutableListOf<ShufflePuck>()

        for (slot in nativeSlots) {
            val floats = slot.floatBuffer

            val x = floats.get(0)
            val y = floats.get(1)
            val angle = floats.get(2)
            val vx = floats.get(3)
            val vy = floats.get(4)
            val player = floats.get(6).toInt().coerceIn(1, 2)

            updated.add(
                ShufflePuck(
                    x = x,
                    y = y,
                    player = player,
                    bodyAngle = angle,
                    shotAngle = 0f,
                    shotDistance = 0f,
                    velocityX = vx,
                    velocityY = vy
                )
            )
        }

        pucks.clear()
        pucks.addAll(updated)
    }

    private fun buildLaunchBoardReplay(
        shotAngleRad: Float,
        shotDistance: Float
    ): String {
        val readyX = cuePuckXNorm * READY_PUCK_X_LIMIT
        val readyY = readyYForPlayer(localPlayer)
        var wroteReadyPuck = false

        return buildString {
            append("board:")
            append(score1)
            append(",")
            append(score2)

            for (puck in pucks) {
                val outputPuck = if (isReadyPuckForPlayer(puck, localPlayer)) {
                    wroteReadyPuck = true

                    puck.copy(
                        x = readyX,
                        y = readyY,
                        bodyAngle = 0f,
                        shotAngle = shotAngleRad,
                        shotDistance = shotDistance,
                        velocityX = 0f,
                        velocityY = 0f
                    )
                } else {
                    puck
                }

                appendReplayPuck(outputPuck)
            }

            if (!wroteReadyPuck) {
                appendReplayPuck(
                    ShufflePuck(
                        x = readyX,
                        y = readyY,
                        player = localPlayer,
                        bodyAngle = 0f,
                        shotAngle = shotAngleRad,
                        shotDistance = shotDistance
                    )
                )
            }
        }
    }

    private fun buildZeroShotBoardReplay(): String {
        return buildString {
            append("board:")
            append(score1)
            append(",")
            append(score2)

            for (puck in pucks) {
                appendReplayPuck(
                    puck.copy(
                        shotAngle = 0f,
                        shotDistance = 0f,
                        velocityX = 0f,
                        velocityY = 0f
                    )
                )
            }
        }
    }

    private fun readyYForPlayer(player: Int): Float {
        return if (player == 2) {
            READY_PUCK_PLAYER2_Y
        } else {
            READY_PUCK_PLAYER1_Y
        }
    }

    private fun isReadyPuckForPlayer(
        puck: ShufflePuck,
        player: Int
    ): Boolean {
        return when (player) {
            2 -> puck.player == 2 && puck.y >= 200f
            else -> puck.player == 1 && puck.y <= -200f
        }
    }

    private fun StringBuilder.appendReplayPuck(puck: ShufflePuck) {
        append("#")
        append(format6(puck.x))
        append(",")
        append(format6(puck.y))
        append(",")
        append(puck.player)
        append(",")
        append(format6(puck.bodyAngle))
        append(",")
        append(format6(puck.shotAngle))
        append(",")
        append(format6(puck.shotDistance))
    }

    private fun format6(value: Float): String {
        return String.format(
            java.util.Locale.US,
            "%.6f",
            value
        )
    }

    private fun drawReservePucks(
        canvas: Canvas,
        cx: Float,
        cy: Float
    ) {
        val s = dp(18f)

        drawPuck(canvas, cx, cy - dp(9f), 1, 0f, s)
        drawPuck(canvas, cx - dp(10f), cy + dp(8f), 1, 0f, s)
        drawPuck(canvas, cx + dp(10f), cy + dp(8f), 1, 0f, s)
    }

    private fun calculateBoardRect(
        w: Float,
        h: Float
    ): RectF {
        val boardWidth = min(
            w - dp(32f),
            h * 0.46f
        )

        val boardHeight = boardWidth * BOARD_ASPECT_HEIGHT_OVER_WIDTH
        val left = (w - boardWidth) * 0.5f

        val availableTop = dp(44f)
        val availableBottom = h - dp(150f)
        val availableHeight = (availableBottom - availableTop).coerceAtLeast(boardHeight)

        val top = availableTop + ((availableHeight - boardHeight) * 0.5f)

        return RectF(
            left,
            top,
            left + boardWidth,
            top + boardHeight
        )
    }

    private fun cuePuckScreenX(boardRect: RectF): Float {
        return boardRect.centerX() + cuePuckXNorm * iosSize(READY_PUCK_X_LIMIT, boardRect)
    }

    private fun updateCueDragFromTouch(
        touchX: Float,
        touchY: Float,
        boardRect: RectF
    ) {
        val gameX = screenToGameX(touchX, boardRect)
        val gameY = screenToGameY(touchY, boardRect)

        // iOS behavior:
        // dragging below the board moves the ready puck horizontally only.
        if (gameY <= READY_PUCK_PLAYER1_Y + READY_ROW_DRAG_PAD) {
            updateCuePositionFromGameX(gameX)
            return
        }

        // Dragging into the table/board area sets the aim arrow.
        if (
            gameX >= -TABLE_AIM_X_LIMIT &&
            gameX <= TABLE_AIM_X_LIMIT &&
            gameY >= -TABLE_AIM_Y_LIMIT &&
            gameY <= TABLE_AIM_Y_LIMIT
        ) {
            updateCueAimFromGameTouch(
                touchGameX = gameX,
                touchGameY = gameY
            )
            return
        }

        // If the drag is above the ready puck but just outside the board bounds,
        // still allow aiming so the interaction does not feel dead near the edge.
        if (gameY > READY_PUCK_PLAYER1_Y) {
            updateCueAimFromGameTouch(
                touchGameX = gameX.coerceIn(-TABLE_AIM_X_LIMIT, TABLE_AIM_X_LIMIT),
                touchGameY = gameY.coerceIn(-TABLE_AIM_Y_LIMIT, TABLE_AIM_Y_LIMIT)
            )
        }
    }

    private fun updateCuePositionFromGameX(gameX: Float) {
        cuePuckXNorm = (gameX / READY_PUCK_X_LIMIT)
            .coerceIn(-1.0f, 1.0f)
    }

    private fun updateCueAimFromGameTouch(
        touchGameX: Float,
        touchGameY: Float
    ) {
        val cueGameX = cuePuckXNorm * READY_PUCK_X_LIMIT
        val cueGameY = READY_PUCK_PLAYER1_Y

        val dxGame = touchGameX - cueGameX
        val dyGame = touchGameY - cueGameY

        val dist = hypot(dxGame, dyGame)

        if (dist < MIN_AIM_DISTANCE) {
            return
        }

        // SpriteKit/iOS game-space Y increases upward.
        // Android canvas Y increases downward, so negate dy for drawing.
        val drawAngle = atan2(-dyGame, dxGame)

        val minAngle = (-155.0).toRadiansFloat()
        val maxAngle = (-25.0).toRadiansFloat()

        cueAimAngleRad = drawAngle.coerceIn(minAngle, maxAngle)
        cueAimDist = dist.coerceIn(MIN_AIM_DISTANCE, MAX_AIM_DISTANCE)
        hasCueAim = true
    }

    private fun cueAimLengthPx(boardRect: RectF): Float {
        return iosSize(
            cueAimDist.coerceIn(MIN_AIM_VISUAL_LENGTH, MAX_AIM_DISTANCE),
            boardRect
        )
    }

    private fun screenToGameX(
        screenX: Float,
        boardRect: RectF
    ): Float {
        return (screenX - boardRect.centerX()) / iosSceneScale(boardRect)
    }

    private fun screenToGameY(
        screenY: Float,
        boardRect: RectF
    ): Float {
        return (boardRect.centerY() - screenY) / iosSceneScale(boardRect)
    }

    private fun puckScreenX(
        gameX: Float,
        boardRect: RectF
    ): Float {
        return boardRect.centerX() + gameX * iosSceneScale(boardRect)
    }

    private fun puckScreenY(
        gameY: Float,
        boardRect: RectF
    ): Float {
        return boardRect.centerY() - gameY * iosSceneScale(boardRect)
    }

    private fun iosSize(
        points: Float,
        boardRect: RectF
    ): Float {
        return points * iosSceneScale(boardRect)
    }

    private fun puckSize(boardRect: RectF): Float {
        return iosSize(32f, boardRect)
    }

    private fun outOfPlayPuckCenterGap(boardRect: RectF): Float {
        // Distance from board edge to puck center.
        // puck radius = 16 iOS points. Extra visual gap = 14 iOS points.
        return (puckSize(boardRect) / 2f) + iosSize(14f, boardRect)
    }

    private fun topOutOfPlayPuckY(boardRect: RectF): Float {
        return boardRect.top - outOfPlayPuckCenterGap(boardRect)
    }

    private fun bottomOutOfPlayPuckY(boardRect: RectF): Float {
        return boardRect.bottom + outOfPlayPuckCenterGap(boardRect)
    }

    private fun parseReplay(replayValue: String?) {
        pucks.clear()

        val latestBoard = replayValue
            ?.split("|")
            ?.lastOrNull { it.startsWith("board:") }
            ?: DEFAULT_REPLAY

        val boardPayload = latestBoard.removePrefix("board:")
        val chunks = boardPayload
            .split("#")
            .map { it.trim() }
            .filter { it.isNotEmpty() }

        if (chunks.isNotEmpty()) {
            val scoreParts = chunks[0]
                .split(",")
                .mapNotNull { it.trim().toIntOrNull() }

            score1 = scoreParts.getOrNull(0) ?: 0
            score2 = scoreParts.getOrNull(1) ?: 0
        }

        for (chunk in chunks.drop(1)) {
            val values = chunk
                .split(",")
                .mapNotNull { it.trim().toFloatOrNull() }

            if (values.size < 6) {
                continue
            }

            pucks.add(
                ShufflePuck(
                    x = values[0],
                    y = values[1],
                    player = values[2].toInt().coerceIn(1, 2),
                    bodyAngle = values[3],
                    shotAngle = values[4],
                    shotDistance = values[5]
                )
            )
        }

        if (pucks.isEmpty()) {
            pucks.add(
                ShufflePuck(
                    x = 0f,
                    y = -215f,
                    player = 1,
                    bodyAngle = 0f,
                    shotAngle = 0f,
                    shotDistance = 0f
                )
            )

            pucks.add(
                ShufflePuck(
                    x = 0f,
                    y = 215f,
                    player = 2,
                    bodyAngle = 0f,
                    shotAngle = 0f,
                    shotDistance = 0f
                )
            )
        }
    }

    private fun loadAssets() {
        puck1Bitmap = loadAssetBitmap(
            "shuffle/shuffle_puck1_Normal@3x.png",
            "shuffle_puck1_Normal@3x.png"
        )

        puck2Bitmap = loadAssetBitmap(
            "shuffle/shuffle_puck2_Normal@3x.png",
            "shuffle_puck2_Normal@3x.png"
        )

        puckShadowBitmap = loadAssetBitmap(
            "shuffle/shuffle_puck_shadow_Normal@3x.png",
            "shuffle_puck_shadow_Normal@3x.png"
        )

        bumperBitmap = loadAssetBitmap(
            "shuffle/shuffle_bumper_Normal@3x.png",
            "shuffle_bumper_Normal@3x.png"
        )

        bumperShadowBitmap = loadAssetBitmap(
            "shuffle/shuffle_bumper_shadow_Normal@3x.png",
            "shuffle_bumper_shadow_Normal@3x.png"
        )
    }

    private fun loadAssetBitmap(
        vararg paths: String
    ): Bitmap? {
        for (path in paths) {
            try {
                context.assets.open(path).use { stream ->
                    val bitmap = BitmapFactory.decodeStream(stream)

                    if (bitmap != null) {
                        OpenPigeonLog.i(
                            "ShuffleRenderer",
                            "Loaded asset $path ${bitmap.width}x${bitmap.height}"
                        )

                        return bitmap
                    }
                }
            } catch (_: Exception) {
                // Try next path.
            }
        }

        OpenPigeonLog.w(
            "ShuffleRenderer",
            "Could not load asset paths=${paths.joinToString()}"
        )

        return null
    }

    private fun dp(value: Float): Float {
        return value * density
    }

    private companion object {
        private const val IOS_BOARD_WIDTH = 380f
        private const val IOS_BOARD_HEIGHT = 410f
        private const val BOARD_ASPECT_HEIGHT_OVER_WIDTH = IOS_BOARD_HEIGHT / IOS_BOARD_WIDTH

        // iOS ready puck movement/selection constants from ShuffleScene touch handling.
        private const val READY_PUCK_X_LIMIT = 159f
        private const val READY_PUCK_PICK_RADIUS = 35f
        private const val READY_PUCK_PLAYER1_Y = -215f
        private const val READY_PUCK_PLAYER2_Y = 215f
        private const val SHOT_DISTANCE_EPS = 0.001f
        private const val ARROW_MAX_ALPHA = 0.80f
        private const val PREPLAY_ARROW_HOLD_MS = 1050L

        private const val WALL_INTRO_DELAY_MS = 180L
        private const val WALL_INTRO_DURATION_MS = 520L
        private const val WALL_INTRO_START_SCALE = 1.50f
        private const val WALL_INTRO_THICKNESS = 12f

        private const val FINAL_BOARD_X_LIMIT = 178f
        private const val FINAL_BOARD_Y_LIMIT = 193f

        // iOS only starts aim behavior when the touch is inside the table/board region.
        private const val TABLE_AIM_X_LIMIT = 195f
        private const val TABLE_AIM_Y_LIMIT = 205f
        private const val READY_ROW_DRAG_PAD = 10f

        private const val MIN_AIM_DISTANCE = 28f
        private const val MIN_AIM_VISUAL_LENGTH = 45f
        private const val MAX_AIM_DISTANCE = 420f

        private val DEFAULT_MAP_SCORES_MODE_1 = listOf(
            5, 10, 5, 2, 3, 10,
            6, 3, 2, 5, 3, 6
        )

        private val DEFAULT_MAP_SCORES_MODE_2 = listOf(
            6, 5, 8, 10,
            10, 8, 5, 6,
            6, 5, 6, 2,
            5, 2, 7, 3
        )

        private val DEFAULT_MAP_SCORES_MODE_3 = listOf(
            3, 2, 5,
            10, 7, 7, 6, 5,
            6, 4, 7, 8, 6,
            10, 4, 4, 4, 8,
            5, 3, 5
        )

        private const val DEFAULT_REPLAY =
            "board:0,0#" +
                    "0.000000,-215.000000,1,0.000000,0.000000,0.000000#" +
                    "0.000000,215.000000,2,0.000000,0.000000,0.000000#"
    }
}