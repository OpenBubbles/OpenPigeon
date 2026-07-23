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
import android.view.HapticFeedbackConstants
import org.json.JSONArray
import org.json.JSONObject
import androidx.core.graphics.withClip

class ShuffleRenderer @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
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
        val traceId: Int, val byteBuffer: ByteBuffer, val floatBuffer: FloatBuffer
    )

    private data class PushStickState(
        val player: Int,
        val startX: Float,
        val startY: Float,
        val shotAngle: Float,
    )

    private data class ScoreAnimationItem(
        val puckIndex: Int,
        val player: Int,
        val score: Int,
    )

    private enum class ShuffleUiMode {
        Aiming, Waiting, Playing, SentWaiting, Spectating, GameOver,
    }

    private val density = resources.displayMetrics.density
    private var darkMode = false

    private var mode: Int = 1
    private var layoutMode: Int = 1
    private var replay: String = DEFAULT_REPLAY
    private var currentPlayer: Int = 1
    private var score1: Int = 0
    private var score2: Int = 0
    private val pucks = mutableListOf<ShufflePuck>()
    private val committedUsedPucksByPlayer = IntArray(3)
    private var mapScores: List<Int> = defaultMapScoresForMode(1)

    private var draggingCuePuck = false
    private var draggingArrowHead = false
    private var lastAimHapticStep = -1
    private var cuePuckXNorm = 0.0f

    private var aimUiAlpha = 0f
    private var aimUiFadeStartMs = 0L

    private var hasCueAim = false
    private var cueAimAngleRad = (-90.0).toRadiansFloat()
    private var cueAimDist = 0.0f

    private var nativeTablePtr: Long = 0L
    private var nativeRunning = false
    private val nativeSlots = mutableListOf<NativePuckSlot>()

    private var nativeTraceRunId = ""

    private var nativeTraceShotIndex = 0

    private var nativeTraceFrame = 0

    private var nativeTraceInput = ""

    private var nativeTraceHash = ""

    var onLaunchReplayReady: ((String) -> Unit)? = null

    var onTopHudAlphaChanged: ((Float) -> Unit)? = null

    private var topHudAlpha = 1f
    private var topHudFadeFrom = 1f
    private var topHudFadeTo = 1f
    private var topHudFadeStartMs = 0L

    private var uiMode = ShuffleUiMode.Aiming
    private var localPlayer = 1
    private var spectatorMode = false
    private var nativeRoundFinished: (() -> Unit)? = null

    private var showReplayArrows = false
    private var replayArrowAlpha = 0f
    private var opponentRevealStartMs = 0L
    private var opponentRevealEndMs = 0L
    private var pendingRoundStartRunnable: Runnable? = null

    private var pendingReplayPrefix = ""
    private var currentRoundStartBoard = ""

    private var pushStickStates: List<PushStickState> = emptyList()

    private var pushStickStartMs = 0L
    private var pushStickActive = false
    private var pushStickPushStartMs = 0L
    private var currentRoundFiredTraceIds: List<Int> = emptyList()

    private var scoreAnimationItems: List<ScoreAnimationItem> = emptyList()

    private var scoreAnimationStartMs = 0L
    private var scoreAnimationActive = false
    private var scoreAnimationAppliedCount = 0

    private var wallIntroStartMs = 0L
    private var wallIntroActive = false
    private var wallAnimationReversed = false
    private var wallAnimationCompletion: (() -> Unit)? = null

    private val launchButtonRect = RectF()
    private var launchButtonProgress = 0f
    private var launchButtonPressed = false

    private var puck1Bitmap: Bitmap? = null
    private var puck2Bitmap: Bitmap? = null
    private var puckShadowBitmap: Bitmap? = null
    private var stickBitmap: Bitmap? = null
    private var bumperBitmap: Bitmap? = null
    private var bumperShadowBitmap: Bitmap? = null

    private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val stickPaint = Paint(
        Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG,
    )

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

        //  uses mode as the board selector.
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
                "Map count mismatch for shuffle layout. dataMode=$mode layoutMode=$layoutMode " + "rawMap=${data["map"]} parsed=${parsedScores.size} expected=$expectedCount; using default"
            )

            defaultMapScoresForMode(layoutMode)
        }

        pendingReplayPrefix = ""
        currentRoundStartBoard = ""
        currentRoundFiredTraceIds = emptyList()

        stopPushStickAnimation()
        stopScoreAnimation()
        stopOpponentPositionReveal()
        setTopHudVisible(true)

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

        cancelWallAnimation()

        OpenPigeonLog.i(
            "ShuffleRenderer",
            "setGameData dataMode=$mode layoutMode=$layoutMode currentPlayer=$currentPlayer " + "mapRaw=${data["map"]} mapCount=${mapScores.size} mapScores=$mapScores " + "pucks=${pucks.size} score=$score1,$score2"
        )

        invalidate()
    }

    private fun Double.toRadiansFloat(): Float {
        return Math.toRadians(this).toFloat()
    }

    private fun stopOpponentPositionReveal() {
        opponentRevealStartMs = 0L
        opponentRevealEndMs = 0L
    }

    private fun startWallAnimation(
        reversed: Boolean,
        startAtMs: Long = System.currentTimeMillis(),
        onFinished: (() -> Unit)? = null,
    ) {
        wallAnimationReversed = reversed
        wallIntroStartMs = startAtMs
        wallIntroActive = true
        wallAnimationCompletion = onFinished

        postInvalidateOnAnimation()
    }

    private fun cancelWallAnimation() {
        wallIntroActive = false
        wallIntroStartMs = 0L
        wallAnimationReversed = false
        wallAnimationCompletion = null
    }

    private fun finishWallExitAnimation() {
        val completion = wallAnimationCompletion

        cancelWallAnimation()

        if (completion != null) {
            post {
                completion.invoke()
            }
        }

        postInvalidateOnAnimation()
    }

    override fun onDraw(
        canvas: Canvas,
    ) {
        super.onDraw(canvas)

        updateNativeSimulationFrame()
        updateScoreAnimation()
        updateAimUiFade()
        updateTopHudFade()

        val w = width.toFloat()

        val h = height.toFloat()

        drawBackground(
            canvas,
            w,
            h,
        )

        drawTopHud(
            canvas,
            w,
        )

        drawBoardAndPucks(
            canvas,
            w,
            h,
        )

        drawBottomHud(
            canvas,
            w,
            h,
        )
    }

    private fun setTopHudVisible(
        visible: Boolean,
        now: Long = System.currentTimeMillis(),
    ) {
        val target = if (visible) {
            1f
        } else {
            0f
        }

        if (topHudFadeTo == target && (topHudFadeStartMs > 0L || abs(topHudAlpha - target) < 0.001f)) {
            return
        }

        topHudFadeFrom = topHudAlpha
        topHudFadeTo = target
        topHudFadeStartMs = now

        postInvalidateOnAnimation()
    }


    private fun updateTopHudFade() {
        val now = System.currentTimeMillis()

        if (uiMode == ShuffleUiMode.Playing && !scoreAnimationActive && pushStickActive && pushStickStartMs > 0L && now >= pushStickStartMs && topHudFadeTo != 0f) {
            setTopHudVisible(
                visible = false,
                now = now,
            )
        }

        if (topHudFadeStartMs <= 0L) {
            return
        }

        val progress =
            ((now - topHudFadeStartMs).toFloat() / TOP_HUD_FADE_DURATION_MS.toFloat()).coerceIn(
                0f,
                1f,
            )

        val eased = progress * progress * (3f - 2f * progress)

        topHudAlpha = topHudFadeFrom + (topHudFadeTo - topHudFadeFrom) * eased

        onTopHudAlphaChanged?.invoke(
            topHudAlpha,
        )

        if (progress < 1f) {
            postInvalidateOnAnimation()
        } else {
            topHudAlpha = topHudFadeTo

            topHudFadeStartMs = 0L

            onTopHudAlphaChanged?.invoke(
                topHudAlpha,
            )
        }
    }

    private fun updateAimUiFade() {
        if (uiMode != ShuffleUiMode.Aiming) {
            aimUiAlpha = 0f
            aimUiFadeStartMs = 0L
            return
        }

        if (aimUiFadeStartMs <= 0L) {
            aimUiAlpha = 1f
            return
        }

        val elapsed = (System.currentTimeMillis() - aimUiFadeStartMs).coerceAtLeast(0L)

        val progress = (elapsed.toFloat() / AIM_UI_FADE_DURATION_MS.toFloat()).coerceIn(
            0f,
            1f,
        )


        aimUiAlpha = 1f - ((1f - progress) * (1f - progress))

        if (progress < 1f) {
            postInvalidateOnAnimation()
        } else {
            aimUiAlpha = 1f
            aimUiFadeStartMs = 0L
        }
    }

    fun setSpectatorMode(
        enabled: Boolean,
    ) {
        spectatorMode = enabled

        if (enabled) {
            localPlayer = 1

            hasCueAim = false

            draggingCuePuck = false

            draggingArrowHead = false

            launchButtonPressed = false

            launchButtonProgress = 0f

            launchButtonRect.set(
                0f,
                0f,
                0f,
                0f,
            )

            if (uiMode != ShuffleUiMode.Playing) {
                uiMode = ShuffleUiMode.Spectating
            }
        }

        syncCuePositionFromReadyPuck()
        invalidate()
    }


    fun currentScores(): Pair<Int, Int> {
        return score1 to score2
    }


    fun hasGameEnded(): Boolean {
        return (score1 >= WINNING_SCORE || score2 >= WINNING_SCORE)
    }

    fun completedRoundReplayForSend(): String {
        return pendingReplayPrefix + replay
    }


    fun showSpectating() {
        showPassiveMode(
            ShuffleUiMode.Spectating,
        )
    }


    fun showGameOver() {
        showPassiveMode(
            ShuffleUiMode.GameOver,
        )
    }

    private fun normalizeShuffleTraceInput(
        rawReplay: String,
    ): String {
        var normalized = rawReplay.trim().trimEnd('|')

        val shootMarker = normalized.indexOf(
            "|shoot:1|",
        )

        if (shootMarker >= 0) {
            normalized = normalized.substring(
                0,
                shootMarker,
            )
        }

        val boardSegments = normalized.split('|').map {
            it.trim()
        }.filter {
            it.startsWith(
                "board:",
            )
        }

        return (boardSegments.lastOrNull() ?: normalized).trimEnd('|')
    }

    private fun shuffleTraceHash(
        value: String,
    ): String {
        return value.hashCode().toUInt().toString(
            radix = 16,
        ).padStart(
            length = 8,
            padChar = '0',
        )
    }

    private fun buildTracePuckArray(): JSONArray {
        val array = JSONArray()

        pucks.forEachIndexed { index, puck ->
            array.put(
                JSONObject().put(
                    "traceId",
                    index,
                ).put(
                    "player",
                    puck.player,
                ).put(
                    "x",
                    puck.x,
                ).put(
                    "y",
                    puck.y,
                ).put(
                    "bodyAngle",
                    puck.bodyAngle,
                ).put(
                    "shotAngle",
                    puck.shotAngle,
                ).put(
                    "shotDistance",
                    puck.shotDistance,
                ),
            )
        }

        return array
    }


    private fun showPassiveMode(
        targetMode: ShuffleUiMode,
    ) {
        uiMode = targetMode

        pendingRoundStartRunnable?.let {
            removeCallbacks(
                it,
            )
        }

        pendingRoundStartRunnable = null

        stopPushStickAnimation()
        stopScoreAnimation()
        stopOpponentPositionReveal()
        setTopHudVisible(true)

        hasCueAim = false

        draggingCuePuck = false

        draggingArrowHead = false

        lastAimHapticStep = -1

        launchButtonPressed = false

        launchButtonProgress = 0f

        launchButtonRect.set(
            0f,
            0f,
            0f,
            0f,
        )

        aimUiAlpha = 0f

        aimUiFadeStartMs = 0L

        showReplayArrows = false

        replayArrowAlpha = 0f

        cancelWallAnimation()

        invalidate()
    }

    fun setDarkMode(
        enabled: Boolean,
    ) {
        if (darkMode == enabled) {
            return
        }

        darkMode = enabled

        invalidate()
    }

    fun setLocalPlayer(
        player: Int,
    ) {
        localPlayer = if (spectatorMode) {
            1
        } else {
            player.coerceIn(
                1,
                2,
            )
        }

        syncCuePositionFromReadyPuck()
        invalidate()
    }

    private fun opponentPlayer(): Int {
        return if (localPlayer == 1) 2 else 1
    }

    private fun normalizeRadians(
        angle: Float,
    ): Float {
        val pi = Math.PI.toFloat()
        val twoPi = pi * 2f
        var result = angle % twoPi

        while (result > pi) {
            result -= twoPi
        }

        while (result <= -pi) {
            result += twoPi
        }

        return result
    }

    private fun worldXToVisual(
        worldX: Float,
    ): Float {
        return if (localPlayer == 2) {
            -worldX
        } else {
            worldX
        }
    }

    private fun visualXToWorld(
        visualX: Float,
    ): Float {
        return if (localPlayer == 2) {
            -visualX
        } else {
            visualX
        }
    }

    private fun worldYToVisual(
        worldY: Float,
    ): Float {
        return if (localPlayer == 2) {
            -worldY
        } else {
            worldY
        }
    }

    private fun worldShotAngleToScreen(
        worldAngle: Float,
    ): Float {
        val screenAngle = if (localPlayer == 2) {
            Math.PI.toFloat() - worldAngle
        } else {
            -worldAngle
        }

        return normalizeRadians(screenAngle)
    }

    private fun screenAimAngleToWorld(
        screenAngle: Float,
    ): Float {
        val worldAngle = if (localPlayer == 2) {
            Math.PI.toFloat() - screenAngle
        } else {
            -screenAngle
        }

        return normalizeRadians(worldAngle)
    }

    private fun scoreForPlayer(player: Int): Int {
        return if (player == 1) score1 else score2
    }

    private fun playerHudColor(
        player: Int,
    ): Int {
        return when {
            player == 1 -> {
                Color.rgb(
                    255,
                    226,
                    0,
                )
            }

            darkMode -> {
                Color.rgb(
                    235,
                    239,
                    242,
                )
            }

            else -> {
                Color.rgb(
                    45,
                    48,
                    50,
                )
            }
        }
    }

    private fun playerArrowColor(
        player: Int,
    ): Int {
        return if (player == 1) {
            Color.rgb(255, 220, 0)
        } else {
            Color.rgb(35, 35, 35)
        }
    }

    private fun isPuckOnReadyRowForPlayer(
        puck: ShufflePuck,
        player: Int,
    ): Boolean {
        val normalizedPlayer = player.coerceIn(1, 2)

        if (puck.player != normalizedPlayer) {
            return false
        }

        return abs(
            puck.y - readyYForPlayer(normalizedPlayer),
        ) <= READY_PUCK_Y_TOLERANCE
    }

    private fun readyPuckForPlayer(
        player: Int,
    ): ShufflePuck? {
        return pucks.lastOrNull { puck ->
            isPuckOnReadyRowForPlayer(
                puck = puck,
                player = player,
            )
        }
    }

    private fun syncCuePositionFromReadyPuck() {
        val readyPuck = readyPuckForPlayer(localPlayer) ?: return

        cuePuckXNorm = (worldXToVisual(readyPuck.x) / READY_PUCK_X_LIMIT).coerceIn(
            -1f,
            1f,
        )
    }

    fun showAiming() {
        if (spectatorMode) {
            showSpectating()
            return
        }

        uiMode = ShuffleUiMode.Aiming

        nativeRoundFinished = null

        pendingRoundStartRunnable?.let {
            removeCallbacks(it)
        }

        pendingRoundStartRunnable = null

        stopPushStickAnimation()
        stopScoreAnimation()
        stopOpponentPositionReveal()
        setTopHudVisible(true)

        showReplayArrows = false
        replayArrowAlpha = 0f

        cancelWallAnimation()

        hasCueAim = false
        draggingCuePuck = false
        draggingArrowHead = false
        lastAimHapticStep = -1

        launchButtonPressed = false
        launchButtonProgress = 0f

        launchButtonRect.set(
            0f,
            0f,
            0f,
            0f,
        )

        aimUiAlpha = 0f
        aimUiFadeStartMs = System.currentTimeMillis()

        invalidate()
    }

    fun showWaitingForOpponent() {
        uiMode = ShuffleUiMode.Waiting

        stopPushStickAnimation()
        stopScoreAnimation()
        stopOpponentPositionReveal()
        setTopHudVisible(true)

        hasCueAim = false

        draggingCuePuck = false
        draggingArrowHead = false

        launchButtonPressed = false
        launchButtonProgress = 0f

        launchButtonRect.set(
            0f,
            0f,
            0f,
            0f,
        )

        cancelWallAnimation()

        aimUiAlpha = 0f
        aimUiFadeStartMs = 0L

        showReplayArrows = false
        replayArrowAlpha = 0f

        invalidate()
    }

    fun showPlaying() {
        uiMode = ShuffleUiMode.Playing

        stopPushStickAnimation()
        stopScoreAnimation()
        stopOpponentPositionReveal()
        setTopHudVisible(true)

        hasCueAim = false

        draggingCuePuck = false
        draggingArrowHead = false

        launchButtonPressed = false
        launchButtonProgress = 0f

        launchButtonRect.set(
            0f,
            0f,
            0f,
            0f,
        )

        aimUiAlpha = 0f
        aimUiFadeStartMs = 0L

        showReplayArrows = pucks.any { puck ->
            puck.shotDistance > SHOT_DISTANCE_EPS
        }

        replayArrowAlpha = if (showReplayArrows) {
            ARROW_MAX_ALPHA
        } else {
            0f
        }

        invalidate()
    }

    fun showSentThenWaiting() {
        uiMode = ShuffleUiMode.SentWaiting

        stopPushStickAnimation()
        stopScoreAnimation()
        stopOpponentPositionReveal()
        setTopHudVisible(
            true,
        )

        hasCueAim = false

        draggingCuePuck = false

        draggingArrowHead = false

        lastAimHapticStep = -1

        launchButtonPressed = false

        launchButtonProgress = 0f

        launchButtonRect.set(
            0f,
            0f,
            0f,
            0f,
        )

        cancelWallAnimation()

        aimUiAlpha = 0f

        aimUiFadeStartMs = 0L

        showReplayArrows = pucks.any { puck ->
            puck.shotDistance > SHOT_DISTANCE_EPS
        }

        replayArrowAlpha = if (showReplayArrows) {
            ARROW_MAX_ALPHA
        } else {
            0f
        }

        invalidate()
    }

    fun isPlayingRound(): Boolean {
        return nativeRunning || uiMode == ShuffleUiMode.Playing
    }

    fun hasShotForPlayer(player: Int): Boolean {
        return pucks.any {
            it.player == player.coerceIn(1, 2) && it.shotDistance > SHOT_DISTANCE_EPS
        }
    }

    fun hasBothPlayerShots(): Boolean {
        return hasShotForPlayer(1) && hasShotForPlayer(2)
    }

    fun prepareNextLocalAimAfterPlayback(): String {
        val settledPucks = pucks.filterNot { puck ->
            isPuckOnReadyRowForPlayer(
                puck = puck,
                player = puck.player,
            )
        }

        pucks.clear()

        pucks += ShufflePuck(
            x = 0f,
            y = READY_PUCK_PLAYER1_Y,
            player = 1,
            bodyAngle = 0f,
            shotAngle = 0f,
            shotDistance = 0f,
        )

        pucks += ShufflePuck(
            x = 0f,
            y = READY_PUCK_PLAYER2_Y,
            player = 2,
            bodyAngle = 0f,
            shotAngle = 0f,
            shotDistance = 0f,
        )

        pucks.addAll(settledPucks)

        cuePuckXNorm = 0f
        hasCueAim = false
        draggingCuePuck = false
        draggingArrowHead = false
        lastAimHapticStep = -1

        rebuildCommittedUsedPuckCounts()
        syncCuePositionFromReadyPuck()

        replay = buildBoardSegment(
            pucks,
        )

        invalidate()

        return replay
    }

    override fun onTouchEvent(
        event: MotionEvent,
    ): Boolean {
        if (spectatorMode || uiMode != ShuffleUiMode.Aiming || nativeRunning) {
            return true
        }

        val boardRect = calculateBoardRect(
            width.toFloat(),
            height.toFloat(),
        )

        val cueX = cuePuckScreenX(boardRect)

        val cueY = bottomOutOfPlayPuckY(boardRect)

        val puckTouchRadius = size(
            READY_PUCK_PICK_RADIUS,
            boardRect,
        )

        val arrowHeadTouchRadius = size(
            34f,
            boardRect,
        )

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (launchButtonProgress > 0.85f && launchButtonRect.contains(
                        event.x,
                        event.y,
                    )
                ) {
                    launchButtonPressed = true
                    invalidate()
                    return true
                }

                val puckDx = event.x - cueX

                val puckDy = event.y - cueY

                val touchedCuePuck =
                    puckDx * puckDx + puckDy * puckDy <= puckTouchRadius * puckTouchRadius

                if (touchedCuePuck) {
                    draggingCuePuck = true
                    draggingArrowHead = false
                    lastAimHapticStep = -1

                    parent?.requestDisallowInterceptTouchEvent(
                        true,
                    )

                    updateCueDragFromTouch(
                        touchX = event.x,
                        touchY = event.y,
                        boardRect = boardRect,
                    )

                    invalidate()
                    return true
                }

                if (hasCueAim) {
                    val arrowHead = arrowHeadScreenPosition(
                        boardRect = boardRect,
                        cueX = cueX,
                        cueY = cueY,
                    )

                    val arrowDx = event.x - arrowHead.first

                    val arrowDy = event.y - arrowHead.second

                    val touchedArrowHead =
                        arrowDx * arrowDx + arrowDy * arrowDy <= arrowHeadTouchRadius * arrowHeadTouchRadius

                    if (touchedArrowHead) {
                        draggingArrowHead = true
                        draggingCuePuck = false
                        lastAimHapticStep = -1

                        parent?.requestDisallowInterceptTouchEvent(
                            true,
                        )

                        updateCueAimFromScreenTouch(
                            touchX = event.x,
                            touchY = event.y,
                            boardRect = boardRect,
                        )

                        invalidate()
                        return true
                    }
                }

                if (boardRect.contains(
                        event.x,
                        event.y,
                    )
                ) {
                    draggingArrowHead = true
                    draggingCuePuck = false
                    lastAimHapticStep = -1

                    parent?.requestDisallowInterceptTouchEvent(
                        true,
                    )

                    updateCueAimFromScreenTouch(
                        touchX = event.x,
                        touchY = event.y,
                        boardRect = boardRect,
                    )

                    invalidate()
                    return true
                }
            }

            MotionEvent.ACTION_MOVE -> {
                if (launchButtonPressed) {
                    launchButtonPressed = launchButtonRect.contains(
                        event.x,
                        event.y,
                    )

                    invalidate()
                    return true
                }

                if (draggingCuePuck) {
                    updateCueDragFromTouch(
                        touchX = event.x,
                        touchY = event.y,
                        boardRect = boardRect,
                    )

                    invalidate()
                    return true
                }

                if (draggingArrowHead) {
                    updateCueAimFromScreenTouch(
                        touchX = event.x,
                        touchY = event.y,
                        boardRect = boardRect,
                    )

                    invalidate()
                    return true
                }
            }

            MotionEvent.ACTION_UP -> {
                if (launchButtonPressed) {
                    val wasInside = launchButtonRect.contains(
                        event.x,
                        event.y,
                    )

                    launchButtonPressed = false

                    if (wasInside) {
                        onLaunchPressed()
                        performClick()
                    }

                    invalidate()
                    return true
                }

                if (draggingCuePuck) {
                    updateCueDragFromTouch(
                        touchX = event.x,
                        touchY = event.y,
                        boardRect = boardRect,
                    )

                    draggingCuePuck = false
                    draggingArrowHead = false
                    lastAimHapticStep = -1

                    parent?.requestDisallowInterceptTouchEvent(
                        false,
                    )

                    performClick()
                    invalidate()
                    return true
                }

                if (draggingArrowHead) {
                    updateCueAimFromScreenTouch(
                        touchX = event.x,
                        touchY = event.y,
                        boardRect = boardRect,
                    )

                    draggingArrowHead = false
                    draggingCuePuck = false
                    lastAimHapticStep = -1

                    parent?.requestDisallowInterceptTouchEvent(
                        false,
                    )

                    performClick()
                    invalidate()
                    return true
                }
            }

            MotionEvent.ACTION_CANCEL -> {
                launchButtonPressed = false
                draggingCuePuck = false
                draggingArrowHead = false
                lastAimHapticStep = -1

                parent?.requestDisallowInterceptTouchEvent(
                    false,
                )

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
        ShuffleNativePhysics.setShuffleDebugLogging(
            NATIVE_TRACE_ENABLED,
        )

        if (nativeTablePtr == 0L) {
            nativeTablePtr = ShuffleNativePhysics.createShuffleTable()

            ShuffleNativePhysics.setShuffleMode(
                tablePtr = nativeTablePtr,
                mode = layoutMode,
            )
        }

        return nativeTablePtr
    }

    private fun destroyNativeTable() {
        stopPushStickAnimation()
        stopScoreAnimation()
        cancelWallAnimation()

        if (nativeTablePtr != 0L) {
            ShuffleNativePhysics.clearShuffleTraceContext(
                nativeTablePtr,
            )

            ShuffleNativePhysics.destroyShuffleTable(
                nativeTablePtr,
            )

            nativeTablePtr = 0L
        }

        nativeSlots.clear()

        nativeRunning = false

        nativeTraceRunId = ""

        nativeTraceFrame = 0
    }

    private fun drawBackground(
        canvas: Canvas,
        w: Float,
        h: Float,
    ) {
        fillPaint.shader = null
        fillPaint.alpha = 255
        fillPaint.style = Paint.Style.FILL

        val topColor = if (darkMode) {
            Color.rgb(
                91,
                100,
                107,
            )
        } else {
            Color.rgb(
                197,
                207,
                214,
            )
        }

        val bottomColor = if (darkMode) {
            Color.rgb(
                56,
                64,
                70,
            )
        } else {
            Color.rgb(
                176,
                187,
                193,
            )
        }

        fillPaint.shader = LinearGradient(
            0f,
            0f,
            0f,
            h,
            topColor,
            bottomColor,
            Shader.TileMode.CLAMP,
        )

        canvas.drawRect(
            0f,
            0f,
            w,
            h,
            fillPaint,
        )

        fillPaint.shader = null

        fillPaint.color = if (darkMode) {
            Color.argb(
                34,
                245,
                248,
                250,
            )
        } else {
            Color.argb(
                95,
                240,
                245,
                248,
            )
        }

        canvas.drawRoundRect(
            RectF(
                dp(
                    4f,
                ),
                dp(
                    6f,
                ),
                w - dp(
                    4f,
                ),
                h - dp(
                    6f,
                ),
            ),
            dp(
                10f,
            ),
            dp(
                10f,
            ),
            fillPaint,
        )

        fillPaint.color = if (darkMode) {
            Color.argb(
                115,
                225,
                230,
                234,
            )
        } else {
            Color.argb(
                90,
                68,
                79,
                86,
            )
        }

        canvas.drawRoundRect(
            RectF(
                w * 0.43f,
                dp(
                    9f,
                ),
                w * 0.57f,
                dp(
                    13f,
                ),
            ),
            dp(
                2f,
            ),
            dp(
                2f,
            ),
            fillPaint,
        )
    }

    private fun drawOutlinedHudText(
        canvas: Canvas,
        text: String,
        x: Float,
        baseline: Float,
        alignment: Paint.Align,
        fillColor: Int,
    ) {
        textPaint.textAlign = alignment

        textPaint.style = Paint.Style.STROKE

        textPaint.strokeWidth = dp(
            1.35f,
        )

        textPaint.color = Color.argb(
            210,
            0,
            0,
            0,
        )

        canvas.drawText(
            text,
            x,
            baseline,
            textPaint,
        )

        textPaint.style = Paint.Style.FILL

        textPaint.color = fillColor

        canvas.drawText(
            text,
            x,
            baseline,
            textPaint,
        )
    }

    private fun drawTopHud(
        canvas: Canvas,
        w: Float,
    ) {
        if (topHudAlpha <= 0.001f) {
            return
        }

        val hudLayer = canvas.saveLayerAlpha(
            RectF(
                0f,
                0f,
                w,
                dp(
                    100f,
                ),
            ),
            (topHudAlpha * 255f).toInt().coerceIn(
                0,
                255,
            ),
        )

        val avatarWidth = dp(
            64f,
        )

        val avatarHeight = dp(
            46f,
        )

        val avatarCenterY = dp(
            40f,
        ) + avatarHeight / 2f

        val leftTextX = dp(
            10f,
        ) + avatarWidth + dp(
            8f,
        )

        val rightTextX = w - dp(
            10f,
        ) - avatarWidth - dp(
            8f,
        )

        val leftHudPlayer = if (spectatorMode) {
            1
        } else {
            localPlayer
        }

        val rightHudPlayer = if (spectatorMode) {
            2
        } else {
            opponentPlayer()
        }

        textPaint.typeface = android.graphics.Typeface.DEFAULT_BOLD

        textPaint.textSize = dp(
            12f,
        )

        val playerLabelBaseline = avatarCenterY - dp(
            6f,
        ) - (textPaint.descent() + textPaint.ascent()) / 2f

        drawOutlinedHudText(
            canvas = canvas,
            text = if (spectatorMode) {
                "Player 1"
            } else {
                "You"
            },
            x = leftTextX,
            baseline = playerLabelBaseline,
            alignment = Paint.Align.LEFT,
            fillColor = playerHudColor(
                leftHudPlayer,
            ),
        )

        if (spectatorMode) {
            drawOutlinedHudText(
                canvas = canvas,
                text = "Player 2",
                x = rightTextX,
                baseline = playerLabelBaseline,
                alignment = Paint.Align.RIGHT,
                fillColor = playerHudColor(
                    rightHudPlayer,
                ),
            )
        }

        textPaint.textSize = dp(
            14f,
        )

        val scoreBaseline = avatarCenterY + dp(
            7f,
        ) - (textPaint.descent() + textPaint.ascent()) / 2f

        drawOutlinedHudText(
            canvas = canvas,
            text = "${scoreForPlayer(leftHudPlayer)}/$WINNING_SCORE",
            x = leftTextX,
            baseline = scoreBaseline,
            alignment = Paint.Align.LEFT,
            fillColor = playerHudColor(
                leftHudPlayer,
            ),
        )

        drawOutlinedHudText(
            canvas = canvas,
            text = "${scoreForPlayer(rightHudPlayer)}/$WINNING_SCORE",
            x = rightTextX,
            baseline = scoreBaseline,
            alignment = Paint.Align.RIGHT,
            fillColor = playerHudColor(
                rightHudPlayer,
            ),
        )

        textPaint.style = Paint.Style.FILL

        canvas.restoreToCount(
            hudLayer,
        )
    }

    private fun drawBoardAndPucks(
        canvas: Canvas,
        w: Float,
        h: Float,
    ) {
        val boardRect = calculateBoardRect(
            w,
            h,
        )

        drawBoard(
            canvas,
            boardRect,
        )

        if (layoutMode == 2) {
            drawMode2Bumper(
                canvas,
                boardRect,
            )
        }

        drawIncomingWalls(
            canvas,
            boardRect,
        )

        drawPushSticks(
            canvas,
            boardRect,
        )

        if (scoreAnimationActive) {
            drawScoringPucks(
                canvas,
                boardRect,
            )
        } else {
            for (puck in pucks) {
                drawReplayPuck(
                    canvas,
                    boardRect,
                    puck,
                )
            }
        }

        drawReplayShotArrows(
            canvas,
            boardRect,
        )

        if (scoreAnimationActive) {
            drawScoringLabels(
                canvas,
                boardRect,
            )
        }

        if (!spectatorMode && uiMode == ShuffleUiMode.Aiming && aimUiAlpha > 0.001f) {
            drawOpponentReadyPuck(
                canvas = canvas,
                boardRect = boardRect,
                alpha = aimUiAlpha,
            )

            drawCueLineAndPuck(
                canvas = canvas,
                boardRect = boardRect,
                alpha = aimUiAlpha,
            )
        }
    }

    private fun drawScoringPucks(
        canvas: Canvas,
        boardRect: RectF,
    ) {
        val now = System.currentTimeMillis()

        val cleanupProgress = scoreCleanupProgress(
            now,
        )

        val cleanupEase = cleanupProgress * cleanupProgress * (3f - 2f * cleanupProgress)

        val cleanupScale = 1f - cleanupEase

        for (itemIndex in scoreAnimationItems.indices) {
            val item = scoreAnimationItems[itemIndex]

            val puck = pucks.getOrNull(
                item.puckIndex,
            ) ?: continue

            val itemProgress = scoreAnimationProgress(
                itemIndex,
                now,
            )

            val individualEase = itemProgress * itemProgress * (3f - 2f * itemProgress)

            val countedPuckScale = 1f - 0.5f * individualEase

            val finalPuckScale = countedPuckScale * cleanupScale

            if (finalPuckScale <= 0.001f) {
                continue
            }

            drawPuck(
                canvas = canvas,
                cx = puckVisualScreenX(
                    puck,
                    boardRect,
                ),
                cy = puckVisualScreenY(
                    puck,
                    boardRect,
                ),
                player = puck.player,
                rotation = puck.bodyAngle,
                size = pucksize(
                    boardRect,
                ) * finalPuckScale,
            )
        }

        postInvalidateOnAnimation()
    }

    private fun drawScoringLabels(
        canvas: Canvas,
        boardRect: RectF,
    ) {
        val now = System.currentTimeMillis()

        val cleanupProgress = scoreCleanupProgress(
            now,
        )

        val cleanupAlpha = 1f - cleanupProgress

        for (itemIndex in scoreAnimationItems.indices) {
            val item = scoreAnimationItems[itemIndex]

            val progress = scoreAnimationProgress(
                itemIndex,
                now,
            )

            if (progress <= 0f || cleanupAlpha <= 0.001f) {
                continue
            }

            val puck = pucks.getOrNull(
                item.puckIndex,
            ) ?: continue

            val puckX = puckVisualScreenX(
                puck,
                boardRect,
            )

            val puckY = puckVisualScreenY(
                puck,
                boardRect,
            )

            val growProgress = (progress / 0.70f).coerceIn(
                0f,
                1f,
            )

            val scoreScale = if (growProgress < 0.80f) {
                0.25f + 1.25f * (growProgress / 0.80f)
            } else {
                1.50f - 0.50f * ((growProgress - 0.80f) / 0.20f)
            }

            val appearanceAlpha = (progress / 0.22f).coerceIn(
                0f,
                1f,
            )

            val finalAlpha = appearanceAlpha * cleanupAlpha

            val riseProgress = 1f - (1f - progress) * (1f - progress)

            val scoreY = puckY - pucksize(
                boardRect,
            ) * 0.42f - size(
                2f + 8f * riseProgress,
                boardRect,
            )

            val scoreText = "+${item.score}"

            val scoreColor = playerArrowColor(
                item.player,
            )

            val outlineColor = if (item.player == 1) {
                Color.BLACK
            } else {
                Color.WHITE
            }

            textPaint.textAlign = Paint.Align.CENTER

            textPaint.typeface = android.graphics.Typeface.DEFAULT_BOLD

            textPaint.textSize = size(
                23f,
                boardRect,
            ) * scoreScale

            textPaint.style = Paint.Style.STROKE

            textPaint.strokeWidth = size(
                2.2f,
                boardRect,
            )

            textPaint.color = Color.argb(
                (220f * finalAlpha).toInt().coerceIn(
                    0,
                    255,
                ),
                Color.red(
                    outlineColor,
                ),
                Color.green(
                    outlineColor,
                ),
                Color.blue(
                    outlineColor,
                ),
            )

            canvas.drawText(
                scoreText,
                puckX,
                scoreY,
                textPaint,
            )

            textPaint.style = Paint.Style.FILL

            textPaint.color = Color.argb(
                (255f * finalAlpha).toInt().coerceIn(
                    0,
                    255,
                ),
                Color.red(
                    scoreColor,
                ),
                Color.green(
                    scoreColor,
                ),
                Color.blue(
                    scoreColor,
                ),
            )

            canvas.drawText(
                scoreText,
                puckX,
                scoreY,
                textPaint,
            )
        }

        textPaint.style = Paint.Style.FILL
    }

    private fun playableBoardRect(
        rect: RectF,
    ): RectF {
        val inset = size(
            BOARD_BORDER_GAME,
            rect,
        )

        return RectF(
            rect.left + inset,
            rect.top + inset,
            rect.right - inset,
            rect.bottom - inset,
        )
    }

    private fun drawPushSticks(
        canvas: Canvas,
        boardRect: RectF,
    ) {
        if (!pushStickActive || pushStickStartMs <= 0L || pushStickStates.isEmpty()) {
            return
        }

        val now = System.currentTimeMillis()

        if (now < pushStickStartMs) {
            postInvalidateOnAnimation()
            return
        }

        val stick = stickBitmap ?: return

        val isPushPhase = pushStickPushStartMs > 0L

        val backwardOffset: Float
        val pushTravelGame: Float
        val stickAlpha: Float

        if (!isPushPhase) {
            val approachElapsed = (now - pushStickStartMs).coerceAtLeast(0L)

            val approachProgress =
                (approachElapsed.toFloat() / STICK_APPROACH_DURATION_MS.toFloat()).coerceIn(
                    0f,
                    1f,
                )

            val approachEase = 1f - ((1f - approachProgress) * (1f - approachProgress))

            backwardOffset = size(
                STICK_START_OFFSET_GAME,
                boardRect,
            ) * (1f - approachEase)

            pushTravelGame = 0f
            stickAlpha = 0.96f
        } else {
            val pushElapsed = (now - pushStickPushStartMs).coerceAtLeast(0L)

            val totalPushDuration = STICK_PUSH_MOVE_DURATION_MS + STICK_PUSH_FADE_DURATION_MS

            if (pushElapsed >= totalPushDuration) {
                stopPushStickAnimation()
                return
            }

            val moveProgress =
                (pushElapsed.toFloat() / STICK_PUSH_MOVE_DURATION_MS.toFloat()).coerceIn(
                    0f,
                    1f,
                )

            val moveEase = moveProgress * moveProgress * (3f - 2f * moveProgress)

            pushTravelGame = STICK_PUSH_TRAVEL_GAME * moveEase

            val fadeProgress =
                ((pushElapsed - STICK_PUSH_MOVE_DURATION_MS).toFloat() / STICK_PUSH_FADE_DURATION_MS.toFloat()).coerceIn(
                    0f,
                    1f,
                )

            val fadeEase = fadeProgress * fadeProgress * (3f - 2f * fadeProgress)

            backwardOffset = 0f

            stickAlpha = 0.96f * (1f - fadeEase)
        }

        val stickWidth = size(
            STICK_WIDTH_GAME,
            boardRect,
        )

        val stickHeight = stickWidth * (stick.height.toFloat() / stick.width.toFloat())

        val forkForwardOffset = size(
            STICK_FORK_FORWARD_OFFSET_GAME,
            boardRect,
        )

        stickPaint.alpha = (255f * stickAlpha).toInt().coerceIn(
            0,
            255,
        )

        for (state in pushStickStates) {
            val travelWorldX = cos(
                state.shotAngle,
            ) * pushTravelGame

            val travelWorldY = sin(
                state.shotAngle,
            ) * pushTravelGame

            val anchorX = puckScreenX(
                worldXToVisual(
                    state.startX + travelWorldX,
                ),
                boardRect,
            )

            val projectedStartY = puckScreenY(
                worldYToVisual(
                    state.startY,
                ),
                boardRect,
            )

            val projectedMovedY = puckScreenY(
                worldYToVisual(
                    state.startY + travelWorldY,
                ),
                boardRect,
            )

            val readyBaseY = if (state.player == localPlayer) {
                bottomOutOfPlayPuckY(
                    boardRect,
                )
            } else {
                topOutOfPlayPuckY(
                    boardRect,
                )
            }

            val anchorY = readyBaseY + (projectedMovedY - projectedStartY)

            val screenAngle = worldShotAngleToScreen(
                state.shotAngle,
            )

            val angleDegrees = Math.toDegrees(
                screenAngle.toDouble(),
            ).toFloat()

            val destination = RectF(
                anchorX - stickWidth + forkForwardOffset - backwardOffset,
                anchorY - stickHeight / 2f,
                anchorX + forkForwardOffset - backwardOffset,
                anchorY + stickHeight / 2f,
            )

            canvas.withRotation(
                degrees = angleDegrees,
                pivotX = anchorX,
                pivotY = anchorY,
            ) {
                drawBitmap(
                    stick,
                    null,
                    destination,
                    stickPaint,
                )
            }
        }

        stickPaint.alpha = 255

        postInvalidateOnAnimation()
    }

    private fun drawReplayShotArrows(
        canvas: Canvas,
        boardRect: RectF,
    ) {
        if (!showReplayArrows || replayArrowAlpha <= 0.001f) {
            return
        }

        val now = System.currentTimeMillis()

        if (opponentRevealEndMs > 0L && now < opponentRevealEndMs) {
            postInvalidateOnAnimation()
            return
        }

        for (puck in pucks) {
            if (puck.shotDistance <= SHOT_DISTANCE_EPS) {
                continue
            }

            val originX = puckVisualScreenX(
                puck,
                boardRect,
            )

            val originY = puckVisualScreenY(
                puck,
                boardRect,
            )

            drawCueAimArrow(
                canvas = canvas,
                boardRect = boardRect,
                cueX = originX,
                cueY = originY,
                angle = replayArrowDrawAngle(
                    puck,
                ),
                distance = puck.shotDistance,
                alpha = replayArrowAlpha,
                player = puck.player,
            )
        }
    }

    private fun puckVisualScreenX(
        puck: ShufflePuck,
        boardRect: RectF,
    ): Float {
        val targetX = puckScreenX(
            worldXToVisual(
                puck.x,
            ),
            boardRect,
        )

        val isOpponentPendingShot =
            uiMode == ShuffleUiMode.Playing && puck.player == opponentPlayer() && puck.shotDistance > SHOT_DISTANCE_EPS && isPuckOnReadyRowForPlayer(
                puck = puck,
                player = opponentPlayer(),
            )

        if (isOpponentPendingShot && opponentRevealStartMs > 0L && opponentRevealEndMs > opponentRevealStartMs) {
            val now = System.currentTimeMillis()

            val revealProgress =
                ((now - opponentRevealStartMs).toFloat() / (opponentRevealEndMs - opponentRevealStartMs).toFloat()).coerceIn(
                    0f,
                    1f,
                )

            val easedProgress = revealProgress * revealProgress * (3f - 2f * revealProgress)

            if (revealProgress < 1f) {
                postInvalidateOnAnimation()
            }

            return boardRect.centerX() + (targetX - boardRect.centerX()) * easedProgress
        }

        if (isPuckOnReadyRowForPlayer(
                puck = puck,
                player = localPlayer,
            )
        ) {
            return cuePuckScreenX(
                boardRect,
            )
        }

        return targetX
    }

    private fun puckVisualScreenY(
        puck: ShufflePuck,
        boardRect: RectF,
    ): Float {
        return when {
            isPuckOnReadyRowForPlayer(
                puck = puck,
                player = localPlayer,
            ) -> {
                bottomOutOfPlayPuckY(boardRect)
            }

            isPuckOnReadyRowForPlayer(
                puck = puck,
                player = opponentPlayer(),
            ) -> {
                topOutOfPlayPuckY(boardRect)
            }

            else -> {
                puckScreenY(
                    worldYToVisual(puck.y),
                    boardRect,
                )
            }
        }
    }

    private fun replayArrowDrawAngle(
        puck: ShufflePuck,
    ): Float {
        return worldShotAngleToScreen(
            puck.shotAngle,
        )
    }

    private fun drawIncomingWalls(
        canvas: Canvas,
        boardRect: RectF,
    ) {
        if (!wallIntroActive) {
            return
        }

        val now = System.currentTimeMillis()

        if (wallIntroStartMs <= 0L || now < wallIntroStartMs) {
            postInvalidateOnAnimation()
            return
        }

        val rawProgress =
            ((now - wallIntroStartMs).toFloat() / WALL_INTRO_DURATION_MS.toFloat()).coerceIn(
                0f,
                1f,
            )

        if (wallAnimationReversed && rawProgress >= WALL_EXIT_FADE_END_PROGRESS) {
            finishWallExitAnimation()
            return
        }

        val directedProgress = if (wallAnimationReversed) {
            1f - rawProgress
        } else {
            rawProgress
        }

        val easedProgress = 1f - ((1f - directedProgress) * (1f - directedProgress))

        val scale = WALL_INTRO_START_SCALE + (1f - WALL_INTRO_START_SCALE) * easedProgress

        val wallAlpha = if (wallAnimationReversed) {
            val fadeProgress =
                ((rawProgress - WALL_EXIT_FADE_START_PROGRESS) / (WALL_EXIT_FADE_END_PROGRESS - WALL_EXIT_FADE_START_PROGRESS)).coerceIn(
                    0f,
                    1f,
                )

            val easedFade = fadeProgress * fadeProgress * (3f - 2f * fadeProgress)

            1f - easedFade
        } else {
            1f
        }

        if (wallAlpha <= 0.001f) {
            if (wallAnimationReversed) {
                finishWallExitAnimation()
            }

            return
        }

        val outerRect = scaleRectAboutCenter(
            rect = boardRect,
            cx = boardRect.centerX(),
            cy = boardRect.centerY(),
            scale = scale,
        )

        val thickness = size(
            BOARD_BORDER_GAME,
            boardRect,
        )

        val innerRect = RectF(
            outerRect.left + thickness,
            outerRect.top + thickness,
            outerRect.right - thickness,
            outerRect.bottom - thickness,
        )

        if (innerRect.width() <= 0f || innerRect.height() <= 0f) {
            return
        }

        val wallPath = Path().apply {
            fillType = Path.FillType.EVEN_ODD

            addRect(
                outerRect,
                Path.Direction.CW,
            )

            addRect(
                innerRect,
                Path.Direction.CCW,
            )
        }

        val previousFillAlpha = fillPaint.alpha

        val previousLineAlpha = linePaint.alpha

        val paintAlpha = (wallAlpha * 255f).toInt().coerceIn(
            0,
            255,
        )

        fillPaint.shader = null

        fillPaint.style = Paint.Style.FILL

        fillPaint.color = BOARD_WALL_COLOR

        fillPaint.alpha = paintAlpha

        canvas.drawPath(
            wallPath,
            fillPaint,
        )

        linePaint.style = Paint.Style.STROKE

        linePaint.strokeWidth = size(
            WALL_LINE_WIDTH_GAME,
            boardRect,
        )

        linePaint.color = Color.WHITE

        linePaint.alpha = paintAlpha

        canvas.drawRect(
            outerRect,
            linePaint,
        )

        canvas.drawRect(
            innerRect,
            linePaint,
        )

        fillPaint.alpha = previousFillAlpha

        linePaint.alpha = previousLineAlpha

        if (wallAnimationReversed || rawProgress < 1f) {
            postInvalidateOnAnimation()
        }
    }

    private fun scaleRectAboutCenter(
        rect: RectF, cx: Float, cy: Float, scale: Float
    ): RectF {
        val halfW = rect.width() * 0.5f * scale
        val halfH = rect.height() * 0.5f * scale

        return RectF(
            cx - halfW, cy - halfH, cx + halfW, cy + halfH
        )
    }

    private fun drawMode2Bumper(
        canvas: Canvas, boardRect: RectF
    ) {
        val cx = boardRect.centerX()
        val cy = boardRect.centerY()

        val bumpersize = size(53f, boardRect)
        val shadowsize = size(56f, boardRect)

        val shadowRect = RectF(
            cx - shadowsize / 2f,
            cy - shadowsize / 2f + size(1.5f, boardRect),
            cx + shadowsize / 2f,
            cy + shadowsize / 2f + size(1.5f, boardRect)
        )

        val bumperRect = RectF(
            cx - bumpersize / 2f, cy - bumpersize / 2f, cx + bumpersize / 2f, cy + bumpersize / 2f
        )

        val shadow = bumperShadowBitmap
        val bumper = bumperBitmap

        if (shadow != null) {
            canvas.drawBitmap(shadow, null, shadowRect, imagePaint)
        } else {
            fillPaint.style = Paint.Style.FILL
            fillPaint.color = Color.argb(65, 0, 0, 0)
            canvas.drawCircle(cx, cy + size(1.5f, boardRect), shadowsize / 2f, fillPaint)
        }

        if (bumper != null) {
            canvas.drawBitmap(bumper, null, bumperRect, imagePaint)
        } else {
            fillPaint.style = Paint.Style.FILL
            fillPaint.color = Color.rgb(215, 215, 215)
            canvas.drawCircle(cx, cy, bumpersize / 2f, fillPaint)
        }
    }

    private fun drawOpponentReadyPuck(
        canvas: Canvas,
        boardRect: RectF,
        alpha: Float,
    ) {
        if (uiMode != ShuffleUiMode.Aiming || alpha <= 0.001f) {
            return
        }

        val opponent = opponentPlayer()

        val topPuck = readyPuckForPlayer(
            opponent,
        )

        val hiddenPositionX = boardRect.centerX()

        drawPuck(
            canvas = canvas,
            cx = hiddenPositionX,
            cy = topOutOfPlayPuckY(
                boardRect,
            ),
            player = opponent,
            rotation = topPuck?.bodyAngle ?: 0f,
            size = pucksize(
                boardRect,
            ),
            alpha = alpha,
        )
    }

    private fun drawCueLineAndPuck(
        canvas: Canvas,
        boardRect: RectF,
        alpha: Float,
    ) {
        if (uiMode != ShuffleUiMode.Aiming || alpha <= 0.001f) {
            return
        }

        val cueY = bottomOutOfPlayPuckY(
            boardRect,
        )

        val cueX = cuePuckScreenX(
            boardRect,
        )

        val guideColor = playerHudColor(
            localPlayer,
        )

        linePaint.style = Paint.Style.STROKE

        linePaint.strokeCap = Paint.Cap.ROUND

        linePaint.strokeWidth = dp(1.2f)

        linePaint.color = Color.argb(
            (170f * alpha).toInt().coerceIn(0, 255),
            Color.red(guideColor),
            Color.green(guideColor),
            Color.blue(guideColor),
        )

        val guideStartX = boardRect.centerX() - size(
            READY_PUCK_X_LIMIT,
            boardRect,
        )

        val guideEndX = boardRect.centerX() + size(
            READY_PUCK_X_LIMIT,
            boardRect,
        )

        canvas.drawLine(
            guideStartX,
            cueY,
            guideEndX,
            cueY,
            linePaint,
        )

        if (!hasCueAim) {
            val phase =
                (System.currentTimeMillis() % HIGHLIGHT_PULSE_PERIOD_MS).toFloat() / HIGHLIGHT_PULSE_PERIOD_MS.toFloat()

            val triangle = if (phase <= 0.5f) {
                phase * 2f
            } else {
                (1f - phase) * 2f
            }

            val pulseScale = 1f + (HIGHLIGHT_PULSE_MAX_SCALE - 1f) * triangle

            val ringColor = playerArrowColor(
                localPlayer,
            )

            linePaint.style = Paint.Style.STROKE

            linePaint.strokeCap = Paint.Cap.ROUND

            linePaint.strokeWidth = size(
                1.8f,
                boardRect,
            )

            linePaint.color = Color.argb(
                (255f * ARROW_MAX_ALPHA * alpha).toInt().coerceIn(
                    0,
                    255,
                ),
                Color.red(ringColor),
                Color.green(ringColor),
                Color.blue(ringColor),
            )

            val ringRadius = (pucksize(boardRect) * 0.5f + size(
                4f,
                boardRect,
            )) * pulseScale

            canvas.drawCircle(
                cueX,
                cueY,
                ringRadius,
                linePaint,
            )

            postInvalidateOnAnimation()
        }

        val bottomPuck = readyPuckForPlayer(
            localPlayer,
        )

        if (hasCueAim) {
            drawCueAimArrow(
                canvas = canvas,
                boardRect = boardRect,
                cueX = cueX,
                cueY = cueY,
                angle = cueAimAngleRad,
                distance = cueAimDist,
                alpha = ARROW_MAX_ALPHA,
                player = localPlayer,
            )
        }

        drawPuck(
            canvas = canvas,
            cx = cueX,
            cy = cueY,
            player = localPlayer,
            rotation = bottomPuck?.bodyAngle ?: 0f,
            size = pucksize(boardRect),
            alpha = alpha,
        )
    }

    private fun updateCueAimFromScreenTouch(
        touchX: Float,
        touchY: Float,
        boardRect: RectF,
    ) {
        val cueX = cuePuckScreenX(
            boardRect,
        )

        val cueY = bottomOutOfPlayPuckY(
            boardRect,
        )

        val dx = touchX - cueX

        val dy = touchY - cueY

        val distance = hypot(
            dx,
            dy,
        ) / sceneScale(
            boardRect,
        )

        if (distance < MIN_AIM_DISTANCE) {
            return
        }

        cueAimAngleRad = atan2(
            dy,
            dx,
        )

        cueAimDist = distance.coerceAtMost(
            MAX_AIM_DISTANCE,
        )

        hasCueAim = true

        updateAimHaptic()
    }

    private fun drawCueAimArrow(
        canvas: Canvas,
        boardRect: RectF,
        cueX: Float,
        cueY: Float,
        angle: Float = cueAimAngleRad,
        distance: Float = cueAimDist,
        alpha: Float = ARROW_MAX_ALPHA,
        player: Int = localPlayer,
    ) {
        if (distance <= MIN_AIM_DISTANCE) {
            return
        }

        val arrowColor = playerArrowColor(
            player,
        )

        val shadowColor = if (player == 1) {
            Color.BLACK
        } else {
            Color.WHITE
        }

        val visualAlpha = (255f * alpha).toInt().coerceIn(
            0,
            255,
        )

        val shadowAlpha = (if (player == 1) {
            80f * alpha
        } else {
            115f * alpha
        }).toInt().coerceIn(
            0,
            255,
        )

        val startOffset = 0f

        val requestedLength = size(
            distance.coerceIn(
                MIN_AIM_VISUAL_LENGTH,
                MAX_AIM_DISTANCE,
            ),
            boardRect,
        )

        val availableLength = requestedLength.coerceAtLeast(
            size(
                8f,
                boardRect,
            ),
        )

        val headLength = min(
            size(
                24f,
                boardRect,
            ),
            availableLength * 0.55f,
        )

        val headHalfWidth = min(
            size(
                10f,
                boardRect,
            ),
            headLength * 0.55f,
        )

        val shaftHalfWidth = size(
            2.8f,
            boardRect,
        )

        val cosA = cos(angle)

        val sinA = sin(angle)

        val normalX = -sinA

        val startX = cueX + cosA * startOffset

        val startY = cueY + sinA * startOffset

        val tipX = cueX + cosA * requestedLength

        val tipY = cueY + sinA * requestedLength

        val headBackX = tipX - cosA * headLength

        val headBackY = tipY - sinA * headLength

        val arrowPath = Path().apply {
            moveTo(
                startX + normalX * shaftHalfWidth,
                startY + cosA * shaftHalfWidth,
            )

            lineTo(
                headBackX + normalX * shaftHalfWidth,
                headBackY + cosA * shaftHalfWidth,
            )

            lineTo(
                headBackX + normalX * headHalfWidth,
                headBackY + cosA * headHalfWidth,
            )

            lineTo(
                tipX,
                tipY,
            )

            lineTo(
                headBackX - normalX * headHalfWidth,
                headBackY - cosA * headHalfWidth,
            )

            lineTo(
                headBackX - normalX * shaftHalfWidth,
                headBackY - cosA * shaftHalfWidth,
            )

            lineTo(
                startX - normalX * shaftHalfWidth,
                startY - cosA * shaftHalfWidth,
            )

            close()
        }

        val shadowOffset = size(
            1.5f,
            boardRect,
        )

        val shadowPath = Path().apply {
            moveTo(
                startX + normalX * shaftHalfWidth + shadowOffset,
                startY + cosA * shaftHalfWidth + shadowOffset,
            )

            lineTo(
                headBackX + normalX * shaftHalfWidth + shadowOffset,
                headBackY + cosA * shaftHalfWidth + shadowOffset,
            )

            lineTo(
                headBackX + normalX * headHalfWidth + shadowOffset,
                headBackY + cosA * headHalfWidth + shadowOffset,
            )

            lineTo(
                tipX + shadowOffset,
                tipY + shadowOffset,
            )

            lineTo(
                headBackX - normalX * headHalfWidth + shadowOffset,
                headBackY - cosA * headHalfWidth + shadowOffset,
            )

            lineTo(
                headBackX - normalX * shaftHalfWidth + shadowOffset,
                headBackY - cosA * shaftHalfWidth + shadowOffset,
            )

            lineTo(
                startX - normalX * shaftHalfWidth + shadowOffset,
                startY - cosA * shaftHalfWidth + shadowOffset,
            )

            close()
        }

        fillPaint.style = Paint.Style.FILL

        fillPaint.color = Color.argb(
            shadowAlpha,
            Color.red(shadowColor),
            Color.green(shadowColor),
            Color.blue(shadowColor),
        )

        canvas.drawPath(
            shadowPath,
            fillPaint,
        )

        fillPaint.color = Color.argb(
            visualAlpha,
            Color.red(arrowColor),
            Color.green(arrowColor),
            Color.blue(arrowColor),
        )

        canvas.drawPath(
            arrowPath,
            fillPaint,
        )
    }

    private fun drawBoard(
        canvas: Canvas,
        rect: RectF,
    ) {
        drawGeneratedShuffleBoard(
            canvas = canvas,
            rect = rect,
            mode = layoutMode,
            scores = mapScores,
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
        scores: List<Int>,
    ) {
        val segments = shuffleSegmentSpecs(
            mode,
        )

        val defaults = defaultMapScoresForMode(
            mode,
        )

        val playableRect = playableBoardRect(
            rect,
        )

        canvas.withClip(
            playableRect,
        ) {

            fillPaint.shader = null
            fillPaint.alpha = 255
            fillPaint.style = Paint.Style.FILL
            fillPaint.color = baseBoardColor(
                mode,
            )

            canvas.drawRect(
                playableRect,
                fillPaint,
            )

            for (index in segments.indices) {
                val score = scores.getOrNull(
                    index,
                ) ?: defaults.getOrNull(
                    index,
                ) ?: 0

                fillPaint.color = segmentFillColor(
                    mode = mode,
                    score = score,
                )

                drawShuffleSegmentPolygon(
                    canvas = canvas,
                    boardRect = rect,
                    points = segments[index].points,
                    paint = fillPaint,
                )
            }

            linePaint.alpha = 255
            linePaint.style = Paint.Style.STROKE
            linePaint.strokeWidth = dp(1.25f)

            linePaint.color = Color.argb(
                235,
                255,
                255,
                255,
            )

            for (segment in segments) {
                drawShuffleSegmentPolygonStroke(
                    canvas = canvas,
                    boardRect = rect,
                    points = segment.points,
                    paint = linePaint,
                )
            }

            drawGeneratedBoardLabels(
                canvas = canvas,
                rect = rect,
                mode = mode,
                scores = scores,
            )

        }

        linePaint.alpha = 255
        linePaint.style = Paint.Style.STROKE
        linePaint.strokeWidth = dp(2f)
        linePaint.color = Color.WHITE

        canvas.drawRect(
            playableRect,
            linePaint,
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
            //  mode 1: shuffle_board, 12 segments

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
            //  mode 2: shuffle_board3, 16 segments

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
            //  mode 3: shuffle_board4, 21 segments

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
        canvas: Canvas, boardRect: RectF, points: List<Pair<Float, Float>>, paint: Paint
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
        canvas: Canvas, boardRect: RectF, points: List<Pair<Float, Float>>, paint: Paint
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
        scores: List<Int>,
    ) {
        val segments = shuffleSegmentSpecs(
            mode,
        )

        val defaults = defaultMapScoresForMode(
            mode,
        )

        textPaint.textAlign = Paint.Align.CENTER

        textPaint.typeface = android.graphics.Typeface.create(
            "sans-serif-black",
            android.graphics.Typeface.NORMAL,
        )

        textPaint.isFakeBoldText = true
        textPaint.style = Paint.Style.FILL

        textPaint.textSize = size(
            when (mode) {
                1 -> 19f
                2 -> 17f
                3 -> 15.5f
                else -> 19f
            },
            rect,
        )

        textPaint.color = Color.WHITE

        for (index in segments.indices) {
            val score = scores.getOrNull(
                index,
            ) ?: defaults.getOrNull(
                index,
            ) ?: 0

            val center = segmentCentroid(
                points = segments[index].points,
                rect = rect,
            )

            val baseline = center.second - (textPaint.descent() + textPaint.ascent()) / 2f

            canvas.drawText(
                score.toString(),
                center.first,
                baseline,
                textPaint,
            )
        }

        textPaint.isFakeBoldText = false
        textPaint.typeface = android.graphics.Typeface.DEFAULT_BOLD
    }

    private fun segmentCentroid(
        points: List<Pair<Float, Float>>, rect: RectF
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

    private fun sceneScale(boardRect: RectF): Float {
        return boardRect.width() / BOARD_WIDTH
    }

    private fun shuffleBoardX(
        gameX: Float,
        boardRect: RectF,
    ): Float {
        val visualX = if (localPlayer == 2) {
            -gameX
        } else {
            gameX
        }

        return boardRect.centerX() + visualX * sceneScale(boardRect)
    }


    private fun shuffleBoardY(
        gameY: Float,
        boardRect: RectF,
    ): Float {
        val visualY = if (localPlayer == 2) {
            -gameY
        } else {
            gameY
        }

        return boardRect.centerY() - visualY * sceneScale(boardRect)
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
        mode: Int, score: Int
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
        val cleaned =
            mapValue?.trim()?.removePrefix("[")?.removeSuffix("]")?.replace(" ", "").orEmpty()

        if (cleaned.isBlank()) {
            return emptyList()
        }

        return cleaned.split(",").mapNotNull { it.trim().toIntOrNull() }
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
        puck: ShufflePuck,
    ) {
        val isOnReadyRow = isPuckOnReadyRowForPlayer(
            puck = puck,
            player = 1,
        ) || isPuckOnReadyRowForPlayer(
            puck = puck,
            player = 2,
        )

        val showReadyRowPuck = when (uiMode) {
            ShuffleUiMode.Playing,
            ShuffleUiMode.Waiting,
            ShuffleUiMode.SentWaiting,
                -> {
                true
            }

            ShuffleUiMode.Aiming,
            ShuffleUiMode.Spectating,
            ShuffleUiMode.GameOver,
                -> {
                false
            }
        }

        if (isOnReadyRow && !showReadyRowPuck) {
            return
        }

        drawPuck(
            canvas = canvas,
            cx = puckVisualScreenX(
                puck,
                boardRect,
            ),
            cy = puckVisualScreenY(
                puck,
                boardRect,
            ),
            player = puck.player,
            rotation = puck.bodyAngle,
            size = pucksize(
                boardRect,
            ),
        )
    }

    private fun drawPuck(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        player: Int,
        rotation: Float,
        size: Float,
        alpha: Float = 1f,
    ) {
        val clampedAlpha = alpha.coerceIn(
            0f,
            1f,
        )

        if (clampedAlpha <= 0.001f) {
            return
        }

        val previousImageAlpha = imagePaint.alpha

        val previousFillAlpha = fillPaint.alpha

        val paintAlpha = (clampedAlpha * 255f).toInt().coerceIn(
            0,
            255,
        )

        imagePaint.alpha = paintAlpha

        fillPaint.alpha = paintAlpha

        val shadowsize = size * 1.25f

        val shadow = puckShadowBitmap

        val shadowRect = RectF(
            cx - shadowsize / 2f,
            cy - shadowsize / 2f + dp(2f),
            cx + shadowsize / 2f,
            cy + shadowsize / 2f + dp(2f),
        )

        if (shadow != null) {
            canvas.drawBitmap(
                shadow,
                null,
                shadowRect,
                imagePaint,
            )
        } else {
            fillPaint.style = Paint.Style.FILL

            fillPaint.color = Color.argb(
                65,
                0,
                0,
                0,
            )

            canvas.drawCircle(
                cx + dp(1f),
                cy + dp(2f),
                shadowsize / 2f,
                fillPaint,
            )
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
            cy + size / 2f,
        )

        if (bitmap != null) {
            canvas.withRotation(
                degrees = Math.toDegrees(
                    rotation.toDouble(),
                ).toFloat(),
                pivotX = cx,
                pivotY = cy,
            ) {
                drawBitmap(
                    bitmap,
                    null,
                    rect,
                    imagePaint,
                )
            }
        } else {
            fillPaint.style = Paint.Style.FILL

            fillPaint.color = if (player == 1) {
                Color.rgb(
                    255,
                    215,
                    0,
                )
            } else {
                Color.rgb(
                    35,
                    35,
                    35,
                )
            }

            canvas.drawCircle(
                cx,
                cy,
                size / 2f,
                fillPaint,
            )
        }

        imagePaint.alpha = previousImageAlpha

        fillPaint.alpha = previousFillAlpha
    }

    private fun drawBottomHud(
        canvas: Canvas,
        w: Float,
        h: Float,
    ) {
        if (spectatorMode || uiMode == ShuffleUiMode.Spectating || uiMode == ShuffleUiMode.GameOver) {
            launchButtonProgress = 0f

            launchButtonPressed = false

            launchButtonRect.set(
                0f,
                0f,
                0f,
                0f,
            )

            return
        }

        updateLaunchButtonAnimation()

        val controlCenterY = h - dp(
            BOTTOM_CONTROL_BOTTOM_MARGIN_DP + BOTTOM_CONTROL_SIZE_DP / 2f,
        )

        if (uiMode == ShuffleUiMode.Aiming) {
            val textAlpha = ((1f - launchButtonProgress) * aimUiAlpha * 255f).toInt().coerceIn(
                0,
                255,
            )

            if (textAlpha > 0) {
                textPaint.textAlign = Paint.Align.CENTER

                textPaint.typeface = android.graphics.Typeface.DEFAULT_BOLD

                textPaint.textSize = dp(
                    16f,
                )

                textPaint.color = if (darkMode) {
                    Color.argb(
                        textAlpha,
                        225,
                        231,
                        235,
                    )
                } else {
                    Color.argb(
                        textAlpha,
                        105,
                        111,
                        115,
                    )
                }

                val textBaseline = controlCenterY - (textPaint.descent() + textPaint.ascent()) / 2f

                canvas.drawText(
                    "Adjust position and trajectory.",
                    w * 0.50f,
                    textBaseline,
                    textPaint,
                )
            }

            drawLaunchButton(
                canvas = canvas,
                w = w,
                h = h,
                targetCenterY = controlCenterY,
            )
        } else {
            launchButtonProgress = 0f

            launchButtonRect.set(
                0f,
                0f,
                0f,
                0f,
            )
        }

        val reserveAlpha = when (uiMode) {
            ShuffleUiMode.Aiming -> {
                aimUiAlpha
            }

            ShuffleUiMode.Waiting, ShuffleUiMode.SentWaiting -> {
                1f
            }

            ShuffleUiMode.Playing, ShuffleUiMode.Spectating, ShuffleUiMode.GameOver -> {
                0f
            }
        }

        if (reserveAlpha > 0.001f) {
            drawReservePucks(
                canvas = canvas,
                cx = w - dp(
                    BOTTOM_CONTROL_SIZE_DP / 2f,
                ),
                cy = controlCenterY,
                alpha = reserveAlpha,
            )
        }
    }

    private fun arrowHeadScreenPosition(
        boardRect: RectF, cueX: Float, cueY: Float
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
        targetCenterY: Float,
    ) {
        if (launchButtonProgress <= 0.001f) {
            launchButtonRect.set(
                0f,
                0f,
                0f,
                0f,
            )

            return
        }

        val buttonWidth = dp(148f)

        val buttonHeight = dp(42f)

        val cornerRadius = dp(10f)

        val hiddenCenterY = h + buttonHeight

        val currentCenterY = hiddenCenterY + (targetCenterY - hiddenCenterY) * launchButtonProgress

        val left = (w - buttonWidth) * 0.5f

        val top = currentCenterY - buttonHeight / 2f

        val right = left + buttonWidth

        val bottom = top + buttonHeight

        launchButtonRect.set(
            left,
            top,
            right,
            bottom,
        )

        fillPaint.style = Paint.Style.FILL

        fillPaint.color = Color.argb(
            28,
            0,
            0,
            0,
        )

        canvas.drawRoundRect(
            RectF(
                left - dp(2f),
                top + dp(3f),
                right + dp(2f),
                bottom + dp(7f),
            ),
            cornerRadius + dp(2f),
            cornerRadius + dp(2f),
            fillPaint,
        )

        fillPaint.color = Color.argb(
            65,
            0,
            0,
            0,
        )

        canvas.drawRoundRect(
            RectF(
                left,
                top + dp(2f),
                right,
                bottom + dp(4f),
            ),
            cornerRadius,
            cornerRadius,
            fillPaint,
        )

        val normalButtonColor = playerArrowColor(
            localPlayer,
        )

        val pressedButtonColor = if (localPlayer == 1) {
            Color.rgb(
                232,
                196,
                0,
            )
        } else {
            Color.rgb(
                15,
                15,
                15,
            )
        }

        fillPaint.color = if (launchButtonPressed) {
            pressedButtonColor
        } else {
            normalButtonColor
        }

        canvas.drawRoundRect(
            launchButtonRect,
            cornerRadius,
            cornerRadius,
            fillPaint,
        )

        linePaint.style = Paint.Style.STROKE

        linePaint.strokeWidth = dp(1.2f)

        linePaint.color = if (localPlayer == 1) {
            Color.argb(
                80,
                120,
                95,
                0,
            )
        } else {
            Color.argb(
                130,
                255,
                255,
                255,
            )
        }

        canvas.drawRoundRect(
            launchButtonRect,
            cornerRadius,
            cornerRadius,
            linePaint,
        )

        textPaint.textAlign = Paint.Align.CENTER

        textPaint.typeface = android.graphics.Typeface.DEFAULT_BOLD

        textPaint.textSize = dp(18f)

        textPaint.color = if (localPlayer == 1) {
            Color.rgb(
                70,
                62,
                0,
            )
        } else {
            Color.WHITE
        }

        val baseline = launchButtonRect.centerY() - (textPaint.descent() + textPaint.ascent()) / 2f

        canvas.drawText(
            "Launch",
            launchButtonRect.centerX(),
            baseline,
            textPaint,
        )
    }

    private fun onLaunchPressed() {
        if (!hasCueAim || uiMode != ShuffleUiMode.Aiming) {
            return
        }

        val shotAngleRad = screenAimAngleToWorld(
            cueAimAngleRad,
        )
        val shotDistance = cueAimDist

        val stagedReplay = buildLaunchBoardReplay(
            shotAngleRad = shotAngleRad, shotDistance = shotDistance
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
            "Launch staged localPlayer=$localPlayer angle=$shotAngleRad dist=$shotDistance replay=${
                stagedReplay.take(
                    260
                )
            }"
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
        onFinished: () -> Unit,
    ) {
        pendingRoundStartRunnable?.let {
            removeCallbacks(it)
        }

        pendingRoundStartRunnable = null

        stopPushStickAnimation()
        stopScoreAnimation()
        stopOpponentPositionReveal()

        replay = roundReplay

        parseReplay(
            roundReplay,
        )

        nativeTraceInput = normalizeShuffleTraceInput(
            roundReplay,
        )

        nativeTraceHash = shuffleTraceHash(
            nativeTraceInput,
        )

        OpenPigeonLog.i(
            "ShuffleTrace",
            "SHUFFLE_ANDROID_INPUT=" + JSONObject().put(
                "replayHash",
                nativeTraceHash,
            ).put(
                "input",
                nativeTraceInput,
            ).put(
                "mode",
                layoutMode,
            ).put(
                "pucks",
                buildTracePuckArray(),
            ).toString(),
        )

        currentRoundStartBoard = buildBoardSegment(
            pucks,
        )

        currentRoundFiredTraceIds = pucks.indices.filter { index ->
            pucks[index].shotDistance > SHOT_DISTANCE_EPS
        }

        pushStickStates = currentRoundFiredTraceIds.mapNotNull { traceId ->
            pucks.getOrNull(
                traceId,
            )?.let { puck ->
                PushStickState(
                    player = puck.player,
                    startX = puck.x,
                    startY = puck.y,
                    shotAngle = puck.shotAngle,
                )
            }
        }

        val now = System.currentTimeMillis()

        val hasOpponentPendingShot = currentRoundFiredTraceIds.any { traceId ->
            val puck = pucks.getOrNull(
                traceId,
            )

            puck != null && puck.player == opponentPlayer() && isPuckOnReadyRowForPlayer(
                puck = puck,
                player = opponentPlayer(),
            )
        }

        opponentRevealStartMs = now

        opponentRevealEndMs = now + if (hasOpponentPendingShot) {
            OPPONENT_POSITION_REVEAL_DURATION_MS
        } else {
            0L
        }

        pushStickStartMs = opponentRevealEndMs

        pushStickPushStartMs = 0L

        pushStickActive = pushStickStates.isNotEmpty()

        uiMode = ShuffleUiMode.Playing

        nativeRoundFinished = onFinished

        hasCueAim = false
        draggingCuePuck = false
        draggingArrowHead = false

        launchButtonPressed = false
        launchButtonProgress = 0f

        launchButtonRect.set(
            0f,
            0f,
            0f,
            0f,
        )

        aimUiAlpha = 0f
        aimUiFadeStartMs = 0L

        showReplayArrows = currentRoundFiredTraceIds.isNotEmpty()

        replayArrowAlpha = if (showReplayArrows) {
            ARROW_MAX_ALPHA
        } else {
            0f
        }

        cancelWallAnimation()

        val revealDuration = (opponentRevealEndMs - opponentRevealStartMs).coerceAtLeast(
            0L,
        )

        OpenPigeonLog.i(
            "ShuffleRenderer",
            "Shuffle preplay started " + "fired=${currentRoundFiredTraceIds.size} " + "opponentReveal=$hasOpponentPendingShot " + "revealDuration=$revealDuration " + "stickStates=${pushStickStates.size} " + "assetLoaded=${stickBitmap != null}",
        )

        val startRunnable = Runnable {
            pendingRoundStartRunnable = null

            startNativeRoundFromCurrentPucks()
        }

        pendingRoundStartRunnable = startRunnable

        invalidate()
        postInvalidateOnAnimation()

        postDelayed(
            startRunnable,
            revealDuration + STICK_APPROACH_DURATION_MS + STICK_CONTACT_HOLD_DURATION_MS,
        )
    }

    private fun startNativeRoundFromCurrentPucks() {
        showReplayArrows = false

        replayArrowAlpha = 0f

        commitCurrentRoundShots()

        val pushStartMs = System.currentTimeMillis()

        pushStickPushStartMs = pushStartMs

        pushStickActive = pushStickStates.isNotEmpty()

        startWallAnimation(
            reversed = false,
            startAtMs = pushStartMs + STICK_PUSH_MOVE_DURATION_MS + STICK_PUSH_FADE_DURATION_MS + WALL_INTRO_AFTER_STICK_GAP_MS,
        )

        val tablePtr = ensureNativeTable()

        nativeTraceShotIndex += 1

        nativeTraceFrame = 0

        nativeTraceRunId = "shuffle-$nativeTraceHash-$nativeTraceShotIndex"

        ShuffleNativePhysics.setShuffleTraceContext(
            tablePtr = tablePtr,
            runId = nativeTraceRunId,
            shotIndex = nativeTraceShotIndex,
            frame = nativeTraceFrame,
            phase = "setup",
        )

        ShuffleNativePhysics.setShuffleMode(
            tablePtr = tablePtr,
            mode = layoutMode,
        )

        ShuffleNativePhysics.clearShufflePucks(
            tablePtr = tablePtr,
        )

        nativeSlots.clear()

        var firedCount = 0

        for ((index, puck) in pucks.withIndex()) {
            val byteBuffer = ByteBuffer.allocateDirect(
                8 * 4,
            ).order(
                ByteOrder.nativeOrder(),
            )

            val floatBuffer = byteBuffer.asFloatBuffer()

            nativeSlots.add(
                NativePuckSlot(
                    traceId = index,
                    byteBuffer = byteBuffer,
                    floatBuffer = floatBuffer,
                ),
            )

            ShuffleNativePhysics.makeShufflePuck(
                tablePtr = tablePtr,
                x = puck.x,
                y = puck.y,
                angle = puck.bodyAngle,
                traceId = index,
                player = puck.player,
                outputsBuffer = byteBuffer,
            )
        }

        ShuffleNativePhysics.setShuffleTraceContext(
            tablePtr = tablePtr,
            runId = nativeTraceRunId,
            shotIndex = nativeTraceShotIndex,
            frame = nativeTraceFrame,
            phase = "fire",
        )

        for ((index, puck) in pucks.withIndex()) {
            if (puck.shotDistance > SHOT_DISTANCE_EPS) {
                ShuffleNativePhysics.fireShufflePuck(
                    tablePtr = tablePtr,
                    traceId = index,
                    shootDirRadians = puck.shotAngle,
                    dist = puck.shotDistance,
                )

                firedCount++
            }
        }

        if (firedCount == 0) {
            nativeRunning = false

            cancelWallAnimation()

            stopPushStickAnimation()
            stopOpponentPositionReveal()
            setTopHudVisible(
                true,
            )

            ShuffleNativePhysics.clearShuffleTraceContext(
                tablePtr,
            )

            nativeTraceRunId = ""

            nativeTraceFrame = 0

            uiMode = ShuffleUiMode.Aiming

            val callback = nativeRoundFinished

            nativeRoundFinished = null

            callback?.invoke()

            invalidate()
            return
        }

        ShuffleNativePhysics.refreshShuffleOutputs(
            tablePtr = tablePtr,
        )

        syncNativePucksFromOutputs()

        OpenPigeonLog.i(
            "ShuffleTrace",
            "SHUFFLE_ANDROID_RUN_START=" + JSONObject().put(
                "runId",
                nativeTraceRunId,
            ).put(
                "replayHash",
                nativeTraceHash,
            ).put(
                "input",
                nativeTraceInput,
            ).put(
                "mode",
                layoutMode,
            ).put(
                "timeStep",
                1.0 / 60.0,
            ).put(
                "velocityIterations",
                60,
            ).put(
                "positionIterations",
                60,
            ).put(
                "puckRadius",
                15.0,
            ).put(
                "linearDamping",
                1.5,
            ).put(
                "angularDamping",
                2.0,
            ).put(
                "pucks",
                buildTracePuckArray(),
            ).toString(),
        )

        nativeRunning = true

        OpenPigeonLog.i(
            "ShuffleRenderer",
            "Native round started " + "runId=$nativeTraceRunId " + "shotIndex=$nativeTraceShotIndex " + "firedCount=$firedCount " + "stickStates=${pushStickStates.size} " + "stickActive=$pushStickActive " + "pushStart=$pushStickPushStartMs " + "pucks=${pucks.size} " + "usedP1=${committedUsedPucksByPlayer[1]} " + "usedP2=${committedUsedPucksByPlayer[2]}",
        )

        postInvalidateOnAnimation()
    }

    private fun orderSettledPucksMostRecentFirst() {
        if (pucks.isEmpty()) {
            return
        }

        val firedIds = currentRoundFiredTraceIds.toSet()

        val newestPucks = currentRoundFiredTraceIds.mapNotNull { traceId ->
            pucks.getOrNull(traceId)
        }.filterNot { puck ->
            isPuckOnReadyRowForPlayer(
                puck,
                puck.player,
            )
        }.sortedBy { puck ->
            if (puck.player == localPlayer) {
                0
            } else {
                1
            }
        }

        val olderPucks = pucks.filterIndexed { index, puck ->
            index !in firedIds && !isPuckOnReadyRowForPlayer(
                puck,
                puck.player,
            )
        }

        pucks.clear()
        pucks.addAll(newestPucks)
        pucks.addAll(olderPucks)
    }

    private fun updateNativeSimulationFrame() {
        if (!nativeRunning || nativeTablePtr == 0L) {
            return
        }

        ShuffleNativePhysics.setShuffleTraceContext(
            tablePtr = nativeTablePtr,
            runId = nativeTraceRunId,
            shotIndex = nativeTraceShotIndex,
            frame = nativeTraceFrame,
            phase = "worldStep",
        )

        val moving = ShuffleNativePhysics.updateShuffle(
            tablePtr = nativeTablePtr,
        )

        syncNativePucksFromOutputs()

        nativeTraceFrame++

        if (moving) {
            postInvalidateOnAnimation()
            return
        }

        val completedRunId = nativeTraceRunId

        val completedReplayHash = nativeTraceHash

        val completedTraceInput = nativeTraceInput

        val completedFrameCount = nativeTraceFrame

        val finalNativePucksForTrace = buildTracePuckArray()

        nativeRunning = false

        stopPushStickAnimation()
        stopOpponentPositionReveal()

        orderSettledPucksMostRecentFirst()

        pendingReplayPrefix = if (currentRoundStartBoard.isNotBlank()) {
            "$currentRoundStartBoard|shoot:1|"
        } else {
            ""
        }

        replay = buildBoardSegment(
            pucks,
        )

        val settledBoardForTrace = replay

        showReplayArrows = false

        replayArrowAlpha = 0f

        OpenPigeonLog.i(
            "ShuffleTrace",
            "SHUFFLE_ANDROID_RUN_END=" + JSONObject().put(
                    "runId",
                    completedRunId,
                ).put(
                    "replayHash",
                    completedReplayHash,
                ).put(
                    "frames",
                    completedFrameCount,
                ).put(
                    "input",
                    completedTraceInput,
                ).put(
                    "finalBoard",
                    settledBoardForTrace,
                ).put(
                    "pucks",
                    finalNativePucksForTrace,
                ).toString(),
        )

        ShuffleNativePhysics.clearShuffleTraceContext(
            nativeTablePtr,
        )

        val allPucksPlayed = haveAllPucksBeenPlayed()

        OpenPigeonLog.i(
            "ShuffleRenderer",
            "Native shuffle stopped " + "runId=$completedRunId " + "replayHash=$completedReplayHash " + "frames=$completedFrameCount " + "allPlayed=$allPucksPlayed " + "pucks=${pucks.size} " + "prefixLen=${pendingReplayPrefix.length} " + "finalBoard=${
                settledBoardForTrace.take(300)
            }",
        )

        nativeTraceRunId = ""

        nativeTraceHash = ""

        nativeTraceInput = ""

        nativeTraceFrame = 0

        if (allPucksPlayed) {
            startWallAnimation(
                reversed = true,
                onFinished = {
                    startScoreAnimation()
                },
            )

            return
        }

        val callback = nativeRoundFinished

        nativeRoundFinished = null

        startWallAnimation(
            reversed = true,
            onFinished = {
                setTopHudVisible(
                    true,
                )

                uiMode = ShuffleUiMode.Aiming

                callback?.invoke()

                invalidate()
            },
        )
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

    private fun buildBoardSegment(
        boardPucks: List<ShufflePuck>,
    ): String {
        return buildString {
            append("board:")
            append(score1)
            append(",")
            append(score2)

            boardPucks.forEach { puck ->
                appendReplayPuck(puck)
            }
            append("#")
        }
    }

    private fun buildLaunchBoardReplay(
        shotAngleRad: Float,
        shotDistance: Float,
    ): String {
        val visualReadyX = cuePuckXNorm * READY_PUCK_X_LIMIT

        val readyX = visualXToWorld(
            visualReadyX,
        )

        val readyY = readyYForPlayer(
            localPlayer,
        )

        val outputPucks = mutableListOf<ShufflePuck>()

        var wroteLocalReadyPuck = false

        for (puck in pucks) {
            val outputPuck = if (isPuckOnReadyRowForPlayer(
                    puck = puck,
                    player = localPlayer,
                )
            ) {
                wroteLocalReadyPuck = true

                puck.copy(
                    x = readyX,
                    y = readyY,
                    bodyAngle = 0f,
                    shotAngle = shotAngleRad,
                    shotDistance = shotDistance,
                    velocityX = 0f,
                    velocityY = 0f,
                )
            } else {
                puck
            }

            outputPucks += outputPuck
        }

        if (!wroteLocalReadyPuck) {
            outputPucks += ShufflePuck(
                x = readyX,
                y = readyY,
                player = localPlayer,
                bodyAngle = 0f,
                shotAngle = shotAngleRad,
                shotDistance = shotDistance,
                velocityX = 0f,
                velocityY = 0f,
            )
        }

        val opponent = opponentPlayer()

        val hasOpponentReadyPuck = outputPucks.any { puck ->
            isPuckOnReadyRowForPlayer(
                puck = puck,
                player = opponent,
            )
        }

        if (!hasOpponentReadyPuck) {
            outputPucks += ShufflePuck(
                x = 0f,
                y = readyYForPlayer(
                    opponent,
                ),
                player = opponent,
                bodyAngle = 0f,
                shotAngle = 0f,
                shotDistance = 0f,
                velocityX = 0f,
                velocityY = 0f,
            )
        }

        val currentBoard = buildBoardSegment(
            outputPucks,
        )

        val stagedReplay = buildString {
            if (pendingReplayPrefix.isNotBlank()) {
                append(
                    pendingReplayPrefix,
                )
            }

            append(
                currentBoard,
            )

            append("|")

            append(
                currentBoard,
            )
        }

        OpenPigeonLog.i(
            "ShuffleRenderer",
            "Built launch replay " + "localPlayer=$localPlayer " + "endsWithPipe=${
                stagedReplay.endsWith("|")
            } " + "length=${stagedReplay.length} " + "replay=${stagedReplay.take(420)}",
        )

        return stagedReplay
    }

    private fun readyYForPlayer(player: Int): Float {
        return if (player == 2) {
            READY_PUCK_PLAYER2_Y
        } else {
            READY_PUCK_PLAYER1_Y
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
            java.util.Locale.US, "%.6f", value
        )
    }

    private fun derivedUsedPuckCountForPlayer(
        player: Int,
    ): Int {
        val normalizedPlayer = player.coerceIn(
            1,
            2,
        )

        return pucks.count { puck ->
            puck.player == normalizedPlayer && !isPuckOnReadyRowForPlayer(
                puck = puck,
                player = normalizedPlayer,
            )
        }.coerceIn(
            0,
            PUCKS_PER_PLAYER,
        )
    }

    private fun rebuildCommittedUsedPuckCounts() {
        for (player in 1..2) {
            committedUsedPucksByPlayer[player] = derivedUsedPuckCountForPlayer(
                player,
            )
        }
    }


    private fun commitCurrentRoundShots() {
        for (puck in pucks) {
            if (puck.shotDistance > SHOT_DISTANCE_EPS) {
                val player = puck.player.coerceIn(
                    1,
                    2,
                )

                committedUsedPucksByPlayer[player] = maxOf(
                    committedUsedPucksByPlayer[player],
                    derivedUsedPuckCountForPlayer(
                        player,
                    ),
                ).coerceIn(
                    0,
                    PUCKS_PER_PLAYER,
                )
            }
        }
    }

    private fun usedPuckCountForPlayer(
        player: Int,
    ): Int {
        val normalizedPlayer = player.coerceIn(
            1,
            2,
        )

        val derivedCount = derivedUsedPuckCountForPlayer(
            normalizedPlayer,
        )

        return maxOf(
            committedUsedPucksByPlayer[normalizedPlayer],
            derivedCount,
        ).coerceIn(
            0,
            PUCKS_PER_PLAYER,
        )
    }

    private fun reservePuckCountForLocalPlayer(): Int {
        val usedOnBoard = usedPuckCountForPlayer(
            localPlayer,
        )

        val currentRoundPuckAllocated = when {
            uiMode == ShuffleUiMode.Aiming -> {
                1
            }

            hasShotForPlayer(
                localPlayer,
            ) -> {
                1
            }

            else -> {
                0
            }
        }

        return (PUCKS_PER_PLAYER - usedOnBoard - currentRoundPuckAllocated).coerceIn(
            0,
            PUCKS_PER_PLAYER,
        )
    }

    private fun drawReservePucks(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        alpha: Float,
    ) {
        if (alpha <= 0.001f) {
            return
        }

        val remaining = reservePuckCountForLocalPlayer()

        if (remaining <= 0) {
            return
        }

        val size = dp(18f)

        val horizontalOffset = dp(9f)

        val verticalOffset = dp(8f)

        when (remaining) {
            4 -> {
                drawPuck(
                    canvas = canvas,
                    cx = cx - horizontalOffset,
                    cy = cy - verticalOffset,
                    player = localPlayer,
                    rotation = 0f,
                    size = size,
                    alpha = alpha,
                )

                drawPuck(
                    canvas = canvas,
                    cx = cx + horizontalOffset,
                    cy = cy - verticalOffset,
                    player = localPlayer,
                    rotation = 0f,
                    size = size,
                    alpha = alpha,
                )

                drawPuck(
                    canvas = canvas,
                    cx = cx - horizontalOffset,
                    cy = cy + verticalOffset,
                    player = localPlayer,
                    rotation = 0f,
                    size = size,
                    alpha = alpha,
                )

                drawPuck(
                    canvas = canvas,
                    cx = cx + horizontalOffset,
                    cy = cy + verticalOffset,
                    player = localPlayer,
                    rotation = 0f,
                    size = size,
                    alpha = alpha,
                )
            }

            3 -> {
                drawPuck(
                    canvas = canvas,
                    cx = cx,
                    cy = cy - dp(9f),
                    player = localPlayer,
                    rotation = 0f,
                    size = size,
                    alpha = alpha,
                )

                drawPuck(
                    canvas = canvas,
                    cx = cx - dp(10f),
                    cy = cy + dp(8f),
                    player = localPlayer,
                    rotation = 0f,
                    size = size,
                    alpha = alpha,
                )

                drawPuck(
                    canvas = canvas,
                    cx = cx + dp(10f),
                    cy = cy + dp(8f),
                    player = localPlayer,
                    rotation = 0f,
                    size = size,
                    alpha = alpha,
                )
            }

            2 -> {
                drawPuck(
                    canvas = canvas,
                    cx = cx - dp(9f),
                    cy = cy,
                    player = localPlayer,
                    rotation = 0f,
                    size = size,
                    alpha = alpha,
                )

                drawPuck(
                    canvas = canvas,
                    cx = cx + dp(9f),
                    cy = cy,
                    player = localPlayer,
                    rotation = 0f,
                    size = size,
                    alpha = alpha,
                )
            }

            1 -> {
                drawPuck(
                    canvas = canvas,
                    cx = cx,
                    cy = cy,
                    player = localPlayer,
                    rotation = 0f,
                    size = size,
                    alpha = alpha,
                )
            }
        }
    }

    private fun updateAimHaptic() {
        val currentStep = (cueAimDist / AIM_HAPTIC_STEP_DISTANCE).toInt()

        if (currentStep == lastAimHapticStep) {
            return
        }

        lastAimHapticStep = currentStep

        performHapticFeedback(
            HapticFeedbackConstants.VIRTUAL_KEY,
            HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING,
        )
    }

    private fun calculateBoardRect(
        w: Float, h: Float
    ): RectF {
        val boardWidth = min(
            w - dp(32f), h * 0.46f
        )

        val boardHeight = boardWidth * BOARD_ASPECT_HEIGHT_OVER_WIDTH
        val left = (w - boardWidth) * 0.5f

        val availableTop = dp(44f)
        val availableBottom = h - dp(150f)
        val availableHeight = (availableBottom - availableTop).coerceAtLeast(boardHeight)

        val top = availableTop + ((availableHeight - boardHeight) * 0.5f)

        return RectF(
            left, top, left + boardWidth, top + boardHeight
        )
    }

    private fun cuePuckScreenX(boardRect: RectF): Float {
        return boardRect.centerX() + cuePuckXNorm * size(READY_PUCK_X_LIMIT, boardRect)
    }

    private fun updateCueDragFromTouch(
        touchX: Float,
        touchY: Float,
        boardRect: RectF,
    ) {
        val gameY = screenToGameY(
            touchY,
            boardRect,
        )

        if (gameY <= READY_PUCK_PLAYER1_Y + READY_ROW_DRAG_PAD) {
            updateCuePositionFromGameX(
                screenToGameX(
                    touchX,
                    boardRect,
                ),
            )

            return
        }

        updateCueAimFromScreenTouch(
            touchX = touchX,
            touchY = touchY,
            boardRect = boardRect,
        )
    }

    private fun updateCuePositionFromGameX(
        gameX: Float,
    ) {
        cuePuckXNorm = (gameX / READY_PUCK_X_LIMIT).coerceIn(
            -1f,
            1f,
        )
    }

    private fun cueAimLengthPx(boardRect: RectF): Float {
        return size(
            cueAimDist.coerceIn(MIN_AIM_VISUAL_LENGTH, MAX_AIM_DISTANCE), boardRect
        )
    }

    private fun stopScoreAnimation() {
        scoreAnimationActive = false
        scoreAnimationStartMs = 0L
        scoreAnimationAppliedCount = 0
        scoreAnimationItems = emptyList()
    }


    private fun haveAllPucksBeenPlayed(): Boolean {
        for (player in 1..2) {
            val playedCount = pucks.count { puck ->
                puck.player == player && !isPuckOnReadyRowForPlayer(
                    puck = puck,
                    player = player,
                )
            }

            if (playedCount < PUCKS_PER_PLAYER) {
                return false
            }
        }

        return true
    }


    private fun startScoreAnimation() {
        stopPushStickAnimation()
        stopScoreAnimation()
        setTopHudVisible(true)

        scoreAnimationItems = pucks.indices.map { puckIndex ->
            val puck = pucks[puckIndex]

            ScoreAnimationItem(
                puckIndex = puckIndex,
                player = puck.player,
                score = scoreForSettledPuck(puck),
            )
        }

        scoreAnimationAppliedCount = 0
        scoreAnimationStartMs = System.currentTimeMillis()

        scoreAnimationActive = scoreAnimationItems.isNotEmpty()

        showReplayArrows = false
        replayArrowAlpha = 0f

        cancelWallAnimation()

        OpenPigeonLog.i(
            "ShuffleRenderer",
            "Score animation started " + "items=${
                scoreAnimationItems.joinToString { item ->
                    "index=${item.puckIndex},p=${item.player},score=${item.score}"
                }
            }",
        )

        if (!scoreAnimationActive) {
            finishScoreAnimation()
            return
        }

        postInvalidateOnAnimation()
    }

    private fun applyScoreItem(
        item: ScoreAnimationItem,
    ) {
        if (item.player == 1) {
            score1 += item.score
        } else {
            score2 += item.score
        }

        if (!spectatorMode && item.player == localPlayer && item.score > 0) {
            val flags = HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING

            val confirmed = performHapticFeedback(
                HapticFeedbackConstants.CONFIRM,
                flags,
            )

            if (!confirmed) {
                performHapticFeedback(
                    HapticFeedbackConstants.VIRTUAL_KEY,
                    flags,
                )
            }
        }
    }

    private fun updateScoreAnimation() {
        if (!scoreAnimationActive || scoreAnimationStartMs <= 0L) {
            return
        }

        val now = System.currentTimeMillis()

        val elapsed = (now - scoreAnimationStartMs).coerceAtLeast(0L)

        while (scoreAnimationAppliedCount < scoreAnimationItems.size) {
            val itemIndex = scoreAnimationAppliedCount

            val itemCommitTime =
                SCORE_ANIMATION_INITIAL_DELAY_MS + itemIndex * SCORE_ANIMATION_ITEM_STEP_MS + (SCORE_ANIMATION_ITEM_DURATION_MS * SCORE_HUD_COMMIT_PROGRESS).toLong()

            if (elapsed < itemCommitTime) {
                break
            }

            val item = scoreAnimationItems[itemIndex]

            applyScoreItem(
                item,
            )

            scoreAnimationAppliedCount++

            OpenPigeonLog.i(
                "ShuffleRenderer",
                "Applied puck score " + "index=${item.puckIndex} " + "player=${item.player} " + "score=${item.score} " + "totals=$score1,$score2",
            )
        }

        val totalDuration =
            scoreCountSequenceEndElapsedMs() + SCORE_POST_COUNT_HOLD_MS + SCORE_CLEANUP_DURATION_MS

        if (elapsed >= totalDuration) {
            finishScoreAnimation()
            return
        }

        postInvalidateOnAnimation()
    }

    private fun scoreForSettledPuck(
        puck: ShufflePuck,
    ): Int {
        val segments = shuffleSegmentSpecs(
            layoutMode,
        )

        if (segments.isEmpty()) {
            return 0
        }

        val sampleCounts = IntArray(
            segments.size,
        )

        var totalPuckSamples = 0
        var samplesInsideBoard = 0

        for (gridY in -PUCK_SCORE_SAMPLE_GRID_RADIUS..PUCK_SCORE_SAMPLE_GRID_RADIUS) {
            val offsetY =
                PUCK_RADIUS_GAME * gridY.toFloat() / PUCK_SCORE_SAMPLE_GRID_RADIUS.toFloat()

            for (gridX in -PUCK_SCORE_SAMPLE_GRID_RADIUS..PUCK_SCORE_SAMPLE_GRID_RADIUS) {
                val offsetX =
                    PUCK_RADIUS_GAME * gridX.toFloat() / PUCK_SCORE_SAMPLE_GRID_RADIUS.toFloat()

                if (offsetX * offsetX + offsetY * offsetY > PUCK_RADIUS_GAME * PUCK_RADIUS_GAME) {
                    continue
                }

                totalPuckSamples++

                val sampleX = puck.x + offsetX

                val sampleY = puck.y + offsetY

                var matchedBoard = false

                for (segmentIndex in segments.indices) {
                    if (pointIsInsidePolygon(
                            x = sampleX,
                            y = sampleY,
                            points = segments[segmentIndex].points,
                        )
                    ) {
                        sampleCounts[segmentIndex]++

                        matchedBoard = true
                    }
                }

                if (matchedBoard) {
                    samplesInsideBoard++
                }
            }
        }

        if (totalPuckSamples <= 0) {
            return 0
        }

        val boardCoverage = samplesInsideBoard.toFloat() / totalPuckSamples.toFloat()

        if (boardCoverage < PUCK_MIN_BOARD_COVERAGE) {
            return 0
        }

        val centerSegment = segments.indices.firstOrNull { segmentIndex ->
            pointIsInsidePolygon(
                x = puck.x,
                y = puck.y,
                points = segments[segmentIndex].points,
            )
        }

        var bestSegment = centerSegment ?: 0

        var bestCount = sampleCounts[bestSegment]

        for (segmentIndex in sampleCounts.indices) {
            val count = sampleCounts[segmentIndex]

            if (count > bestCount) {
                bestCount = count
                bestSegment = segmentIndex
            }
        }

        if (bestCount <= 0) {
            return 0
        }

        val defaults = defaultMapScoresForMode(
            layoutMode,
        )

        return mapScores.getOrNull(
            bestSegment,
        ) ?: defaults.getOrNull(
            bestSegment,
        ) ?: 0
    }


    private fun pointIsInsidePolygon(
        x: Float,
        y: Float,
        points: List<Pair<Float, Float>>,
    ): Boolean {
        if (points.size < 3) {
            return false
        }

        var inside = false
        var previousIndex = points.lastIndex

        for (currentIndex in points.indices) {
            val current = points[currentIndex]

            val previous = points[previousIndex]

            val currentX = current.first

            val currentY = current.second

            val previousX = previous.first

            val previousY = previous.second

            val crossesY = (currentY > y) != (previousY > y)

            if (crossesY) {
                val intersectionX =
                    (previousX - currentX) * (y - currentY) / (previousY - currentY) + currentX

                if (x < intersectionX) {
                    inside = !inside
                }
            }

            previousIndex = currentIndex
        }

        return inside
    }

    private fun finishScoreAnimation() {
        while (scoreAnimationAppliedCount < scoreAnimationItems.size) {
            val item = scoreAnimationItems[scoreAnimationAppliedCount]

            applyScoreItem(
                item,
            )

            scoreAnimationAppliedCount++
        }

        OpenPigeonLog.i(
            "ShuffleRenderer",
            "Score animation finished " + "score1=$score1 score2=$score2",
        )

        stopScoreAnimation()
        stopOpponentPositionReveal()

        pucks.clear()

        committedUsedPucksByPlayer.fill(
            0,
        )

        replay = buildBoardSegment(
            pucks,
        )

        uiMode = when {
            hasGameEnded() -> {
                ShuffleUiMode.GameOver
            }

            spectatorMode -> {
                ShuffleUiMode.Spectating
            }

            else -> {
                ShuffleUiMode.Aiming
            }
        }

        val callback = nativeRoundFinished

        nativeRoundFinished = null

        callback?.invoke()

        invalidate()
    }

    private fun scoreCountSequenceEndElapsedMs(): Long {
        return if (scoreAnimationItems.isEmpty()) {
            SCORE_ANIMATION_INITIAL_DELAY_MS
        } else {
            SCORE_ANIMATION_INITIAL_DELAY_MS + (scoreAnimationItems.size - 1) * SCORE_ANIMATION_ITEM_STEP_MS + SCORE_ANIMATION_ITEM_DURATION_MS
        }
    }


    private fun scoreCleanupProgress(
        nowMs: Long,
    ): Float {
        if (!scoreAnimationActive || scoreAnimationStartMs <= 0L) {
            return 0f
        }

        val cleanupStartMs =
            scoreAnimationStartMs + scoreCountSequenceEndElapsedMs() + SCORE_POST_COUNT_HOLD_MS

        return ((nowMs - cleanupStartMs).toFloat() / SCORE_CLEANUP_DURATION_MS.toFloat()).coerceIn(
            0f,
            1f,
        )
    }

    private fun scoreAnimationProgress(
        itemIndex: Int,
        nowMs: Long,
    ): Float {
        if (!scoreAnimationActive || scoreAnimationStartMs <= 0L) {
            return 0f
        }

        val itemStart =
            scoreAnimationStartMs + SCORE_ANIMATION_INITIAL_DELAY_MS + itemIndex * SCORE_ANIMATION_ITEM_STEP_MS

        return ((nowMs - itemStart).toFloat() / SCORE_ANIMATION_ITEM_DURATION_MS.toFloat()).coerceIn(
            0f,
            1f,
        )
    }

    private fun stopPushStickAnimation() {
        pushStickActive = false
        pushStickStartMs = 0L
        pushStickPushStartMs = 0L
        pushStickStates = emptyList()
    }

    private fun screenToGameX(
        screenX: Float, boardRect: RectF
    ): Float {
        return (screenX - boardRect.centerX()) / sceneScale(boardRect)
    }

    private fun screenToGameY(
        screenY: Float, boardRect: RectF
    ): Float {
        return (boardRect.centerY() - screenY) / sceneScale(boardRect)
    }

    private fun puckScreenX(
        gameX: Float, boardRect: RectF
    ): Float {
        return boardRect.centerX() + gameX * sceneScale(boardRect)
    }

    private fun puckScreenY(
        gameY: Float, boardRect: RectF
    ): Float {
        return boardRect.centerY() - gameY * sceneScale(boardRect)
    }

    private fun size(
        points: Float, boardRect: RectF
    ): Float {
        return points * sceneScale(boardRect)
    }

    private fun pucksize(boardRect: RectF): Float {
        return size(32f, boardRect)
    }

    private fun readyPuckScreenY(
        player: Int,
        boardRect: RectF,
    ): Float {
        val readyWorldY = readyYForPlayer(
            player,
        )

        val readyVisualY = worldYToVisual(
            readyWorldY,
        )

        return puckScreenY(
            readyVisualY,
            boardRect,
        )
    }

    private fun topOutOfPlayPuckY(
        boardRect: RectF,
    ): Float {
        return readyPuckScreenY(
            player = opponentPlayer(),
            boardRect = boardRect,
        )
    }


    private fun bottomOutOfPlayPuckY(
        boardRect: RectF,
    ): Float {
        return readyPuckScreenY(
            player = localPlayer,
            boardRect = boardRect,
        )
    }

    private fun parseReplay(replayValue: String?) {
        pucks.clear()

        val latestBoard =
            replayValue?.split("|")?.lastOrNull { it.startsWith("board:") } ?: DEFAULT_REPLAY

        val boardPayload = latestBoard.removePrefix("board:")
        val chunks = boardPayload.split("#").map { it.trim() }.filter { it.isNotEmpty() }

        if (chunks.isNotEmpty()) {
            val scoreParts = chunks[0].split(",").mapNotNull { it.trim().toIntOrNull() }

            score1 = scoreParts.getOrNull(0) ?: 0
            score2 = scoreParts.getOrNull(1) ?: 0
        }

        for (chunk in chunks.drop(1)) {
            val values = chunk.split(",").mapNotNull { it.trim().toFloatOrNull() }

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
                    x = 0f, y = -215f, player = 1, bodyAngle = 0f, shotAngle = 0f, shotDistance = 0f
                )
            )

            pucks.add(
                ShufflePuck(
                    x = 0f, y = 215f, player = 2, bodyAngle = 0f, shotAngle = 0f, shotDistance = 0f
                )
            )
        }

        rebuildCommittedUsedPuckCounts()
        syncCuePositionFromReadyPuck()
    }

    private fun loadAssets() {
        puck1Bitmap = loadAssetBitmap(
            "shuffle/shuffle_puck1_Normal@3x.png",
            "shuffle_puck1_Normal@3x.png",
        )

        puck2Bitmap = loadAssetBitmap(
            "shuffle/shuffle_puck2_Normal@3x.png",
            "shuffle_puck2_Normal@3x.png",
        )

        puckShadowBitmap = loadAssetBitmap(
            "shuffle/shuffle_puck_shadow_Normal@3x.png",
            "shuffle_puck_shadow_Normal@3x.png",
        )

        bumperBitmap = loadAssetBitmap(
            "shuffle/shuffle_bumper_Normal@3x.png",
            "shuffle_bumper_Normal@3x.png",
        )

        bumperShadowBitmap = loadAssetBitmap(
            "shuffle/shuffle_bumper_shadow_Normal@3x.png",
            "shuffle_bumper_shadow_Normal@3x.png",
        )

        val loadedStick = loadAssetBitmap(
            "shuffle/shuffle_stick_Normal@3x.png",
            "shuffle_stick_Normal@3x.png",
        )

        stickBitmap = if (loadedStick != null) {
            sanitizeStickBitmap(
                loadedStick,
            )
        } else {
            null
        }
    }

    private fun sanitizeStickBitmap(
        source: Bitmap,
    ): Bitmap {
        val width = source.width

        val height = source.height

        val pixels = IntArray(
            width * height,
        )

        source.getPixels(
            pixels,
            0,
            width,
            0,
            0,
            width,
            height,
        )

        var removedPixelCount = 0

        for (index in pixels.indices) {
            val pixel = pixels[index]

            val alpha = Color.alpha(
                pixel,
            )

            val red = Color.red(
                pixel,
            )

            val green = Color.green(
                pixel,
            )

            val blue = Color.blue(
                pixel,
            )

            val darkestChannelMaximum = maxOf(
                red,
                green,
                blue,
            )

            val shouldRemove =
                alpha <= STICK_ZERO_ALPHA_CUTOFF || (alpha <= STICK_DARK_ALPHA_CUTOFF && darkestChannelMaximum <= STICK_DARK_RGB_CUTOFF)

            if (shouldRemove) {
                pixels[index] = Color.TRANSPARENT

                removedPixelCount++
            }
        }

        OpenPigeonLog.i(
            "ShuffleRenderer",
            "Sanitized stick bitmap " + "size=${width}x$height " + "removedPixels=$removedPixelCount",
        )

        return Bitmap.createBitmap(
            pixels,
            width,
            height,
            Bitmap.Config.ARGB_8888,
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
                            "ShuffleRenderer", "Loaded asset $path ${bitmap.width}x${bitmap.height}"
                        )

                        return bitmap
                    }
                }
            } catch (_: Exception) {
                // Try next path.
            }
        }

        OpenPigeonLog.w(
            "ShuffleRenderer", "Could not load asset paths=${paths.joinToString()}"
        )

        return null
    }

    private fun dp(value: Float): Float {
        return value * density
    }

    private companion object {
        private const val BOARD_WIDTH = 380f
        private const val BOARD_HEIGHT = 410f

        private const val PUCKS_PER_PLAYER = 4

        private const val AIM_UI_FADE_DURATION_MS = 280L

        private const val HIGHLIGHT_PULSE_PERIOD_MS = 900L
        private const val HIGHLIGHT_PULSE_MAX_SCALE = 1.10f

        private const val BOARD_ASPECT_HEIGHT_OVER_WIDTH = BOARD_HEIGHT / BOARD_WIDTH
        private const val AIM_HAPTIC_STEP_DISTANCE = 4f

        private const val MIN_AIM_DISTANCE = 8f
        private const val MIN_AIM_VISUAL_LENGTH = 8f
        private const val MAX_AIM_DISTANCE = 560f

        private const val BOTTOM_CONTROL_SIZE_DP = 48f

        private const val BOTTOM_CONTROL_BOTTOM_MARGIN_DP = 16f

        //  ready puck movement/selection constants from ShuffleScene touch handling.
        private const val READY_PUCK_X_LIMIT = 159f
        private const val READY_PUCK_PICK_RADIUS = 35f
        private const val READY_PUCK_PLAYER1_Y = -215f
        private const val READY_PUCK_PLAYER2_Y = 215f
        private const val SHOT_DISTANCE_EPS = 0.001f
        private const val ARROW_MAX_ALPHA = 0.80f
        private const val STICK_APPROACH_DURATION_MS = 1000L
        private const val STICK_CONTACT_HOLD_DURATION_MS = 500L
        private const val STICK_PUSH_MOVE_DURATION_MS = 150L
        private const val STICK_PUSH_TRAVEL_GAME = 14f
        private const val STICK_PUSH_FADE_DURATION_MS = 230L
        private const val STICK_ZERO_ALPHA_CUTOFF = 3
        private const val STICK_DARK_ALPHA_CUTOFF = 72
        private const val STICK_DARK_RGB_CUTOFF = 96

        private const val STICK_WIDTH_GAME = 240f
        private const val STICK_START_OFFSET_GAME = 36f
        private const val STICK_FORK_FORWARD_OFFSET_GAME = 2f
        private const val OPPONENT_POSITION_REVEAL_DURATION_MS = 420L
        private const val WALL_INTRO_AFTER_STICK_GAP_MS = 40L
        private const val WALL_INTRO_DURATION_MS = 520L
        private const val WALL_INTRO_START_SCALE = 1.50f
        private const val WALL_EXIT_FADE_START_PROGRESS = 0.12f
        private const val WALL_EXIT_FADE_END_PROGRESS = 0.58f
        private const val PUCK_RADIUS_GAME = 15f
        private const val NATIVE_TRACE_ENABLED = true
        private const val READY_PUCK_Y_TOLERANCE = 2f
        private const val READY_ROW_DRAG_PAD = 10f
        private const val SCORE_ANIMATION_INITIAL_DELAY_MS = 220L
        private const val SCORE_ANIMATION_ITEM_DURATION_MS = 440L
        private const val SCORE_ANIMATION_ITEM_STEP_MS = 500L
        private const val SCORE_POST_COUNT_HOLD_MS = 500L

        private const val SCORE_CLEANUP_DURATION_MS = 320L
        private const val SCORE_HUD_COMMIT_PROGRESS = 0.52f
        private const val PUCK_SCORE_SAMPLE_GRID_RADIUS = 6
        private const val PUCK_MIN_BOARD_COVERAGE = 0.50f
        private const val TOP_HUD_FADE_DURATION_MS = 220L
        private const val BOARD_BORDER_GAME = 12f

        private const val WALL_LINE_WIDTH_GAME = 1.4f
        private const val WINNING_SCORE = 50

        private val BOARD_WALL_COLOR = Color.rgb(
            238,
            242,
            245,
        )

        private val DEFAULT_MAP_SCORES_MODE_1 = listOf(
            5, 10, 5, 2, 3, 10, 6, 3, 2, 5, 3, 6
        )

        private val DEFAULT_MAP_SCORES_MODE_2 = listOf(
            6, 5, 8, 10, 10, 8, 5, 6, 6, 5, 6, 2, 5, 2, 7, 3
        )

        private val DEFAULT_MAP_SCORES_MODE_3 = listOf(
            3, 2, 5, 10, 7, 7, 6, 5, 6, 4, 7, 8, 6, 10, 4, 4, 4, 8, 5, 3, 5
        )

        private const val DEFAULT_REPLAY =
            "board:0,0#" + "0.000000,-215.000000,1,0.000000,0.000000,0.000000#" + "0.000000,215.000000,2,0.000000,0.000000,0.000000#"
    }
}