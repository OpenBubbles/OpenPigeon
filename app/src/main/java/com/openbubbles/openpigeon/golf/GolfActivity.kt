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
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import com.openbubbles.openpigeon.godot.GameSessionIPC
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog
import android.graphics.PointF
import android.graphics.BitmapFactory
import android.widget.ImageButton
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.SettingsSheet
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

class GolfActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "GolfNative"
    }

    private lateinit var root: FrameLayout
    private lateinit var renderer: GolfRenderer
    private lateinit var stateLabel: TextView
    private lateinit var holeOverlay: FrameLayout
    private lateinit var holeTitle: TextView
    private lateinit var zoomButton: Button
    private lateinit var settingsButton: ImageButton
    private lateinit var settingsSheet: SettingsSheet
    private lateinit var gameAvatarAnchor: FrameLayout
    private lateinit var oppAvatarAnchor: FrameLayout
    private lateinit var waitingOverlay: FrameLayout
    private lateinit var waitingLabel: TextView
    private lateinit var skipReplayButton: ImageButton
    private var skipReplayNormalBitmap: Bitmap? = null
    private var skipReplayPressedBitmap: Bitmap? = null
    private lateinit var aimInstructionLabel: TextView

    private val generator = GolfMapGenerator()
    private var gameSessionIPC: GameSessionIPC? = null
    private var sessionId: String = ""
    private var lastMessage: Map<String, String> = emptyMap()
    private var gameData: GolfGameData? = null

    private var currentMap: GolfMap? = null
    private var lastRenderedKey: String = ""

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

    private val stateLabelHandler = Handler(Looper.getMainLooper())
    private var waitingDotsRunnable: Runnable? = null
    private var stateLabelAnimator: ValueAnimator? = null
    private var sentWaitingSequenceActive = false

    private var dualReplayRunning = false
    private var dualReplayWaitingToFire = false
    private var dualReplayFireAtMs = 0L
    private var dualReplayLastMs = 0L
    private var dualReplayShotIndex = 0

    private var dualReplayMineShots: List<GolfReplay.Shot> = emptyList()
    private var dualReplayOpponentShots: List<GolfReplay.Shot> = emptyList()

    private var dualReplayOpponentBallCourse: PointF? = null
    private val dualReplayMineVelocityCourse = PointF(0f, 0f)
    private val dualReplayOpponentVelocityCourse = PointF(0f, 0f)

    private var dualReplayMineInHole = false
    private var dualReplayOpponentInHole = false
    private var physicsRunning = false
    private var lastPhysicsMs = 0L

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
            stepDualReplay()

            if (dualReplayRunning) {
                renderer.postOnAnimation(this)
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        val startedAt = SystemClock.elapsedRealtime()
        super.onCreate(savedInstanceState)
        OpenPigeonLog.installContext(applicationContext)
        OpenPigeonLog.title(TAG, "Mini Golf", "onCreate start")
        AvatarData.init(applicationContext)

        try {
            OpenPigeonLog.i(TAG, "onCreate: request no title / hide actionbar")
            requestWindowFeature(Window.FEATURE_NO_TITLE)
            supportActionBar?.hide()

            OpenPigeonLog.i(TAG, "onCreate: buildLayout start")
            buildLayout()
            OpenPigeonLog.i(TAG, "onCreate: buildLayout complete rootChildren=${root.childCount}")

            settingsSheet = SettingsSheet(this, root)

            settingsSheet.attachGameAvatar(gameAvatarAnchor)
            settingsSheet.attachOpponentAvatar(oppAvatarAnchor)

            settingsButton.setOnClickListener {
                settingsSheet.open()
            }

            ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets -> insets }

            renderer.setOnTouchListener { _, event ->
                handleGolfTouch(event)
            }

            zoomButton.alpha = 0.72f

            zoomButton.setOnClickListener {
                setZoomOverviewEnabled(!zoomOverviewEnabled)
            }

            sessionId = intent.getStringExtra("SESSION") ?: ""
            OpenPigeonLog.i(
                TAG,
                "onCreate: sessionIdBlank=${sessionId.isBlank()} extras=${intent.extras?.keySet()?.sorted().orEmpty()}"
            )

            OpenPigeonLog.i(TAG, "onCreate: GameSessionIPC init start")
            GameSessionIPC(applicationContext) { ipc ->
                OpenPigeonLog.i(TAG, "GameSessionIPC callback entered elapsedMs=${SystemClock.elapsedRealtime() - startedAt}")
                gameSessionIPC = ipc

                val currentMessage = try {
                    if (sessionId.isNotEmpty()) {
                        OpenPigeonLog.i(TAG, "IPC getCurrentMessage start sessionBlank=false")
                        ipc.getCurrentMessage(sessionId)
                    } else {
                        OpenPigeonLog.w(TAG, "IPC getCurrentMessage skipped because sessionId blank")
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
                                OpenPigeonLog.i(TAG, "UI handleMessage from update start")
                                handleMessage(msg)
                            }
                        }
                        OpenPigeonLog.i(TAG, "IPC onMessageUpdated registration complete")
                    } catch (t: Throwable) {
                        OpenPigeonLog.e(TAG, "IPC onMessageUpdated registration failed", t)
                    }

                    runOnUiThread {
                        OpenPigeonLog.i(TAG, "UI handleMessage currentMessage start")
                        handleMessage(currentMessage)
                    }
                } else {
                    runOnUiThread {
                        OpenPigeonLog.w(TAG, "No current message; opening default local visual message")
                        handleMessage(defaultLocalMessage())
                    }
                }
            }
            OpenPigeonLog.i(TAG, "onCreate: GameSessionIPC constructor returned elapsedMs=${SystemClock.elapsedRealtime() - startedAt}")
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "onCreate failed before Mini Golf could load", t)
            safeShowFallbackFromOnCreateFailure()
        }
    }

    private fun buildLayout() {
        root = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(182, 202, 209))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        renderer = GolfRenderer(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
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

        settingsButton = ImageButton(this).apply {
            background = rounded(Color.argb(155, 0, 0, 0), dp(16).toFloat())
            scaleType = android.widget.ImageView.ScaleType.CENTER_INSIDE
            setPadding(dp(9), dp(9), dp(9), dp(9))

            try {
                val bm = assets.open("global/settings.png").use { BitmapFactory.decodeStream(it) }
                setImageBitmap(bm)
            } catch (t: Throwable) {
                OpenPigeonLog.e(TAG, "Unable to load settings icon", t)
                setImageResource(android.R.drawable.ic_menu_manage)
            }

            layoutParams = FrameLayout.LayoutParams(
                dp(54),
                dp(54),
                Gravity.BOTTOM or Gravity.START
            ).apply {
                bottomMargin = dp(28)
                marginStart = dp(14)
            }
        }
        root.addView(settingsButton)

        gameAvatarAnchor = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                dp(58),
                dp(58),
                Gravity.TOP or Gravity.START
            ).apply {
                topMargin = dp(20)
                marginStart = dp(14)
            }
        }
        root.addView(gameAvatarAnchor)

        oppAvatarAnchor = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                dp(58),
                dp(58),
                Gravity.TOP or Gravity.END
            ).apply {
                topMargin = dp(20)
                marginEnd = dp(14)
            }
        }
        root.addView(oppAvatarAnchor)

        zoomButton = Button(this).apply {
            text = "Zoom"
            textSize = 14f
            setTextColor(Color.WHITE)
            background = rounded(Color.argb(155, 0, 0, 0), dp(16).toFloat())
            minWidth = dp(92)

            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                dp(54),
                Gravity.BOTTOM or Gravity.END
            ).apply {
                bottomMargin = dp(28)
                marginEnd = dp(14)
            }
        }
        root.addView(zoomButton)

        buildAimInstructionLabel()
        buildSkipReplayButton()
        buildHoleOverlay()
        buildWaitingOverlay()
        setContentView(root)
    }

    private fun buildHoleOverlay() {
        holeOverlay = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(182, 202, 209))
            alpha = 0f
            visibility = View.GONE
            isClickable = true
            elevation = 1000f
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        holeTitle = TextView(this).apply {
            text = "Hole 1/3"
            setTextColor(Color.WHITE)
            textSize = 46f
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            setShadowLayer(4f, 0f, 2f, Color.argb(100, 0, 0, 0))
            alpha = 0f
            scaleX = 1f
            scaleY = 1f
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }

        holeOverlay.addView(holeTitle)
        root.addView(holeOverlay)
    }

    private fun buildWaitingOverlay() {
        waitingOverlay = FrameLayout(this).apply {
            visibility = View.GONE
            alpha = 0f
            isClickable = true
            isFocusable = true
            elevation = 1200f
            background = rounded(Color.argb(135, 32, 32, 32), 0f)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        waitingLabel = TextView(this).apply {
            text = "WAITING FOR OPPONENT."
            setTextColor(Color.WHITE)
            textSize = 17f
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
            elevation = 950f
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
        val ball = runtimeBallCourse ?: currentMap?.let { primaryBallStartFor(it) } ?: return

        if (::aimInstructionLabel.isInitialized) {

            aimInstructionLabel.animate().cancel()

            if (aimInstructionLabel.visibility != View.VISIBLE) {
                aimInstructionLabel.alpha = 0f
                aimInstructionLabel.visibility = View.VISIBLE
            }

            aimInstructionLabel
                .animate()
                .alpha(1f)
                .setDuration(140L)
                .start()

            aimInstructionLabel.bringToFront()
        }

        renderer.setAimReadyIndicator(ball)
    }

    private fun hideAimReadyUi(immediate: Boolean = false) {
        if (::aimInstructionLabel.isInitialized) {
            aimInstructionLabel.animate().cancel()

            if (immediate) {
                aimInstructionLabel.alpha = 0f
                aimInstructionLabel.visibility = View.GONE
            } else if (aimInstructionLabel.visibility == View.VISIBLE) {
                aimInstructionLabel
                    .animate()
                    .alpha(0f)
                    .setDuration(110L)
                    .withEndAction {
                        if (aimInstructionLabel.alpha <= 0.01f) {
                            aimInstructionLabel.visibility = View.GONE
                        }
                    }
                    .start()
            }
        }

        if (::renderer.isInitialized) {
            renderer.setAimReadyIndicator(null)
        }
    }

    private fun canAimNow(): Boolean {
        return currentMap != null &&
                !physicsRunning &&
                !dualReplayRunning &&
                !dualReplayWaitingToFire &&
                !waitingForOpponent &&
                !ballInHole &&
                !roundResultSent &&
                !isAiming
    }

    private fun updateAimReadyUi() {
        if (canAimNow()) {
            showAimReadyUi()
        } else {
            hideAimReadyUi()
        }
    }

    private fun buildSkipReplayButton() {
        skipReplayNormalBitmap = loadUiBitmap(
            "global/skip_replay.png",
            "global/next.png"
        )

        skipReplayPressedBitmap = loadUiBitmap(
            "global/skip_replay_pressed.png",
            "global/next_pressed.png"
        ) ?: skipReplayNormalBitmap

        skipReplayButton = ImageButton(this).apply {
            visibility = View.GONE
            alpha = 1f
            background = null
            setBackgroundColor(Color.TRANSPARENT)
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = "Skip Replay"
            elevation = 1100f

            if (skipReplayNormalBitmap != null) {
                setImageBitmap(skipReplayNormalBitmap)
            } else {
                setImageResource(android.R.drawable.ic_media_ff)
            }

            layoutParams = FrameLayout.LayoutParams(
                dp(82),
                dp(82),
                Gravity.TOP or Gravity.CENTER_HORIZONTAL
            )
        }

        skipReplayButton.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    skipReplayPressedBitmap?.let { skipReplayButton.setImageBitmap(it) }
                    true
                }

                MotionEvent.ACTION_UP -> {
                    skipReplayNormalBitmap?.let { skipReplayButton.setImageBitmap(it) }
                    skipDualReplayToEnd()
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
        for (path in paths) {
            try {
                return assets.open(path).use { BitmapFactory.decodeStream(it) }
            } catch (_: Throwable) {
            }
        }

        OpenPigeonLog.w(TAG, "Unable to load any UI bitmap paths=${paths.joinToString()}")
        return null
    }

    private fun positionSkipReplayButton() {
        if (!::skipReplayButton.isInitialized || root.height <= 0) return

        val params = skipReplayButton.layoutParams as FrameLayout.LayoutParams
        params.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL

        params.topMargin = ((root.height * 2f / 3f) - dp(41)).toInt()
            .coerceAtLeast(dp(8))

        skipReplayButton.layoutParams = params
    }

    private fun showSkipReplayButton() {
        if (!::skipReplayButton.isInitialized) return

        positionSkipReplayButton()

        skipReplayButton.animate().cancel()
        skipReplayButton.alpha = 0f
        skipReplayButton.visibility = View.VISIBLE
        skipReplayButton.bringToFront()

        skipReplayButton
            .animate()
            .alpha(1f)
            .setDuration(220L)
            .start()
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

            val parsed = GolfGameData.fromMessage(msg, previous = previousData)
            gameData = parsed

            seed = parsed.seed
            mode = parsed.mode
            holeCount = parsed.holeCount
            mapNum = parsed.mapNum
            player = parsed.player
            player1Id = parsed.player1Id
            player2Id = parsed.player2Id

            val localPlayer = localPlayerNumberFor(parsed)
            localReplay = if (localPlayer == 1) {
                parsed.replay
            } else {
                parsed.replay2
            }

            val opponentAvatar = if (localPlayer == 1) {
                msg["avatar2"].orEmpty()
            } else {
                msg["avatar1"].orEmpty()
            }

            if (opponentAvatar.isNotBlank() && ::settingsSheet.isInitialized) {
                runOnUiThread {
                    settingsSheet.applyOpponentAvatarString(opponentAvatar)
                }
            }

            OpenPigeonLog.i(
                TAG,
                "handleMessage parsed prev=($previousSeed,$previousMode,$previousMapNum) " +
                        "now=(seed=$seed seedText=${parsed.seedText} unsignedSeed=${parsed.seedWasUnsignedDecimal} " +
                        "mode=$mode holeCount=$holeCount mapNum=$mapNum rawNum=${parsed.rawNum} " +
                        "messagePlayer=$player localPlayer=$localPlayer) " +
                        "replayLen=${parsed.replay.length} replay2Len=${parsed.replay2.length} " +
                        "renderKey=${parsed.renderKey}"
            )

            if (parsed.renderKey == lastRenderedKey) {
                OpenPigeonLog.i(
                    TAG,
                    "handleMessage duplicate skipped renderKey=${parsed.renderKey} " +
                            "elapsedMs=${SystemClock.elapsedRealtime() - startedAt}"
                )
                return
            }
            lastRenderedKey = parsed.renderKey

            val messageFromMe = isCurrentMessageFromMe(msg)
            val shouldReplay = hasBothReplaysForCurrentHole(parsed)

            waitingForOpponent = messageFromMe && !shouldReplay

            val shouldPreserveSettledHoleWhileWaiting =
                waitingForOpponent &&
                        currentMap != null &&
                        (ballInHole || roundResultSent)

            if (shouldPreserveSettledHoleWhileWaiting) {
                OpenPigeonLog.i(
                    TAG,
                    "handleMessage preserving settled hole while waiting mapNum=$mapNum " +
                            "ballInHole=$ballInHole roundResultSent=$roundResultSent"
                )

                stopBallPhysics(clearVelocity = true)
                stopDualReplay()
                hideAimReadyUi()
                focusCameraOnCurrentBall()

                if (!sentWaitingSequenceActive) {
                    showWaitingLabelAnimated()
                }

                OpenPigeonLog.i(TAG, "handleMessage complete preserved waiting elapsedMs=${SystemClock.elapsedRealtime() - startedAt}")
                return
            }

            when {
                shouldReplay -> {
                    waitingForOpponent = false
                    stopStateLabelAnimation()

                    generateAndShowMap(
                        showIntro = false,
                        source = "handleMessage replay"
                    )

                    startDualReplayFromData(parsed)
                }

                waitingForOpponent -> {
                    generateAndShowMap(
                        showIntro = false,
                        source = "handleMessage waiting"
                    )

                    focusCameraOnCurrentBall()

                    if (!sentWaitingSequenceActive) {
                        showWaitingLabelAnimated()
                    }
                }

                else -> {
                    waitingForOpponent = false
                    stopStateLabelAnimation()

                    generateAndShowMap(
                        showIntro = true,
                        source = "handleMessage our turn"
                    )
                }
            }

            OpenPigeonLog.i(TAG, "handleMessage complete elapsedMs=${SystemClock.elapsedRealtime() - startedAt}")
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "Failed to open Mini Golf message ${messageSummary(msg)}", t)
            waitingForOpponent = false
            stopStateLabelAnimation()
            stateLabel.text = "Mini Golf failed to load — using local visual fallback"
            seed = GolfConstants.DEFAULT_SEED
            mode = GolfConstants.DEFAULT_MODE
            holeCount = GolfConstants.holeCountFor(mode)
            mapNum = 0
            gameData = GolfGameData.fromMessage(defaultLocalMessage(), previous = null)
            generateAndShowMap(showIntro = false, source = "handleMessage fallback")
        }
    }

    private fun handleGolfTouch(event: MotionEvent): Boolean {
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
                    moveStartVisual = aimMoveStartVisual,
                    currentTouchVisual = visual
                )
                renderer.setAimingCamera(ball, activeAim)
                renderer.setAimPreview(ball, activeAim)

                OpenPigeonLog.i(
                    TAG,
                    "touch MOVE visual=(${visual.x},${visual.y}) aimDist=${activeAim.dist} aimRot=${activeAim.rotation}"
                )

                return true
            }

            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL -> {
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

                activeAim = GolfShot.Aim.NONE
                return true
            }
        }

        return true
    }

    private fun launchCurrentAim(aim: GolfShot.Aim) {
        hideAimReadyUi()
        val ball = runtimeBallCourse ?: currentMap?.ballStart1 ?: return

        localReplay = GolfReplay.appendShot(
            replay = localReplay,
            holeIndex = mapNum,
            shot = GolfReplay.Shot(
                dist = aim.dist,
                rotation = aim.rotation
            )
        )

        val velocityVisual = GolfShot.launchVelocityVisual(aim)
        val velocityCourse = renderer.visualDeltaToCourseDelta(
            dxVisual = velocityVisual.x,
            dyVisual = velocityVisual.y
        )

        runtimeVelocityCourse.set(
            velocityCourse.x,
            velocityCourse.y
        )

        runtimeBallCourse = PointF(ball.x, ball.y)
        renderer.setRuntimeBallCourse(runtimeBallCourse)
        renderer.setShotCamera(runtimeBallCourse, 0f)

        OpenPigeonLog.i(
            TAG,
            "launch aimDist=${aim.dist} aimRot=${aim.rotation} " +
                    "velVisual=(${velocityVisual.x},${velocityVisual.y}) " +
                    "velCourse=(${runtimeVelocityCourse.x},${runtimeVelocityCourse.y}) " +
                    "localReplayLen=${localReplay.length}"
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

    private fun stepBallPhysics() {
        val g = currentMap ?: return
        val ball = runtimeBallCourse ?: return

        val now = SystemClock.elapsedRealtime()
        val dt = ((now - lastPhysicsMs).coerceIn(1L, 34L)).toFloat() / 1000f
        lastPhysicsMs = now

        val wasInHole = ballInHole

        val stoppedByMotion = GolfPhysics.step(
            map = g,
            positionCourse = ball,
            velocityCourse = runtimeVelocityCourse,
            dtSeconds = dt
        )

        val holeStep = GolfPhysics.applyHoleCup(
            map = g,
            positionCourse = ball,
            velocityCourse = runtimeVelocityCourse,
            dtSeconds = dt,
            alreadyCaptured = wasInHole
        )

        flagPulled = holeStep.flagPulled
        ballInHole = holeStep.captured

        renderer.setRuntimeBallCourse(ball)
        renderer.setHoleState(
            flagPulled = flagPulled,
            ballInHole = ballInHole
        )

        if (holeStep.captured && !wasInHole) {
            hideAimReadyUi()
            OpenPigeonLog.i(
                TAG,
                "hole entered ball=(${ball.x},${ball.y}) hole=(${g.hole.x},${g.hole.y}) " +
                        "velocity=(${runtimeVelocityCourse.x},${runtimeVelocityCourse.y})"
            )

            stateLabel.text = "In the hole"
        }

        if (holeStep.settled) {
            hideAimReadyUi()
            OpenPigeonLog.i(
                TAG,
                "hole settled ball=(${ball.x},${ball.y}) hole=(${g.hole.x},${g.hole.y})"
            )

            renderer.setRuntimeBallCourse(ball)
            renderer.setHoleState(
                flagPulled = true,
                ballInHole = true
            )

            stopBallPhysics(clearVelocity = true)
            hideAimReadyUi()

            if (!roundResultSent) {
                roundResultSent = true
                sendCompletedRoundState()
            }

            return
        }

        if (stoppedByMotion && !ballInHole) {
            OpenPigeonLog.i(
                TAG,
                "physics stop ball=(${ball.x},${ball.y}) " +
                        "velocity=(${runtimeVelocityCourse.x},${runtimeVelocityCourse.y}) " +
                        "flagPulled=$flagPulled"
            )

            stopBallPhysics(clearVelocity = true)
            updateAimReadyUi()
        }
    }

    private fun generateAndShowMap(showIntro: Boolean, source: String) {
        val startedAt = SystemClock.elapsedRealtime()
        OpenPigeonLog.i(TAG, "generateAndShowMap enter source=$source seed=$seed mode=$mode mapNum=$mapNum holeCount=$holeCount showIntro=$showIntro")

        try {
            val generated = generator.createMap(seed, mapNum, mode)
            OpenPigeonLog.i(TAG, "generateAndShowMap generated ${generated.summary()} elapsedMs=${SystemClock.elapsedRealtime() - startedAt}")

            currentMap = generated
            stopDualReplay()
            roundResultSent = false

            val localStart = primaryBallStartFor(generated)

            runtimeBallCourse = PointF(
                localStart.x,
                localStart.y
            )
            stopBallPhysics(clearVelocity = true)
            activeAim = GolfShot.Aim.NONE
            isAiming = false
            flagPulled = false
            ballInHole = false

            renderer.setMap(generated)
            renderer.setRuntimeBallCourse(runtimeBallCourse)
            renderer.setHoleState(flagPulled = false, ballInHole = false)
            renderer.clearAimPreview()
            renderer.clearOpponentBallCourse()
            renderer.clearReplayAimPreview()

            setZoomOverviewEnabled(false)
            renderer.clearCameraFocus()
            stateLabel.text = "Hole ${generated.holeNumber}/${generated.holeCount}   seed=$seed   ${generated.xCells}x${generated.yCells}"
            if (showIntro) showHoleIntro(generated.holeNumber, generated.holeCount)

            updateAimReadyUi()
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "generateAndShowMap failed source=$source seed=$seed mode=$mode mapNum=$mapNum", t)
            throw t
        }
    }

    private fun showHoleIntro(hole: Int, total: Int) {
        OpenPigeonLog.i(TAG, "showHoleIntro hole=$hole total=$total")
        holeOverlay.animate().cancel()
        holeTitle.animate().cancel()

        holeTitle.text = "Hole $hole/$total"
        holeOverlay.visibility = View.VISIBLE
        holeOverlay.alpha = 1f
        holeTitle.alpha = 0f
        holeTitle.scaleX = 1f
        holeTitle.scaleY = 1f

        holeTitle.animate()
            .alpha(1f)
            .setDuration(GolfConstants.INTRO_FADE_IN_MS)
            .withEndAction {
                OpenPigeonLog.i(TAG, "showHoleIntro title fade-in complete hole=$hole")
                holeTitle.animate()
                    .setStartDelay(GolfConstants.INTRO_HOLD_MS)
                    .scaleX(1.7f)
                    .scaleY(1.7f)
                    .alpha(0f)
                    .setDuration(GolfConstants.INTRO_SCALE_MS)
                    .start()
            }
            .start()

        holeOverlay.animate()
            .setStartDelay(GolfConstants.INTRO_FADE_OUT_DELAY_MS)
            .alpha(0f)
            .setDuration(GolfConstants.INTRO_FADE_OUT_MS)
            .withEndAction {
                OpenPigeonLog.i(TAG, "showHoleIntro overlay hidden hole=$hole")
                holeOverlay.visibility = View.GONE
            }
            .start()
    }

    private fun showWaitingOverlay() {
        hideAimReadyUi()
        if (!::waitingOverlay.isInitialized) return

        waitingOverlay.animate().cancel()
        waitingOverlay.alpha = 1f
        waitingOverlay.visibility = View.VISIBLE
        waitingOverlay.bringToFront()
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
        var dots = 1

        waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }

        val runnable = object : Runnable {
            override fun run() {
                if (waitingDotsRunnable !== this) return

                if (
                    ::waitingOverlay.isInitialized &&
                    waitingOverlay.visibility == View.VISIBLE &&
                    label.visibility == View.VISIBLE
                ) {
                    label.text = "WAITING FOR OPPONENT" + ".".repeat(dots)
                    dots = if (dots >= 3) 1 else dots + 1
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

            waitingLabel.text = "Sent"
            waitingLabel.alpha = 0f
            waitingLabel.setTextColor(Color.WHITE)
            waitingLabel.visibility = View.VISIBLE

            waitingLabel.animate()
                .alpha(1f)
                .setDuration(250L)
                .start()

            stateLabelHandler.postDelayed({
                if (!sentWaitingSequenceActive) return@postDelayed

                val sentCheck = SpannableString("Sent ✔")
                sentCheck.setSpan(
                    ForegroundColorSpan(0xFF7257D8.toInt()),
                    5,
                    6,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                waitingLabel.text = sentCheck
            }, 1000L)

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

                    addUpdateListener { animation ->
                        val animatedParams = waitingLabel.layoutParams
                        animatedParams.width = animation.animatedValue as Int
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

                                addUpdateListener { textAnimation ->
                                    val alpha = textAnimation.animatedValue as Int
                                    waitingLabel.setTextColor((alpha shl 24) or 0x00FFFFFF)
                                }

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
            }, 2000L)
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

    private fun sendVisualStateOnly() {
        sendCurrentGolfState(roundComplete = false)
    }

    private fun sendCompletedRoundState() {
        sendCurrentGolfState(roundComplete = true)
    }

    private fun safeBuildAvatarString(fallback: String): String {
        return runCatching {
            AvatarView.buildAvatarString()
        }.getOrElse { t ->
            OpenPigeonLog.e(TAG, "AvatarView.buildAvatarString failed; preserving existing avatar", t)
            fallback
        }
    }

    private fun sendCurrentGolfState(roundComplete: Boolean) {
        val ipc = gameSessionIPC
        if (ipc == null || sessionId.isBlank()) {
            OpenPigeonLog.w(
                TAG,
                "sendCurrentGolfState skipped ipcNull=${ipc == null} sessionBlank=${sessionId.isBlank()}"
            )
            stateLabel.text = "No IPC session — visual only"
            return
        }

        try {
            val current = ipc.getCurrentMessage(sessionId).ifEmpty { lastMessage }
            val myId = ipc.getSenderUUID(sessionId).takeIf { it.isNotBlank() }.orEmpty()

            val localPlayer = localPlayerNumberFor(
                data = gameData,
                current = current
            )

            val existingPlayer1 = current["player1"].orEmpty().ifBlank { player1Id }
            val existingPlayer2 = current["player2"].orEmpty().ifBlank { player2Id }
            val existingAvatar1 = current["avatar1"].orEmpty()
            val existingAvatar2 = current["avatar2"].orEmpty()
            val existingReplay = current["replay"].orEmpty()
            val existingReplay2 = current["replay2"].orEmpty()

            val outgoing = current.toMutableMap()

            outgoing["game"] = "golf"
            outgoing["game_name"] = "Mini Golf"
            outgoing["version"] = "41"
            outgoing["v3"] = "3"
            outgoing["mode"] = mode
            outgoing["seed"] = current["seed"]?.takeIf { it.isNotBlank() } ?: seed.toString()
            outgoing["sender"] = myId
            outgoing["player"] = localPlayer.toString()

            if (roundComplete) {
                outgoing["v2"] = "2"
                outgoing["num"] = (mapNum + 2).coerceAtMost(holeCount + 1).toString()
            } else {
                outgoing["num"] = current["num"] ?: (mapNum + 1).toString()
            }

            if (localPlayer == 1) {
                outgoing["player1"] = myId
                outgoing["avatar1"] = safeBuildAvatarString(existingAvatar1)

                if (existingPlayer2.isNotBlank()) {
                    outgoing["player2"] = existingPlayer2
                }
                if (existingAvatar2.isNotBlank()) {
                    outgoing["avatar2"] = existingAvatar2
                }
                if (existingReplay2.isNotBlank()) {
                    outgoing["replay2"] = existingReplay2
                }

                if (localReplay.isNotBlank()) {
                    outgoing["replay"] = localReplay
                }
            } else {
                if (existingPlayer1.isNotBlank()) {
                    outgoing["player1"] = existingPlayer1
                }
                if (existingAvatar1.isNotBlank()) {
                    outgoing["avatar1"] = existingAvatar1
                }
                if (existingReplay.isNotBlank()) {
                    outgoing["replay"] = existingReplay
                }

                outgoing["player2"] = myId
                outgoing["avatar2"] = safeBuildAvatarString(existingAvatar2)

                if (localReplay.isNotBlank()) {
                    outgoing["replay2"] = localReplay
                }
            }

            if (outgoing["replay"].isNullOrBlank()) {
                outgoing.remove("replay")
            }
            if (outgoing["replay2"].isNullOrBlank()) {
                outgoing.remove("replay2")
            }

            OpenPigeonLog.i(
                TAG,
                "sendCurrentGolfState roundComplete=$roundComplete localPlayer=$localPlayer " +
                        "myId=$myId p1=${outgoing["player1"].orEmpty()} p2=${outgoing["player2"].orEmpty()} " +
                        "num=${outgoing["num"]} replayLen=${outgoing["replay"].orEmpty().length} " +
                        "replay2Len=${outgoing["replay2"].orEmpty().length} keys=${outgoing.keys.sorted()}"
            )

            val hasOpponentReplayAlready = if (localPlayer == 1) {
                existingReplay2.isNotBlank()
            } else {
                existingReplay.isNotBlank()
            }

            ipc.updateSession(outgoing, sessionId) {
                OpenPigeonLog.i(TAG, "sendCurrentGolfState updateSession callback")

                runOnUiThread {
                    if (hasOpponentReplayAlready) {
                        waitingForOpponent = false
                        hideAimReadyUi()
                        stopStateLabelAnimation()
                        stateLabel.text = "Replay"
                    } else {
                        waitingForOpponent = true
                        hideAimReadyUi()
                        focusCameraOnCurrentBall()
                        playSentThenWaitingAnimation()
                    }
                }
            }
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "sendCurrentGolfState failed roundComplete=$roundComplete", t)
            stateLabel.text = "Mini Golf send failed"
        }
    }

    private fun localPlayerNumberFor(
        data: GolfGameData? = gameData,
        current: Map<String, String> = lastMessage
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

        val messagePlayer = current["player"]
            ?.toIntOrNull()
            ?.coerceIn(1, 2)
            ?: data?.player
            ?: player.coerceIn(1, 2)

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
        g: GolfMap,
        localPlayer: Int = localPlayerNumberFor(gameData)
    ): PointF {
        return if (localPlayer == 2) {
            g.ballStart2
        } else {
            g.ballStart1
        }
    }

    private fun opponentBallStartFor(
        g: GolfMap,
        localPlayer: Int = localPlayerNumberFor(gameData)
    ): PointF {
        return if (localPlayer == 2) {
            g.ballStart1
        } else {
            g.ballStart2
        }
    }

    private fun hasBothReplaysForCurrentHole(data: GolfGameData): Boolean {
        return GolfReplay.hasSegment(data.replay, data.mapNum) &&
                GolfReplay.hasSegment(data.replay2, data.mapNum)
    }

    private fun startDualReplayFromData(data: GolfGameData) {
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

        renderer.setReplayCamera(
            runtimeBallCourse,
            dualReplayOpponentBallCourse
        )

        stopStateLabelAnimation()
        showSkipReplayButton()

        stateLabel.text = "Replay"

        OpenPigeonLog.i(
            TAG,
            "startDualReplay localPlayer=$localPlayer mapNum=${data.mapNum} " +
                    "mineShots=${dualReplayMineShots.size} opponentShots=${dualReplayOpponentShots.size}"
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

        val mineAim = mineShot?.let { GolfShot.Aim(it.dist, it.rotation) }
        val opponentAim = opponentShot?.let { GolfShot.Aim(it.dist, it.rotation) }
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
            "dualReplay preview shotIndex=$dualReplayShotIndex " +
                    "mineShot=${mineShot != null} opponentShot=${opponentShot != null}"
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

            dualReplayMineShots.getOrNull(dualReplayShotIndex)?.let { shot ->
                dualReplayMineVelocityCourse.set(shotVelocityCourse(shot))
            }

            dualReplayOpponentShots.getOrNull(dualReplayShotIndex)?.let { shot ->
                dualReplayOpponentVelocityCourse.set(shotVelocityCourse(shot))
            }

            dualReplayWaitingToFire = false
            dualReplayLastMs = now

            OpenPigeonLog.i(
                TAG,
                "dualReplay fire shotIndex=$dualReplayShotIndex " +
                        "mineVel=(${dualReplayMineVelocityCourse.x},${dualReplayMineVelocityCourse.y}) " +
                        "oppVel=(${dualReplayOpponentVelocityCourse.x},${dualReplayOpponentVelocityCourse.y})"
            )

            return
        }

        val dt = ((now - dualReplayLastMs).coerceIn(1L, 34L)).toFloat() / 1000f
        dualReplayLastMs = now

        var mineDone = dualReplayMineInHole || dualReplayMineShots.getOrNull(dualReplayShotIndex) == null
        var opponentDone = dualReplayOpponentInHole || dualReplayOpponentShots.getOrNull(dualReplayShotIndex) == null

        if (!mineDone) {
            val stopped = GolfPhysics.step(
                map = g,
                positionCourse = mineBall,
                velocityCourse = dualReplayMineVelocityCourse,
                dtSeconds = dt
            )

            val holeStep = GolfPhysics.applyHoleCup(
                map = g,
                positionCourse = mineBall,
                velocityCourse = dualReplayMineVelocityCourse,
                dtSeconds = dt,
                alreadyCaptured = dualReplayMineInHole
            )

            dualReplayMineInHole = holeStep.captured
            mineDone = holeStep.settled || (stopped && !holeStep.captured)
        }

        if (!opponentDone) {
            val stopped = GolfPhysics.step(
                map = g,
                positionCourse = opponentBall,
                velocityCourse = dualReplayOpponentVelocityCourse,
                dtSeconds = dt
            )

            val holeStep = GolfPhysics.applyHoleCup(
                map = g,
                positionCourse = opponentBall,
                velocityCourse = dualReplayOpponentVelocityCourse,
                dtSeconds = dt,
                alreadyCaptured = dualReplayOpponentInHole
            )

            dualReplayOpponentInHole = holeStep.captured
            opponentDone = holeStep.settled || (stopped && !holeStep.captured)
        }

        renderer.setRuntimeBallCourse(mineBall)
        renderer.setOpponentBallCourse(opponentBall)
        renderer.setReplayCamera(mineBall, opponentBall)

        if (mineDone && opponentDone) {
            dualReplayShotIndex += 1
            scheduleNextDualReplayShot()
        }
    }

    private fun shotVelocityCourse(shot: GolfReplay.Shot): PointF {
        val velocityVisual = GolfShot.launchVelocityVisual(
            GolfShot.Aim(
                dist = shot.dist,
                rotation = shot.rotation
            )
        )

        return renderer.visualDeltaToCourseDelta(
            dxVisual = velocityVisual.x,
            dyVisual = velocityVisual.y
        )
    }

    private fun finishDualReplay(immediateAdvance: Boolean = false) {
        OpenPigeonLog.i(
            TAG,
            "finishDualReplay shotIndex=$dualReplayShotIndex mapNum=$mapNum holeCount=$holeCount " +
                    "immediateAdvance=$immediateAdvance"
        )

        dualReplayRunning = false
        dualReplayWaitingToFire = false

        renderer.removeCallbacks(dualReplayTick)
        renderer.clearReplayAimPreview()
        renderer.clearOpponentBallCourse()
        hideSkipReplayButton()
        stopStateLabelAnimation()
        hideAimReadyUi()

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
            waitingForOpponent = false
            stateLabel.text = "Game complete"
        }
    }

    private fun advanceAfterReplayToNextHole(source: String) {
        if (mapNum + 1 >= holeCount) {
            waitingForOpponent = false
            stateLabel.text = "Game complete"
            return
        }

        mapNum += 1

        val shouldWait = isCurrentMessageFromMe(lastMessage)
        waitingForOpponent = shouldWait

        OpenPigeonLog.i(
            TAG,
            "advanceAfterReplayToNextHole source=$source mapNum=$mapNum shouldWait=$shouldWait " +
                    "lastMessageFromMe=${isCurrentMessageFromMe(lastMessage)}"
        )

        generateAndShowMap(
            showIntro = !shouldWait,
            source = source
        )

        if (shouldWait) {
            focusCameraOnCurrentBall()
            showWaitingLabelAnimated()
        } else {
            stopStateLabelAnimation()
            updateAimReadyUi()
        }
    }

    private fun stopDualReplay() {
        hideSkipReplayButton()

        if (!dualReplayRunning && !dualReplayWaitingToFire) return

        dualReplayRunning = false
        dualReplayWaitingToFire = false

        renderer.removeCallbacks(dualReplayTick)
        renderer.clearReplayAimPreview()
        renderer.clearOpponentBallCourse()

        dualReplayMineVelocityCourse.set(0f, 0f)
        dualReplayOpponentVelocityCourse.set(0f, 0f)
    }

    private fun safeShowFallbackFromOnCreateFailure() {
        try {
            if (!::root.isInitialized) buildLayout()
            stateLabel.text = "Mini Golf failed to initialize — local fallback"
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

    private fun messageSummary(msg: Map<String, String>): String {
        if (msg.isEmpty()) return "messageKeys=[]"
        val selected = listOf("game", "mode", "game_mode", "holes", "seed", "game_seed", "random_seed", "num", "map_num", "mapNum", "hole", "hole_index", "player", "isYourTurn", "turn", "subcaption")
            .mapNotNull { key -> msg[key]?.let { value -> "$key=$value" } }
        return "messageKeys=${msg.keys.sorted()} selected=${selected.joinToString(",")} replayLen=${msg["replay"].orEmpty().length} replay2Len=${msg["replay2"].orEmpty().length}"
    }

    private class OutlineTextView(context: android.content.Context) : androidx.appcompat.widget.AppCompatTextView(context) {
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

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onStart() {
        super.onStart()
        OpenPigeonLog.i(TAG, "onStart")
    }

    override fun onResume() {
        super.onResume()
        OpenPigeonLog.i(TAG, "onResume")
    }

    override fun onPause() {
        OpenPigeonLog.i(TAG, "onPause")

        if (::renderer.isInitialized) {
            stopBallPhysics(clearVelocity = false)
            stopDualReplay()
            renderer.clearAimPreview()
            stopStateLabelAnimation()
            hideAimReadyUi()
        }

        super.onPause()
    }

    override fun onDestroy() {
        OpenPigeonLog.i(TAG, "onDestroy sessionBlank=${sessionId.isBlank()} ipcNull=${gameSessionIPC == null}")

        if (::renderer.isInitialized) {
            stopBallPhysics(clearVelocity = true)
            stopDualReplay()
            renderer.clearAimPreview()
            stopStateLabelAnimation()
            hideAimReadyUi()
        }

        runCatching {
            if (sessionId.isNotBlank()) gameSessionIPC?.setSuppressNotifications(sessionId, false)
        }.onFailure { OpenPigeonLog.e(TAG, "onDestroy setSuppressNotifications(false) failed", it) }

        if (::settingsSheet.isInitialized) {
            settingsSheet.detach()
        }
        gameSessionIPC = null
        super.onDestroy()
    }
}
