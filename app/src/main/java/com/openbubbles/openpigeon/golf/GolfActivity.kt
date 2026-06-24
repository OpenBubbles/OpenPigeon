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
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import com.openbubbles.openpigeon.godot.GameSessionIPC
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog
import android.graphics.PointF

/**
 * First native Android Mini Golf screen.
 *
 * Diagnostic v3:
 *   - Every diagnostic uses OpenPigeonLog.
 *   - Logs all lifecycle / IPC / parse / generate / render handoffs.
 *   - Fails open to a local visual board if a bad incoming message throws.
 */
class GolfActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "GolfNative"
    }

    private lateinit var root: FrameLayout
    private lateinit var renderer: GolfRenderer
    private lateinit var stateLabel: TextView
    private lateinit var holeOverlay: FrameLayout
    private lateinit var holeTitle: TextView
    private lateinit var nextButton: Button
    private lateinit var sendButton: Button

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

    private var isAiming = false
    private var aimMoveStartVisual = PointF(0f, 0f)
    private var activeAim: GolfShot.Aim = GolfShot.Aim.NONE

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

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        val startedAt = SystemClock.elapsedRealtime()
        super.onCreate(savedInstanceState)
        OpenPigeonLog.installContext(applicationContext)
        OpenPigeonLog.title(TAG, "Mini Golf", "onCreate start")

        try {
            OpenPigeonLog.i(TAG, "onCreate: request no title / hide actionbar")
            requestWindowFeature(Window.FEATURE_NO_TITLE)
            supportActionBar?.hide()

            OpenPigeonLog.i(TAG, "onCreate: buildLayout start")
            buildLayout()
            OpenPigeonLog.i(TAG, "onCreate: buildLayout complete rootChildren=${root.childCount}")

            ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets -> insets }

            renderer.setOnTouchListener { _, event ->
                handleGolfTouch(event)
            }

            nextButton.setOnClickListener {
                OpenPigeonLog.i(TAG, "Next Hole button clicked currentMapNum=$mapNum holeCount=$holeCount")
                showNextHoleLocal()
            }
            sendButton.setOnClickListener {
                OpenPigeonLog.i(TAG, "Send button clicked currentMapNum=$mapNum mode=$mode seed=$seed")
                sendVisualStateOnly()
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

        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            ).apply { bottomMargin = dp(28) }
        }

        nextButton = Button(this).apply {
            text = "Next Hole"
            textSize = 16f
            setTextColor(Color.WHITE)
            background = rounded(Color.rgb(72, 145, 235), dp(18).toFloat())
            minWidth = dp(132)
        }
        buttons.addView(nextButton, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(52)).apply {
            marginEnd = dp(10)
        })

        sendButton = Button(this).apply {
            text = "Send"
            textSize = 16f
            setTextColor(Color.WHITE)
            background = rounded(Color.rgb(73, 170, 103), dp(18).toFloat())
            minWidth = dp(104)
        }
        buttons.addView(sendButton, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(52)))
        root.addView(buttons)

        buildHoleOverlay()
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
            localReplay = parsed.replay

            seed = parsed.seed
            mode = parsed.mode
            holeCount = parsed.holeCount
            mapNum = parsed.mapNum
            player = parsed.player
            player1Id = parsed.player1Id
            player2Id = parsed.player2Id

            OpenPigeonLog.i(
                TAG,
                "handleMessage parsed prev=($previousSeed,$previousMode,$previousMapNum) " +
                    "now=(seed=$seed seedText=${parsed.seedText} unsignedSeed=${parsed.seedWasUnsignedDecimal} " +
                    "mode=$mode holeCount=$holeCount mapNum=$mapNum rawNum=${parsed.rawNum} player=$player) " +
                    "renderKey=${parsed.renderKey}"
            )

            if (parsed.renderKey == lastRenderedKey) {
                OpenPigeonLog.i(TAG, "handleMessage duplicate skipped renderKey=${parsed.renderKey} elapsedMs=${SystemClock.elapsedRealtime() - startedAt}")
                return
            }
            lastRenderedKey = parsed.renderKey

            generateAndShowMap(showIntro = true, source = "handleMessage")
            OpenPigeonLog.i(TAG, "handleMessage complete elapsedMs=${SystemClock.elapsedRealtime() - startedAt}")
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "Failed to open Mini Golf message ${messageSummary(msg)}", t)
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

                /*
                 * iOS uses the touch-down point as move_start, not the ball center.
                 */
                isAiming = true
                aimMoveStartVisual = visual
                activeAim = GolfShot.Aim.NONE

                stopBallPhysics(clearVelocity = true)
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
                }

                activeAim = GolfShot.Aim.NONE
                return true
            }
        }

        return true
    }

    private fun launchCurrentAim(aim: GolfShot.Aim) {
        val ball = runtimeBallCourse ?: currentMap?.ballStart1 ?: return

        /*
         * iOS replay stores dist,rotation for the normal one-ball scene.
         */
        localReplay = GolfReplay.appendShot(
            replay = localReplay,
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
        val ball = runtimeBallCourse ?: return

        val now = SystemClock.elapsedRealtime()
        val dt = ((now - lastPhysicsMs).coerceIn(1L, 34L)).toFloat() / 1000f
        lastPhysicsMs = now

        ball.x += runtimeVelocityCourse.x * dt
        ball.y += runtimeVelocityCourse.y * dt

        /*
         * Temporary roll decay until we decode -[GolfScene update:].
         * Initial shot velocity is decoded; this damping is intentionally isolated here.
         */
        val damping = GolfShot.temporaryDampingFactor(dt)
        runtimeVelocityCourse.x *= damping
        runtimeVelocityCourse.y *= damping

        renderer.setRuntimeBallCourse(ball)

        if (GolfShot.isTemporaryStopped(runtimeVelocityCourse.x, runtimeVelocityCourse.y)) {
            OpenPigeonLog.i(
                TAG,
                "physics stop ball=(${ball.x},${ball.y}) velocity=(${runtimeVelocityCourse.x},${runtimeVelocityCourse.y})"
            )

            stopBallPhysics(clearVelocity = true)
        }
    }

    private fun generateAndShowMap(showIntro: Boolean, source: String) {
        val startedAt = SystemClock.elapsedRealtime()
        OpenPigeonLog.i(TAG, "generateAndShowMap enter source=$source seed=$seed mode=$mode mapNum=$mapNum holeCount=$holeCount showIntro=$showIntro")

        try {
            val generated = generator.createMap(seed, mapNum, mode)
            OpenPigeonLog.i(TAG, "generateAndShowMap generated ${generated.summary()} elapsedMs=${SystemClock.elapsedRealtime() - startedAt}")

            currentMap = generated

            runtimeBallCourse = PointF(
                generated.ballStart1.x,
                generated.ballStart1.y
            )
            stopBallPhysics(clearVelocity = true)
            activeAim = GolfShot.Aim.NONE
            isAiming = false

            renderer.setMap(generated)
            renderer.setRuntimeBallCourse(runtimeBallCourse)
            renderer.clearAimPreview()
            stateLabel.text = "Hole ${generated.holeNumber}/${generated.holeCount}   seed=$seed   ${generated.xCells}x${generated.yCells}"
            nextButton.text = if (mapNum + 1 < holeCount) "Next Hole" else "Restart"
            if (showIntro) showHoleIntro(generated.holeNumber, generated.holeCount)
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "generateAndShowMap failed source=$source seed=$seed mode=$mode mapNum=$mapNum", t)
            throw t
        }
    }

    private fun showNextHoleLocal() {
        mapNum = if (mapNum + 1 < holeCount) mapNum + 1 else 0
        localReplay = ""
        generateAndShowMap(showIntro = true, source = "nextButton")
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

    private fun sendVisualStateOnly() {
        val ipc = gameSessionIPC
        if (ipc == null || sessionId.isBlank()) {
            OpenPigeonLog.w(TAG, "sendVisualStateOnly skipped ipcNull=${ipc == null} sessionBlank=${sessionId.isBlank()}")
            stateLabel.text = "No IPC session — visual only"
            return
        }

        try {
            val current = ipc.getCurrentMessage(sessionId).ifEmpty { lastMessage }
            val myId = ipc.getSenderUUID(sessionId).takeIf { it.isNotBlank() }.orEmpty()
            val outgoing = current.toMutableMap()
            outgoing["game"] = "golf"
            outgoing["mode"] = mode
            outgoing["seed"] = seed.toString()
            outgoing["num"] = (mapNum + 1).toString()
            outgoing["player"] = player.toString()
            outgoing["sender"] = myId
            outgoing["replay"] = localReplay.ifBlank { outgoing["replay"].orEmpty() }
            outgoing["replay2"] = outgoing["replay2"].orEmpty()

            if (player == 1) {
                outgoing["player1"] = myId
                if (player2Id.isNotBlank()) outgoing["player2"] = player2Id
                outgoing["avatar1"] = AvatarView.buildAvatarString()
            } else {
                if (player1Id.isNotBlank()) outgoing["player1"] = player1Id
                outgoing["player2"] = myId
                outgoing["avatar2"] = AvatarView.buildAvatarString()
            }

            OpenPigeonLog.i(TAG, "sendVisualStateOnly updateSession ${messageSummary(outgoing)}")
            ipc.updateSession(outgoing, sessionId) {
                OpenPigeonLog.i(TAG, "sendVisualStateOnly updateSession callback")
                runOnUiThread { stateLabel.text = "Sent visual Mini Golf state" }
            }
        } catch (t: Throwable) {
            OpenPigeonLog.e(TAG, "sendVisualStateOnly failed", t)
            stateLabel.text = "Mini Golf send failed"
        }
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
            renderer.clearAimPreview()
        }

        super.onPause()
    }

    override fun onDestroy() {
        OpenPigeonLog.i(TAG, "onDestroy sessionBlank=${sessionId.isBlank()} ipcNull=${gameSessionIPC == null}")

        if (::renderer.isInitialized) {
            stopBallPhysics(clearVelocity = true)
            renderer.clearAimPreview()
        }

        runCatching {
            if (sessionId.isNotBlank()) gameSessionIPC?.setSuppressNotifications(sessionId, false)
        }.onFailure { OpenPigeonLog.e(TAG, "onDestroy setSuppressNotifications(false) failed", it) }

        gameSessionIPC = null
        super.onDestroy()
    }
}
