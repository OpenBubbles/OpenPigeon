package com.openbubbles.openpigeon.golf

import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.Window
import android.widget.FrameLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import com.openbubbles.openpigeon.godot.GameSessionIPC
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog
import android.graphics.PointF
import androidx.appcompat.widget.AppCompatImageButton
import android.graphics.BitmapFactory
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.os.Handler
import android.os.Looper
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import kotlin.math.ceil
import android.graphics.Bitmap
import android.widget.ImageView
import android.graphics.Canvas
import android.graphics.Paint
import android.view.HapticFeedbackConstants
import android.widget.LinearLayout
import android.view.ViewGroup
import androidx.core.view.WindowInsetsCompat
import android.view.animation.OvershootInterpolator
import com.openbubbles.openpigeon.ui.RulesPopup
import android.content.Context
import android.util.TypedValue
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import com.openbubbles.openpigeon.ui.GameMenuController
import com.openbubbles.openpigeon.ui.GameMenuPlacement
import com.openbubbles.openpigeon.settings.AvatarWinBurstController
import com.openbubbles.openpigeon.ui.TurnRecoveryOverlayController
import com.openbubbles.openpigeon.ui.attachTurnRecoveryOverlay

@SuppressLint("SetTextI18n")
class GolfActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "GolfNative"

        private const val LAYER_HUD = 900f
        private const val LAYER_SKIP_REPLAY = 1100f

        private const val MUSIC_TRACK_PATH = "golf/golf.wav"
        private const val LAYER_WAITING = 14000f
        private const val LAYER_INTRO = 15000f
        private var debugGolfReplayTraceAuto = false
        private var debugGolfReplayTraceFull = true
        private var debugGolfReplayTraceIosAnchors = false

        private const val DEBUG_VISUAL_TRACE_FRAME_DELAY_MS = 16L
        private const val DEBUG_VISUAL_TRACE_MAX_FRAMES_PER_SHOT = 1200

        private const val STATE_LAST_AUTO_REPLAY_KEY = "golf_last_auto_replay_key"
        private const val STATE_MAP_NUM = "golf_map_num"
        private const val STATE_SEED = "golf_seed"
        private const val STATE_MODE = "golf_mode"
        private const val STATE_HOLE_COUNT = "golf_hole_count"
        private const val STATE_WAITING_FOR_OPPONENT = "golf_waiting_for_opponent"
        private const val STATE_ROUND_RESULT_SENT = "golf_round_result_sent"
    }

    private lateinit var root: FrameLayout
    private lateinit var renderer: GolfRenderer
    private lateinit var stateLabel: TextView
    private lateinit var holeOverlay: FrameLayout
    private lateinit var holeIntroContainer: LinearLayout
    private lateinit var holePoleImage: ImageView
    private lateinit var holeTitle: TextView
    private lateinit var zoomButton: AppCompatImageButton
    private lateinit var settingsButton: AppCompatImageButton
    private lateinit var gameMenu: GameMenuController

    private lateinit var turnRecoveryOverlay: TurnRecoveryOverlayController
    private val recoveryHandler = Handler(Looper.getMainLooper())
    private var recoveryCheckRunnable: Runnable? = null
    private var recoveryRetryInFlight = false
    private var lastShotStartCourse: PointF? = null
    private val lastShotVelocityCourse = PointF(0f, 0f)
    private var restoringLastShot = false
    private var recoverySettledBallCourse: PointF? = null

    private lateinit var debugMenuItem: TextView
    private var debugUiEnabled = false

    private lateinit var gameAvatarAnchor: FrameLayout
    private lateinit var oppAvatarAnchor: FrameLayout
    private lateinit var avatarWinBurstController: AvatarWinBurstController
    private lateinit var localAvatarYouLabel: TextView
    private lateinit var spectatorLabel: TextView

    private lateinit var localStrokeCounterView: FrameLayout
    private lateinit var opponentStrokeCounterView: FrameLayout

    private lateinit var localStrokeCounterBg: ImageView
    private lateinit var opponentStrokeCounterBg: ImageView

    private lateinit var localStrokeLabel: TextView
    private lateinit var opponentStrokeLabel: TextView
    private lateinit var waitingOverlay: FrameLayout
    private lateinit var waitingLabel: TextView
    private lateinit var skipReplayButton: AppCompatImageButton
    private var lastReplayTraceKey = ""
    private var skipReplayNormalBitmap: Bitmap? = null
    private var skipReplayPressedBitmap: Bitmap? = null
    private lateinit var aimInstructionLabel: TextView
    private lateinit var gameOverLabel: TextView
    private var gameOverShown = false
    private var gameContentShown = false

    private var topHudInsetPx = 0

    private val avatarBarTopPaddingDp = 6
    private val tallAvatarTopPaddingDp = 43
    private val avatarBarSidePaddingDp = 12

    private val generator = GolfMapGenerator()
    private var gameSessionIPC: GameSessionIPC? = null
    private var sessionId: String = ""
    private var lastMessage: Map<String, String> = emptyMap()
    private var gameData: GolfGameData? = null

    private var currentMap: GolfMap? = null
    private var lastRenderedKey: String = ""
    private var lastRenderedSender: String = ""
    private var lastRenderedWinner: String = ""

    private var pendingGameOverForcedResult: Int? = null
    private var pendingGameOverShouldSendWinner = false

    private var seed: Int = GolfConstants.DEFAULT_SEED
    private var mode: String = GolfConstants.DEFAULT_MODE
    private var holeCount: Int = 3
    private var mapNum: Int = 0
    private var player: Int = 1
    private var player1Id: String = ""
    private var player2Id: String = ""
    private var localReplay: String = ""

    private var runtimeBallCourse: PointF? = null
    private val runtimeVelocityCourse = PointF(0f, 0f)
    private var flagPulled = false
    private var ballInHole = false

    private var isAiming = false
    private var aimMoveStartVisual = PointF(0f, 0f)
    private var activeAim: GolfShot.Aim = GolfShot.Aim.NONE
    private var zoomOverviewEnabled = false
    private var roundResultSent = false
    private var waitingForOpponent = false
    private var spectatorMode = false
    private var activityExiting = false

    private val stateLabelHandler = Handler(Looper.getMainLooper())
    private var waitingDotsRunnable: Runnable? = null
    private var stateLabelAnimator: ValueAnimator? = null
    private var sentWaitingSequenceActive = false
    private var lastAimHapticMs = 0L
    private var lastAimHapticBucket = -1

    private var dualReplayRunning = false
    private var dualReplayWaitingToFire = false
    private var dualReplayFireAtMs = 0L
    private var dualReplayLastMs = 0L
    private var dualReplayShotIndex = 0
    private var lastAutoReplayKey = ""
    private var dualReplayPausedByLifecycle = false
    private var dualReplayRemainingFireDelayMs = 0L

    private var dualReplayMineShots: List<GolfReplay.Shot> = emptyList()
    private var dualReplayOpponentShots: List<GolfReplay.Shot> = emptyList()
    private var dualReplayMineDisplayedStrokes = 0
    private var dualReplayOpponentDisplayedStrokes = 0
    private var dualReplayMineBaseStrokes = 0
    private var dualReplayOpponentBaseStrokes = 0
    private var replayStrokeHudLocked = false
    private var dualReplayOpponentBallCourse: PointF? = null
    private val dualReplayMineVelocityCourse = PointF(0f, 0f)
    private val dualReplayOpponentVelocityCourse = PointF(0f, 0f)

    private var dualReplayMineInHole = false
    private var dualReplayOpponentInHole = false
    private var physicsRunning = false
    private var lastPhysicsMs = 0L

    private data class DebugVisualTraceShot(
        val label: String,
        val runIdSuffix: String,
        val shotIndex: Int,
        val dist: Float,
        val rotation: Float,
        val explicitStart: PointF? = null,
        val resetNativeBeforeShot: Boolean = false
    )

    private var debugVisualTraceRunning = false
    private var debugVisualTraceShots: List<DebugVisualTraceShot> = emptyList()
    private var debugVisualTraceShotListIndex = 0
    private var debugVisualTraceFrame = 0
    private var debugVisualTraceCaptured = false
    private var debugVisualTraceCurrent: DebugVisualTraceShot? = null
    private var debugVisualTraceSource = ""
    private var debugVisualTraceRunId = ""

    private var debugVisualTraceSavedBall: PointF? = null
    private val debugVisualTraceSavedVelocity = PointF(0f, 0f)
    private var debugVisualTraceSavedBallInHole = false
    private var debugVisualTraceSavedFlagPulled = false
    private var debugVisualTraceSavedWaitingForOpponent = false
    private var debugVisualTraceSavedRoundResultSent = false
    private var debugVisualTraceSavedZoomOverviewEnabled = false

    private var debugVisualTraceBall = PointF(0f, 0f)
    private val debugVisualTraceVelocity = PointF(0f, 0f)

    private val debugVisualTraceTick = object : Runnable {
        override fun run() {
            stepDebugVisualTrace()

            if (debugVisualTraceRunning) {
                renderer.postDelayed(this, DEBUG_VISUAL_TRACE_FRAME_DELAY_MS)
            }
        }
    }

    private val physicsTick = object : Runnable {
        override fun run() {
            stepBallPhysics()

            if (physicsRunning) {
                renderer.postOnAnimation(this)
            }
        }
    }

    private val dualReplayTick = object : Runnable {
        override fun run() {
            try {
                stepDualReplay()
            } catch (t: Throwable) {
                handleDualReplayError(t)
                return
            }

            if (dualReplayRunning) {
                renderer.postOnAnimation(this)
            }
        }
    }

    private fun setupTurnRecoveryOverlay() {
        turnRecoveryOverlay = attachTurnRecoveryOverlay(root) { retryPendingGolfSend() }
    }

    private fun hideTurnRecoveryRetry() {
        if (::turnRecoveryOverlay.isInitialized) turnRecoveryOverlay.hideRetry()
    }

    private fun showTurnRecoveryRetry() {
        recoveryRetryInFlight = false
        runOnUiThread {
            stopStateLabelAnimation()
            hideAimReadyUi(immediate = true)
            if (::turnRecoveryOverlay.isInitialized) turnRecoveryOverlay.showRetry()
        }
    }

    private fun cancelPendingRecoveryCheck() {
        recoveryCheckRunnable?.let { recoveryHandler.removeCallbacks(it) }
        recoveryCheckRunnable = null
    }

    private fun schedulePendingSendCheck() {
        cancelPendingRecoveryCheck()
        val check = Runnable {
            recoveryCheckRunnable = null
            recoveryRetryInFlight = false
            val stillPending = try {
                gameSessionIPC?.hasPendingSend(sessionId) == true
            } catch (t: Throwable) {
                OpenPigeonLog.e(TAG, "Unable to check pending Golf send", t)
                true
            }
            if (stillPending) showTurnRecoveryRetry() else hideTurnRecoveryRetry()
        }
        recoveryCheckRunnable = check
        recoveryHandler.postDelayed(check, 8000L)
    }

    private fun retryPendingGolfSend() {
        if (recoveryRetryInFlight) return
        val ipc = gameSessionIPC
        if (ipc == null || sessionId.isBlank()) {
            showTurnRecoveryRetry()
            return
        }

        cancelPendingRecoveryCheck()
        recoveryRetryInFlight = true
        hideTurnRecoveryRetry()
        if (!gameOverShown) showSendingLabelImmediately()

        val dispatched = ipc.retryPendingSend(sessionId) {
            runOnUiThread {
                recoveryRetryInFlight = false
                cancelPendingRecoveryCheck()
                hideTurnRecoveryRetry()
                if (!gameOverShown) playSentThenWaitingAnimation()
            }
        }

        if (!dispatched) {
            recoveryRetryInFlight = false
            showTurnRecoveryRetry()
            return
        }

        schedulePendingSendCheck()
    }

    private fun restoreSavedGolfState(savedInstanceState: Bundle?) {
        if (savedInstanceState == null) {
            OpenPigeonLog.i(TAG, "restoreSavedGolfState skipped savedInstanceState=null")
            return
        }

        lastAutoReplayKey = savedInstanceState.getString(
            STATE_LAST_AUTO_REPLAY_KEY, ""
        )

        seed = savedInstanceState.getInt(
            STATE_SEED, seed
        )

        mode = savedInstanceState.getString(
            STATE_MODE, mode
        ).ifBlank { GolfConstants.DEFAULT_MODE }

        holeCount = savedInstanceState.getInt(
            STATE_HOLE_COUNT, holeCount
        )

        mapNum = savedInstanceState.getInt(
            STATE_MAP_NUM, mapNum
        )

        waitingForOpponent = savedInstanceState.getBoolean(
            STATE_WAITING_FOR_OPPONENT, waitingForOpponent
        )

        roundResultSent = savedInstanceState.getBoolean(
            STATE_ROUND_RESULT_SENT, roundResultSent
        )

        OpenPigeonLog.i(
            TAG,
            "restoreSavedGolfState restored " + "seed=$seed mode=$mode mapNum=$mapNum holeCount=$holeCount " + "lastAutoReplayKeyBlank=${lastAutoReplayKey.isBlank()} " + "waitingForOpponent=$waitingForOpponent " + "roundResultSent=$roundResultSent"
        )
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString(STATE_LAST_AUTO_REPLAY_KEY, lastAutoReplayKey)
        outState.putInt(STATE_SEED, seed)
        outState.putString(STATE_MODE, mode)
        outState.putInt(STATE_HOLE_COUNT, holeCount)
        outState.putInt(STATE_MAP_NUM, mapNum)
        outState.putBoolean(STATE_WAITING_FOR_OPPONENT, waitingForOpponent)
        outState.putBoolean(STATE_ROUND_RESULT_SENT, roundResultSent)

        OpenPigeonLog.i(
            TAG,
            "onSaveInstanceState saved " + "seed=$seed mode=$mode mapNum=$mapNum holeCount=$holeCount " + "lastAutoReplayKeyBlank=${lastAutoReplayKey.isBlank()} " + "waitingForOpponent=$waitingForOpponent " + "roundResultSent=$roundResultSent"
        )

        super.onSaveInstanceState(outState)
    }

    private fun saveGolfProgress(phase: String, ball: PointF? = runtimeBallCourse) {
        if (spectatorMode || sessionId.isBlank()) return
        val ipc = gameSessionIPC ?: return
        val start = lastShotStartCourse
        val values = mutableMapOf(
            "phase" to phase,
            "localReplay" to localReplay,
            "seed" to seed.toString(),
            "mode" to mode,
            "holeCount" to holeCount.toString(),
            "mapNum" to mapNum.toString(),
            "ballX" to (ball?.x?.toString() ?: ""),
            "ballY" to (ball?.y?.toString() ?: ""),
            "shotStartX" to (start?.x?.toString() ?: ""),
            "shotStartY" to (start?.y?.toString() ?: ""),
            "shotVelocityX" to lastShotVelocityCourse.x.toString(),
            "shotVelocityY" to lastShotVelocityCourse.y.toString(),
            "ballInHole" to ballInHole.toString(),
            "flagPulled" to flagPulled.toString()
        )
        val saved = ipc.saveTurnProgress(sessionId, values)
        OpenPigeonLog.i(TAG, "Golf recovery saved phase=$phase replayLen=${localReplay.length} saved=$saved")
    }

    private fun cancelGolfPlaybackForRecovery() {
        stopBallPhysics(clearVelocity = true)
        stopDualReplay()
        stopStateLabelAnimation()
        isAiming = false
        activeAim = GolfShot.Aim.NONE
        renderer.clearAimPreview()
        holeOverlay.animate().cancel()
        holeIntroContainer.animate().cancel()
        holeTitle.animate().cancel()
        holePoleImage.animate().cancel()
        holeOverlay.visibility = View.GONE
        holeOverlay.alpha = 0f
    }

    private fun restoreGolfTurnProgress(progress: Map<String, String>): Boolean {
        val phase = progress["phase"].orEmpty()
        val savedReplay = progress["localReplay"].orEmpty()
        if (phase.isBlank() || savedReplay.isBlank()) return false

        seed = progress["seed"]?.toIntOrNull() ?: seed
        mode = progress["mode"].orEmpty().ifBlank { mode }
        holeCount = progress["holeCount"]?.toIntOrNull() ?: holeCount
        mapNum = progress["mapNum"]?.toIntOrNull()?.coerceIn(0, (holeCount - 1).coerceAtLeast(0)) ?: mapNum
        localReplay = savedReplay
        waitingForOpponent = false
        roundResultSent = false
        ballInHole = false
        flagPulled = false

        val ballX = progress["ballX"]?.toFloatOrNull()
        val ballY = progress["ballY"]?.toFloatOrNull()
        val startX = progress["shotStartX"]?.toFloatOrNull()
        val startY = progress["shotStartY"]?.toFloatOrNull()
        val velocityX = progress["shotVelocityX"]?.toFloatOrNull()
        val velocityY = progress["shotVelocityY"]?.toFloatOrNull()

        cancelGolfPlaybackForRecovery()

        generateAndShowMap(showIntro = false, source = "turn recovery", afterIntro = {
            if (startX != null && startY != null && velocityX != null && velocityY != null) {
                lastShotStartCourse = PointF(startX, startY)
                lastShotVelocityCourse.set(velocityX, velocityY)
                runtimeBallCourse = PointF(startX, startY)
                runtimeVelocityCourse.set(velocityX, velocityY)
                restoringLastShot = phase == "aim"
                recoverySettledBallCourse = if (phase == "aim" && ballX != null && ballY != null) PointF(ballX, ballY) else null
                ballInHole = false
                flagPulled = false
                renderer.setRuntimeBallCourse(runtimeBallCourse)
                renderer.setHoleState(flagPulled = false, ballInHole = false)
                renderer.clearAimPreview()
                hideAimReadyUi(immediate = true)
                focusCameraOnCurrentBall()
                startBallPhysics()
                return@generateAndShowMap
            }

            if (phase == "aim" && ballX != null && ballY != null) {
                runtimeBallCourse = PointF(ballX, ballY)
                renderer.setRuntimeBallCourse(runtimeBallCourse)
                renderer.setHoleState(flagPulled = false, ballInHole = false)
                updateStrokeHud()
                updateAimReadyUi()
                focusCameraOnCurrentBall()
                return@generateAndShowMap
            }

            if (phase == "roundComplete") {
                sendCurrentGolfState()
                return@generateAndShowMap
            }

            updateAimReadyUi()
        })

        return true
    }

    private fun restoreGolfRecovery(remoteMessage: Map<String, String>) {
        val ipc = gameSessionIPC
        if (ipc == null || sessionId.isBlank()) {
            handleMessage(remoteMessage)
            return
        }

        val recovery = try {
            ipc.getTurnRecovery(sessionId)
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "Unable to load Golf recovery", t)
            null
        }

        if (recovery == null) {
            hideTurnRecoveryRetry()
            handleMessage(remoteMessage)
            return
        }

        if (recovery.sendAttempted) {
            val pendingDisplay = remoteMessage.toMutableMap().apply { putAll(recovery.pendingUpdates) }
            handleMessage(pendingDisplay)
            showTurnRecoveryRetry()
            return
        }

        handleMessage(remoteMessage)

        if (!restoreGolfTurnProgress(recovery.progress)) {
            OpenPigeonLog.w(TAG, "Unable to restore Golf turn progress")
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        val startedAt = SystemClock.elapsedRealtime()
        super.onCreate(savedInstanceState)
        OpenPigeonLog.installContext(applicationContext)
        OpenPigeonLog.title(TAG, "Mini Golf", "onCreate start")
        restoreSavedGolfState(savedInstanceState)

        try {
            OpenPigeonLog.i(TAG, "onCreate: request no title / hide actionbar")
            requestWindowFeature(Window.FEATURE_NO_TITLE)
            supportActionBar?.hide()

            OpenPigeonLog.i(TAG, "onCreate: buildLayout start")
            buildLayout()
            OpenPigeonLog.i(TAG, "onCreate: buildLayout complete rootChildren=${root.childCount}")

            setupGameMenu()
            setupTurnRecoveryOverlay()

            gameAvatarAnchor.post {
                normalizeAvatarAnchor(gameAvatarAnchor)
                positionLocalAvatarYouLabel()
                attachStrokeCountersToAvatarAnchors()
                syncStrokeCounterTextSizing()
            }

            oppAvatarAnchor.post {
                normalizeAvatarAnchor(oppAvatarAnchor)
                attachStrokeCountersToAvatarAnchors()
                syncStrokeCounterTextSizing()
            }

            ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
                val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
                topHudInsetPx = bars.top

                applyTopHudLayout()
                positionLocalAvatarYouLabel()
                attachStrokeCountersToAvatarAnchors()
                syncStrokeCounterTextSizing()

                insets
            }

            root.requestApplyInsets()

            renderer.setOnTouchListener { _, event ->
                handleGolfTouch(event)
            }

            zoomButton.alpha = 0.72f

            zoomButton.setOnClickListener {
                setZoomOverviewEnabled(!zoomOverviewEnabled)
            }

            sessionId = intent.getStringExtra("SESSION") ?: ""
            OpenPigeonLog.i(
                TAG, "onCreate: sessionIdBlank=${sessionId.isBlank()} extras=${
                    intent.extras?.keySet()?.sorted().orEmpty()
                }"
            )

            OpenPigeonLog.i(TAG, "onCreate: GameSessionIPC init start")
            GameSessionIPC(applicationContext) { ipc ->
                OpenPigeonLog.i(
                    TAG,
                    "GameSessionIPC callback entered elapsedMs=${SystemClock.elapsedRealtime() - startedAt}"
                )
                gameSessionIPC = ipc

                val currentMessage = try {
                    if (sessionId.isNotEmpty()) {
                        OpenPigeonLog.i(TAG, "IPC getCurrentMessage start sessionBlank=false")
                        ipc.getCurrentMessage(sessionId)
                    } else {
                        OpenPigeonLog.w(
                            TAG, "IPC getCurrentMessage skipped because sessionId blank"
                        )
                        emptyMap()
                    }
                } catch (t: Throwable) {
                    OpenPigeonLog.e(TAG, "IPC getCurrentMessage failed", t)
                    emptyMap()
                }

                OpenPigeonLog.i(TAG, "IPC currentMessage ${messageSummary(currentMessage)}")

                if (currentMessage.isNotEmpty()) {
                    try {
                        OpenPigeonLog.i(TAG, "IPC lockMsgHandle start")
                        ipc.lockMsgHandle(sessionId)
                        OpenPigeonLog.i(TAG, "IPC lockMsgHandle complete")
                    } catch (t: Throwable) {
                        OpenPigeonLog.e(TAG, "IPC lockMsgHandle failed", t)
                    }

                    try {
                        OpenPigeonLog.i(TAG, "IPC setSuppressNotifications(true) start")
                        ipc.setSuppressNotifications(sessionId, true)
                        OpenPigeonLog.i(TAG, "IPC setSuppressNotifications(true) complete")
                    } catch (t: Throwable) {
                        OpenPigeonLog.e(TAG, "IPC setSuppressNotifications(true) failed", t)
                    }

                    try {
                        OpenPigeonLog.i(TAG, "IPC onMessageUpdated registration start")
                        ipc.onMessageUpdated(sessionId) { msg ->
                            OpenPigeonLog.i(TAG, "IPC onMessageUpdated callback ${messageSummary(msg)}")
                            runOnUiThread {
                                handleMessage(msg)

                                val stillPending = try {
                                    ipc.hasPendingSend(sessionId)
                                } catch (t: Throwable) {
                                    OpenPigeonLog.e(TAG, "Unable to check pending Golf send after update", t)
                                    false
                                }

                                if (!stillPending) {
                                    recoveryRetryInFlight = false
                                    cancelPendingRecoveryCheck()
                                    hideTurnRecoveryRetry()
                                } else if (::turnRecoveryOverlay.isInitialized && turnRecoveryOverlay.isShowingRetry()) {
                                    turnRecoveryOverlay.showRetry()
                                }
                            }
                        }
                        OpenPigeonLog.i(TAG, "IPC onMessageUpdated registration complete")
                    } catch (t: Throwable) {
                        OpenPigeonLog.e(TAG, "IPC onMessageUpdated registration failed", t)
                    }

                    runOnUiThread {
                        OpenPigeonLog.i(TAG, "UI restoreGolfRecovery currentMessage start")
                        restoreGolfRecovery(currentMessage)
                    }
                } else {
                    runOnUiThread {
                        OpenPigeonLog.w(
                            TAG, "No current message; opening default local visual message"
                        )
                        handleMessage(defaultLocalMessage())
                    }
                }
            }
            OpenPigeonLog.i(
                TAG,
                "onCreate: GameSessionIPC constructor returned elapsedMs=${SystemClock.elapsedRealtime() - startedAt}"
            )
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "onCreate failed before Mini Golf could load", t)
            safeShowFallbackFromOnCreateFailure()
        }
    }

    private fun setupGameMenu() {
        gameMenu = GameMenuController(
            activity = this,
            rootFrame = root,
            gameId = "golf",
            rulesTitle = "Mini Golf Rules",
            rulesSections = golfRulesSections(),
            musicAssetPath = MUSIC_TRACK_PATH,
            placement = GameMenuPlacement.BOTTOM_START,
            existingButton = settingsButton,
            fallbackDarkOverlayAlpha = 0.18f,
            onSettingsClosed = {
                if (spectatorMode) {
                    restoreSpectatorAvatarsAfterSettingsOpen()
                }
            },
        )

        gameMenu.sheet.attachGameAvatar(
            gameAvatarAnchor,
        )

        gameMenu.sheet.attachOpponentAvatar(
            oppAvatarAnchor,
        )

        avatarWinBurstController = AvatarWinBurstController(
            root = root,
            localAnchor = gameAvatarAnchor,
            opponentAnchor = oppAvatarAnchor,
        )

        configureSettingsAvatarTarget()

        if (GolfConstants.debugToolsEnabled) {
            debugMenuItem = gameMenu.addMenuAction(
                label = "Debug: Off",
                closeMenuOnClick = false,
            ) {
                debugUiEnabled = !debugUiEnabled

                applyDebugUiState()
            }

            gameMenu.addMenuAction(
                label = "Run Trace",
            ) {
                debugRunReplayTraceNow()
            }

            gameMenu.addMenuAction(
                label = "Watch Trace",
            ) {
                debugWatchReplayTraceOnBoard()
            }

            gameMenu.addMenuAction(
                label = "Replay Again",
            ) {
                debugReplayCurrentHoleAgain()
            }
        }

        applyDebugUiState()
    }


    private fun golfRulesSections(): List<RulesPopup.Section> {
        return listOf(
            RulesPopup.Section(
                "Objective",
                "Finish all holes in the fewest total strokes.",
            ),
            RulesPopup.Section(
                "How to Play",
                "• Pull back from the ball to set power and direction.\n" + "• Release to hit the ball.\n" + "• The farther you pull, the harder the ball is hit.\n" + "• After the ball stops, you can take your next stroke.",
            ),
            RulesPopup.Section(
                "The Hole",
                "• Get the ball into the cup to finish the hole.\n" + "• When enough of the ball overlaps the cup, the hole will pull it in.\n" + "• Once the ball is in the cup, your turn for that hole is complete.",
            ),
            RulesPopup.Section(
                "Turns",
                "• Play through the current hole until your ball goes in.\n" + "• When you finish a hole, your result is sent to your opponent.\n" + "• If it is not your turn, wait for your opponent to finish.",
            ),
            RulesPopup.Section(
                "Replays",
                "• When both players have completed a hole, both shots replay together.\n" + "• Stroke counters increase during the replay as each shot is taken.\n" + "• After the replay, the game advances to the next hole.",
            ),
            RulesPopup.Section(
                "Winning",
                "After the final hole replay, the player with fewer total strokes wins.\n" + "If both players have the same number of strokes, the game is a draw.",
            ),
        )
    }

    private fun buildLayout() {
        root = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(182, 202, 209))
            isInvisible = true
            alpha = 0f
            clipChildren = false
            clipToPadding = false
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        renderer = GolfRenderer(this).apply {
            isInvisible = true

            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        root.addView(renderer)

        stateLabel = TextView(this).apply {
            text = "Mini Golf loading..."
            setTextColor(Color.WHITE)
            textSize = 16f
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(12), dp(7), dp(12), dp(7))
            background = rounded(Color.argb(125, 0, 0, 0), dp(16).toFloat())
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.CENTER_HORIZONTAL
            ).apply { topMargin = dp(20) }
        }
        root.addView(stateLabel)

        settingsButton = AppCompatImageButton(this).apply {
            background = null
            setBackgroundColor(Color.TRANSPARENT)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setUiLayer(this, LAYER_HUD)
            setPadding(dp(4), dp(4), dp(4), dp(4))

            layoutParams = FrameLayout.LayoutParams(
                dp(54), dp(54), Gravity.BOTTOM or Gravity.START
            ).apply {
                bottomMargin = dp(28)
                marginStart = dp(14)
            }

            contentDescription = "Menu"
        }
        root.addView(settingsButton)

        gameAvatarAnchor = FrameLayout(this).apply {
            clipChildren = false
            clipToPadding = false
            setUiLayer(this, LAYER_HUD)

            layoutParams = FrameLayout.LayoutParams(
                dp(58), dp(44), Gravity.TOP or Gravity.START
            ).apply {
                topMargin = dp(tallAvatarTopPaddingDp)
                marginStart = dp(avatarBarSidePaddingDp)
            }
        }
        root.addView(gameAvatarAnchor)

        oppAvatarAnchor = FrameLayout(this).apply {
            clipChildren = false
            clipToPadding = false
            setUiLayer(this, LAYER_HUD)

            layoutParams = FrameLayout.LayoutParams(
                dp(58), dp(44), Gravity.TOP or Gravity.END
            ).apply {
                topMargin = dp(tallAvatarTopPaddingDp)
                marginEnd = dp(avatarBarSidePaddingDp)
            }
        }
        root.addView(oppAvatarAnchor)

        buildLocalAvatarYouLabel()
        buildSpectatorLabel()
        buildStrokeHud()

        zoomButton = AppCompatImageButton(this).apply {
            background = null
            setBackgroundColor(Color.TRANSPARENT)
            setUiLayer(this, LAYER_HUD)
            scaleType = ImageView.ScaleType.FIT_CENTER
            adjustViewBounds = false
            setPadding(dp(2), dp(2), dp(2), dp(2))
            contentDescription = "Zoom"

            setImageResource(android.R.drawable.ic_menu_search)

            layoutParams = FrameLayout.LayoutParams(
                dp(54), dp(54), Gravity.BOTTOM or Gravity.END
            ).apply {
                bottomMargin = dp(22)
                marginEnd = dp(8)
            }
        }
        root.addView(zoomButton)

        buildAimInstructionLabel()
        buildSkipReplayButton()

        buildHoleOverlay()
        buildWaitingOverlay()
        buildGameOverLabel()
        setContentView(root)

        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            applyTopHudLayout()
            positionLocalAvatarYouLabel()
            attachStrokeCountersToAvatarAnchors()
            syncStrokeCounterTextSizing()
        }

        root.post {
            applyTopHudLayout()
            positionLocalAvatarYouLabel()
            attachStrokeCountersToAvatarAnchors()
            syncStrokeCounterTextSizing()
        }

        applyDebugUiState()
    }

    private fun buildGameOverLabel() {
        gameOverLabel = TextView(this).apply {
            visibility = View.GONE
            alpha = 0f
            scaleX = 0.65f
            scaleY = 0.65f

            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            typeface = Typeface.DEFAULT_BOLD
            includeFontPadding = false
            setPadding(dp(10), dp(6), dp(10), dp(6))
            background = rounded(Color.argb(205, 0, 0, 0), dp(8).toFloat())
            setShadowLayer(0f, 0f, 0f, Color.TRANSPARENT)

            setUiLayer(this, LAYER_WAITING + 100f)

            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }

        root.addView(gameOverLabel)
    }

    private fun positionLocalAvatarYouLabel() {
        if (!::root.isInitialized || !::gameAvatarAnchor.isInitialized || !::localAvatarYouLabel.isInitialized) {
            return
        }

        if (spectatorMode) {
            localAvatarYouLabel.visibility = View.GONE
            return
        }

        localAvatarYouLabel.visibility = View.VISIBLE

        val anchorParams = gameAvatarAnchor.layoutParams as? FrameLayout.LayoutParams ?: return

        val anchorWidth =
            gameAvatarAnchor.width.takeIf { it > 0 } ?: anchorParams.width.takeIf { it > 0 } ?: dp(
                58
            )

        val anchorHeight =
            gameAvatarAnchor.height.takeIf { it > 0 } ?: anchorParams.height.takeIf { it > 0 }
            ?: dp(44)

        val labelWidth = localAvatarYouLabel.width.takeIf { it > 0 }
            ?: localAvatarYouLabel.layoutParams?.width?.takeIf { it > 0 } ?: dp(42)

        val labelHeight = localAvatarYouLabel.height.takeIf { it > 0 }
            ?: localAvatarYouLabel.layoutParams?.height?.takeIf { it > 0 } ?: dp(20)

        val params = FrameLayout.LayoutParams(
            labelWidth, labelHeight, Gravity.TOP or Gravity.START
        ).apply {
            topMargin = anchorParams.topMargin + anchorHeight + dp(2)
            marginStart = anchorParams.marginStart + ((anchorWidth - labelWidth) / 2)
        }

        localAvatarYouLabel.layoutParams = params
        setUiLayer(localAvatarYouLabel, LAYER_HUD + 20f)
        localAvatarYouLabel.bringToFront()

        bringGameMenuToFront()
    }

    private fun buildSpectatorLabel() {
        spectatorLabel = TextView(this).apply {
            text = "Spectating..."
            visibility = View.GONE

            setTextColor(Color.WHITE)
            setTextSize(
                TypedValue.COMPLEX_UNIT_SP, 24f
            )

            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            includeFontPadding = false

            setPadding(0, 0, 0, 0)
            background = null

            // Slight drop shadow.
            setShadowLayer(
                3f, 0f, 2f, Color.argb(145, 0, 0, 0)
            )

            setUiLayer(this, LAYER_HUD + 10f)

            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.CENTER_HORIZONTAL
            )
        }

        root.addView(spectatorLabel)
    }

    private fun buildLocalAvatarYouLabel() {
        localAvatarYouLabel = TextView(this).apply {
            text = "You"
            setTextColor(Color.WHITE)
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            includeFontPadding = false
            setPadding(0, 0, 0, 0)
            background = null
            setShadowLayer(3f, 0f, 1f, Color.argb(170, 0, 0, 0))
            setUiLayer(this, LAYER_HUD + 20f)

            layoutParams = FrameLayout.LayoutParams(
                dp(42), dp(20), Gravity.TOP or Gravity.START
            )
        }

        root.addView(localAvatarYouLabel)
        positionLocalAvatarYouLabel()
    }

    private fun buildStrokeHud() {
        val localCounter = createStrokeCounter(
            assetFileName = "golf_count_w.png",
            textColor = Color.rgb(45, 45, 45),
            fallbackColor = Color.argb(220, 245, 245, 245)
        )

        localStrokeCounterView = localCounter.container
        localStrokeCounterBg = localCounter.background
        localStrokeLabel = localCounter.label

        val opponentCounter = createStrokeCounter(
            assetFileName = "golf_count_b.png",
            textColor = Color.WHITE,
            fallbackColor = Color.argb(210, 75, 75, 75)
        )

        opponentStrokeCounterView = opponentCounter.container
        opponentStrokeCounterBg = opponentCounter.background
        opponentStrokeLabel = opponentCounter.label

        root.addView(localStrokeCounterView)
        root.addView(opponentStrokeCounterView)

        attachStrokeCountersToAvatarAnchors()
        syncStrokeCounterTextSizing()
    }

    private fun attachStrokeCountersToAvatarAnchors() {
        if (!::root.isInitialized || !::gameAvatarAnchor.isInitialized || !::oppAvatarAnchor.isInitialized || !::localStrokeCounterView.isInitialized || !::opponentStrokeCounterView.isInitialized) {
            return
        }

        positionStrokeCounterBesideAvatar(
            anchor = gameAvatarAnchor, counterView = localStrokeCounterView, isLeftAvatar = true
        )

        positionStrokeCounterBesideAvatar(
            anchor = oppAvatarAnchor, counterView = opponentStrokeCounterView, isLeftAvatar = false
        )

        syncStrokeCounterTextSizing()
    }

    private fun positionStrokeCounterBesideAvatar(
        anchor: FrameLayout, counterView: FrameLayout, isLeftAvatar: Boolean
    ) {
        val currentParent = counterView.parent as? ViewGroup

        if (currentParent !== root) {
            currentParent?.removeView(counterView)
            root.addView(counterView)
        }

        val anchorParams = anchor.layoutParams as? FrameLayout.LayoutParams ?: return

        val anchorWidth =
            anchor.width.takeIf { it > 0 } ?: anchorParams.width.takeIf { it > 0 } ?: dp(58)

        val anchorHeight =
            anchor.height.takeIf { it > 0 } ?: anchorParams.height.takeIf { it > 0 } ?: dp(44)

        val counterSize = (anchorHeight * 1.12f).toInt().coerceIn(dp(50), dp(58))

        val verticalTop = anchorParams.topMargin + ((anchorHeight - counterSize) / 2)

        val params = if (isLeftAvatar) {
            FrameLayout.LayoutParams(
                counterSize, counterSize, Gravity.TOP or Gravity.START
            ).apply {
                topMargin = verticalTop
                marginStart = anchorParams.marginStart + anchorWidth
            }
        } else {
            FrameLayout.LayoutParams(
                counterSize, counterSize, Gravity.TOP or Gravity.END
            ).apply {
                topMargin = verticalTop
                marginEnd = anchorParams.marginEnd + anchorWidth
            }
        }

        counterView.layoutParams = params
        counterView.bringToFront()
        bringGameMenuToFront()
    }

    private fun syncStrokeCounterTextSizing() {
        if (!::localStrokeCounterView.isInitialized || !::opponentStrokeCounterView.isInitialized || !::localStrokeLabel.isInitialized || !::opponentStrokeLabel.isInitialized) {
            return
        }

        fun sync(label: TextView, counterView: FrameLayout) {
            val sizePx = counterView.height.takeIf { it > 0 }
                ?: counterView.layoutParams?.height?.takeIf { it > 0 } ?: dp(36)

            label.setTextSize(
                TypedValue.COMPLEX_UNIT_PX, sizePx * 0.28f
            )
        }

        sync(localStrokeLabel, localStrokeCounterView)
        sync(opponentStrokeLabel, opponentStrokeCounterView)
    }

    private fun applyTopHudLayout() {
        val avatarTop = topHudInsetPx + dp(tallAvatarTopPaddingDp)
        val labelTop = topHudInsetPx + dp(avatarBarTopPaddingDp)
        val side = dp(avatarBarSidePaddingDp)

        if (::gameAvatarAnchor.isInitialized) {
            (gameAvatarAnchor.layoutParams as? FrameLayout.LayoutParams)?.let { params ->
                params.gravity = Gravity.TOP or Gravity.START
                avatarTop.also { params.topMargin = it }
                params.marginStart = side
                gameAvatarAnchor.layoutParams = params
            }
        }

        if (::oppAvatarAnchor.isInitialized) {
            (oppAvatarAnchor.layoutParams as? FrameLayout.LayoutParams)?.let { params ->
                params.gravity = Gravity.TOP or Gravity.END
                params.topMargin = avatarTop
                params.marginEnd = side
                oppAvatarAnchor.layoutParams = params
            }
        }

        if (::stateLabel.isInitialized) {
            (stateLabel.layoutParams as? FrameLayout.LayoutParams)?.let { params ->
                params.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                params.topMargin = labelTop + dp(4)
                stateLabel.layoutParams = params
            }
        }

        if (::spectatorLabel.isInitialized) {
            (spectatorLabel.layoutParams as? FrameLayout.LayoutParams)?.let { params ->
                params.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                params.topMargin = labelTop + dp(4)
                spectatorLabel.layoutParams = params
            }
        }

        if (spectatorMode && ::spectatorLabel.isInitialized) {
            spectatorLabel.visibility = View.VISIBLE
            spectatorLabel.bringToFront()
        }

        positionLocalAvatarYouLabel()
        attachStrokeCountersToAvatarAnchors()
        bringGameMenuToFront()
    }

    private fun normalizeAvatarAnchor(anchor: FrameLayout) {
        anchor.clipChildren = false
        anchor.clipToPadding = false

        AvatarView.configureTallAnchor(anchor)
        anchor.requestLayout()
    }

    private data class StrokeCounterViews(
        val container: FrameLayout, val background: ImageView, val label: TextView
    )

    private fun createStrokeCounter(
        assetFileName: String, textColor: Int, fallbackColor: Int
    ): StrokeCounterViews {
        val defaultSize = dp(54)

        val container = FrameLayout(this).apply {
            clipChildren = false
            clipToPadding = false
            setUiLayer(this, LAYER_HUD + 20f)
            isClickable = false
            isFocusable = false

            layoutParams = FrameLayout.LayoutParams(
                defaultSize, defaultSize
            )
        }

        val bg = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            adjustViewBounds = false
            isClickable = false
            isFocusable = false
            setBackgroundColor(Color.TRANSPARENT)

            scaleX = 1.22f
            scaleY = 1.22f

            val bm = loadGolfUiBitmap(assetFileName)

            if (bm != null) {
                setImageBitmap(bm)
                background = null

                OpenPigeonLog.i(
                    TAG,
                    "Stroke counter asset loaded file=$assetFileName size=${bm.width}x${bm.height}"
                )
            } else {
                OpenPigeonLog.w(
                    TAG, "Stroke counter asset missing file=$assetFileName; using fallback"
                )

                background = rounded(fallbackColor, defaultSize * 0.5f)
            }

            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
        }

        val label = TextView(this).apply {
            text = "0"
            setTextColor(textColor)
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            includeFontPadding = false
            isClickable = false
            isFocusable = false
            background = null
            translationX = dp(3).toFloat()
            translationY = -dp(5).toFloat()

            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
        }

        container.addView(bg)
        container.addView(label)

        return StrokeCounterViews(
            container = container, background = bg, label = label
        )
    }

    private fun totalStrokesForReplay(
        replay: String, holes: Int = holeCount
    ): Int {
        var total = 0
        val safeHoles = holes.coerceAtLeast(0)

        for (holeIndex in 0 until safeHoles) {
            total += GolfReplay.segmentAt(replay, holeIndex).size
        }

        return total
    }

    private fun totalStrokesBeforeHole(
        replay: String, holeIndex: Int
    ): Int {
        var total = 0
        val endExclusive = holeIndex.coerceIn(0, holeCount)

        for (i in 0 until endExclusive) {
            total += GolfReplay.segmentAt(replay, i).size
        }

        return total
    }

    private fun totalStrokesThroughHole(
        replay: String, holeIndex: Int
    ): Int {
        var total = 0
        val endInclusive = holeIndex.coerceIn(0, holeCount - 1)

        for (i in 0..endInclusive) {
            total += GolfReplay.segmentAt(replay, i).size
        }

        return total
    }

    private fun localResultFromWinnerValue(winner: String): Int? {
        if (winner.isBlank()) return null

        val parts = winner.split("|")
        if (parts.size < 2) return null

        val winnerSenderId = parts[0]
        val senderResult = parts[1].toIntOrNull()?.coerceIn(-1, 1) ?: return null

        val myId = runCatching {
            gameSessionIPC?.getSenderUUID(sessionId)
        }.getOrNull().orEmpty()

        if (senderResult == 0) return 0

        return if (myId.isNotBlank() && winnerSenderId != myId) {
            -senderResult
        } else {
            senderResult
        }
    }

    private fun resultTextFor(result: Int): String {
        if (spectatorMode) {
            return when {
                result > 0 -> "Player 1 Wins!"
                result < 0 -> "Player 2 Wins!"
                else -> "Draw"
            }
        }

        return when {
            result > 0 -> "You Win!"
            result < 0 -> "You Lose!"
            else -> "Draw!"
        }
    }

    private fun resultColorFor(result: Int): Int {
        return when {
            result > 0 -> Color.rgb(242, 202, 72)   // gold
            result < 0 -> Color.rgb(235, 62, 72)    // red
            else -> Color.WHITE
        }
    }

    private fun hideGameOverLabel() {
        gameOverShown = false
        if (::avatarWinBurstController.isInitialized) {
            avatarWinBurstController.clear()
        }

        if (!::gameOverLabel.isInitialized) return

        gameOverLabel.animate().cancel()
        gameOverLabel.alpha = 0f
        gameOverLabel.visibility = View.GONE
        gameOverLabel.scaleX = 0.65f
        gameOverLabel.scaleY = 0.65f
    }

    private fun showGameOverLabel(result: Int) {
        if (!::gameOverLabel.isInitialized) return

        gameOverShown = true

        hideAimReadyUi(immediate = true)
        hideSkipReplayButton()
        hideWaitingOverlay()
        closeGameMenu()

        gameOverLabel.animate().cancel()
        gameOverLabel.text = resultTextFor(result)
        gameOverLabel.setTextColor(resultColorFor(result))

        setUiLayer(gameOverLabel, LAYER_WAITING + 100f)

        gameOverLabel.alpha = 0f
        gameOverLabel.scaleX = 0.88f
        gameOverLabel.scaleY = 0.88f
        gameOverLabel.visibility = View.VISIBLE
        if (::avatarWinBurstController.isInitialized) {
            avatarWinBurstController.show(
                result = result,
                label = gameOverLabel,
            )
        }
        gameOverLabel.bringToFront()

        gameOverLabel.animate().alpha(1f).scaleX(1f).scaleY(1f).setDuration(260L)
            .setInterpolator(OvershootInterpolator(1.2f)).start()
    }

    private fun showGameOverAfterReplay() {
        val forcedResult = pendingGameOverForcedResult
        val shouldSendWinner = pendingGameOverShouldSendWinner && forcedResult == null

        pendingGameOverForcedResult = null
        pendingGameOverShouldSendWinner = false

        waitingForOpponent = false

        showGameOverFromData(
            data = gameData, shouldSendWinner = shouldSendWinner, forcedLocalResult = forcedResult
        )
    }

    private fun showGameOverFromData(
        data: GolfGameData?, shouldSendWinner: Boolean, forcedLocalResult: Int? = null
    ) {
        val d = data ?: gameData ?: return

        waitingForOpponent = false
        physicsRunning = false
        dualReplayRunning = false
        dualReplayWaitingToFire = false

        val localPlayer = localPlayerNumberFor(d)

        val p1Strokes = totalStrokesForReplay(
            replay = d.replay, holes = d.holeCount
        )

        val p2Strokes = totalStrokesForReplay(
            replay = d.replay2, holes = d.holeCount
        )

        val localStrokes = if (localPlayer == 1) p1Strokes else p2Strokes

        val opponentStrokes = if (localPlayer == 1) p2Strokes else p1Strokes

        val hasBothScores = p1Strokes > 0 && p2Strokes > 0

        val scoreBasedResult = if (spectatorMode) {
            when {
                p1Strokes < p2Strokes -> 1
                p1Strokes > p2Strokes -> -1
                else -> 0
            }
        } else {
            when {
                localStrokes < opponentStrokes -> 1
                localStrokes > opponentStrokes -> -1
                else -> 0
            }
        }

        val localResult = if (hasBothScores) {
            scoreBasedResult
        } else {
            forcedLocalResult ?: scoreBasedResult
        }

        OpenPigeonLog.i(
            TAG,
            "showGameOverFromData localPlayer=$localPlayer " + "p1Strokes=$p1Strokes p2Strokes=$p2Strokes " + "localStrokes=$localStrokes opponentStrokes=$opponentStrokes " + "scoreBasedResult=$scoreBasedResult forcedLocalResult=$forcedLocalResult " + "finalResult=$localResult shouldSendWinner=$shouldSendWinner " + "replayLen=${d.replay.length} replay2Len=${d.replay2.length}"
        )

        setStrokeHudCounts(
            localCount = if (spectatorMode) p1Strokes else localStrokes,
            opponentCount = if (spectatorMode) p2Strokes else opponentStrokes
        )

        showGameOverLabel(result = localResult)

        if (shouldSendWinner && !spectatorMode) {
            sendWinnerResultIfNeeded(localResult)
        }
    }

    private fun sendWinnerResultIfNeeded(localResult: Int) {
        if (spectatorMode) return
        val ipc = gameSessionIPC
        if (ipc == null || sessionId.isBlank()) return

        try {
            val myId = ipc.getSenderUUID(sessionId).takeIf { it.isNotBlank() }.orEmpty()
            if (myId.isBlank()) return

            val current = ipc.getCurrentMessage(sessionId).ifEmpty { lastMessage }
            if (current["winner"].orEmpty().isNotBlank()) return

            val outgoing = current.toMutableMap()
            outgoing["game"] = "golf"
            outgoing["game_name"] = "Mini Golf"
            outgoing["sender"] = myId
            outgoing["winner"] = "$myId|${localResult.coerceIn(-1, 1)}"

            val dispatched = ipc.updateSession(outgoing, sessionId) {
                runOnUiThread {
                    recoveryRetryInFlight = false
                    cancelPendingRecoveryCheck()
                    hideTurnRecoveryRetry()
                }
            }

            if (!dispatched) showTurnRecoveryRetry() else schedulePendingSendCheck()
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "sendWinnerResultIfNeeded failed result=$localResult", t)
            val pending = try { ipc.hasPendingSend(sessionId) } catch (_: Throwable) { false }
            if (pending) showTurnRecoveryRetry()
        }
    }

    private fun setStrokeHudCounts(
        localCount: Int, opponentCount: Int
    ) {
        if (!::localStrokeLabel.isInitialized || !::opponentStrokeLabel.isInitialized) return

        attachStrokeCountersToAvatarAnchors()
        syncStrokeCounterTextSizing()

        localStrokeLabel.text = localCount.coerceAtLeast(0).toString()
        opponentStrokeLabel.text = opponentCount.coerceAtLeast(0).toString()
    }

    private fun setPreReplayStrokeHud(
        data: GolfGameData, localPlayer: Int
    ) {
        val myReplay = if (localPlayer == 1) {
            data.replay
        } else {
            data.replay2
        }

        val opponentReplay = if (localPlayer == 1) {
            data.replay2
        } else {
            data.replay
        }

        val localBeforeHole = totalStrokesBeforeHole(
            replay = myReplay, holeIndex = data.mapNum
        )

        val opponentBeforeHole = totalStrokesBeforeHole(
            replay = opponentReplay, holeIndex = data.mapNum
        )

        setStrokeHudCounts(
            localCount = localBeforeHole, opponentCount = opponentBeforeHole
        )

        OpenPigeonLog.i(
            TAG,
            "setPreReplayStrokeHud mapNum=${data.mapNum} localPlayer=$localPlayer " + "localBeforeHole=$localBeforeHole opponentBeforeHole=$opponentBeforeHole"
        )
    }

    private fun prepareDualReplayStrokeHud(
        data: GolfGameData, localPlayer: Int
    ) {
        val myReplay = if (localPlayer == 1) {
            data.replay
        } else {
            data.replay2
        }

        val opponentReplay = if (localPlayer == 1) {
            data.replay2
        } else {
            data.replay
        }

        dualReplayMineBaseStrokes = totalStrokesBeforeHole(myReplay, data.mapNum)
        dualReplayOpponentBaseStrokes = totalStrokesBeforeHole(opponentReplay, data.mapNum)

        dualReplayMineDisplayedStrokes = dualReplayMineBaseStrokes
        dualReplayOpponentDisplayedStrokes = dualReplayOpponentBaseStrokes

        setStrokeHudCounts(
            localCount = dualReplayMineDisplayedStrokes,
            opponentCount = dualReplayOpponentDisplayedStrokes
        )

        OpenPigeonLog.i(
            TAG,
            "prepareDualReplayStrokeHud mapNum=${data.mapNum} localPlayer=$localPlayer " + "mineBase=$dualReplayMineBaseStrokes opponentBase=$dualReplayOpponentBaseStrokes " + "mineShots=${dualReplayMineShots.size} opponentShots=${dualReplayOpponentShots.size} " + "mineDisplayed=$dualReplayMineDisplayedStrokes " + "opponentDisplayed=$dualReplayOpponentDisplayedStrokes"
        )
    }

    private fun markDualReplayStrokeFired(
        mineFired: Boolean, opponentFired: Boolean
    ) {
        if (mineFired) {
            dualReplayMineDisplayedStrokes += 1
        }

        if (opponentFired) {
            dualReplayOpponentDisplayedStrokes += 1
        }

        setStrokeHudCounts(
            localCount = dualReplayMineDisplayedStrokes,
            opponentCount = dualReplayOpponentDisplayedStrokes
        )
    }

    private fun updateStrokeHud(data: GolfGameData? = gameData) {
        if (!::localStrokeLabel.isInitialized || !::opponentStrokeLabel.isInitialized || replayStrokeHudLocked) return

        attachStrokeCountersToAvatarAnchors()
        syncStrokeCounterTextSizing()

        val localPlayer = localPlayerNumberFor(data)

        val localReplayForHud = localReplay.ifBlank {
            if (localPlayer == 1) {
                data?.replay.orEmpty()
            } else {
                data?.replay2.orEmpty()
            }
        }

        val opponentReplay = if (localPlayer == 1) {
            data?.replay2.orEmpty()
        } else {
            data?.replay.orEmpty()
        }

        val localCount = totalStrokesThroughHole(localReplayForHud, mapNum)
        val opponentCount = totalStrokesBeforeHole(opponentReplay, mapNum)

        setStrokeHudCounts(
            localCount = localCount, opponentCount = opponentCount
        )
    }

    private fun buildHoleOverlay() {
        holeOverlay = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(182, 202, 209))
            alpha = 0f
            visibility = View.GONE
            isClickable = true
            setUiLayer(this, LAYER_INTRO)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        holeIntroContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            alpha = 0f
            scaleX = 1f
            scaleY = 1f

            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }

        holePoleImage = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            adjustViewBounds = true

            val bm = loadUiBitmap(
                "golf/golf_pole.png", "golf/reference_original/golf_pole.png", "golf_pole.png"
            )

            if (bm != null) {
                setImageBitmap(bm)
                visibility = View.VISIBLE
            } else {
                OpenPigeonLog.w(TAG, "Intro pole asset missing golf_pole.png")
                visibility = View.GONE
            }

            layoutParams = LinearLayout.LayoutParams(
                dp(72), dp(72)
            ).apply {
                bottomMargin = dp(10)
                gravity = Gravity.CENTER_HORIZONTAL
            }
        }

        holeTitle = TextView(this).apply {
            text = "Hole 1/3"
            setTextColor(Color.WHITE)
            textSize = 46f
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            typeface = Typeface.DEFAULT_BOLD
            setShadowLayer(4f, 0f, 2f, Color.argb(100, 0, 0, 0))
            alpha = 1f
            scaleX = 1f
            scaleY = 1f

            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        }

        holeIntroContainer.addView(holePoleImage)
        holeIntroContainer.addView(holeTitle)

        holeOverlay.addView(holeIntroContainer)
        root.addView(holeOverlay)
    }

    private fun buildWaitingOverlay() {
        waitingOverlay = FrameLayout(this).apply {
            visibility = View.GONE
            alpha = 0f
            isClickable = true
            isFocusable = true
            setUiLayer(this, LAYER_WAITING)
            background = rounded(Color.argb(135, 32, 32, 32), 0f)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        waitingLabel = TextView(this).apply {
            text = "WAITING FOR OPPONENT."
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(16), dp(9), dp(16), dp(9))
            background = rounded(Color.argb(187, 0, 0, 0), dp(14).toFloat())
            maxLines = 1

            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }

        waitingOverlay.addView(waitingLabel)
        root.addView(waitingOverlay)
    }

    private fun debugWatchReplayTraceOnBoard() {
        if (!GolfConstants.debugToolsEnabled) return
        val data = gameData

        if (data == null) {
            OpenPigeonLog.w(
                TAG,
                "GOLF_ANDROID_TRACE={\"kind\":\"debugVisualTraceSkip\",\"reason\":\"gameData null\"}"
            )
            return
        }

        val mapForCurrentData = currentMap?.takeIf {
            it.seed == data.seed && it.mode == data.mode && it.mapNum == data.mapNum
        } ?: run {
            try {
                generator.createMap(
                    seed = data.seed, mapNum = data.mapNum, mode = data.mode
                )
            } catch (t: Throwable) {
                OpenPigeonLog.e(TAG, "debugWatchReplayTraceOnBoard createMap failed", t)
                return
            }
        }

        val shots = buildDebugVisualTraceShots(
            data = data
        )

        if (shots.isEmpty()) {
            OpenPigeonLog.w(
                TAG,
                "GOLF_ANDROID_TRACE={\"kind\":\"debugVisualTraceSkip\",\"reason\":\"no visual shots\",\"seed\":${data.seed},\"mode\":\"${data.mode}\",\"mapNum\":${data.mapNum}}"
            )

            stateLabel.visibility = View.VISIBLE
            stateLabel.text = "No trace shots"
            return
        }

        startDebugVisualTrace(
            map = mapForCurrentData, shots = shots
        )
    }

    private fun buildDebugVisualTraceShots(
        data: GolfGameData
    ): List<DebugVisualTraceShot> {
        val result = mutableListOf<DebugVisualTraceShot>()

        val p1Shots = GolfReplay.segmentAt(data.replay, data.mapNum)

        p1Shots.forEachIndexed { index, shot ->
            result += DebugVisualTraceShot(
                label = "P1 full shot $index",
                runIdSuffix = "p1_full_visual_shot$index",
                shotIndex = index,
                dist = shot.dist,
                rotation = shot.rotation,
                explicitStart = null,
                resetNativeBeforeShot = index == 0
            )
        }

        if (debugGolfReplayTraceIosAnchors && data.seed == 1853352027 && data.mode == "3" && data.mapNum == 0) {
            result += DebugVisualTraceShot(
                label = "iOS anchor shot 3",
                runIdSuffix = "ios_anchor_visual_shot3",
                shotIndex = 3,
                dist = 188.9313f,
                rotation = 1.708533f,
                explicitStart = PointF(46.56711f, 60.4934f),
                resetNativeBeforeShot = true
            )

            result += DebugVisualTraceShot(
                label = "iOS anchor shot 4",
                runIdSuffix = "ios_anchor_visual_shot4",
                shotIndex = 4,
                dist = 60.0733f,
                rotation = -2.299651f,
                explicitStart = PointF(-4.903124f, 304.27774f),
                resetNativeBeforeShot = true
            )
        }

        return result
    }

    private fun startDebugVisualTrace(
        map: GolfMap, shots: List<DebugVisualTraceShot>
    ) {
        val source = "debugMenuWatchTrace"
        if (debugVisualTraceRunning) {
            stopDebugVisualTrace(restoreBoard = true)
        }

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_TRACE=" + "{" + "\"kind\":\"debugVisualTraceStart\"," + "\"source\":\"$source\"," + "\"seed\":${map.seed}," + "\"mode\":\"${map.mode}\"," + "\"mapNum\":${map.mapNum}," + "\"shotCount\":${shots.size}" + "}"
        )

        debugVisualTraceSavedBall = runtimeBallCourse?.let {
            PointF(it.x, it.y)
        }

        debugVisualTraceSavedVelocity.set(
            runtimeVelocityCourse.x, runtimeVelocityCourse.y
        )

        debugVisualTraceSavedBallInHole = ballInHole
        debugVisualTraceSavedFlagPulled = flagPulled
        debugVisualTraceSavedWaitingForOpponent = waitingForOpponent
        debugVisualTraceSavedRoundResultSent = roundResultSent
        debugVisualTraceSavedZoomOverviewEnabled = zoomOverviewEnabled

        stopBallPhysics(clearVelocity = true)
        stopDualReplay()
        hideAimReadyUi()
        hideSkipReplayButton()
        hideWaitingOverlay()

        currentMap = map
        renderer.setMap(map)

        debugVisualTraceRunning = true
        debugVisualTraceShots = shots
        debugVisualTraceShotListIndex = 0
        debugVisualTraceFrame = 0
        debugVisualTraceCaptured = false
        debugVisualTraceCurrent = null
        debugVisualTraceSource = source

        stateLabel.visibility = View.VISIBLE
        stateLabel.text = "Watching trace"

        setZoomOverviewEnabled(false)

        startNextDebugVisualTraceShot()
    }

    private fun startNextDebugVisualTraceShot() {
        if (!debugVisualTraceRunning) return

        val map = currentMap ?: run {
            stopDebugVisualTrace(restoreBoard = true)
            return
        }

        val shot = debugVisualTraceShots.getOrNull(debugVisualTraceShotListIndex)

        if (shot == null) {
            stopDebugVisualTrace(restoreBoard = true)

            OpenPigeonLog.i(
                TAG,
                "GOLF_ANDROID_TRACE=" + "{" + "\"kind\":\"debugVisualTraceComplete\"," + "\"source\":\"$debugVisualTraceSource\"," + "\"seed\":${map.seed}," + "\"mode\":\"${map.mode}\"," + "\"mapNum\":${map.mapNum}" + "}"
            )

            stateLabel.visibility = View.VISIBLE
            stateLabel.text = "Trace complete"
            return
        }

        if (shot.resetNativeBeforeShot) {
            GolfNativePhysics.reset()
        }

        val start = shot.explicitStart ?: if (debugVisualTraceShotListIndex == 0) {
            map.ballStart1
        } else {
            debugVisualTraceBall
        }

        debugVisualTraceBall = PointF(start.x, start.y)

        val velocity = GolfShot.launchVelocityVisual(
            GolfShot.Aim(
                dist = shot.dist, rotation = shot.rotation
            )
        )

        debugVisualTraceVelocity.set(
            velocity.x, velocity.y
        )

        debugVisualTraceCurrent = shot
        debugVisualTraceFrame = 0
        debugVisualTraceCaptured = false

        debugVisualTraceRunId =
            "${debugVisualTraceSource}_${map.seed}_${map.mapNum}_${shot.runIdSuffix}"

        runtimeBallCourse = PointF(
            debugVisualTraceBall.x, debugVisualTraceBall.y
        )

        renderer.setRuntimeBallCourse(runtimeBallCourse)
        renderer.setHoleState(
            flagPulled = false, ballInHole = false
        )
        renderer.setShotCamera(runtimeBallCourse, 0f)

        stateLabel.visibility = View.VISIBLE
        stateLabel.text = shot.label

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_TRACE=" + "{" + "\"kind\":\"debugVisualShotStart\"," + "\"runId\":\"$debugVisualTraceRunId\"," + "\"source\":\"$debugVisualTraceSource\"," + "\"seed\":${map.seed}," + "\"mode\":\"${map.mode}\"," + "\"mapNum\":${map.mapNum}," + "\"shotIndex\":${shot.shotIndex}," + "\"label\":\"${
                jsonEscape(shot.label)
            }\"," + "\"dist\":${shot.dist}," + "\"rotation\":${shot.rotation}," + "\"startPos\":{\"x\":${debugVisualTraceBall.x},\"y\":${debugVisualTraceBall.y}}," + "\"velocity\":{\"x\":${debugVisualTraceVelocity.x},\"y\":${debugVisualTraceVelocity.y}}" + "}"
        )

        renderer.removeCallbacks(debugVisualTraceTick)
        renderer.postDelayed(debugVisualTraceTick, DEBUG_VISUAL_TRACE_FRAME_DELAY_MS)
    }

    private fun stepDebugVisualTrace() {
        if (!debugVisualTraceRunning) return

        val map = currentMap ?: run {
            stopDebugVisualTrace(restoreBoard = true)
            return
        }

        val shot = debugVisualTraceCurrent ?: run {
            startNextDebugVisualTraceShot()
            return
        }

        val stoppedByMotion = try {
            GolfNativePhysics.setTraceContext(
                map = map,
                runId = debugVisualTraceRunId,
                shotIndex = shot.shotIndex,
                frame = debugVisualTraceFrame,
                phase = "visualNativeStep"
            )

            GolfPhysics.step(
                map = map,
                positionCourse = debugVisualTraceBall,
                velocityCourse = debugVisualTraceVelocity,
                dtSeconds = 1f / 60f
            )
        } finally {
            GolfNativePhysics.clearTraceContext()
        }

        val holeStep = GolfPhysics.applyHoleCup(
            map = map,
            positionCourse = debugVisualTraceBall,
            velocityCourse = debugVisualTraceVelocity,
            dtSeconds = 1f / 60f,
            alreadyCaptured = debugVisualTraceCaptured
        )

        debugVisualTraceCaptured = holeStep.captured

        runtimeBallCourse = PointF(
            debugVisualTraceBall.x, debugVisualTraceBall.y
        )

        renderer.setRuntimeBallCourse(runtimeBallCourse)
        renderer.setHoleState(
            flagPulled = holeStep.flagPulled, ballInHole = holeStep.captured
        )
        renderer.setShotCamera(runtimeBallCourse, 0f)

        val done =
            holeStep.settled || (stoppedByMotion && !holeStep.captured) || debugVisualTraceFrame >= DEBUG_VISUAL_TRACE_MAX_FRAMES_PER_SHOT

        debugVisualTraceFrame += 1

        if (!done) return

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_TRACE=" + "{" + "\"kind\":\"debugVisualShotStop\"," + "\"runId\":\"$debugVisualTraceRunId\"," + "\"source\":\"$debugVisualTraceSource\"," + "\"seed\":${map.seed}," + "\"mode\":\"${map.mode}\"," + "\"mapNum\":${map.mapNum}," + "\"shotIndex\":${shot.shotIndex}," + "\"label\":\"${
                jsonEscape(shot.label)
            }\"," + "\"frameCount\":$debugVisualTraceFrame," + "\"finalPos\":{\"x\":${debugVisualTraceBall.x},\"y\":${debugVisualTraceBall.y}}," + "\"finalVel\":{\"x\":${debugVisualTraceVelocity.x},\"y\":${debugVisualTraceVelocity.y}}," + "\"captured\":${holeStep.captured}," + "\"settled\":${holeStep.settled}," + "\"stoppedByMotion\":$stoppedByMotion" + "}"
        )

        debugVisualTraceShotListIndex += 1
        debugVisualTraceCurrent = null

        renderer.removeCallbacks(debugVisualTraceTick)

        if (debugVisualTraceRunning) {
            renderer.postDelayed({
                startNextDebugVisualTraceShot()
            }, 450L)
        }
    }

    private fun stopDebugVisualTrace(restoreBoard: Boolean) {
        if (!debugVisualTraceRunning && !restoreBoard) return

        debugVisualTraceRunning = false
        renderer.removeCallbacks(debugVisualTraceTick)

        GolfNativePhysics.clearTraceContext()
        GolfNativePhysics.reset()

        debugVisualTraceShots = emptyList()
        debugVisualTraceShotListIndex = 0
        debugVisualTraceFrame = 0
        debugVisualTraceCaptured = false
        debugVisualTraceCurrent = null
        debugVisualTraceRunId = ""

        if (!restoreBoard) return

        val savedBall = debugVisualTraceSavedBall

        runtimeBallCourse = savedBall?.let {
            PointF(it.x, it.y)
        } ?: currentMap?.let {
            PointF(it.ballStart1.x, it.ballStart1.y)
        }

        runtimeVelocityCourse.set(
            debugVisualTraceSavedVelocity.x, debugVisualTraceSavedVelocity.y
        )

        ballInHole = debugVisualTraceSavedBallInHole
        flagPulled = debugVisualTraceSavedFlagPulled
        waitingForOpponent = debugVisualTraceSavedWaitingForOpponent
        roundResultSent = debugVisualTraceSavedRoundResultSent

        renderer.setRuntimeBallCourse(runtimeBallCourse)
        renderer.setHoleState(
            flagPulled = flagPulled, ballInHole = ballInHole
        )
        renderer.clearAimPreview()
        renderer.clearReplayAimPreview()
        renderer.clearOpponentBallCourse()

        setZoomOverviewEnabled(debugVisualTraceSavedZoomOverviewEnabled)

        if (waitingForOpponent) {
            showWaitingLabelAnimated()
        } else {
            hideWaitingOverlay()
            updateAimReadyUi()
        }
    }

    private fun debugRunReplayTraceNow() {
        if (!GolfConstants.debugToolsEnabled) return
        val source = "debugMenuRunTrace"

        val data = gameData
        if (data == null) {
            OpenPigeonLog.w(
                TAG, "GOLF_ANDROID_TRACE={\"kind\":\"debugTraceSkip\",\"reason\":\"gameData null\"}"
            )
            return
        }

        val mapForCurrentData = currentMap?.takeIf {
            it.seed == data.seed && it.mode == data.mode && it.mapNum == data.mapNum
        } ?: run {
            try {
                generator.createMap(
                    seed = data.seed, mapNum = data.mapNum, mode = data.mode
                )
            } catch (t: Throwable) {
                OpenPigeonLog.e(TAG, "debugRunReplayTraceNow createMap failed", t)
                return
            }
        }

        lastReplayTraceKey = ""

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_TRACE=" + "{" + "\"kind\":\"debugTraceStart\"," + "\"source\":\"$source\"," + "\"seed\":${data.seed}," + "\"mode\":\"${data.mode}\"," + "\"dataMapNum\":${data.mapNum}," + "\"currentMapNum\":${mapForCurrentData.mapNum}," + "\"replayLen\":${data.replay.length}," + "\"replay2Len\":${data.replay2.length}" + "}"
        )

        GolfTrace.mapTruth(
            reason = "$source:traceMap", map = mapForCurrentData
        )

        maybeRunReplayTraceLab(
            source = source, data = data, map = mapForCurrentData
        )
    }

    private fun debugReplayCurrentHoleAgain() {
        if (!GolfConstants.debugToolsEnabled) return
        val data = gameData
        if (data == null) {
            OpenPigeonLog.w(TAG, "debugReplayCurrentHoleAgain skipped gameData null")
            return
        }

        val hasP1 = GolfReplay.hasSegment(data.replay, data.mapNum)
        val hasP2 = GolfReplay.hasSegment(data.replay2, data.mapNum)

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_TRACE=" + "{" + "\"kind\":\"debugReplayAgainStart\"," + "\"seed\":${data.seed}," + "\"mode\":\"${data.mode}\"," + "\"mapNum\":${data.mapNum}," + "\"hasP1\":$hasP1," + "\"hasP2\":$hasP2," + "\"replayLen\":${data.replay.length}," + "\"replay2Len\":${data.replay2.length}" + "}"
        )

        if (!hasP1 || !hasP2) {
            stateLabel.text = "Replay needs both players"
            return
        }

        stopBallPhysics(clearVelocity = true)
        stopDualReplay()
        stopStateLabelAnimation()

        waitingForOpponent = false
        roundResultSent = false
        ballInHole = false
        flagPulled = false
        dualReplayRunning = false
        dualReplayWaitingToFire = false

        seed = data.seed
        mode = data.mode
        holeCount = data.holeCount
        mapNum = data.mapNum

        generateAndShowMap(
            showIntro = false, source = "debugReplayCurrentHoleAgain"
        )

        renderer.post {
            startDualReplayFromData(data)
        }
    }

    private fun closeGameMenu() {
        if (::gameMenu.isInitialized) {
            gameMenu.closeMenu()
        }
    }

    private fun applyDebugUiState() {
        val effectiveDebugUiEnabled = GolfConstants.debugToolsEnabled && debugUiEnabled

        if (::renderer.isInitialized) {
            renderer.setDebugOverlayEnabled(
                effectiveDebugUiEnabled,
            )
        }

        if (::stateLabel.isInitialized) {
            stateLabel.visibility = if (effectiveDebugUiEnabled) {
                View.VISIBLE
            } else {
                View.GONE
            }
        }

        if (::debugMenuItem.isInitialized) {
            debugMenuItem.text = if (effectiveDebugUiEnabled) {
                "Debug: On"
            } else {
                "Debug: Off"
            }
        }
    }

    private fun buildAimInstructionLabel() {
        aimInstructionLabel = OutlineTextView(this).apply {
            text = "Pull back and release."
            setTextColor(Color.WHITE)
            textSize = 19f
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            typeface = Typeface.DEFAULT_BOLD
            visibility = View.GONE
            alpha = 1f
            setUiLayer(this, LAYER_HUD)
            includeFontPadding = false
            setPadding(dp(12), dp(6), dp(12), dp(30))

            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            )
        }

        root.addView(aimInstructionLabel)
    }

    private fun showAimReadyUi() {
        val ball = runtimeBallCourse ?: currentMap?.ballStart1 ?: return

        if (::aimInstructionLabel.isInitialized) {
            aimInstructionLabel.animate().cancel()

            if (aimInstructionLabel.visibility != View.VISIBLE) {
                aimInstructionLabel.alpha = 0f
                aimInstructionLabel.visibility = View.VISIBLE
            }

            aimInstructionLabel.animate().alpha(1f).setDuration(140L).start()

            aimInstructionLabel.bringToFront()
            bringGameMenuToFront()
        }

        renderer.setAimReadyIndicator(ball)
    }

    private fun hideAimReadyUi(immediate: Boolean = false) {
        if (::aimInstructionLabel.isInitialized) {
            aimInstructionLabel.animate().cancel()

            if (immediate) {
                aimInstructionLabel.alpha = 0f
                aimInstructionLabel.visibility = View.GONE
            } else if (aimInstructionLabel.isVisible) {
                aimInstructionLabel.animate().alpha(0f).setDuration(110L).withEndAction {
                    if (aimInstructionLabel.alpha <= 0.01f) {
                        aimInstructionLabel.visibility = View.GONE
                    }
                }.start()
            }
        }

        if (::renderer.isInitialized) {
            renderer.setAimReadyIndicator(null)
        }
    }

    private fun canAimNow(): Boolean {
        return !spectatorMode && currentMap != null && !physicsRunning && !dualReplayRunning && !dualReplayWaitingToFire && !waitingForOpponent && !ballInHole && !roundResultSent && !isAiming
    }

    private fun resetAimHapticState() {
        lastAimHapticMs = 0L
        lastAimHapticBucket = -1
    }

    private fun maybePlayAimHaptic(aim: GolfShot.Aim) {
        if (!aim.active) return
        if (!::renderer.isInitialized) return

        val now = SystemClock.elapsedRealtime()
        val bucket = (aim.dist / 7.5f).toInt()
        val bucketChanged = bucket != lastAimHapticBucket
        val timeReady = now - lastAimHapticMs >= 55L

        if (bucketChanged && timeReady) {
            renderer.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
            lastAimHapticMs = now
            lastAimHapticBucket = bucket
        }
    }

    private fun updateAimReadyUi() {
        if (canAimNow()) {
            showAimReadyUi()
        } else {
            hideAimReadyUi()
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun buildSkipReplayButton() {
        skipReplayNormalBitmap = loadUiBitmap(
            "global/skip_replay.png", "global/next.png"
        )

        skipReplayPressedBitmap = loadUiBitmap(
            "global/skip_replay_pressed.png", "global/next_pressed.png"
        ) ?: skipReplayNormalBitmap

        skipReplayButton = object : AppCompatImageButton(this) {
            override fun performClick(): Boolean {
                super.performClick()
                return true
            }
        }.apply {
            isVisible = false
            alpha = 1f
            background = null
            setBackgroundColor(Color.TRANSPARENT)
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = "Skip Replay"
            setUiLayer(this, LAYER_SKIP_REPLAY)

            if (skipReplayNormalBitmap != null) {
                setImageBitmap(skipReplayNormalBitmap)
            } else {
                setImageResource(android.R.drawable.ic_media_ff)
            }

            layoutParams = FrameLayout.LayoutParams(
                dp(82), dp(82), Gravity.TOP or Gravity.CENTER_HORIZONTAL
            )
        }

        skipReplayButton.setOnClickListener {
            skipDualReplayToEnd()
        }

        skipReplayButton.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    skipReplayPressedBitmap?.let { skipReplayButton.setImageBitmap(it) }
                    true
                }

                MotionEvent.ACTION_UP -> {
                    skipReplayNormalBitmap?.let { skipReplayButton.setImageBitmap(it) }
                    view.performClick()
                    true
                }

                MotionEvent.ACTION_CANCEL -> {
                    skipReplayNormalBitmap?.let { skipReplayButton.setImageBitmap(it) }
                    true
                }

                else -> true
            }
        }

        root.addView(skipReplayButton)

        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            positionSkipReplayButton()
        }

        root.post {
            positionSkipReplayButton()
        }
    }

    private fun loadUiBitmap(vararg paths: String): Bitmap? {
        for (path in paths.distinct()) {
            try {
                val bitmap = assets.open(path).use { BitmapFactory.decodeStream(it) }

                if (bitmap != null) {
                    OpenPigeonLog.i(
                        TAG, "UI asset loaded path=$path size=${bitmap.width}x${bitmap.height}"
                    )
                    return bitmap
                }

                OpenPigeonLog.w(TAG, "UI asset decoded null path=$path")
            } catch (_: Throwable) {
                OpenPigeonLog.w(TAG, "UI asset missing path=$path")
            }
        }

        OpenPigeonLog.w(
            TAG, "Unable to load any UI bitmap paths=${paths.distinct().joinToString()}"
        )
        return null
    }

    private fun loadGolfUiBitmap(fileName: String): Bitmap? {
        return loadUiBitmap(
            "golf/$fileName", "golf/reference_original/$fileName", fileName
        )
    }

    private fun positionSkipReplayButton() {
        if (!::skipReplayButton.isInitialized || root.height <= 0) return

        val params = skipReplayButton.layoutParams as FrameLayout.LayoutParams
        params.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL

        params.topMargin = ((root.height * 2f / 3f) - dp(41)).toInt().coerceAtLeast(dp(8))

        skipReplayButton.layoutParams = params
    }

    private fun showSkipReplayButton() {
        if (!::skipReplayButton.isInitialized) return

        positionSkipReplayButton()

        skipReplayButton.animate().cancel()
        skipReplayButton.alpha = 0f
        skipReplayButton.visibility = View.VISIBLE
        skipReplayButton.bringToFront()

        skipReplayButton.animate().alpha(1f).setDuration(220L).start()
    }

    private fun hideSkipReplayButton() {
        if (!::skipReplayButton.isInitialized) return

        skipReplayButton.animate().cancel()
        skipReplayButton.alpha = 0f
        skipReplayButton.visibility = View.GONE
        skipReplayNormalBitmap?.let { skipReplayButton.setImageBitmap(it) }
    }

    private fun skipDualReplayToEnd() {
        if (!dualReplayRunning && !dualReplayWaitingToFire) return

        OpenPigeonLog.i(TAG, "skipDualReplayToEnd shotIndex=$dualReplayShotIndex")
        finishDualReplay(immediateAdvance = true)
    }

    private fun handleMessage(msg: Map<String, String>) {
        val startedAt = SystemClock.elapsedRealtime()
        try {
            OpenPigeonLog.i(TAG, "handleMessage enter ${messageSummary(msg)}")
            lastMessage = msg

            val previousSeed = seed
            val previousMode = mode
            val previousMapNum = mapNum
            val previousData = gameData

            var parsed = GolfGameData.fromMessage(msg, previous = previousData)
            gameData = parsed

            seed = parsed.seed
            mode = parsed.mode
            holeCount = parsed.holeCount
            mapNum = parsed.mapNum
            player = parsed.player
            player1Id = parsed.player1Id
            player2Id = parsed.player2Id

            updateSpectatorMode(
                data = parsed, current = msg
            )

            val localPlayer = localPlayerNumberFor(parsed)
            val messageFromMe = isCurrentMessageFromMe(msg)

            val incomingLocalPlayableMapNum = if (spectatorMode) {
                null
            } else {
                firstLocalPlayableHoleForIncomingData(
                    data = parsed, localPlayer = localPlayer, messageFromMe = messageFromMe
                )
            }

            if (incomingLocalPlayableMapNum != null && incomingLocalPlayableMapNum != parsed.mapNum) {
                OpenPigeonLog.i(
                    TAG,
                    "handleMessage correcting incoming playable map " + "from parsedMapNum=${parsed.mapNum} to localPlayableMapNum=$incomingLocalPlayableMapNum " + "messageFromMe=$messageFromMe localPlayer=$localPlayer " + "replayLen=${parsed.replay.length} replay2Len=${parsed.replay2.length}"
                )

                parsed = parsed.copy(mapNum = incomingLocalPlayableMapNum)
                gameData = parsed
                mapNum = parsed.mapNum
            }

            localReplay = if (localPlayer == 1) {
                parsed.replay
            } else {
                parsed.replay2
            }

            traceParsedReplayVectors(
                data = parsed, localPlayer = localPlayer
            )

            if (!spectatorMode) {
                val opponentAvatar = if (localPlayer == 1) {
                    msg["avatar2"].orEmpty()
                } else {
                    msg["avatar1"].orEmpty()
                }

                if (opponentAvatar.isNotBlank() && ::gameMenu.isInitialized) {
                    runOnUiThread {
                        gameMenu.sheet.applyOpponentAvatarString(
                            opponentAvatar,
                        )
                    }
                }
            }

            OpenPigeonLog.i(
                TAG,
                "handleMessage parsed prev=($previousSeed,$previousMode,$previousMapNum) " + "now=(seed=$seed seedText=${parsed.seedText} unsignedSeed=${parsed.seedWasUnsignedDecimal} " + "mode=$mode holeCount=$holeCount mapNum=$mapNum rawNum=${parsed.rawNum} " + "messagePlayer=$player localPlayer=$localPlayer) " + "replayLen=${parsed.replay.length} replay2Len=${parsed.replay2.length} " + "renderKey=${parsed.renderKey}"
            )

            val renderSender = msg["sender"].orEmpty()
            val renderWinner = msg["winner"].orEmpty()

            if (parsed.renderKey == lastRenderedKey && renderSender == lastRenderedSender && renderWinner == lastRenderedWinner) {
                OpenPigeonLog.i(
                    TAG,
                    "handleMessage duplicate skipped renderKey=${parsed.renderKey} sender=$renderSender winner=$renderWinner " + "elapsedMs=${SystemClock.elapsedRealtime() - startedAt}"
                )
                return
            }

            lastRenderedKey = parsed.renderKey
            lastRenderedSender = renderSender
            lastRenderedWinner = renderWinner

            val currentHoleHasBothReplays = hasBothReplaysForHole(parsed, parsed.mapNum)
            val previousCompletedReplayMapNum = latestCompletedReplayHoleBeforeCurrent(parsed)
            val incomingWinnerResult = localResultFromWinnerValue(renderWinner)

            if (incomingWinnerResult != null && gameOverShown) {
                OpenPigeonLog.i(
                    TAG, "handleMessage winner ignored because gameOverShown winner=$renderWinner"
                )
                return
            }

            val completedReplayMapNumCandidate = when {
                currentHoleHasBothReplays -> {
                    parsed.mapNum
                }

                previousCompletedReplayMapNum != null -> {
                    previousCompletedReplayMapNum
                }

                else -> {
                    null
                }
            }

            val completedReplayIsFinalHole =
                completedReplayMapNumCandidate != null && completedReplayMapNumCandidate + 1 >= parsed.holeCount

            val replayAllowedByTurn = !messageFromMe || completedReplayIsFinalHole

            val replayMapNumCandidate =
                if (completedReplayMapNumCandidate != null && replayAllowedByTurn) {
                    completedReplayMapNumCandidate
                } else {
                    null
                }

            val replayKey = replayMapNumCandidate?.let { replayAutoKey(parsed, it) }

            val shouldReplay =
                replayMapNumCandidate != null && replayKey != null && replayKey != lastAutoReplayKey

            val replayData = replayMapNumCandidate?.let { replayMapNum ->
                parsed.copy(mapNum = replayMapNum)
            }

            replayStrokeHudLocked = shouldReplay

            OpenPigeonLog.i(
                TAG,
                "GOLF_ANDROID_REPLAY_DECISION=" + "{" + "\"parsedMapNum\":${parsed.mapNum}," + "\"replayMapNumCandidate\":${replayMapNumCandidate ?: -1}," + "\"holeCount\":${parsed.holeCount}," + "\"messagePlayer\":${parsed.player}," + "\"localPlayer\":$localPlayer," + "\"messageFromMe\":$messageFromMe," + "\"currentHoleHasBothReplays\":$currentHoleHasBothReplays," + "\"previousCompletedReplayMapNum\":${previousCompletedReplayMapNum ?: -1}," + "\"completedReplayMapNumCandidate\":${completedReplayMapNumCandidate ?: -1}," + "\"completedReplayIsFinalHole\":$completedReplayIsFinalHole," + "\"replayAllowedByTurn\":$replayAllowedByTurn," + "\"shouldReplay\":$shouldReplay," + "\"lastAutoReplayKeyMatches\":${replayKey != null && replayKey == lastAutoReplayKey}," + "\"lastAutoReplayKeyBlank\":${lastAutoReplayKey.isBlank()}," + "\"replayKeyBlank\":${replayKey.isNullOrBlank()}," + "\"replayLen\":${parsed.replay.length}," + "\"replay2Len\":${parsed.replay2.length}," + "\"replay\":\"${
                    parsed.replay.replace(
                        "\\", "\\\\"
                    ).replace("\"", "\\\"")
                }\"," + "\"replay2\":\"${
                    parsed.replay2.replace("\\", "\\\\").replace("\"", "\\\"")
                }\"" + "}"
            )

            if (incomingWinnerResult != null && !shouldReplay) {
                OpenPigeonLog.i(
                    TAG,
                    "handleMessage winner present without replay winner=$renderWinner localResult=$incomingWinnerResult"
                )

                waitingForOpponent = false
                stopStateLabelAnimation()

                generateAndShowMap(
                    showIntro = false, source = "handleMessage winner"
                )

                showGameOverFromData(
                    data = parsed,
                    shouldSendWinner = false,
                    forcedLocalResult = incomingWinnerResult
                )

                return
            }

            val replayIsFinalHole =
                replayMapNumCandidate != null && replayMapNumCandidate + 1 >= parsed.holeCount

            pendingGameOverForcedResult = if (shouldReplay && replayIsFinalHole) {
                incomingWinnerResult
            } else {
                null
            }

            pendingGameOverShouldSendWinner =
                shouldReplay && replayIsFinalHole && incomingWinnerResult == null

            waitingForOpponent = !spectatorMode && messageFromMe && !shouldReplay

            if (waitingForOpponent) {
                val waitingDisplayMapNum = waitingDisplayHoleForSentMessage(
                    data = parsed, localPlayer = localPlayer
                )

                if (waitingDisplayMapNum != null && waitingDisplayMapNum != parsed.mapNum) {
                    OpenPigeonLog.i(TAG, "handleMessage correcting waiting display map from parsedMapNum=${parsed.mapNum} to waitingDisplayMapNum=$waitingDisplayMapNum localPlayer=$localPlayer rawNum=${parsed.rawNum} replayLen=${parsed.replay.length} replay2Len=${parsed.replay2.length}")

                    parsed = parsed.copy(mapNum = waitingDisplayMapNum)
                    gameData = parsed
                    mapNum = parsed.mapNum

                    localReplay = if (localPlayer == 1) {
                        parsed.replay
                    } else {
                        parsed.replay2
                    }
                }
            }

            val shouldPreserveSettledHoleWhileWaiting =
                waitingForOpponent && currentMap != null && (ballInHole || roundResultSent)

            if (shouldPreserveSettledHoleWhileWaiting) {
                OpenPigeonLog.i(
                    TAG,
                    "handleMessage preserving settled hole while waiting mapNum=$mapNum " + "ballInHole=$ballInHole roundResultSent=$roundResultSent"
                )

                stopBallPhysics(clearVelocity = true)
                stopDualReplay()
                hideAimReadyUi()
                focusCameraOnCurrentBall()

                if (!sentWaitingSequenceActive) {
                    showWaitingLabelAnimated()
                }

                OpenPigeonLog.i(
                    TAG,
                    "handleMessage complete preserved waiting elapsedMs=${SystemClock.elapsedRealtime() - startedAt}"
                )
                return
            }

            when {
                shouldReplay && replayData != null -> {
                    waitingForOpponent = false
                    stopStateLabelAnimation()
                    hideWaitingOverlay()
                    hideAimReadyUi()

                    lastAutoReplayKey = replayKey
                    gameData = replayData
                    mapNum = replayData.mapNum

                    localReplay = if (localPlayer == 1) {
                        replayData.replay
                    } else {
                        replayData.replay2
                    }

                    setPreReplayStrokeHud(
                        data = replayData, localPlayer = localPlayer
                    )

                    OpenPigeonLog.i(
                        TAG,
                        "handleMessage replay selected parsedMapNum=${parsed.mapNum} " + "replayMapNum=${replayData.mapNum} " + "currentHoleHasBothReplays=$currentHoleHasBothReplays " + "previousCompletedReplayMapNum=${previousCompletedReplayMapNum ?: -1}"
                    )

                    generateAndShowMap(
                        showIntro = true,
                        source = "handleMessage replay map=${replayData.mapNum} parsedMap=${parsed.mapNum}",
                        updateStrokeHudAfterMap = false,
                        afterIntro = {
                            if (isFinishing || isDestroyed) return@generateAndShowMap

                            OpenPigeonLog.i(
                                TAG,
                                "handleMessage starting replay after intro replayMapNum=${replayData.mapNum} " + "parsedMapNum=${parsed.mapNum} " + "replayLen=${replayData.replay.length} replay2Len=${replayData.replay2.length}"
                            )

                            startDualReplayFromData(replayData)
                        })
                }

                spectatorMode -> {
                    waitingForOpponent = false

                    stopStateLabelAnimation()
                    hideWaitingOverlay()
                    hideAimReadyUi(immediate = true)
                    hideSkipReplayButton()

                    stopBallPhysics(clearVelocity = true)
                    stopDualReplay()

                    generateAndShowMap(
                        showIntro = false, source = "handleMessage spectator", afterIntro = {
                            if (isFinishing || isDestroyed) {
                                return@generateAndShowMap
                            }

                            hideWaitingOverlay()
                            hideAimReadyUi(immediate = true)

                            if (::spectatorLabel.isInitialized) {
                                spectatorLabel.visibility = View.VISIBLE
                                spectatorLabel.bringToFront()
                            }

                            renderer.clearAimPreview()
                            renderer.setAimReadyIndicator(null)
                            renderer.clearCameraFocus()
                        })
                }

                waitingForOpponent -> {
                    stopStateLabelAnimation()
                    hideAimReadyUi()

                    generateAndShowMap(
                        showIntro = true, source = "handleMessage waiting", afterIntro = {
                            if (isFinishing || isDestroyed) return@generateAndShowMap

                            focusCameraOnCurrentBall()

                            if (!sentWaitingSequenceActive) {
                                showWaitingLabelAnimated()
                            }
                        })
                }

                else -> {
                    waitingForOpponent = false
                    stopStateLabelAnimation()
                    hideWaitingOverlay()

                    generateAndShowMap(
                        showIntro = true, source = "handleMessage our turn", afterIntro = {
                            if (isFinishing || isDestroyed) return@generateAndShowMap

                            updateAimReadyUi()
                            focusCameraOnCurrentBall()
                        })
                }
            }

            OpenPigeonLog.i(
                TAG, "handleMessage complete elapsedMs=${SystemClock.elapsedRealtime() - startedAt}"
            )
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "Failed to open Mini Golf message ${messageSummary(msg)}", t)

            runCatching {
                stopBallPhysics(clearVelocity = true)
                stopDualReplay()
                GolfNativePhysics.reset()
            }.onFailure { cleanupError ->
                OpenPigeonLog.e(TAG, "handleMessage cleanup failed", cleanupError)
            }

            waitingForOpponent = false
            stopStateLabelAnimation()
            hideAimReadyUi()
            hideSkipReplayButton()

            if (currentMap != null) {
                stateLabel.text = "Mini Golf recovered"
                renderer.clearReplayAimPreview()
                renderer.clearOpponentBallCourse()
                renderer.setRuntimeBallCourse(runtimeBallCourse)
                updateAimReadyUi()
                focusCameraOnCurrentBall()

                OpenPigeonLog.w(
                    TAG,
                    "handleMessage recovered on existing map instead of default fallback " + "seed=$seed mode=$mode mapNum=$mapNum"
                )

                return
            }

            stateLabel.text = "Mini Golf failed to load - using local visual fallback"
            seed = GolfConstants.DEFAULT_SEED
            mode = GolfConstants.DEFAULT_MODE
            holeCount = GolfConstants.holeCountFor(mode)
            mapNum = 0
            gameData = GolfGameData.fromMessage(defaultLocalMessage(), previous = null)
            generateAndShowMap(showIntro = false, source = "handleMessage fallback")
        }
    }

    @Suppress("SameReturnValue")
    private fun handleGolfTouch(event: MotionEvent): Boolean {
        if (spectatorMode) {
            return true
        }

        val g = currentMap ?: return true
        if (dualReplayRunning) {
            return true
        }

        if (waitingForOpponent) {
            return true
        }

        if (physicsRunning) {
            return true
        }

        if (ballInHole) {
            return true
        }

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val course = renderer.screenToCourse(event.x, event.y)
                val visual = renderer.screenToVisual(event.x, event.y)

                OpenPigeonLog.i(
                    TAG,
                    "touch DOWN screen=(${event.x},${event.y}) course=(${course.x},${course.y}) visual=(${visual.x},${visual.y})"
                )

                if (!renderer.isScreenNearPrimaryBall(event.x, event.y)) {
                    OpenPigeonLog.i(TAG, "touch DOWN ignored: not near primary ball")
                    return true
                }

                if (!canAimNow()) {
                    OpenPigeonLog.i(TAG, "touch DOWN ignored: ball is not ready to aim")
                    return true
                }

                hideAimReadyUi()
                resetAimHapticState()
                renderer.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)

                isAiming = true
                aimMoveStartVisual = visual
                activeAim = GolfShot.Aim.NONE

                stopBallPhysics(clearVelocity = true)

                val ball = runtimeBallCourse ?: g.ballStart1
                renderer.setAimingCamera(ball, GolfShot.Aim.NONE)
                renderer.clearAimPreview()

                return true
            }

            MotionEvent.ACTION_MOVE -> {
                if (!isAiming) return true

                val ball = runtimeBallCourse ?: g.ballStart1
                val visual = renderer.screenToVisual(event.x, event.y)

                activeAim = GolfShot.computeAim(
                    moveStartVisual = aimMoveStartVisual, currentTouchVisual = visual
                )
                renderer.setAimingCamera(ball, activeAim)
                renderer.setAimPreview(ball, activeAim)
                maybePlayAimHaptic(activeAim)

                OpenPigeonLog.i(
                    TAG,
                    "touch MOVE visual=(${visual.x},${visual.y}) aimDist=${activeAim.dist} aimRot=${activeAim.rotation}"
                )

                return true
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (!isAiming) return true

                isAiming = false
                renderer.clearAimPreview()

                OpenPigeonLog.i(
                    TAG,
                    "touch UP aimDist=${activeAim.dist} aimRot=${activeAim.rotation} action=${event.actionMasked}"
                )

                if (event.actionMasked == MotionEvent.ACTION_UP && activeAim.active) {
                    launchCurrentAim(activeAim)
                } else {
                    val ball = runtimeBallCourse ?: primaryBallStartFor(g)
                    renderer.setAimingCamera(ball, GolfShot.Aim.NONE)
                    updateAimReadyUi()
                }

                resetAimHapticState()
                activeAim = GolfShot.Aim.NONE
                return true
            }
        }

        return true
    }

    private fun launchCurrentAim(aim: GolfShot.Aim) {
        hideAimReadyUi()

        val ball = runtimeBallCourse ?: currentMap?.ballStart1 ?: return
        val replayRotationCourse = -aim.rotation

        val velocityVisual = GolfShot.launchVelocityVisual(aim)
        val velocityCourse = renderer.visualDeltaToCourseDelta(
            dxVisual = velocityVisual.x, dyVisual = velocityVisual.y
        )

        localReplay = GolfReplay.appendShot(
            replay = localReplay, holeIndex = mapNum, shot = GolfReplay.Shot(
                dist = aim.dist, rotation = replayRotationCourse
            )
        )

        updateStrokeHud()

        GolfTrace.localLaunch(
            map = currentMap,
            localPlayer = localPlayerNumberFor(gameData),
            mapNum = mapNum,
            shotIndex = GolfReplay.segmentAt(localReplay, mapNum).size,
            ballCourse = ball,
            ballVisual = renderer.courseToVisual(ball),
            dist = aim.dist,
            rotation = replayRotationCourse,
            velocityVisual = velocityVisual,
            velocityCourse = velocityCourse,
            replay = localReplay
        )

        runtimeVelocityCourse.set(
            velocityCourse.x, velocityCourse.y
        )

        runtimeBallCourse = PointF(ball.x, ball.y)
        renderer.setRuntimeBallCourse(runtimeBallCourse)
        renderer.setShotCamera(runtimeBallCourse, 0f)

        OpenPigeonLog.i(
            TAG,
            "launch aimDist=${aim.dist} " + "aimRotVisual=${aim.rotation} " + "replayRotCourse=$replayRotationCourse " + "velVisual=(${velocityVisual.x},${velocityVisual.y}) " + "velCourse=(${runtimeVelocityCourse.x},${runtimeVelocityCourse.y}) " + "localReplayLen=${localReplay.length}"
        )

        stateLabel.text = "Shot dist=${"%.1f".format(aim.dist)}"

        startBallPhysics()
    }

    private fun startBallPhysics() {
        hideAimReadyUi()
        physicsRunning = true
        lastPhysicsMs = SystemClock.elapsedRealtime()
        renderer.removeCallbacks(physicsTick)
        renderer.postOnAnimation(physicsTick)
    }

    private fun stopBallPhysics(clearVelocity: Boolean) {
        physicsRunning = false
        renderer.removeCallbacks(physicsTick)

        if (clearVelocity) {
            runtimeVelocityCourse.set(0f, 0f)
        }
    }

    private fun speedOf(v: PointF): Float {
        return kotlin.math.sqrt(v.x * v.x + v.y * v.y)
    }

    private fun maybeTriggerBumperPulse(
        map: GolfMap, ball: PointF, beforeVelocity: PointF, afterVelocity: PointF, source: String
    ) {
        if (map.obstacles.none { it.bouncy }) return

        val beforeSpeed = speedOf(beforeVelocity)
        val afterSpeed = speedOf(afterVelocity)
        val speedJump = afterSpeed - beforeSpeed
        if (speedJump < 120f) return

        var nearestBouncy: GolfObstacle? = null
        var nearestDist2 = Float.POSITIVE_INFINITY

        for (obstacle in map.obstacles) {
            if (!obstacle.bouncy) continue

            val dx = obstacle.x - ball.x
            val dy = obstacle.y - ball.y
            val d2 = dx * dx + dy * dy

            if (d2 < nearestDist2) {
                nearestDist2 = d2
                nearestBouncy = obstacle
            }
        }

        val bumper = nearestBouncy ?: return

        if (nearestDist2 <= 45f * 45f) {
            renderer.pulseBumperAtCourse(bumper.x, bumper.y)

            OpenPigeonLog.i(
                TAG,
                "GOLF_ANDROID_BUMPER_PULSE_TRIGGER source=$source " + "bumper=(${bumper.x},${bumper.y}) " + "ball=(${ball.x},${ball.y}) " + "beforeSpeed=$beforeSpeed afterSpeed=$afterSpeed speedJump=$speedJump"
            )
        }
    }

    private fun stepBallPhysics() {
        val g = currentMap ?: return
        val ball = runtimeBallCourse ?: return

        val now = SystemClock.elapsedRealtime()
        val dt = ((now - lastPhysicsMs).coerceIn(1L, 34L)).toFloat() / 1000f
        lastPhysicsMs = now

        val wasInHole = ballInHole

        val beforeVelocity = PointF(runtimeVelocityCourse.x, runtimeVelocityCourse.y)

        val stoppedByMotion = GolfPhysics.step(
            map = g, positionCourse = ball, velocityCourse = runtimeVelocityCourse, dtSeconds = dt
        )

        maybeTriggerBumperPulse(
            map = g,
            ball = ball,
            beforeVelocity = beforeVelocity,
            afterVelocity = runtimeVelocityCourse,
            source = "local"
        )

        val holeStep = GolfPhysics.applyHoleCup(
            map = g,
            positionCourse = ball,
            velocityCourse = runtimeVelocityCourse,
            dtSeconds = dt,
            alreadyCaptured = wasInHole
        )

        GolfTrace.holeCup(
            phase = "localAfterApplyHoleCup",
            map = g,
            pos = ball,
            vel = runtimeVelocityCourse,
            holeStep = holeStep,
            alreadyCaptured = wasInHole
        )

        flagPulled = holeStep.flagPulled
        ballInHole = holeStep.captured

        renderer.setRuntimeBallCourse(ball)
        renderer.setHoleState(
            flagPulled = flagPulled, ballInHole = ballInHole
        )

        GolfTrace.frame(
            kind = "localFrame",
            map = currentMap,
            localPlayer = localPlayerNumberFor(gameData),
            mapNum = mapNum,
            shotIndex = GolfReplay.segmentAt(localReplay, mapNum).size,
            mineBallCourse = ball,
            opponentBallCourse = null,
            mineVelocityCourse = runtimeVelocityCourse,
            opponentVelocityCourse = null
        )

        if (holeStep.captured && !wasInHole) {
            hideAimReadyUi()
            OpenPigeonLog.i(
                TAG,
                "hole entered ball=(${ball.x},${ball.y}) hole=(${g.hole.x},${g.hole.y}) " + "velocity=(${runtimeVelocityCourse.x},${runtimeVelocityCourse.y})"
            )

            stateLabel.text = "In the hole"
        }

        if (holeStep.settled) {
            hideAimReadyUi()

            OpenPigeonLog.i(
                TAG, "hole settled ball=(${ball.x},${ball.y}) hole=(${g.hole.x},${g.hole.y})"
            )

            renderer.setRuntimeBallCourse(ball)
            renderer.setHoleState(
                flagPulled = true, ballInHole = true
            )

            stopBallPhysics(clearVelocity = true)
            restoringLastShot = false
            recoverySettledBallCourse = null

            if (!roundResultSent) {
                saveGolfProgress("roundComplete", ball)
                roundResultSent = true
                sendCompletedRoundState()
            }

            return
        }

        if (stoppedByMotion && !ballInHole) {
            OpenPigeonLog.i(TAG, "physics stop ball=(${ball.x},${ball.y}) velocity=(${runtimeVelocityCourse.x},${runtimeVelocityCourse.y}) flagPulled=$flagPulled")

            stopBallPhysics(clearVelocity = true)

            if (restoringLastShot) {
                recoverySettledBallCourse?.let {
                    ball.x = it.x
                    ball.y = it.y
                    runtimeBallCourse = PointF(it.x, it.y)
                    renderer.setRuntimeBallCourse(runtimeBallCourse)
                }
                restoringLastShot = false
                recoverySettledBallCourse = null
            }

            saveGolfProgress("aim", runtimeBallCourse)
            updateStrokeHud()
            updateAimReadyUi()
            focusCameraOnCurrentBall()
        }
    }

    private fun showGameContentOnceBoardReady() {
        if (gameContentShown || !::root.isInitialized || !::renderer.isInitialized) {
            return
        }

        gameContentShown = true

        renderer.visibility = View.VISIBLE

        root.animate().cancel()
        root.visibility = View.VISIBLE
        root.alpha = 1f

        OpenPigeonLog.i(TAG, "Game content shown after board ready")
    }

    private fun generateAndShowMap(
        showIntro: Boolean,
        source: String,
        afterIntro: (() -> Unit)? = null,
        updateStrokeHudAfterMap: Boolean = true
    ) {
        val startedAt = SystemClock.elapsedRealtime()
        OpenPigeonLog.i(
            TAG,
            "generateAndShowMap enter source=$source seed=$seed mode=$mode mapNum=$mapNum holeCount=$holeCount showIntro=$showIntro"
        )

        hideGameOverLabel()

        try {
            val generated = generator.createMap(seed, mapNum, mode)
            OpenPigeonLog.i(
                TAG,
                "generateAndShowMap generated ${generated.summary()} elapsedMs=${SystemClock.elapsedRealtime() - startedAt}"
            )

            currentMap = generated
            stopDualReplay()
            roundResultSent = false

            val localStart = primaryBallStartFor(generated)

            runtimeBallCourse = PointF(
                localStart.x, localStart.y
            )
            stopBallPhysics(clearVelocity = true)
            activeAim = GolfShot.Aim.NONE
            isAiming = false
            flagPulled = false
            ballInHole = false

            renderer.setMap(generated)

            GolfTrace.mapTruth(
                reason = source, map = generated
            )

            gameData?.let { data ->
                maybeRunReplayTraceLab(
                    source = "generateAndShowMap:$source", data = data, map = generated
                )
            }

            showGameContentOnceBoardReady()

            renderer.setRuntimeBallCourse(runtimeBallCourse)
            renderer.setHoleState(flagPulled = false, ballInHole = false)
            renderer.clearAimPreview()
            renderer.clearOpponentBallCourse()
            renderer.clearReplayAimPreview()

            setZoomOverviewEnabled(false)
            renderer.clearCameraFocus()
            stateLabel.text =
                "Hole ${generated.holeNumber}/${generated.holeCount}   seed=$seed   ${generated.xCells}x${generated.yCells}"
            if (showIntro) {
                showHoleIntro(
                    hole = generated.holeNumber,
                    total = generated.holeCount,
                    onComplete = afterIntro
                )
            } else {
                afterIntro?.invoke()
            }

            if (updateStrokeHudAfterMap) {
                updateStrokeHud()
            }

            updateAimReadyUi()
        } catch (t: Throwable) {
            OpenPigeonLog.e(
                TAG,
                "generateAndShowMap failed source=$source seed=$seed mode=$mode mapNum=$mapNum",
                t
            )
            throw t
        }
    }

    private fun showHoleIntro(
        hole: Int, total: Int, onComplete: (() -> Unit)? = null
    ) {
        OpenPigeonLog.i(TAG, "showHoleIntro hole=$hole total=$total")

        closeGameMenu()

        holeOverlay.animate().cancel()
        holeIntroContainer.animate().cancel()
        holeTitle.animate().cancel()
        holePoleImage.animate().cancel()

        holeTitle.text = "Hole $hole/$total"

        setUiLayer(holeOverlay, LAYER_INTRO)
        holeOverlay.visibility = View.VISIBLE
        holeOverlay.alpha = 1f
        holeOverlay.bringToFront()
        applyOverlayOrdering()

        holeIntroContainer.alpha = 0f
        holeIntroContainer.scaleX = 1f
        holeIntroContainer.scaleY = 1f

        holeIntroContainer.animate().alpha(1f).setDuration(GolfConstants.INTRO_FADE_IN_MS)
            .withEndAction {
                OpenPigeonLog.i(TAG, "showHoleIntro container fade-in complete hole=$hole")

                holeIntroContainer.animate().setStartDelay(GolfConstants.INTRO_HOLD_MS).scaleX(1.7f)
                    .scaleY(1.7f).alpha(0f).setDuration(GolfConstants.INTRO_SCALE_MS).start()
            }.start()

        holeOverlay.animate().setStartDelay(GolfConstants.INTRO_FADE_OUT_DELAY_MS).alpha(0f)
            .setDuration(GolfConstants.INTRO_FADE_OUT_MS).withEndAction {
                OpenPigeonLog.i(TAG, "showHoleIntro overlay hidden hole=$hole")
                holeOverlay.visibility = View.GONE

                if (onComplete != null) {
                    renderer.postDelayed(
                        {
                            if (!isFinishing && !isDestroyed) {
                                OpenPigeonLog.i(
                                    TAG,
                                    "showHoleIntro full-map hold complete hole=$hole " + "delayMs=${GolfConstants.MAP_OVERVIEW_HOLD_AFTER_INTRO_MS}"
                                )
                                onComplete.invoke()
                            }
                        }, GolfConstants.MAP_OVERVIEW_HOLD_AFTER_INTRO_MS
                    )
                }
            }.start()
    }

    private fun showWaitingOverlay() {
        closeGameMenu()
        hideAimReadyUi()
        if (!::waitingOverlay.isInitialized) return

        waitingOverlay.animate().cancel()
        waitingOverlay.alpha = 1f
        waitingOverlay.visibility = View.VISIBLE
        waitingOverlay.bringToFront()
        setUiLayer(waitingOverlay, LAYER_WAITING)
        applyOverlayOrdering()
    }

    private fun hideWaitingOverlay() {
        if (!::waitingOverlay.isInitialized) return

        waitingOverlay.animate().cancel()
        waitingOverlay.alpha = 0f
        waitingOverlay.visibility = View.GONE
    }

    private fun resetWaitingLabelLayout(label: TextView) {
        label.animate().cancel()
        label.alpha = 1f
        label.scaleX = 1f
        label.scaleY = 1f
        label.minWidth = 0
        label.gravity = Gravity.CENTER
        label.textAlignment = View.TEXT_ALIGNMENT_CENTER
        label.setTextColor(Color.WHITE)
        label.background = rounded(Color.argb(187, 0, 0, 0), dp(14).toFloat())
        label.maxLines = 1

        val params = label.layoutParams
        params.width = FrameLayout.LayoutParams.WRAP_CONTENT
        params.height = FrameLayout.LayoutParams.WRAP_CONTENT
        label.layoutParams = params
    }

    private fun measureWaitingLabelWidth(label: TextView, text: CharSequence): Int {
        return ceil(
            label.paint.measureText(text.toString()) + label.paddingLeft + label.paddingRight
        ).toInt()
    }

    private fun shouldKeepWaitingOverlayDuringExit(): Boolean {
        return activityExiting && waitingForOpponent && ::waitingOverlay.isInitialized && waitingOverlay.isVisible
    }

    private fun stopWaitingTimersWithoutHidingOverlay() {
        waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }
        waitingDotsRunnable = null

        stateLabelAnimator?.cancel()
        stateLabelAnimator = null

        sentWaitingSequenceActive = false

        if (::waitingOverlay.isInitialized) {
            waitingOverlay.animate().cancel()
            waitingOverlay.alpha = 1f
            waitingOverlay.visibility = View.VISIBLE
            waitingOverlay.bringToFront()
        }
    }

    private fun stopStateLabelAnimation() {
        waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }
        stateLabelHandler.removeCallbacksAndMessages(null)
        waitingDotsRunnable = null

        stateLabelAnimator?.cancel()
        stateLabelAnimator = null

        sentWaitingSequenceActive = false
        hideWaitingOverlay()
    }

    private fun startWaitingDots(label: TextView) {
        var dots = 0

        waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }

        val runnable = object : Runnable {
            override fun run() {
                if (waitingDotsRunnable !== this) return

                if (::waitingOverlay.isInitialized && waitingOverlay.isVisible && label.isVisible) {
                    dots = if (dots >= 3) {
                        1
                    } else {
                        dots + 1
                    }

                    label.text = "WAITING FOR OPPONENT" + ".".repeat(dots)
                }

                stateLabelHandler.postDelayed(this, 900L)
            }
        }

        waitingDotsRunnable = runnable
        stateLabelHandler.post(runnable)
    }

    private fun showWaitingLabelAnimated() {
        runOnUiThread {
            stopStateLabelAnimation()
            showWaitingOverlay()

            resetWaitingLabelLayout(waitingLabel)

            val waitingWidth = measureWaitingLabelWidth(waitingLabel, "WAITING FOR OPPONENT...")
            val params = waitingLabel.layoutParams
            params.width = waitingWidth
            waitingLabel.layoutParams = params

            waitingLabel.visibility = View.VISIBLE
            startWaitingDots(waitingLabel)
        }
    }

    private fun showSendingLabelImmediately() {
        runOnUiThread {
            stopStateLabelAnimation()
            showWaitingOverlay()
            sentWaitingSequenceActive = true
            resetWaitingLabelLayout(waitingLabel)

            val sentWidth = measureWaitingLabelWidth(waitingLabel, "Sent ✔")
            val params = waitingLabel.layoutParams
            params.width = sentWidth
            waitingLabel.layoutParams = params

            waitingLabel.text = "Sent"
            waitingLabel.alpha = 1f
            waitingLabel.setTextColor(Color.WHITE)
            waitingLabel.visibility = View.VISIBLE
            waitingLabel.bringToFront()
        }
    }

    private fun playSentThenWaitingAnimation() {
        runOnUiThread {
            stopStateLabelAnimation()
            showWaitingOverlay()
            sentWaitingSequenceActive = true
            resetWaitingLabelLayout(waitingLabel)

            val sentWidth = measureWaitingLabelWidth(waitingLabel, "Sent ✔")
            val waitingWidth = measureWaitingLabelWidth(waitingLabel, "WAITING FOR OPPONENT...")
            val params = waitingLabel.layoutParams
            params.width = sentWidth
            waitingLabel.layoutParams = params

            val sentCheck = SpannableString("Sent ✔")
            sentCheck.setSpan(ForegroundColorSpan(0xFF7257D8.toInt()), 5, 6, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            waitingLabel.text = sentCheck
            waitingLabel.alpha = 1f
            waitingLabel.setTextColor(Color.WHITE)
            waitingLabel.visibility = View.VISIBLE
            waitingLabel.bringToFront()

            stateLabelHandler.postDelayed({
                if (!sentWaitingSequenceActive) return@postDelayed

                val oldWidth = waitingLabel.width.takeIf { it > 0 } ?: sentWidth
                val widthParams = waitingLabel.layoutParams
                widthParams.width = oldWidth
                waitingLabel.layoutParams = widthParams

                waitingLabel.animate().cancel()
                waitingLabel.alpha = 1f
                waitingLabel.text = "WAITING FOR OPPONENT."
                waitingLabel.setTextColor(0x00FFFFFF)

                stateLabelAnimator = ValueAnimator.ofInt(oldWidth, waitingWidth).apply {
                    duration = 420L

                    addUpdateListener {
                        val animatedParams = waitingLabel.layoutParams
                        animatedParams.width = it.animatedValue as Int
                        waitingLabel.layoutParams = animatedParams
                    }

                    addListener(object : AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animation: Animator) {
                            if (!sentWaitingSequenceActive) return
                            stateLabelAnimator = null
                            val finalParams = waitingLabel.layoutParams
                            finalParams.width = waitingWidth
                            waitingLabel.layoutParams = finalParams

                            ValueAnimator.ofInt(0, 255).apply {
                                duration = 180L
                                addUpdateListener { textAnimation -> waitingLabel.setTextColor(((textAnimation.animatedValue as Int) shl 24) or 0x00FFFFFF) }
                                addListener(object : AnimatorListenerAdapter() {
                                    override fun onAnimationEnd(animation: Animator) {
                                        if (sentWaitingSequenceActive) {
                                            waitingLabel.setTextColor(Color.WHITE)
                                            startWaitingDots(waitingLabel)
                                        }
                                    }
                                })
                                start()
                            }
                        }
                    })

                    start()
                }
            }, 1000L)
        }
    }

    private fun setZoomOverviewEnabled(enabled: Boolean) {
        zoomOverviewEnabled = enabled
        renderer.setOverviewCameraHeld(enabled)

        if (::zoomButton.isInitialized) {
            zoomButton.alpha = if (enabled) 1f else 0.72f
        }

        OpenPigeonLog.i(TAG, "Zoom overview enabled=$enabled")
    }

    private fun sendCompletedRoundState() {
        sendCurrentGolfState()
    }

    private fun safeBuildAvatarString(fallback: String): String {
        return runCatching {
            AvatarView.buildAvatarString()
        }.getOrElse { t ->
            OpenPigeonLog.e(
                TAG, "AvatarView.buildAvatarString failed; preserving existing avatar", t
            )
            fallback
        }
    }

    private fun sendCurrentGolfState() {
        val ipc = gameSessionIPC
        if (ipc == null || sessionId.isBlank()) {
            OpenPigeonLog.w(TAG, "sendCurrentGolfState skipped ipcNull=${ipc == null} sessionBlank=${sessionId.isBlank()}")
            return
        }

        try {
            val current = ipc.getCurrentMessage(sessionId).ifEmpty { lastMessage }
            val currentData = GolfGameData.fromMessage(current, previous = gameData)
            val myId = ipc.getSenderUUID(sessionId).takeIf { it.isNotBlank() }.orEmpty()
            val localPlayer = localPlayerNumberFor(currentData, current)
            val existingPlayer1 = current["player1"].orEmpty().ifBlank { currentData.player1Id }.ifBlank { player1Id }
            val existingPlayer2 = current["player2"].orEmpty().ifBlank { currentData.player2Id }.ifBlank { player2Id }
            val existingAvatar1 = current["avatar1"].orEmpty()
            val existingAvatar2 = current["avatar2"].orEmpty()
            val existingReplay = currentData.replay
            val existingReplay2 = currentData.replay2
            val outgoing = current.toMutableMap()

            outgoing["game"] = "golf"
            outgoing["game_name"] = "Mini Golf"
            outgoing["version"] = "41"
            outgoing["v3"] = "3"
            outgoing["mode"] = mode
            outgoing["seed"] = current["seed"]?.takeIf { it.isNotBlank() } ?: seed.toString()
            outgoing["sender"] = myId
            outgoing["player"] = localPlayer.toString()
            outgoing["num"] = (mapNum + 2).coerceAtMost(holeCount + 1).toString()

            if (localPlayer == 1) {
                outgoing["player1"] = myId
                outgoing["avatar1"] = safeBuildAvatarString(existingAvatar1)
                if (existingPlayer2.isNotBlank()) outgoing["player2"] = existingPlayer2
                if (existingAvatar2.isNotBlank()) outgoing["avatar2"] = existingAvatar2
                val p1ReplayToSend = localReplay.ifBlank { existingReplay }
                if (p1ReplayToSend.isNotBlank()) outgoing["replay"] = p1ReplayToSend
                if (existingReplay2.isNotBlank()) outgoing["replay2"] = existingReplay2
            } else {
                if (existingPlayer1.isNotBlank()) outgoing["player1"] = existingPlayer1
                if (existingAvatar1.isNotBlank()) outgoing["avatar1"] = existingAvatar1
                outgoing["player2"] = myId
                outgoing["avatar2"] = safeBuildAvatarString(existingAvatar2)
                val p2ReplayToSend = localReplay.ifBlank { existingReplay2 }
                if (existingReplay.isNotBlank()) outgoing["replay"] = existingReplay
                if (p2ReplayToSend.isNotBlank()) outgoing["replay2"] = p2ReplayToSend
            }

            if (outgoing["replay"].isNullOrBlank()) outgoing.remove("replay")
            if (outgoing["replay2"].isNullOrBlank()) outgoing.remove("replay2")

            gameData = GolfGameData.fromMessage(outgoing, previous = currentData)
            waitingForOpponent = true
            hideAimReadyUi()
            focusCameraOnCurrentBall()
            showSendingLabelImmediately()

            OpenPigeonLog.i(TAG, "sendCurrentGolfState roundComplete=true localPlayer=$localPlayer myId=$myId p1=${outgoing["player1"].orEmpty()} p2=${outgoing["player2"].orEmpty()} num=${outgoing["num"]} replayLen=${outgoing["replay"].orEmpty().length} replay2Len=${outgoing["replay2"].orEmpty().length}")

            val dispatched = ipc.updateSession(outgoing, sessionId) {
                runOnUiThread {
                    recoveryRetryInFlight = false
                    cancelPendingRecoveryCheck()
                    hideTurnRecoveryRetry()
                    waitingForOpponent = true
                    hideAimReadyUi()
                    focusCameraOnCurrentBall()
                    playSentThenWaitingAnimation()
                }
            }

            if (!dispatched) {
                showTurnRecoveryRetry()
                return
            }

            schedulePendingSendCheck()
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "sendCurrentGolfState failed roundComplete=true", t)
            val pending = try { ipc.hasPendingSend(sessionId) } catch (_: Throwable) { false }
            if (pending) showTurnRecoveryRetry()
        }
    }

    private fun updateSpectatorMode(
        data: GolfGameData, current: Map<String, String>
    ) {
        val myId = runCatching {
            gameSessionIPC?.getSenderUUID(sessionId)
        }.getOrNull().orEmpty()

        val p1 = current["player1"].orEmpty().ifBlank { data.player1Id }

        val p2 = current["player2"].orEmpty().ifBlank { data.player2Id }

        spectatorMode =
            myId.isNotBlank() && p1.isNotBlank() && p2.isNotBlank() && myId != p1 && myId != p2

        if (::spectatorLabel.isInitialized) {
            spectatorLabel.visibility = if (spectatorMode) View.VISIBLE else View.GONE

            if (spectatorMode) {
                spectatorLabel.text = "Spectating..."
                spectatorLabel.bringToFront()
            }
        }

        if (::localAvatarYouLabel.isInitialized) {
            localAvatarYouLabel.visibility = if (spectatorMode) View.GONE else View.VISIBLE
        }

        if (spectatorMode) {
            applySpectatorAvatars(current)
        }

        if (spectatorMode) {
            waitingForOpponent = false
            stopStateLabelAnimation()
            hideWaitingOverlay()
            hideAimReadyUi(immediate = true)
            hideSkipReplayButton()

            isAiming = false
            activeAim = GolfShot.Aim.NONE
            renderer.clearAimPreview()
            renderer.setAimReadyIndicator(null)
        }

        configureSettingsAvatarTarget()

        OpenPigeonLog.i(
            TAG,
            "updateSpectatorMode spectator=$spectatorMode " + "myIdBlank=${myId.isBlank()} " + "p1Blank=${p1.isBlank()} p2Blank=${p2.isBlank()}"
        )
    }

    private fun findAvatarView(
        anchor: FrameLayout
    ): AvatarView? {
        for (index in 0 until anchor.childCount) {
            val child = anchor.getChildAt(index)

            if (child is AvatarView) {
                return child
            }
        }

        return null
    }

    private fun applyAvatarToAnchor(
        anchor: FrameLayout, avatarString: String
    ) {
        val avatarView = findAvatarView(anchor) ?: return

        if (avatarString.isBlank()) {
            avatarView.showPlaceholder()
        } else {
            avatarView.applyFromOpponentString(avatarString)
        }

        normalizeAvatarAnchor(anchor)
    }

    private fun applySpectatorAvatars(
        message: Map<String, String>
    ) {
        if (!spectatorMode) return

        applyAvatarToAnchor(
            anchor = gameAvatarAnchor, avatarString = message["avatar1"].orEmpty()
        )

        applyAvatarToAnchor(
            anchor = oppAvatarAnchor, avatarString = message["avatar2"].orEmpty()
        )

        gameAvatarAnchor.post {
            normalizeAvatarAnchor(gameAvatarAnchor)
            attachStrokeCountersToAvatarAnchors()
        }

        oppAvatarAnchor.post {
            normalizeAvatarAnchor(oppAvatarAnchor)
            attachStrokeCountersToAvatarAnchors()
        }
    }

    private fun configureSettingsAvatarTarget() {
        if (!::gameMenu.isInitialized) {
            return
        }

        gameMenu.sheet.setGameAvatarRefreshEnabled(
            enabled = !spectatorMode,
        )
    }

    private fun restoreSpectatorAvatarsAfterSettingsOpen() {
        if (!spectatorMode || lastMessage.isEmpty()) return

        gameAvatarAnchor.post {
            if (!spectatorMode || isFinishing || isDestroyed) {
                return@post
            }

            gameMenu.sheet.setGameAvatarRefreshEnabled(
                false,
            )
            applySpectatorAvatars(lastMessage)

            normalizeAvatarAnchor(gameAvatarAnchor)
            normalizeAvatarAnchor(oppAvatarAnchor)

            positionLocalAvatarYouLabel()
            attachStrokeCountersToAvatarAnchors()
            syncStrokeCounterTextSizing()

            spectatorLabel.visibility = View.VISIBLE
            spectatorLabel.bringToFront()
        }
    }

    private fun localPlayerNumberFor(
        data: GolfGameData? = gameData, current: Map<String, String> = lastMessage
    ): Int {
        val myId = runCatching {
            gameSessionIPC?.getSenderUUID(sessionId)
        }.getOrNull().orEmpty()

        val currentPlayer1 = current["player1"].orEmpty().ifBlank { data?.player1Id.orEmpty() }
        val currentPlayer2 = current["player2"].orEmpty().ifBlank { data?.player2Id.orEmpty() }

        if (myId.isNotBlank()) {
            if (currentPlayer1 == myId) return 1
            if (currentPlayer2 == myId) return 2
        }

        if (currentPlayer1.isBlank()) return 1
        if (currentPlayer2.isBlank()) return 2

        val messagePlayer =
            current["player"]?.toIntOrNull()?.coerceIn(1, 2) ?: data?.player ?: player.coerceIn(
                1, 2
            )

        val messageSender = current["sender"].orEmpty()

        if (myId.isNotBlank() && messageSender.isNotBlank()) {
            return if (messageSender == myId) {
                messagePlayer
            } else {
                if (messagePlayer == 1) 2 else 1
            }
        }

        return if (messagePlayer == 1) 2 else 1
    }

    private fun isCurrentMessageFromMe(msg: Map<String, String>): Boolean {
        val myId = runCatching {
            gameSessionIPC?.getSenderUUID(sessionId)
        }.getOrNull().orEmpty()

        val sender = msg["sender"].orEmpty()

        return myId.isNotBlank() && sender.isNotBlank() && sender == myId
    }

    private fun focusCameraOnCurrentBall() {
        val g = currentMap ?: return
        val ball = runtimeBallCourse ?: primaryBallStartFor(g)

        setZoomOverviewEnabled(false)
        renderer.setAimingCamera(ball, GolfShot.Aim.NONE)
    }

    private fun primaryBallStartFor(
        g: GolfMap, localPlayer: Int = localPlayerNumberFor(gameData)
    ): PointF {
        return if (localPlayer == 2) {
            g.ballStart2
        } else {
            g.ballStart1
        }
    }

    private fun opponentBallStartFor(
        g: GolfMap, localPlayer: Int = localPlayerNumberFor(gameData)
    ): PointF {
        return if (localPlayer == 2) {
            g.ballStart1
        } else {
            g.ballStart2
        }
    }

    private fun hasBothReplaysForHole(
        data: GolfGameData, holeIndex: Int
    ): Boolean {
        return holeIndex >= 0 && GolfReplay.hasSegment(
            data.replay, holeIndex
        ) && GolfReplay.hasSegment(data.replay2, holeIndex)
    }

    private fun waitingDisplayHoleForSentMessage(
        data: GolfGameData, localPlayer: Int
    ): Int? {
        val localReplayForTurn = if (localPlayer == 1) {
            data.replay
        } else {
            data.replay2
        }

        val segments = GolfReplay.parseNonRace(localReplayForTurn)

        for (holeIndex in segments.indices.reversed()) {
            if (segments[holeIndex].isNotEmpty()) {
                return holeIndex.coerceIn(
                    0, (data.holeCount - 1).coerceAtLeast(0)
                )
            }
        }

        return null
    }

    private fun firstLocalPlayableHoleForIncomingData(
        data: GolfGameData, localPlayer: Int, messageFromMe: Boolean
    ): Int? {
        if (messageFromMe) return null

        val localReplayForTurn = if (localPlayer == 1) {
            data.replay
        } else {
            data.replay2
        }

        for (holeIndex in 0 until data.holeCount) {
            val localHasHole = GolfReplay.hasSegment(localReplayForTurn, holeIndex)

            if (localHasHole) {
                continue
            }

            var previousHolesComplete = true

            for (previousHole in 0 until holeIndex) {
                if (!hasBothReplaysForHole(data, previousHole)) {
                    previousHolesComplete = false
                    break
                }
            }

            return if (previousHolesComplete) {
                holeIndex
            } else {
                null
            }
        }

        return null
    }

    private fun latestCompletedReplayHoleBeforeCurrent(data: GolfGameData): Int? {
        for (holeIndex in data.mapNum - 1 downTo 0) {
            if (hasBothReplaysForHole(data, holeIndex)) {
                return holeIndex
            }
        }

        return null
    }

    private fun replayAutoKey(
        data: GolfGameData, replayMapNum: Int
    ): String {
        return buildString {
            append(data.seed)
            append('|').append(data.mode)
            append('|').append(data.holeCount)
            append('|').append(replayMapNum)
            append('|').append(data.replay.hashCode())
            append('|').append(data.replay2.hashCode())
            append('|').append(data.replay.length)
            append('|').append(data.replay2.length)
        }
    }

    private fun maybeRunReplayTraceLab(
        source: String, data: GolfGameData, map: GolfMap
    ) {
        if (!GolfConstants.debugToolsEnabled) return
        val manualTraceRequest = source == "debugMenuRunTrace"

        val blockedDuringLiveGameplay =
            dualReplayRunning || dualReplayWaitingToFire || physicsRunning || source == "startDualReplayFromData" || source.startsWith(
                "generateAndShowMap:handleMessage"
            ) || source.startsWith("generateAndShowMap:finishDualReplay") || source.startsWith("generateAndShowMap:skipReplay")

        if (!manualTraceRequest && blockedDuringLiveGameplay) {
            OpenPigeonLog.i(
                TAG, "GOLF_ANDROID_TRACE=" + "{" + "\"kind\":\"traceLabSkip\"," + "\"source\":\"${
                    jsonEscape(source)
                }\"," + "\"reason\":\"blocked during live gameplay/replay\"," + "\"seed\":${data.seed}," + "\"mode\":\"${
                    jsonEscape(
                        data.mode
                    )
                }\"," + "\"mapNum\":${data.mapNum}" + "}"
            )
            return
        }

        if (!manualTraceRequest && !debugGolfReplayTraceAuto) {
            OpenPigeonLog.i(
                TAG, "GOLF_ANDROID_TRACE=" + "{" + "\"kind\":\"traceLabSkip\"," + "\"source\":\"${
                    jsonEscape(source)
                }\"," + "\"reason\":\"debugGolfReplayTraceAuto false\"," + "\"seed\":${data.seed}," + "\"mode\":\"${
                    jsonEscape(
                        data.mode
                    )
                }\"," + "\"mapNum\":${data.mapNum}" + "}"
            )
            return
        }

        val hasP1 = GolfReplay.hasSegment(data.replay, data.mapNum)
        val hasP2 = GolfReplay.hasSegment(data.replay2, data.mapNum)

        if (!hasP1 && !hasP2) {
            OpenPigeonLog.i(
                TAG, "GOLF_ANDROID_TRACE=" + "{" + "\"kind\":\"traceLabSkip\"," + "\"source\":\"${
                    jsonEscape(source)
                }\"," + "\"reason\":\"no replay segments\"," + "\"seed\":${data.seed}," + "\"mode\":\"${
                    jsonEscape(
                        data.mode
                    )
                }\"," + "\"mapNum\":${data.mapNum}," + "\"replayLen\":${data.replay.length}," + "\"replay2Len\":${data.replay2.length}" + "}"
            )
            return
        }

        val traceKey = "${data.seed}|${data.mode}|${data.mapNum}|${data.replay}|${data.replay2}"

        if (traceKey == lastReplayTraceKey) {
            OpenPigeonLog.i(
                TAG, "GOLF_ANDROID_TRACE=" + "{" + "\"kind\":\"traceLabSkip\"," + "\"source\":\"${
                    jsonEscape(source)
                }\"," + "\"reason\":\"duplicate trace key\"," + "\"seed\":${data.seed}," + "\"mode\":\"${
                    jsonEscape(
                        data.mode
                    )
                }\"," + "\"mapNum\":${data.mapNum}" + "}"
            )
            return
        }

        lastReplayTraceKey = traceKey

        GolfTrace.replaySummary(
            source = source,
            seed = data.seed,
            mode = data.mode,
            mapNum = data.mapNum,
            p1Replay = data.replay,
            p2Replay = data.replay2
        )

        val shouldRunIosAnchorTrace =
            debugGolfReplayTraceIosAnchors && manualTraceRequest && data.seed == 1853352027 && data.mode == "3" && data.mapNum == 0

        Thread {
            try {
                GolfReplayTraceRunner.runReplay(
                    source = "${source}_p1_firstShot",
                    map = map,
                    holeIndex = data.mapNum,
                    slot = "p1",
                    replay = data.replay,
                    maxShots = 1
                )

                GolfReplayTraceRunner.runReplay(
                    source = "${source}_p2_firstShot",
                    map = map,
                    holeIndex = data.mapNum,
                    slot = "p2",
                    replay = data.replay2,
                    maxShots = 1
                )

                val shouldRunFullTrace = source == "debugMenuRunTrace" || debugGolfReplayTraceFull

                if (shouldRunFullTrace) {
                    GolfReplayTraceRunner.runReplay(
                        source = "${source}_p1_full",
                        map = map,
                        holeIndex = data.mapNum,
                        slot = "p1",
                        replay = data.replay,
                        maxShots = null
                    )

                    GolfReplayTraceRunner.runReplay(
                        source = "${source}_p2_full",
                        map = map,
                        holeIndex = data.mapNum,
                        slot = "p2",
                        replay = data.replay2,
                        maxShots = null
                    )
                }

                if (shouldRunIosAnchorTrace) {
                    GolfReplayTraceRunner.runIosAnchorShots(
                        source = "${source}_ios_anchor", map = map, holeIndex = data.mapNum
                    )
                }
            } catch (t: Throwable) {
                OpenPigeonLog.e(
                    TAG, "GOLF_ANDROID_TRACE traceLabError source=$source error=${t.message}", t
                )
            }
        }.start()
    }

    private fun startDualReplayFromData(
        data: GolfGameData,
    ) {
        replayStrokeHudLocked = true

        val g = currentMap ?: return

        val p1Shots = GolfReplay.segmentAt(data.replay, data.mapNum)
        val p2Shots = GolfReplay.segmentAt(data.replay2, data.mapNum)

        if (p1Shots.isEmpty() || p2Shots.isEmpty()) {
            OpenPigeonLog.i(
                TAG,
                "startDualReplay skipped p1Shots=${p1Shots.size} p2Shots=${p2Shots.size} mapNum=${data.mapNum}"
            )
            return
        }

        val localPlayer = localPlayerNumberFor(data)

        dualReplayMineShots = if (localPlayer == 1) p1Shots else p2Shots
        dualReplayOpponentShots = if (localPlayer == 1) p2Shots else p1Shots

        hideAimReadyUi()
        stopBallPhysics(clearVelocity = true)

        dualReplayRunning = true
        dualReplayWaitingToFire = false
        dualReplayShotIndex = 0
        dualReplayLastMs = SystemClock.elapsedRealtime()
        dualReplayPausedByLifecycle = false
        dualReplayRemainingFireDelayMs = 0L

        dualReplayMineVelocityCourse.set(0f, 0f)
        dualReplayOpponentVelocityCourse.set(0f, 0f)

        dualReplayMineInHole = false
        dualReplayOpponentInHole = false

        val mineStart = primaryBallStartFor(g, localPlayer)
        val opponentStart = opponentBallStartFor(g, localPlayer)

        runtimeBallCourse = PointF(mineStart.x, mineStart.y)
        dualReplayOpponentBallCourse = PointF(opponentStart.x, opponentStart.y)

        flagPulled = false
        ballInHole = false

        renderer.setRuntimeBallCourse(runtimeBallCourse)
        renderer.setOpponentBallCourse(dualReplayOpponentBallCourse)
        renderer.setHoleState(flagPulled = false, ballInHole = false)

        renderer.setReplayBallHoleStates(
            primaryInHole = false, opponentInHole = false
        )

        renderer.setReplayCamera(
            runtimeBallCourse, dualReplayOpponentBallCourse
        )

        stopStateLabelAnimation()
        closeGameMenu()
        showSkipReplayButton()

        stateLabel.text = "Replay"
        prepareDualReplayStrokeHud(
            data = data,
            localPlayer = localPlayer,
        )

        OpenPigeonLog.i(
            TAG,
            "startDualReplay localPlayer=$localPlayer mapNum=${data.mapNum} " + "p1Shots=${p1Shots.size} p2Shots=${p2Shots.size} " + "mineShots=${dualReplayMineShots.size} opponentShots=${dualReplayOpponentShots.size} " + "p1First=${p1Shots.firstOrNull()} p2First=${p2Shots.firstOrNull()} " + "mineFirst=${dualReplayMineShots.firstOrNull()} " + "opponentFirst=${dualReplayOpponentShots.firstOrNull()} " + "replayLen=${data.replay.length} replay2Len=${data.replay2.length}"
        )

        scheduleNextDualReplayShot()
        renderer.removeCallbacks(dualReplayTick)
        renderer.postOnAnimation(dualReplayTick)
    }

    private fun scheduleNextDualReplayShot() {
        val mineBall = runtimeBallCourse
        val opponentBall = dualReplayOpponentBallCourse

        if (mineBall == null || opponentBall == null) {
            finishDualReplay()
            return
        }

        val mineShot = dualReplayMineShots.getOrNull(dualReplayShotIndex)
        val opponentShot = dualReplayOpponentShots.getOrNull(dualReplayShotIndex)

        if (mineShot == null && opponentShot == null) {
            finishDualReplay()
            return
        }

        dualReplayMineVelocityCourse.set(0f, 0f)
        dualReplayOpponentVelocityCourse.set(0f, 0f)

        val mineAim = replayPreviewAimForShot(mineShot)
        val opponentAim = replayPreviewAimForShot(opponentShot)
        renderer.setReplayCamera(mineBall, opponentBall)

        renderer.setReplayAimPreviews(
            whiteBallCourse = mineBall,
            whiteAim = mineAim,
            grayBallCourse = opponentBall,
            grayAim = opponentAim
        )

        dualReplayWaitingToFire = true
        dualReplayFireAtMs = SystemClock.elapsedRealtime() + 500L
        dualReplayLastMs = SystemClock.elapsedRealtime()

        OpenPigeonLog.i(
            TAG,
            "dualReplay preview shotIndex=$dualReplayShotIndex " + "mineShot=${mineShot != null} opponentShot=${opponentShot != null}"
        )
    }

    private fun stepDualReplay() {
        if (!dualReplayRunning) return

        val g = currentMap ?: return
        val mineBall = runtimeBallCourse ?: return
        val opponentBall = dualReplayOpponentBallCourse ?: return

        val now = SystemClock.elapsedRealtime()

        if (dualReplayWaitingToFire) {
            if (now < dualReplayFireAtMs) {
                return
            }

            renderer.clearReplayAimPreview()

            val mineShotToFire = dualReplayMineShots.getOrNull(dualReplayShotIndex)
            val opponentShotToFire = dualReplayOpponentShots.getOrNull(dualReplayShotIndex)

            markDualReplayStrokeFired(
                mineFired = mineShotToFire != null, opponentFired = opponentShotToFire != null
            )

            mineShotToFire?.let { shot ->
                dualReplayMineVelocityCourse.set(shotVelocityCourse(shot))
            }

            opponentShotToFire?.let { shot ->
                dualReplayOpponentVelocityCourse.set(shotVelocityCourse(shot))
            }

            GolfTrace.replayFire(
                map = currentMap,
                localPlayer = localPlayerNumberFor(gameData),
                mapNum = mapNum,
                shotIndex = dualReplayShotIndex,
                mineShot = mineShotToFire,
                opponentShot = opponentShotToFire,
                mineBallCourse = mineBall,
                opponentBallCourse = opponentBall,
                mineVelocityCourse = dualReplayMineVelocityCourse,
                opponentVelocityCourse = dualReplayOpponentVelocityCourse
            )

            dualReplayWaitingToFire = false
            dualReplayLastMs = now

            OpenPigeonLog.i(
                TAG,
                "dualReplay fire shotIndex=$dualReplayShotIndex " + "mineVel=(${dualReplayMineVelocityCourse.x},${dualReplayMineVelocityCourse.y}) " + "oppVel=(${dualReplayOpponentVelocityCourse.x},${dualReplayOpponentVelocityCourse.y})"
            )

            return
        }

        val dt = ((now - dualReplayLastMs).coerceIn(1L, 34L)).toFloat() / 1000f
        dualReplayLastMs = now

        var mineDone = dualReplayMineShots.getOrNull(dualReplayShotIndex) == null
        var opponentDone = dualReplayOpponentShots.getOrNull(dualReplayShotIndex) == null

        var replayFlagPulled = dualReplayMineInHole || dualReplayOpponentInHole

        if (!mineDone) {
            val beforeVelocity = PointF(
                dualReplayMineVelocityCourse.x, dualReplayMineVelocityCourse.y
            )

            val stoppedByMotion = GolfPhysics.step(
                map = g,
                positionCourse = mineBall,
                velocityCourse = dualReplayMineVelocityCourse,
                dtSeconds = dt
            )

            maybeTriggerBumperPulse(
                map = g,
                ball = mineBall,
                beforeVelocity = beforeVelocity,
                afterVelocity = dualReplayMineVelocityCourse,
                source = "dualReplayMine"
            )

            val wasMineInHole = dualReplayMineInHole

            val holeStep = GolfPhysics.applyHoleCup(
                map = g,
                positionCourse = mineBall,
                velocityCourse = dualReplayMineVelocityCourse,
                dtSeconds = dt,
                alreadyCaptured = wasMineInHole
            )

            GolfTrace.holeCup(
                phase = "dualReplayMineAfterApplyHoleCup",
                map = g,
                pos = mineBall,
                vel = dualReplayMineVelocityCourse,
                holeStep = holeStep,
                alreadyCaptured = wasMineInHole
            )

            if (holeStep.captured && !wasMineInHole) {
                OpenPigeonLog.i(
                    TAG,
                    "dualReplay mine entered hole shotIndex=$dualReplayShotIndex " + "ball=(${mineBall.x},${mineBall.y}) " + "hole=(${g.hole.x},${g.hole.y}) " + "velocity=(${dualReplayMineVelocityCourse.x},${dualReplayMineVelocityCourse.y})"
                )
            }

            dualReplayMineInHole = holeStep.captured
            replayFlagPulled = replayFlagPulled || holeStep.flagPulled

            mineDone = holeStep.settled || (stoppedByMotion && !holeStep.captured)
        }

        if (!opponentDone) {
            val beforeVelocity = PointF(
                dualReplayOpponentVelocityCourse.x, dualReplayOpponentVelocityCourse.y
            )

            val stoppedByMotion = GolfPhysics.step(
                map = g,
                positionCourse = opponentBall,
                velocityCourse = dualReplayOpponentVelocityCourse,
                dtSeconds = dt
            )

            maybeTriggerBumperPulse(
                map = g,
                ball = opponentBall,
                beforeVelocity = beforeVelocity,
                afterVelocity = dualReplayOpponentVelocityCourse,
                source = "dualReplayOpponent"
            )

            val wasOpponentInHole = dualReplayOpponentInHole

            val holeStep = GolfPhysics.applyHoleCup(
                map = g,
                positionCourse = opponentBall,
                velocityCourse = dualReplayOpponentVelocityCourse,
                dtSeconds = dt,
                alreadyCaptured = wasOpponentInHole
            )

            GolfTrace.holeCup(
                phase = "dualReplayOpponentAfterApplyHoleCup",
                map = g,
                pos = opponentBall,
                vel = dualReplayOpponentVelocityCourse,
                holeStep = holeStep,
                alreadyCaptured = wasOpponentInHole
            )

            if (holeStep.captured && !wasOpponentInHole) {
                OpenPigeonLog.i(
                    TAG,
                    "dualReplay opponent entered hole shotIndex=$dualReplayShotIndex " + "ball=(${opponentBall.x},${opponentBall.y}) " + "hole=(${g.hole.x},${g.hole.y}) " + "velocity=(${dualReplayOpponentVelocityCourse.x},${dualReplayOpponentVelocityCourse.y})"
                )
            }

            dualReplayOpponentInHole = holeStep.captured
            replayFlagPulled = replayFlagPulled || holeStep.flagPulled

            opponentDone = holeStep.settled || (stoppedByMotion && !holeStep.captured)
        }

        flagPulled = replayFlagPulled
        ballInHole = dualReplayMineInHole

        renderer.setRuntimeBallCourse(mineBall)
        renderer.setOpponentBallCourse(opponentBall)

        renderer.setHoleState(
            flagPulled = replayFlagPulled, ballInHole = dualReplayMineInHole
        )

        renderer.setReplayBallHoleStates(
            primaryInHole = dualReplayMineInHole, opponentInHole = dualReplayOpponentInHole
        )

        renderer.setReplayCamera(mineBall, opponentBall)

        GolfTrace.frame(
            kind = "replayFrame",
            map = currentMap,
            localPlayer = localPlayerNumberFor(gameData),
            mapNum = mapNum,
            shotIndex = dualReplayShotIndex,
            mineBallCourse = mineBall,
            opponentBallCourse = opponentBall,
            mineVelocityCourse = dualReplayMineVelocityCourse,
            opponentVelocityCourse = dualReplayOpponentVelocityCourse
        )

        if (mineDone && opponentDone) {
            dualReplayShotIndex += 1
            scheduleNextDualReplayShot()
        }
    }

    private fun traceParsedReplayVectors(
        data: GolfGameData, localPlayer: Int
    ) {
        if (!GolfConstants.debugToolsEnabled) return
        val reason = "handleMessage parsed"
        if (!::renderer.isInitialized) return

        fun esc(value: String): String {
            return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
                .replace("\r", "\\r")
        }

        fun pointJson(point: PointF): String {
            return "{\"x\":${point.x},\"y\":${point.y}}"
        }

        fun logShot(
            slot: String, shotIndex: Int, shot: GolfReplay.Shot
        ) {
            val velocityVisual = GolfShot.launchVelocityVisual(
                GolfShot.Aim(
                    dist = shot.dist, rotation = shot.rotation
                )
            )

            val velocityIfIncorrectlyFlipped = renderer.visualDeltaToCourseDelta(
                dxVisual = velocityVisual.x, dyVisual = velocityVisual.y
            )

            val velocityCourseUsed = PointF(
                velocityVisual.x, velocityVisual.y
            )

            OpenPigeonLog.i(
                TAG, "GOLF_ANDROID=" + "{" + "\"kind\":\"parsedReplayShot\"," + "\"reason\":\"${
                    esc(reason)
                }\"," + "\"mapNum\":${data.mapNum}," + "\"holeNumber\":${data.mapNum + 1}," + "\"holeCount\":${data.holeCount}," + "\"localPlayer\":$localPlayer," + "\"slot\":\"${
                    esc(
                        slot
                    )
                }\"," + "\"shotIndex\":$shotIndex," + "\"dist\":${shot.dist}," + "\"rotation\":${shot.rotation}," + "\"velocityVisual\":${
                    pointJson(
                        velocityVisual
                    )
                }," + "\"velocityIfIncorrectlyFlipped\":${pointJson(velocityIfIncorrectlyFlipped)}," + "\"velocityCourseUsed\":${
                    pointJson(
                        velocityCourseUsed
                    )
                }" + "}"
            )
        }

        val p1Shots = GolfReplay.segmentAt(data.replay, data.mapNum)
        val p2Shots = GolfReplay.segmentAt(data.replay2, data.mapNum)

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID=" + "{" + "\"kind\":\"parsedReplaySummary\"," + "\"reason\":\"${esc(reason)}\"," + "\"mapNum\":${data.mapNum}," + "\"holeNumber\":${data.mapNum + 1}," + "\"holeCount\":${data.holeCount}," + "\"localPlayer\":$localPlayer," + "\"p1ReplayLen\":${data.replay.length}," + "\"p2ReplayLen\":${data.replay2.length}," + "\"p1Shots\":${p1Shots.size}," + "\"p2Shots\":${p2Shots.size}," + "\"p1Replay\":\"${
                esc(data.replay)
            }\"," + "\"p2Replay\":\"${esc(data.replay2)}\"" + "}"
        )

        p1Shots.forEachIndexed { index, shot ->
            logShot(
                slot = if (localPlayer == 1) "mine_p1" else "opponent_p1",
                shotIndex = index,
                shot = shot
            )
        }

        p2Shots.forEachIndexed { index, shot ->
            logShot(
                slot = if (localPlayer == 2) "mine_p2" else "opponent_p2",
                shotIndex = index,
                shot = shot
            )
        }
    }

    private fun replayPreviewAimForShot(shot: GolfReplay.Shot?): GolfShot.Aim? {
        if (shot == null) return null

        return GolfShot.Aim(
            dist = shot.dist, rotation = -shot.rotation
        )
    }

    private fun shotVelocityCourse(shot: GolfReplay.Shot): PointF {
        val velocityCourse = GolfShot.launchVelocityVisual(
            GolfShot.Aim(
                dist = shot.dist, rotation = shot.rotation
            )
        )

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_TRACE=" + "{" + "\"kind\":\"shotVelocityCourse\"," + "\"mapNum\":$mapNum," + "\"shotDist\":${shot.dist}," + "\"shotRotationCourse\":${shot.rotation}," + "\"velocityCourse\":{\"x\":${velocityCourse.x},\"y\":${velocityCourse.y}}" + "}"
        )

        return PointF(
            velocityCourse.x, velocityCourse.y
        )
    }

    private fun handleDualReplayError(t: Throwable) {
        OpenPigeonLog.e(
            TAG,
            "dualReplayTick failed mapNum=$mapNum seed=$seed mode=$mode; recovering without default fallback",
            t
        )

        dualReplayRunning = false
        dualReplayWaitingToFire = false
        dualReplayPausedByLifecycle = false
        dualReplayRemainingFireDelayMs = 0L
        replayStrokeHudLocked = false

        renderer.removeCallbacks(dualReplayTick)
        renderer.clearReplayAimPreview()
        renderer.clearOpponentBallCourse()
        renderer.clearReplayBallHoleStates()
        hideSkipReplayButton()
        stopBallPhysics(clearVelocity = true)

        runCatching {
            GolfNativePhysics.reset()
        }.onFailure { resetError ->
            OpenPigeonLog.e(
                TAG, "GolfNativePhysics.reset failed during replay recovery", resetError
            )
        }

        stateLabel.text = "Replay skipped"

        if (mapNum + 1 < holeCount) {
            runCatching {
                advanceAfterReplayToNextHole(source = "dualReplay crash recovery")
            }.onFailure { advanceError ->
                OpenPigeonLog.e(
                    TAG, "advanceAfterReplayToNextHole failed during replay recovery", advanceError
                )
                updateAimReadyUi()
                focusCameraOnCurrentBall()
            }
        } else {
            runCatching {
                showGameOverAfterReplay()
            }.onFailure { gameOverError ->
                OpenPigeonLog.e(
                    TAG, "showGameOverAfterReplay failed during replay recovery", gameOverError
                )
            }
        }
    }

    private fun finishDualReplay(immediateAdvance: Boolean = false) {
        OpenPigeonLog.i(
            TAG,
            "finishDualReplay shotIndex=$dualReplayShotIndex mapNum=$mapNum holeCount=$holeCount " + "immediateAdvance=$immediateAdvance"
        )

        dualReplayRunning = false
        dualReplayWaitingToFire = false
        dualReplayPausedByLifecycle = false
        dualReplayRemainingFireDelayMs = 0L

        renderer.removeCallbacks(dualReplayTick)
        renderer.clearReplayAimPreview()
        renderer.clearOpponentBallCourse()
        renderer.clearReplayBallHoleStates()
        hideSkipReplayButton()
        stopStateLabelAnimation()
        hideAimReadyUi()

        if (dualReplayMineShots.isNotEmpty() || dualReplayOpponentShots.isNotEmpty()) {
            setStrokeHudCounts(
                localCount = dualReplayMineBaseStrokes + dualReplayMineShots.size,
                opponentCount = dualReplayOpponentBaseStrokes + dualReplayOpponentShots.size
            )
        }

        replayStrokeHudLocked = false

        if (mapNum + 1 < holeCount) {
            if (immediateAdvance) {
                advanceAfterReplayToNextHole(source = "skipReplay next hole")
            } else {
                stateLabel.text = "Next hole"

                renderer.postDelayed({
                    if (isFinishing || isDestroyed) return@postDelayed
                    advanceAfterReplayToNextHole(source = "finishDualReplay next hole")
                }, 650L)
            }
        } else {
            showGameOverAfterReplay()
        }
    }

    private fun advanceAfterReplayToNextHole(source: String) {
        if (mapNum + 1 >= holeCount) {
            showGameOverAfterReplay()
            return
        }

        mapNum += 1

        gameData = gameData?.copy(mapNum = mapNum)

        val updatedData = gameData
        val updatedLocalPlayer = localPlayerNumberFor(updatedData)

        localReplay = if (updatedLocalPlayer == 1) {
            updatedData?.replay.orEmpty()
        } else {
            updatedData?.replay2.orEmpty()
        }

        val shouldWait = !spectatorMode && isCurrentMessageFromMe(lastMessage)

        waitingForOpponent = shouldWait

        OpenPigeonLog.i(
            TAG,
            "advanceAfterReplayToNextHole source=$source mapNum=$mapNum shouldWait=$shouldWait " + "lastMessageFromMe=${
                isCurrentMessageFromMe(lastMessage)
            } " + "localPlayer=$updatedLocalPlayer localReplayLen=${localReplay.length}"
        )

        generateAndShowMap(
            showIntro = !shouldWait, source = source, afterIntro = {
                if (isFinishing || isDestroyed) return@generateAndShowMap

                when {
                    spectatorMode -> {
                        waitingForOpponent = false
                        stopStateLabelAnimation()
                        hideWaitingOverlay()
                        hideAimReadyUi(immediate = true)

                        if (::spectatorLabel.isInitialized) {
                            spectatorLabel.visibility = View.VISIBLE
                            spectatorLabel.bringToFront()
                        }

                        renderer.clearAimPreview()
                        renderer.setAimReadyIndicator(null)
                        renderer.clearCameraFocus()
                    }

                    shouldWait -> {
                        focusCameraOnCurrentBall()
                        showWaitingLabelAnimated()
                    }

                    else -> {
                        stopStateLabelAnimation()
                        updateAimReadyUi()
                        focusCameraOnCurrentBall()
                    }
                }
            })
    }

    private fun pauseDualReplayForLifecycle(): Boolean {
        if (!dualReplayRunning && !dualReplayWaitingToFire) {
            dualReplayPausedByLifecycle = false
            dualReplayRemainingFireDelayMs = 0L
            return false
        }

        val now = SystemClock.elapsedRealtime()

        dualReplayPausedByLifecycle = true
        dualReplayRemainingFireDelayMs = if (dualReplayWaitingToFire) {
            (dualReplayFireAtMs - now).coerceAtLeast(0L)
        } else {
            0L
        }

        renderer.removeCallbacks(dualReplayTick)

        OpenPigeonLog.i(
            TAG,
            "pauseDualReplayForLifecycle mapNum=$mapNum " + "shotIndex=$dualReplayShotIndex " + "waitingToFire=$dualReplayWaitingToFire " + "remainingFireDelayMs=$dualReplayRemainingFireDelayMs " + "mineBall=$runtimeBallCourse " + "opponentBall=$dualReplayOpponentBallCourse"
        )

        return true
    }

    private fun resumeDualReplayAfterLifecycle() {
        if (!dualReplayPausedByLifecycle) return

        val hasReplayState =
            dualReplayRunning && currentMap != null && runtimeBallCourse != null && dualReplayOpponentBallCourse != null && (dualReplayMineShots.isNotEmpty() || dualReplayOpponentShots.isNotEmpty())

        if (!hasReplayState) {
            OpenPigeonLog.w(
                TAG,
                "resumeDualReplayAfterLifecycle missing replay state; attempting restart " + "mapNum=$mapNum running=$dualReplayRunning " + "currentMapNull=${currentMap == null} " + "runtimeBallNull=${runtimeBallCourse == null} " + "opponentBallNull=${dualReplayOpponentBallCourse == null}"
            )

            dualReplayPausedByLifecycle = false
            dualReplayRemainingFireDelayMs = 0L

            val data = gameData
            if (data != null && currentMap != null) {
                dualReplayRunning = false
                dualReplayWaitingToFire = false
                startDualReplayFromData(data)
            }

            return
        }

        val now = SystemClock.elapsedRealtime()

        if (dualReplayWaitingToFire) {
            dualReplayFireAtMs = now + dualReplayRemainingFireDelayMs.coerceAtLeast(1L)
        }

        dualReplayLastMs = now
        dualReplayPausedByLifecycle = false
        dualReplayRemainingFireDelayMs = 0L

        renderer.setRuntimeBallCourse(runtimeBallCourse)
        renderer.setOpponentBallCourse(dualReplayOpponentBallCourse)
        renderer.setReplayCamera(runtimeBallCourse, dualReplayOpponentBallCourse)
        renderer.setHoleState(
            flagPulled = flagPulled, ballInHole = dualReplayMineInHole
        )

        showSkipReplayButton()
        stateLabel.text = "Replay"

        renderer.removeCallbacks(dualReplayTick)
        renderer.postOnAnimation(dualReplayTick)

        OpenPigeonLog.i(
            TAG,
            "resumeDualReplayAfterLifecycle resumed mapNum=$mapNum " + "shotIndex=$dualReplayShotIndex " + "waitingToFire=$dualReplayWaitingToFire " + "mineBall=$runtimeBallCourse " + "opponentBall=$dualReplayOpponentBallCourse"
        )
    }

    private fun stopDualReplay() {
        hideSkipReplayButton()
        dualReplayPausedByLifecycle = false
        dualReplayRemainingFireDelayMs = 0L

        if (!dualReplayRunning && !dualReplayWaitingToFire) return

        dualReplayRunning = false
        dualReplayWaitingToFire = false

        renderer.removeCallbacks(dualReplayTick)
        renderer.clearReplayAimPreview()
        renderer.clearOpponentBallCourse()
        renderer.clearReplayBallHoleStates()

        dualReplayMineVelocityCourse.set(0f, 0f)
        dualReplayOpponentVelocityCourse.set(0f, 0f)
    }

    private fun safeShowFallbackFromOnCreateFailure() {
        try {
            if (!::root.isInitialized) buildLayout()
            stateLabel.text = "Mini Golf failed to initialize - local fallback"
            seed = GolfConstants.DEFAULT_SEED
            mode = GolfConstants.DEFAULT_MODE
            holeCount = GolfConstants.holeCountFor(mode)
            mapNum = 0
            generateAndShowMap(showIntro = false, source = "onCreate failure fallback")
        } catch (inner: Throwable) {
            OpenPigeonLog.e(TAG, "Fallback after onCreate failure also failed", inner)
        }
    }

    private fun defaultLocalMessage(): Map<String, String> = mapOf(
        "game" to "golf",
        "mode" to "5",
        "seed" to GolfConstants.DEFAULT_SEED.toString(),
        "num" to "1",
        "player" to "1",
        "isYourTurn" to "true",
        "replay" to "",
        "replay2" to ""
    )

    private fun jsonEscape(value: String): String {
        return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
            .replace("\r", "\\r")
    }

    private fun messageSummary(msg: Map<String, String>): String {
        if (msg.isEmpty()) return "messageKeys=[]"

        val selected = listOf(
            "game",
            "mode",
            "game_mode",
            "holes",
            "seed",
            "game_seed",
            "random_seed",
            "num",
            "number",
            "map_num",
            "mapNum",
            "hole",
            "hole_index",
            "player",
            "isYourTurn",
            "turn",
            "subcaption",
            "replay",
            "replay2",
            "replay_send",
            "replay_send2",
            "replay_string",
            "replay_string2"
        ).mapNotNull { key ->
            msg[key]?.let { value ->
                val safeValue =
                    if (value.length > 90) value.take(90) + "...(${value.length})" else value
                "$key=$safeValue"
            }
        }

        return "messageKeys=${msg.keys.sorted()} selected=${selected.joinToString(",")} " + "replayLen=${msg["replay"].orEmpty().length} " + "replay2Len=${msg["replay2"].orEmpty().length} " + "replaySendLen=${msg["replay_send"].orEmpty().length} " + "replayStringLen=${msg["replay_string"].orEmpty().length} " + "replayString2Len=${msg["replay_string2"].orEmpty().length}"
    }

    private class OutlineTextView(context: Context) :
        androidx.appcompat.widget.AppCompatTextView(context) {
        override fun onDraw(canvas: Canvas) {
            val originalColor = currentTextColor
            val originalStyle = paint.style
            val originalStrokeWidth = paint.strokeWidth

            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 5f
            setTextColor(Color.BLACK)
            super.onDraw(canvas)

            paint.style = Paint.Style.FILL
            paint.strokeWidth = originalStrokeWidth
            setTextColor(originalColor)
            super.onDraw(canvas)

            paint.style = originalStyle
        }
    }

    private fun GolfMap.summary(): String =
        "seed=$seed mode=$mode mapNum=$mapNum hole=${holeNumber}/${holeCount} cells=${xCells}x${yCells} mapSize=$mapSize mapSize2=$mapSize2 complete=$complete path=${longestPath.size}"

    private fun rounded(color: Int, radius: Float): GradientDrawable = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius
    }

    private fun setUiLayer(view: View, layer: Float) {
        view.elevation = layer
        view.translationZ = 0f
        view.z = layer
    }

    private fun bringGameMenuToFront() {
        applyOverlayOrdering()
    }


    private fun applyOverlayOrdering() {
        if (::turnRecoveryOverlay.isInitialized && turnRecoveryOverlay.isShowingRetry()) turnRecoveryOverlay.showRetry()
        if (::gameMenu.isInitialized) {
            gameMenu.bringToFront()
        }

        if (::waitingOverlay.isInitialized && waitingOverlay.isVisible) {
            setUiLayer(
                waitingOverlay,
                LAYER_WAITING,
            )

            root.bringChildToFront(
                waitingOverlay,
            )

            waitingOverlay.bringToFront()
        }

        if (::holeOverlay.isInitialized && holeOverlay.isVisible) {
            setUiLayer(
                holeOverlay,
                LAYER_INTRO,
            )

            root.bringChildToFront(
                holeOverlay,
            )

            holeOverlay.bringToFront()
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun finish() {
        activityExiting = true
        super.finish()
    }

    override fun onStart() {
        super.onStart()
        OpenPigeonLog.i(TAG, "onStart")
    }

    override fun onResume() {
        super.onResume()

        OpenPigeonLog.i(
            TAG,
            "onResume",
        )

        if (::gameMenu.isInitialized) {
            gameMenu.onResume()
        }

        if (::renderer.isInitialized) {
            resumeDualReplayAfterLifecycle()
        }

        if (spectatorMode) {
            restoreSpectatorAvatarsAfterSettingsOpen()
        }
    }

    override fun onPause() {
        OpenPigeonLog.i(
            TAG,
            "onPause",
        )

        if (::gameMenu.isInitialized) {
            gameMenu.onPause()
        }

        if (::renderer.isInitialized) {
            val pausedReplay = pauseDualReplayForLifecycle()

            stopDebugVisualTrace(
                restoreBoard = false,
            )

            closeGameMenu()

            stopBallPhysics(
                clearVelocity = false,
            )

            if (!pausedReplay) {
                stopDualReplay()
            }

            renderer.clearAimPreview()

            hideAimReadyUi(
                immediate = true,
            )

            if (shouldKeepWaitingOverlayDuringExit()) {
                stopWaitingTimersWithoutHidingOverlay()
            } else if (!pausedReplay) {
                stopStateLabelAnimation()
            }
        }

        super.onPause()
    }

    override fun onDestroy() {
        OpenPigeonLog.i(
            TAG,
            "onDestroy sessionBlank=${sessionId.isBlank()} " + "ipcNull=${gameSessionIPC == null}",
        )

        activityExiting = true

        cancelPendingRecoveryCheck()
        recoveryHandler.removeCallbacksAndMessages(null)
        if (::turnRecoveryOverlay.isInitialized) turnRecoveryOverlay.destroy()

        if (::renderer.isInitialized) {
            stopDebugVisualTrace(
                restoreBoard = false,
            )

            closeGameMenu()

            stopBallPhysics(
                clearVelocity = true,
            )

            stopDualReplay()
            renderer.clearAimPreview()

            hideAimReadyUi(
                immediate = true,
            )

            if (shouldKeepWaitingOverlayDuringExit()) {
                stopWaitingTimersWithoutHidingOverlay()
            } else {
                stopStateLabelAnimation()
            }
        }

        if (::avatarWinBurstController.isInitialized) {
            avatarWinBurstController.destroy()
        }

        if (::gameMenu.isInitialized) {
            gameMenu.destroy()
        }

        runCatching {
            if (sessionId.isNotBlank()) {
                gameSessionIPC?.setSuppressNotifications(
                    sessionId,
                    false,
                )
            }
        }.onFailure {
            OpenPigeonLog.e(
                TAG,
                "onDestroy setSuppressNotifications(false) failed",
                it,
            )
        }

        gameSessionIPC = null

        super.onDestroy()
    }
}
