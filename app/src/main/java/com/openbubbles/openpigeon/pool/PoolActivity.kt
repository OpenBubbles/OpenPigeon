package com.openbubbles.openpigeon.pool

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.RectF
import android.os.Bundle
import android.os.Handler
import com.openbubbles.openpigeon.util.OpenPigeonLog
import android.util.TypedValue
import com.openbubbles.openpigeon.settings.AvatarView
import android.widget.ImageButton
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.View
import android.view.Window
import java.util.Locale
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.animation.doOnEnd
import androidx.core.view.ViewCompat
import android.graphics.Paint
import android.graphics.Color
import com.openbubbles.openpigeon.ui.RulesPopup
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GameSessionIPC
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.min
import kotlin.math.sqrt
import kotlin.math.max
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import kotlin.math.floor
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import kotlin.math.ceil
import android.graphics.drawable.GradientDrawable
import android.os.Looper
import android.view.Gravity
import android.view.ViewGroup
import kotlin.random.Random
import android.os.SystemClock
import android.graphics.RadialGradient
import android.graphics.Shader
import androidx.core.view.isVisible
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import androidx.core.graphics.withTranslation
import androidx.core.graphics.createBitmap
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import com.openbubbles.openpigeon.ui.GameMenuController
import com.openbubbles.openpigeon.ui.GameMenuPlacement
import androidx.core.graphics.withSave
import kotlin.math.exp
import com.openbubbles.openpigeon.settings.AvatarWinBurstController
import com.openbubbles.openpigeon.ui.TurnRecoveryOverlayController
import com.openbubbles.openpigeon.ui.attachTurnRecoveryOverlay

class PoolActivity : AppCompatActivity() {
    lateinit var sessionId: String
    var gameSessionIPC: GameSessionIPC? = null
    var baseGame = PoolGame()

    private lateinit var gameMenu: GameMenuController

    private lateinit var turnRecoveryOverlay:
            TurnRecoveryOverlayController

    private val recoveryHandler =
        Handler(
            Looper.getMainLooper(),
        )

    private var recoveryCheckRunnable: Runnable? = null

    private var recoveryRetryInFlight = false

    private var restoringTurnRecovery = false

    private var restoringLastShotReplay = false
    private var recoveryTurnStartBalls = ""
    private var lastShotStartBalls = ""
    private var lastShotStartIsFirst = false

    @Volatile
    private var darkMode = false

    private var gameOpenedLogged = false

    private fun logGameOpened(msg: Map<String, String>) {
        if (gameOpenedLogged) return
        gameOpenedLogged = true

        val gameName = msg["game"] ?: msg["name"] ?: msg["gameName"] ?: baseGame.getName()
        val mode = msg["mode"] ?: "n"

        val title = when (gameName) {
            "pool2" -> "9 Ball"
            "pool3" -> "8 Ball+"
            else -> "8 Ball"
        }

        val difficulty = if (mode == "h") "Hard" else "Normal"

        OpenPigeonLog.title(
            "Pool",
            title,
            "difficulty=$difficulty replayLen=${msg["replay"]?.length ?: 0} player=${msg["player"].orEmpty()} num=${msg["num"].orEmpty()}"
        )
    }

    private fun currentMusicTrack(): String {
        return if (isNineBall) {
            "pool/9ball.wav"
        } else {
            "pool/8ball.wav"
        }
    }

    var table: Long = 0L

    @Volatile
    var poolActivityClosing = false

    lateinit var renderer: PoolRenderer

    enum class PoolMode {
        Playing, Aiming, Disabled, ReplayAiming,
    }


    var mode = PoolMode.Disabled

    var lastAngle = 0f

    private var cueDragLastTimeMs = 0L
    private var cueInertiaVelocity = 0f
    private var cueInertiaLastTimeMs = 0L
    private var cueInertiaRunnable: Runnable? = null

    var touchDownCueX = 0f

    private var lastCueHapticStep = -1

    private val stateLabelHandler = Handler(Looper.getMainLooper())
    private var waitingDotsRunnable: Runnable? = null
    private var stateLabelAnimator: ValueAnimator? = null
    private var sentWaitingSequenceActive = false
    private var statusDimView: View? = null

    @Volatile
    private var statusDimVisible = false

    @Volatile
    private var gameEnded = false

    @Volatile
    private var winLossState = ""

    @Volatile
    private var pendingWinLossState = ""

    private enum class StateLabelVisual { Hidden, Waiting, SentWaiting, GameOver }

    private var stateLabelVisual = StateLabelVisual.Hidden

    private var spectatorMode = false
    private var lastMessageWinner = ""
    private var lastMessage: Map<String, String> = emptyMap()

    private lateinit var gameAvatarAnchor: FrameLayout
    private lateinit var oppAvatarAnchor: FrameLayout
    private lateinit var avatarWinBurstController: AvatarWinBurstController

    fun isPoolDarkModeEnabled(): Boolean {
        return darkMode
    }

    private fun applyDarkModeVisual(
        enabled: Boolean,
    ) {
        darkMode = enabled

        findViewById<FrameLayout>(
            R.id.poolRoot,
        ).setBackgroundResource(
            if (enabled) {
                R.drawable.background_soft_depth_dark
            } else {
                R.drawable.background_soft_depth
            },
        )
    }

    external fun dumpPoolTable(table: Long): String
    external fun setPoolDebugTrace(table: Long, enabled: Boolean, everyFrames: Int)

    private fun updateBallTypeUi() {
        runOnUiThread {
            val playerBall = findViewById<ImageView>(R.id.playerBallType)
            val oppBall = findViewById<ImageView>(R.id.oppBallType)

            if (isNineBall) {
                playerBall.visibility = View.GONE
                oppBall.visibility = View.GONE
                return@runOnUiThread
            }

            playerBall.visibility = View.VISIBLE
            oppBall.visibility = View.VISIBLE

            when (iAmStripes) {
                null -> {
                    playerBall.setImageResource(R.drawable.pool_ball_empty)
                    oppBall.setImageResource(R.drawable.pool_ball_empty)
                }

                true -> {
                    playerBall.setImageResource(R.drawable.pool_ball_stripes)
                    oppBall.setImageResource(R.drawable.pool_ball_solids)
                }

                false -> {
                    playerBall.setImageResource(R.drawable.pool_ball_solids)
                    oppBall.setImageResource(R.drawable.pool_ball_stripes)
                }
            }
        }
    }

    private fun updateNineBallBar() {
        runOnUiThread {
            val bar = findViewById<LinearLayout>(R.id.nineBallBar)

            if (!isNineBall) {
                bar.visibility = View.GONE
                return@runOnUiThread
            }

            bar.visibility = View.VISIBLE

            if (bar.childCount != 9) {
                bar.removeAllViews()

                for (number in 1..9) {
                    val image = ImageView(this).apply {
                        tag = number
                        setImageBitmap(PoolBall.previewBitmap(resources, number))
                        scaleType = ImageView.ScaleType.FIT_CENTER
                        adjustViewBounds = false
                        layoutParams = LinearLayout.LayoutParams(
                            stateLabelDp(22f), stateLabelDp(22f)
                        ).apply {
                            topMargin = stateLabelDp(1f)
                            bottomMargin = stateLabelDp(1f)
                        }
                    }

                    bar.addView(image)
                }
            }

            for (i in 0 until bar.childCount) {
                val image = bar.getChildAt(i) as ImageView
                val number = image.tag as Int
                image.alpha = if (poolBalls.any { it.number == number && !it.sunk }) 1f else 0.22f
            }
        }
    }

    private val nineBallBarRefreshHandler = Handler(Looper.getMainLooper())
    private var nineBallBarRefreshActive = false

    private fun startNineBallBarRefresh() {
        if (!isNineBall || nineBallBarRefreshActive) return

        nineBallBarRefreshActive = true
        nineBallBarRefreshHandler.post(object : Runnable {
            override fun run() {
                if (!nineBallBarRefreshActive) return

                updateNineBallBar()
                nineBallBarRefreshHandler.postDelayed(this, 120L)
            }
        })
    }

    private fun stopNineBallBarRefresh() {
        if (!nineBallBarRefreshActive) {
            updateNineBallBar()
            return
        }

        nineBallBarRefreshActive = false
        nineBallBarRefreshHandler.removeCallbacksAndMessages(null)
        updateNineBallBar()
    }

    private fun vibrateCueTick() {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION") getSystemService(VIBRATOR_SERVICE) as Vibrator
        }

        if (!vibrator.hasVibrator()) return

        vibrator.vibrate(VibrationEffect.createOneShot(12, 180))
    }

    private fun stateLabelDp(value: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics
        ).toInt()
    }

    private fun applyStateLabelBackground(label: TextView) {
        label.background = GradientDrawable().apply {
            setColor(0xBB000000.toInt())
            cornerRadius = stateLabelDp(14f).toFloat()
        }
        label.maxLines = 1
    }

    private fun resetStateLabelLayout(label: TextView) {
        label.animate().cancel()
        label.alpha = 1f
        label.scaleX = 1f
        label.scaleY = 1f
        label.minWidth = 0
        label.gravity = Gravity.CENTER
        label.textAlignment = View.TEXT_ALIGNMENT_CENTER
        label.setTextColor(0xFFFFFFFF.toInt())
        applyStateLabelBackground(label)

        val params = label.layoutParams as? FrameLayout.LayoutParams
        if (params != null) {
            params.width = WRAP_CONTENT
            params.height = WRAP_CONTENT
            params.gravity = Gravity.CENTER
            params.topMargin = 0
            params.bottomMargin = 0
            params.leftMargin = 0
            params.rightMargin = 0
            label.layoutParams = params
        } else {
            val fallbackParams = label.layoutParams
            fallbackParams.width = WRAP_CONTENT
            label.layoutParams = fallbackParams
        }

        label.bringToFront()
    }

    private fun measureStateLabelWidth(label: TextView, text: CharSequence): Int {
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
        stateLabelVisual = StateLabelVisual.Hidden
    }

    private fun ensureStatusDimView(): View? {
        statusDimView?.let { return it }

        val root = findViewById<FrameLayout>(R.id.poolRoot) ?: return null

        root.clipChildren = false
        root.clipToPadding = false

        val dim = View(this).apply {
            setBackgroundColor(Color.argb(115, 0, 0, 0))
            alpha = 0f
            visibility = View.GONE
            isClickable = false
            isFocusable = false
        }

        root.addView(
            dim, FrameLayout.LayoutParams(
                MATCH_PARENT, MATCH_PARENT
            )
        )

        statusDimView = dim
        return dim
    }

    private fun setStatusDimVisible(visible: Boolean) {
        runOnUiThread {
            val dim = ensureStatusDimView() ?: return@runOnUiThread

            dim.animate().cancel()

            if (visible) {
                statusDimVisible = true

                if (dim.visibility != View.VISIBLE) {
                    dim.alpha = 0f
                    dim.visibility = View.VISIBLE
                }

                dim.bringToFront()

                dim.animate().alpha(1f).setDuration(180L).start()
            } else {
                statusDimVisible = false

                dim.animate().alpha(0f).setDuration(160L).withEndAction {
                    if (!statusDimVisible) {
                        dim.visibility = View.GONE
                    }
                }.start()
            }
        }
    }

    private fun isGameOver(): Boolean {
        return gameEnded && winLossState.isNotBlank()
    }

    private fun gameOverText(): String {
        if (spectatorMode) {
            return when (winningPlayerFromWinner(
                lastMessageWinner
            )) {
                1 -> "Player 1 Wins!"
                2 -> "Player 2 Wins!"
                0 -> TEXT_DRAW
                else -> TEXT_DRAW
            }
        }

        return when (winLossState) {
            "1" -> TEXT_YOU_WIN
            "-1" -> TEXT_YOU_LOSE
            "0" -> TEXT_DRAW
            else -> ""
        }
    }

    private fun gameOverTextColor(): Int {
        if (spectatorMode) {
            return when (winningPlayerFromWinner(
                lastMessageWinner
            )) {
                1, 2 -> Color.rgb(255, 214, 0)
                else -> Color.WHITE
            }
        }

        return when (winLossState) {
            "1" -> Color.rgb(255, 214, 0)
            "-1" -> Color.rgb(255, 51, 51)
            "0" -> Color.WHITE
            else -> Color.WHITE
        }
    }

    private fun localWinLossStateFromWinner(rawWinner: String?): String {
        val winner = rawWinner.orEmpty()
        if (winner.isBlank()) return ""

        val parts = winner.split("|", limit = 2)
        if (parts.size != 2) return ""

        val senderWinnerId = parts[0]
        val senderState = parts[1].toIntOrNull()?.coerceIn(-1, 1) ?: return ""
        val myId = gameSessionIPC?.getSenderUUID(sessionId).orEmpty()

        val localState = when {
            senderState == 0 -> 0
            myId.isNotBlank() && senderWinnerId == myId -> senderState
            else -> -senderState
        }

        return localState.toString()
    }

    private fun setPendingWinLossState(state: String) {
        if (state.isBlank()) return

        pendingWinLossState = state
    }

    private fun markGameOver(state: String) {
        if (state.isBlank()) return

        gameEnded = true
        winLossState = state
        mode = PoolMode.Disabled

        setCueUiVisible(false)

        runOnUiThread {
            if (::renderer.isInitialized) {
                renderer.setCueVisible(false)
            }
        }

        showGameOverLabel()
    }

    private fun avatarWinBurstResult(): Int? {
        if (spectatorMode) {
            return when (winningPlayerFromWinner(
                lastMessageWinner,
            )) {
                1 -> {
                    1
                }

                2 -> {
                    -1
                }

                0 -> {
                    0
                }

                else -> {
                    null
                }
            }
        }

        return winLossState.toIntOrNull()?.coerceIn(
            -1,
            1,
        )
    }

    private fun showGameOverLabel() {
        runOnUiThread {
            if (!isGameOver()) return@runOnUiThread

            stopStateLabelAnimation()
            stateLabelVisual = StateLabelVisual.GameOver

            val label = findViewById<TextView>(R.id.state_label)
            resetStateLabelLayout(label)

            val text = gameOverText()
            val labelWidth = measureStateLabelWidth(label, text)

            val params = label.layoutParams
            params.width = labelWidth
            label.layoutParams = params

            label.text = text
            label.setTextColor(gameOverTextColor())
            label.visibility = View.VISIBLE

            setStatusDimVisible(
                true,
            )

            avatarWinBurstResult()?.let { result ->
                if (::avatarWinBurstController.isInitialized) {
                    avatarWinBurstController.show(
                        result = result,
                        dimView = statusDimView,
                        label = label,
                    )
                }
            }

            label.bringToFront()
        }
    }

    private fun showSendingLabelImmediately() {
        runOnUiThread {
            stopStateLabelAnimation()
            sentWaitingSequenceActive = true
            stateLabelVisual = StateLabelVisual.SentWaiting

            val label = findViewById<TextView>(R.id.state_label)
            resetStateLabelLayout(label)

            val sentWidth = measureStateLabelWidth(label, TEXT_SENT_CHECK)

            val params = label.layoutParams
            params.width = sentWidth
            label.layoutParams = params

            label.text = TEXT_SENT
            label.alpha = 1f
            label.setTextColor(0xFFFFFFFF.toInt())
            label.visibility = View.VISIBLE
            label.bringToFront()
        }
    }

    private fun hideStateLabel() {
        stopStateLabelAnimation()

        val label = findViewById<TextView>(R.id.state_label)
        resetStateLabelLayout(label)
        label.text = null
        label.visibility = View.GONE
        if (::avatarWinBurstController.isInitialized) {
            avatarWinBurstController.clear()
        }
        setStatusDimVisible(false)
    }

    private fun startWaitingDots(label: TextView) {
        var dots = 1

        waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }

        val runnable = object : Runnable {
            override fun run() {
                if (waitingDotsRunnable !== this) return

                if (label.isVisible) {
                    label.text = waitingOpponentText(dots)
                    dots = if (dots >= 3) 1 else dots + 1
                }

                stateLabelHandler.postDelayed(this, 900L)
            }
        }

        waitingDotsRunnable = runnable
        stateLabelHandler.post(runnable)
    }

    private fun waitingOpponentText(dots: Int): String {
        return TEXT_WAITING_BASE + ".".repeat(dots.coerceIn(1, 3))
    }

    private fun showWaitingLabelAnimated() {
        runOnUiThread {
            if (isGameOver()) {
                showGameOverLabel()
                return@runOnUiThread
            }

            if (stateLabelVisual == StateLabelVisual.Waiting) return@runOnUiThread
            stopStateLabelAnimation()
            stateLabelVisual = StateLabelVisual.Waiting

            val label = findViewById<TextView>(R.id.state_label)
            resetStateLabelLayout(label)
            label.bringToFront()

            val waitingWidth = measureStateLabelWidth(label, TEXT_WAITING_FULL)
            val params = label.layoutParams
            params.width = waitingWidth
            label.layoutParams = params

            label.visibility = View.VISIBLE
            startWaitingDots(label)
        }
    }

    private fun playSentThenWaitingAnimation() {
        runOnUiThread {
            sentWaitingSequenceActive = true
            stateLabelVisual = StateLabelVisual.SentWaiting

            waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }
            waitingDotsRunnable = null
            stateLabelAnimator?.cancel()
            stateLabelAnimator = null

            val label = findViewById<TextView>(R.id.state_label)
            resetStateLabelLayout(label)

            val sentWidth = measureStateLabelWidth(label, TEXT_SENT_CHECK)
            val waitingWidth = measureStateLabelWidth(label, TEXT_WAITING_FULL)

            val params = label.layoutParams
            params.width = sentWidth
            label.layoutParams = params

            val sentCheck = SpannableString(TEXT_SENT_CHECK)
            sentCheck.setSpan(
                ForegroundColorSpan(0xFF7257D8.toInt()), 5, 6, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )

            label.text = sentCheck
            label.alpha = 1f
            label.setTextColor(0xFFFFFFFF.toInt())
            label.visibility = View.VISIBLE
            label.bringToFront()

            stateLabelHandler.postDelayed({
                if (!sentWaitingSequenceActive || poolActivityClosing) return@postDelayed

                if (isGameOver()) {
                    showGameOverLabel()
                    return@postDelayed
                }

                setStatusDimVisible(true)
                label.bringToFront()

                val oldWidth = label.width.takeIf { it > 0 } ?: sentWidth

                val widthParams = label.layoutParams
                widthParams.width = oldWidth
                label.layoutParams = widthParams

                label.animate().cancel()
                label.alpha = 1f
                label.text = TEXT_WAITING_ONE_DOT
                label.setTextColor(0x00FFFFFF)
                label.visibility = View.VISIBLE
                label.bringToFront()

                stateLabelAnimator = ValueAnimator.ofInt(oldWidth, waitingWidth).apply {
                    duration = 420L

                    addUpdateListener { animation ->
                        val animatedParams = label.layoutParams
                        animatedParams.width = animation.animatedValue as Int
                        label.layoutParams = animatedParams
                    }

                    doOnEnd {
                        if (!sentWaitingSequenceActive || poolActivityClosing) return@doOnEnd

                        stateLabelAnimator = null

                        val finalParams = label.layoutParams
                        finalParams.width = waitingWidth
                        label.layoutParams = finalParams

                        ValueAnimator.ofInt(0, 255).apply {
                            duration = 180L

                            addUpdateListener { textAnimation ->
                                val alpha = textAnimation.animatedValue as Int
                                label.setTextColor((alpha shl 24) or 0x00FFFFFF)
                            }

                            doOnEnd {
                                if (sentWaitingSequenceActive && !poolActivityClosing) {
                                    label.setTextColor(0xFFFFFFFF.toInt())
                                    label.visibility = View.VISIBLE
                                    label.bringToFront()
                                    startWaitingDots(label)
                                }
                            }

                            start()
                        }
                    }

                    start()
                }
            }, 1000L)
        }
    }

    fun setCueDrawAmount(power: Float) {
        val frac = power / 2000
        // negative cue draw is used for the hit animation, don't show in the draw
        val tip = findViewById<ImageView>(R.id.cueTip)
        val width = findViewById<FrameLayout>(R.id.cueContainer).width
        tip.translationX = min(-frac * width, 0f)
        renderer.cueDraw = frac * 500
    }

    private fun shortestAngleDelta(to: Float, from: Float): Float {
        var diff = to - from

        if (diff > PI) {
            diff -= PI.toFloat() * 2f
        }

        if (diff < -PI) {
            diff += PI.toFloat() * 2f
        }

        return diff
    }

    private fun cancelCueInertia() {
        cueInertiaRunnable?.let { stateLabelHandler.removeCallbacks(it) }
        cueInertiaRunnable = null
        cueInertiaVelocity = 0f
        cueInertiaLastTimeMs = 0L
    }

    private fun startCueInertia() {
        if (abs(cueInertiaVelocity) < CUE_INERTIA_START_SPEED) {
            cueInertiaVelocity = 0f
            return
        }

        cueInertiaVelocity = cueInertiaVelocity.coerceIn(
            -CUE_INERTIA_MAX_SPEED, CUE_INERTIA_MAX_SPEED
        )

        cueInertiaLastTimeMs = SystemClock.uptimeMillis()

        val runnable = object : Runnable {
            override fun run() {
                if (poolActivityClosing || mode != PoolMode.Aiming || draggingCue || !::renderer.isInitialized) {
                    cancelCueInertia()
                    return
                }

                val now = SystemClock.uptimeMillis()
                val dt = ((now - cueInertiaLastTimeMs).coerceIn(1L, 50L)).toFloat() / 1000f
                cueInertiaLastTimeMs = now

                renderer.cueRot += cueInertiaVelocity * dt

                val damping = exp((-CUE_INERTIA_DECAY_PER_SECOND * dt).toDouble()).toFloat()
                cueInertiaVelocity *= damping

                if (abs(cueInertiaVelocity) < CUE_INERTIA_STOP_SPEED) {
                    cancelCueInertia()
                    return
                }

                stateLabelHandler.postDelayed(this, 16L)
            }
        }

        cueInertiaRunnable = runnable
        stateLabelHandler.postDelayed(runnable, 16L)
    }

    private fun openCuePopup() {
        runOnUiThread {
            if (cuePopupOpen || cuePopupAnimating || mode != PoolMode.Aiming) return@runOnUiThread

            val cueView = findViewById<FrameLayout>(R.id.cueView)
            val cueOverlay = findViewById<FrameLayout>(R.id.cueOverlay)
            val cuePopup = findViewById<FrameLayout>(R.id.cuePopup)

            cuePopupAnimating = true
            cuePopupOpen = true

            syncCueDots()

            val sourceLoc = IntArray(2)
            val overlayLoc = IntArray(2)
            cueView.getLocationOnScreen(sourceLoc)
            cueOverlay.getLocationOnScreen(overlayLoc)

            val startX = (sourceLoc[0] - overlayLoc[0]).toFloat()
            val startY = (sourceLoc[1] - overlayLoc[1]).toFloat()

            cueOverlay.visibility = View.VISIBLE
            cueOverlay.alpha = 0f
            cuePopup.visibility = View.VISIBLE

            cuePopup.post {
                val endX = (cueOverlay.width - cuePopup.width) / 2f
                val endY = (cueOverlay.height - cuePopup.height) / 2f

                val startScaleX = cueView.width.toFloat() / cuePopup.width.toFloat()
                val startScaleY = cueView.height.toFloat() / cuePopup.height.toFloat()

                cuePopup.x = startX
                cuePopup.y = startY
                cuePopup.scaleX = startScaleX
                cuePopup.scaleY = startScaleY

                cueOverlay.animate().alpha(1f).setDuration(180L).start()

                cuePopup.animate().x(endX).y(endY).scaleX(1f).scaleY(1f).setDuration(220L)
                    .withEndAction {
                        cuePopupAnimating = false
                    }.start()
            }
        }
    }

    private fun closeCuePopup(force: Boolean = false) {
        runOnUiThread {
            val cueView = findViewById<FrameLayout>(R.id.cueView)
            val cueOverlay = findViewById<FrameLayout>(R.id.cueOverlay)
            val cuePopup = findViewById<FrameLayout>(R.id.cuePopup)

            if (force) {
                cueOverlay.animate().cancel()
                cuePopup.animate().cancel()

                cueOverlay.alpha = 0f
                cueOverlay.visibility = View.GONE

                cuePopup.visibility = View.INVISIBLE
                cuePopup.scaleX = 1f
                cuePopup.scaleY = 1f

                cuePopupAnimating = false
                cuePopupOpen = false
                return@runOnUiThread
            }

            if (!cuePopupOpen || cuePopupAnimating) return@runOnUiThread

            cuePopupAnimating = true

            val sourceLoc = IntArray(2)
            val overlayLoc = IntArray(2)

            cueView.getLocationOnScreen(sourceLoc)
            cueOverlay.getLocationOnScreen(overlayLoc)

            val endX = (sourceLoc[0] - overlayLoc[0]).toFloat()
            val endY = (sourceLoc[1] - overlayLoc[1]).toFloat()

            val endScaleX = cueView.width.toFloat() / cuePopup.width.toFloat()
            val endScaleY = cueView.height.toFloat() / cuePopup.height.toFloat()

            cueOverlay.animate().alpha(0f).setDuration(180L).start()

            cuePopup.animate().x(endX).y(endY).scaleX(endScaleX).scaleY(endScaleY).setDuration(220L)
                .withEndAction {
                    cueOverlay.visibility = View.GONE
                    cuePopup.visibility = View.INVISIBLE
                    cuePopupAnimating = false
                    cuePopupOpen = false
                }.start()
        }
    }

    private fun updateCueSpinFromTouch(
        touchX: Float, touchY: Float, container: FrameLayout, dot: ImageView
    ) {
        if (dot.width == 0 || dot.height == 0 || container.width == 0 || container.height == 0) return

        val centerX = container.width / 2f
        val centerY = container.height / 2f
        val maxRadius =
            min(container.width, container.height) / 2f - max(dot.width, dot.height) / 2f

        var dx = touchX - centerX
        var dy = touchY - centerY

        val dist = sqrt(dx * dx + dy * dy)
        if (dist > maxRadius && dist > 0f) {
            val scale = maxRadius / dist
            dx *= scale
            dy *= scale
        }

        setSpinX = (dx / maxRadius) * 30f
        setSpinY = (dy / maxRadius) * 30f

        dot.translationX = dx
        dot.translationY = dy

        syncCueDots()
    }

    private fun syncCueDots() {
        val cueView = findViewById<FrameLayout>(R.id.cueView)
        val cueDot = findViewById<ImageView>(R.id.cueDot)
        val cuePopup = findViewById<FrameLayout>(R.id.cuePopup)
        val cuePopupDot = findViewById<ImageView>(R.id.cuePopupDot)

        fun applyDotPosition(container: FrameLayout, dot: ImageView) {
            if (container.width == 0 || container.height == 0 || dot.width == 0 || dot.height == 0) return

            val maxRadius =
                min(container.width, container.height) / 2f - max(dot.width, dot.height) / 2f
            val dx = (setSpinX / 30f) * maxRadius
            val dy = (setSpinY / 30f) * maxRadius

            dot.translationX = dx
            dot.translationY = dy
        }

        cueView.post {
            applyDotPosition(cueView, cueDot)
        }

        cuePopup.post {
            applyDotPosition(cuePopup, cuePopupDot)
        }
    }

    private fun resetCueSpin() {
        setSpinX = 0f
        setSpinY = 0f
        syncCueDots()
    }

    private fun setCueUiVisible(visible: Boolean) {
        runOnUiThread {
            val leftRail = findViewById<FrameLayout>(R.id.leftRail)
            val rightRail = findViewById<FrameLayout>(R.id.rightRail)
            val cueView = findViewById<FrameLayout>(R.id.cueView)
            val views = listOf<View>(leftRail, cueView)

            syncCueRailsToTable()

            rightRail.animate().cancel()
            rightRail.alpha = 1f
            rightRail.visibility = View.VISIBLE

            if (visible) {
                for (view in views) {
                    view.animate().cancel()
                    if (view.visibility != View.VISIBLE) {
                        view.alpha = 0f
                        view.visibility = View.VISIBLE
                    }
                    view.animate().alpha(1f).setDuration(180L).start()
                }
            } else {
                for (view in views) {
                    view.animate().cancel()
                    view.animate().alpha(0f).setDuration(180L).withEndAction {
                        if (view.alpha == 0f) {
                            view.visibility = View.INVISIBLE
                        }
                    }.start()
                }
                closeCuePopup(force = true)
            }

            updateNineBallBar()
        }
    }

    fun syncCueRailsToTable() {
        runOnUiThread {
            if (!::renderer.isInitialized) return@runOnUiThread

            val root = findViewById<FrameLayout>(R.id.poolRoot)
            val leftRail = findViewById<FrameLayout>(R.id.leftRail)
            val rightRail = findViewById<FrameLayout>(R.id.rightRail)

            if (root.width == 0 || leftRail.width == 0 || rightRail.width == 0) return@runOnUiThread

            @Suppress("DEPRECATION") val isRotated = when (windowManager.defaultDisplay.rotation) {
                android.view.Surface.ROTATION_90, android.view.Surface.ROTATION_180, android.view.Surface.ROTATION_270 -> true
                else -> false
            }

            if (!isRotated) {
                leftRail.translationX = 0f
                rightRail.translationX = 0f
                leftRail.translationY = 0f
                rightRail.translationY = 0f
                return@runOnUiThread
            }

            val bounds = renderer.tableScreenBounds
            if (bounds.width() <= 0f || bounds.height() <= 0f) return@runOnUiThread

            val powerSliderGap = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, 6f, resources.displayMetrics
            )

            val cueAimGap = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, 50f, resources.displayMetrics
            )

            val railOffsetY = 55f

            val leftTarget = max(0f, bounds.left - leftRail.width - powerSliderGap)
            val rightDefaultLeft = root.width - rightRail.width
            val rightTarget = min(rightDefaultLeft.toFloat(), bounds.right + cueAimGap)

            leftRail.translationX = leftTarget
            rightRail.translationX = rightTarget - rightDefaultLeft
            leftRail.translationY = railOffsetY
            rightRail.translationY = railOffsetY
        }
    }

    var setSpinX = 0f
    var setSpinY = 0f
    var draggingCue = false
    var calledPocket: List<Int> = listOf()

    var cuePopupOpen = false
    var cuePopupAnimating = false

    val holes = listOf(
        listOf(40, 40),
        listOf(744, 40),
        listOf(40, 400),
        listOf(744, 400),
        listOf(392, 28),
        listOf(392, 412),
    )

    val cueBallPlacementRadius = 21f
    val cueBallMinX = 40f + cueBallPlacementRadius
    val cueBallMaxX = 744f - cueBallPlacementRadius
    val cueBallMinY = 40f + cueBallPlacementRadius
    val cueBallMaxY = 400f - cueBallPlacementRadius
    val breakLineX = 221f

    private fun setupTurnRecoveryOverlay(
        parent: ViewGroup,
    ) {
        turnRecoveryOverlay =
            attachTurnRecoveryOverlay(
                parent = parent,
                onRetry = {
                    retryPendingPoolSend()
                },
            )
    }

    private fun hideTurnRecoveryRetry() {
        if (::turnRecoveryOverlay.isInitialized) {
            turnRecoveryOverlay.hideRetry()
        }
    }

    private fun showTurnRecoveryRetry() {
        recoveryRetryInFlight =
            false

        runOnUiThread {
            if (!isGameOver()) {
                hideStateLabel()
            }

            mode =
                PoolMode.Disabled

            setCueUiVisible(
                false,
            )

            if (::renderer.isInitialized) {
                renderer.setCueVisible(
                    false,
                )
            }

            if (::turnRecoveryOverlay.isInitialized) {
                turnRecoveryOverlay.showRetry()
            }
        }
    }

    private fun cancelPendingRecoveryCheck() {
        recoveryCheckRunnable?.let { runnable ->
            recoveryHandler.removeCallbacks(
                runnable,
            )
        }

        recoveryCheckRunnable =
            null
    }

    private fun schedulePendingSendCheck() {
        cancelPendingRecoveryCheck()

        val check =
            Runnable {
                recoveryCheckRunnable =
                    null

                recoveryRetryInFlight =
                    false

                val stillPending =
                    try {
                        gameSessionIPC?.hasPendingSend(
                            sessionId,
                        ) == true
                    } catch (throwable: Throwable) {
                        OpenPigeonLog.e(
                            "PoolRecovery",
                            "Unable to check pending Pool send",
                            throwable,
                        )

                        true
                    }

                if (stillPending) {
                    OpenPigeonLog.w(
                        "PoolRecovery",
                        "Automatic send was not confirmed; enabling manual SEND GAME",
                    )

                    showTurnRecoveryRetry()
                } else {
                    hideTurnRecoveryRetry()
                }
            }

        recoveryCheckRunnable =
            check

        recoveryHandler.postDelayed(
            check,
            8000L,
        )
    }

    private fun retryPendingPoolSend() {
        if (recoveryRetryInFlight) {
            return
        }

        val ipc =
            gameSessionIPC

        if (
            ipc == null ||
            sessionId.isBlank()
        ) {
            showTurnRecoveryRetry()
            return
        }

        cancelPendingRecoveryCheck()

        recoveryRetryInFlight =
            true

        hideTurnRecoveryRetry()

        if (!isGameOver()) {
            showSendingLabelImmediately()
        }

        val dispatched =
            ipc.retryPendingSend(
                sessionId,
            ) {
                runOnUiThread {
                    recoveryRetryInFlight =
                        false

                    cancelPendingRecoveryCheck()

                    hideTurnRecoveryRetry()

                    if (isGameOver()) {
                        showGameOverLabel()
                    } else {
                        playSentThenWaitingAnimation()
                    }
                }
            }

        if (!dispatched) {
            recoveryRetryInFlight =
                false

            showTurnRecoveryRetry()

            return
        }

        schedulePendingSendCheck()
    }
    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestWindowFeature(Window.FEATURE_NO_TITLE)
        supportActionBar?.hide()

        table = createPoolTable()

        enableEdgeToEdge()
        setContentView(R.layout.activity_pool)
        findViewById<FrameLayout>(R.id.poolRoot).apply {
            clipChildren = false
            clipToPadding = false
        }
        val contentRoot = findViewById<FrameLayout>(android.R.id.content)
        ViewCompat.setOnApplyWindowInsetsListener(contentRoot) { _, insets ->
            insets
        }

        setupTurnRecoveryOverlay(
            contentRoot,
        )

        applyStateLabelBackground(findViewById(R.id.state_label))
        gameAvatarAnchor = findViewById(
            R.id.gameAvatarAnchor,
        )

        oppAvatarAnchor = findViewById(
            R.id.oppAvatarAnchor,
        )

        val existingMenuButton = findViewById<ImageButton>(
            R.id.settingsButton,
        )

        findViewById<ImageButton>(
            R.id.rulesButton,
        ).visibility = View.GONE

        gameMenu = GameMenuController(
            activity = this,
            rootFrame = contentRoot,
            gameId = "pool",
            rulesTitle = currentPoolRulesTitle(),
            rulesSections = currentPoolRulesSections(),
            musicAssetPath = currentMusicTrack(),
            placement = GameMenuPlacement.BOTTOM_END,
            existingButton = existingMenuButton,
            onDarkModeChanged = ::applyDarkModeVisual,
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

        gameAvatarAnchor.post {
            updatePoolYouLabelLayer()
        }

        avatarWinBurstController = AvatarWinBurstController(
            root = findViewById(
                R.id.poolRoot,
            ),
            localAnchor = gameAvatarAnchor,
            opponentAnchor = oppAvatarAnchor,
        )

        updatePoolYouLabelLayer()

        val cueView = findViewById<FrameLayout>(R.id.cueView)
        val cueOverlay = findViewById<FrameLayout>(R.id.cueOverlay)
        val cuePopup = findViewById<FrameLayout>(R.id.cuePopup)
        val cuePopupDot = findViewById<ImageView>(R.id.cuePopupDot)

        cueView.setOnClickListener {
            if (spectatorMode) {
                return@setOnClickListener
            }

            openCuePopup()
        }

        cueOverlay.setOnClickListener {
            closeCuePopup()
        }

        cuePopup.setOnClickListener {
            // absorb inside clicks so overlay does not close
        }

        cuePopup.setOnTouchListener { _, event ->
            if (spectatorMode) {
                return@setOnTouchListener true
            }

            if (!cuePopupOpen || mode != PoolMode.Aiming) {
                return@setOnTouchListener true
            }

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE, MotionEvent.ACTION_UP -> {
                    updateCueSpinFromTouch(event.x, event.y, cuePopup, cuePopupDot)
                }
            }

            true
        }

        val skipReplayButton = findViewById<ImageButton>(R.id.skip_replay)

        try {
            val normal = assets.open("global/next.png").use { BitmapFactory.decodeStream(it) }
            val pressed =
                assets.open("global/next_pressed.png").use { BitmapFactory.decodeStream(it) }

            skipReplayButton.setImageBitmap(normal)
            skipReplayButton.setBackgroundColor(Color.TRANSPARENT)
            skipReplayButton.scaleType = ImageView.ScaleType.FIT_CENTER

            skipReplayButton.setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        skipReplayButton.setImageBitmap(pressed)
                        true
                    }

                    MotionEvent.ACTION_UP -> {
                        skipReplayButton.setImageBitmap(normal)
                        synchronized(this) {
                            replayWasSkipped = true
                            skipReplayRequested = true
                            finishReplay()
                        }
                        true
                    }

                    MotionEvent.ACTION_CANCEL -> {
                        skipReplayButton.setImageBitmap(normal)
                        true
                    }

                    else -> true
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        val container = findViewById<FrameLayout>(R.id.cueContainer)
        container.setOnTouchListener { _, event ->
            if (spectatorMode) {
                return@setOnTouchListener true
            }

            if (mode != PoolMode.Aiming) {
                return@setOnTouchListener true
            }

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    touchDownCueX = event.x
                    lastCueHapticStep = 0
                }

                MotionEvent.ACTION_MOVE -> {
                    val power = -min(event.x - touchDownCueX, 0.0f) / container.width * 2000
                    setCueDrawAmount(power)

                    val stepSize = 60f
                    val currentStep = floor(power / stepSize).toInt()
                    if (currentStep > lastCueHapticStep) {
                        vibrateCueTick()
                        lastCueHapticStep = currentStep
                    } else if (currentStep < lastCueHapticStep) {
                        vibrateCueTick()
                        lastCueHapticStep = currentStep
                    }
                }

                MotionEvent.ACTION_UP -> {
                    lastCueHapticStep = -1
                    disableSend = false
                    val power = -min(event.x - touchDownCueX, 0.0f) / container.width * 2000
                    if (power < 100) {
                        setCueDrawAmount(0f)
                        return@setOnTouchListener true
                    }
                    // snap back and hit
                    val hit = BallHit(renderer.cueRot, power, setSpinX, setSpinY, iAmStripes)
                    lastShotStartBalls = exportBalls(false)
                    lastShotStartIsFirst = isFirst
                    outgoingReplayHits.add(hit)
                    savePoolTurnProgress("shot", lastShotStartBalls)
                    animateShoot(power, hit)
                }

                MotionEvent.ACTION_CANCEL -> {
                    lastCueHapticStep = -1
                }
            }
            true
        }


        val view = findViewById<SurfaceView>(R.id.surfaceView)
        renderer = PoolRenderer(view.holder, this)

        view.post {
            renderer.transform
            syncCueRailsToTable()
        }

        view.setOnTouchListener { _, event ->
            if (spectatorMode) {
                return@setOnTouchListener true
            }

            val inverted = Matrix()
            renderer.transform.invert(inverted)

            val points = floatArrayOf(event.x, event.y)
            inverted.mapPoints(points)
            if (call8Ball) {
                val clickedHole = holes.find {
                    val distX = points[0] - it[0]
                    val distY = points[1] - it[1]
                    val dist = sqrt(distX * distX + distY * distY)
                    dist < 20
                }
                if (clickedHole == null) return@setOnTouchListener true
                call8Ball = false
                calledPocket = clickedHole

                val label = findViewById<TextView>(R.id.state_label)
                label.visibility = View.GONE

                mode = PoolMode.Aiming
                renderer.setCueVisible(true)
            } else if (mode == PoolMode.Aiming) {
                val cueBall = cueBall ?: return@setOnTouchListener true
                val origPoints = points.copyOf()

                // get distance between ball and finger
                points[0] -= cueBall.x
                points[1] -= cueBall.y

                val position = -atan2(points[0], points[1])

                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        cancelCueInertia()

                        cueDragLastTimeMs = SystemClock.uptimeMillis()
                        cueInertiaVelocity = 0f
                        lastAngle = position

                        if (scratch && abs(points[0]) < 20 && abs(points[1]) < 20) {
                            draggingCue = true
                        }
                    }

                    MotionEvent.ACTION_MOVE -> {
                        val now = SystemClock.uptimeMillis()

                        if (draggingCue) {
                            cueInertiaVelocity = 0f

                            val (moveX, moveY) = clampCueBallPosition(origPoints[0], origPoints[1])
                            for (ball in poolBalls) {
                                if (ball.number == 0) continue
                                val distX = ball.x - moveX
                                val distY = ball.y - moveY
                                val distance = sqrt(distX * distX + distY * distY)
                                if (distance < 20f) {
                                    return@setOnTouchListener true
                                }
                            }

                            synchronized(this) {
                                moveBall(table, 0, moveX, moveY, 0f)
                            }
                        } else {
                            val diff = shortestAngleDelta(position, lastAngle)
                            val appliedDiff = diff * CUE_ROTATION_DRAG_GAIN

                            renderer.cueRot += appliedDiff

                            val dt = ((now - cueDragLastTimeMs).coerceIn(1L, 50L)).toFloat() / 1000f
                            val instantVelocity = (appliedDiff / dt).coerceIn(
                                -CUE_INERTIA_MAX_SPEED, CUE_INERTIA_MAX_SPEED
                            )

                            cueInertiaVelocity =
                                cueInertiaVelocity * CUE_INERTIA_SMOOTHING + instantVelocity * (1f - CUE_INERTIA_SMOOTHING)
                        }

                        cueDragLastTimeMs = now
                        lastAngle = position
                    }

                    MotionEvent.ACTION_UP -> {
                        val wasDraggingCueBall = draggingCue
                        draggingCue = false

                        if (wasDraggingCueBall) {
                            cancelCueInertia()
                        } else {
                            startCueInertia()
                        }

                        lastAngle = position
                    }

                    MotionEvent.ACTION_CANCEL -> {
                        draggingCue = false
                        cancelCueInertia()
                        lastAngle = position
                    }
                }
                // this is our direction vector
                OpenPigeonLog.i("Point", "${points[0]} ${points[1]}")
            }
            true
        }

        findViewById<FrameLayout>(R.id.cueView).post {
            syncCueDots()
        }

        sessionId = intent.getStringExtra("SESSION")!!

        GameSessionIPC(
            applicationContext,
        ) { ipc ->
            gameSessionIPC =
                ipc

            val currentMessage =
                ipc.getCurrentMessage(
                    sessionId,
                )

            if (currentMessage.isEmpty()) {
                OpenPigeonLog.e(
                    "openpigeon-${baseGame.getName()}",
                    "$sessionId does not exist!",
                )

                finish()
                return@GameSessionIPC
            }

            logGameOpened(
                currentMessage,
            )

            ipc.lockMsgHandle(
                sessionId,
            )

            ipc.setSuppressNotifications(
                sessionId,
                true,
            )

            ipc.onMessageUpdated(sessionId) { callbackMessage ->
                synchronized(this) {
                    OpenPigeonLog.i("PoolMsg", "Live update num=${callbackMessage["num"]} sender=${callbackMessage["sender"]} replayLen=${callbackMessage["replay"]?.length ?: 0}")
                    handleMessage(callbackMessage)

                    val stillPending = try {
                        ipc.hasPendingSend(sessionId)
                    } catch (throwable: Throwable) {
                        OpenPigeonLog.e("PoolRecovery", "Unable to check pending Pool send", throwable)
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

            restorePoolRecovery(
                currentMessage,
            )
        }
    }

    override fun onDestroy() {
        poolActivityClosing =
            true

        cancelPendingRecoveryCheck()

        recoveryHandler.removeCallbacksAndMessages(
            null,
        )

        cancelCueInertia()

        disableSend =
            true

        skipReplayRequested =
            true

        mode =
            PoolMode.Disabled

        stopStateLabelAnimation()

        stopNineBallBarRefresh()

        cancelAllShots()

        cancelAllShots = {}

        if (::renderer.isInitialized) {
            renderer.running =
                false
        }

        if (::turnRecoveryOverlay.isInitialized) {
            turnRecoveryOverlay.destroy()
        }

        if (::avatarWinBurstController.isInitialized) {
            avatarWinBurstController.destroy()
        }

        if (::gameMenu.isInitialized) {
            gameMenu.destroy()
        }

        OpenPigeonLog.i(
            "Table",
            "Destroying",
        )

        synchronized(this) {
            if (table != 0L) {
                val oldTable =
                    table

                table =
                    0L

                destroyPoolTable(
                    oldTable,
                )
            }
        }

        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()

        if (::gameMenu.isInitialized) {
            gameMenu.onResume()
        }

        val ipc = gameSessionIPC

        if (ipc != null) {
            ipc.setSuppressNotifications(
                sessionId,
                true,
            )

            if (replayWasSkipped) {
                replayWasSkipped = false

                val currentMessage = ipc.getCurrentMessage(
                    sessionId,
                )

                if (currentMessage.isNotEmpty()) {
                    synchronized(this) {
                        handleMessage(
                            currentMessage,
                        )
                    }
                }
            }
        } else {
            OpenPigeonLog.w(
                "openpigeon-${baseGame.getName()}",
                "onResume called before gameSessionIPC was initialized!",
            )
        }

        if (spectatorMode) {
            restoreSpectatorAvatarsAfterSettingsOpen()
        }
    }


    override fun onPause() {
        if (::gameMenu.isInitialized) {
            gameMenu.onPause()
        }

        gameSessionIPC?.setSuppressNotifications(
            sessionId,
            false,
        )

        super.onPause()
    }

    private fun currentPoolRulesTitle(): String {
        return when {
            isNineBall -> {
                "9 Ball Rules"
            }

            isEightBallPlus -> {
                "8 Ball+ Rules"
            }

            else -> {
                "8 Ball Rules"
            }
        }
    }


    private fun currentPoolRulesSections(): List<RulesPopup.Section> {
        return when {
            isNineBall -> {
                listOf(
                    RulesPopup.Section(
                        "Objective",
                        "Pocket the 9-ball legally to win.",
                    ),
                    RulesPopup.Section(
                        "Ball Order",
                        "• Balls are numbered 1–9.\n" + "• You must always hit the lowest-numbered ball on the table first.\n" + "• Other balls may be pocketed after the lowest ball is contacted.",
                    ),
                    RulesPopup.Section(
                        "How to Play",
                        "• Aim the cue by rotating it around the cue ball.\n" + "• Pull back the cue strip on the left to set your power.\n" + "• Tap the cue dial on the right to set spin.\n" + "• Release to shoot.",
                    ),
                    RulesPopup.Section(
                        "Fouls (Scratch)",
                        "• Sinking the cue ball.\n" + "• Not hitting any ball.\n" + "• Hitting a ball other than the lowest-numbered ball first.\n" + "On a foul, your opponent gets cue ball placement.",
                    ),
                    RulesPopup.Section(
                        "Winning",
                        "Legally pocket the 9-ball to win. Pocketing the 9-ball on a foul does not win the game.",
                    ),
                )
            }

            isEightBallPlus -> {
                listOf(
                    RulesPopup.Section(
                        "Objective",
                        "Be the first player to sink all your group of balls, then pocket the 8-ball to win.",
                    ),
                    RulesPopup.Section(
                        "8 Ball+ Setup",
                        "8 Ball+ uses normal 8 Ball rules, but the balls are randomized across the table instead of starting in a standard rack.",
                    ),
                    RulesPopup.Section(
                        "Ball Groups",
                        "• Solids: balls 1–7\n" + "• Stripes: balls 9–15\n" + "• Your group is decided by the first ball you legally pocket.",
                    ),
                    RulesPopup.Section(
                        "How to Play",
                        "• Aim the cue by rotating it around the cue ball.\n" + "• Pull back the cue strip on the left to set your power.\n" + "• Tap the cue dial on the right to set spin.\n" + "• Release to shoot.",
                    ),
                    RulesPopup.Section(
                        "Fouls (Scratch)",
                        "• Hitting the wrong group first.\n" + "• Sinking the cue ball.\n" + "• Not hitting any ball.\n" + "On a foul, your opponent gets cue ball placement.",
                    ),
                    RulesPopup.Section(
                        "Winning",
                        "Sink the 8-ball after clearing all your group balls. " + "Sinking the 8-ball early, or on a scratch, loses the game immediately.",
                    ),
                )
            }

            else -> {
                listOf(
                    RulesPopup.Section(
                        "Objective",
                        "Be the first player to sink all your group of balls, then pocket the 8-ball to win.",
                    ),
                    RulesPopup.Section(
                        "Ball Groups",
                        "• Solids: balls 1–7\n" + "• Stripes: balls 9–15\n" + "• Your group is decided by the first ball you legally pocket.",
                    ),
                    RulesPopup.Section(
                        "How to Play",
                        "• Aim the cue by rotating it around the cue ball.\n" + "• Pull back the cue strip on the left to set your power.\n" + "• Tap the cue dial on the right to set spin.\n" + "• Release to shoot.",
                    ),
                    RulesPopup.Section(
                        "Fouls (Scratch)",
                        "• Hitting the wrong group first.\n" + "• Sinking the cue ball.\n" + "• Not hitting any ball.\n" + "On a foul your opponent places the cue ball anywhere behind the break line.",
                    ),
                    RulesPopup.Section(
                        "Winning",
                        "Sink the 8-ball after clearing all your group balls. " + "Sinking the 8-ball early, or on a scratch, loses the game immediately.",
                    ),
                )
            }
        }
    }

    external fun createPoolTable(): Long
    external fun destroyPoolTable(table: Long)
    external fun makeBall(
        table: Long,
        x: Float,
        y: Float,
        rot: Float,
        density: Float,
        number: Int,
        shouldGoIn: Int,
        outputs: FloatBuffer
    )

    external fun hitBall(
        table: Long,
        number: Int,
        dir: Float,
        power: Float,
        spinX: Float,
        spinY: Float,
        first: Boolean
    )

    external fun moveBall(table: Long, number: Int, x: Float, y: Float, rot: Float)

    external fun clearBalls(table: Long)

    data class BallHit(
        val direction: Float,
        val power: Float,
        val spinX: Float,
        val spinY: Float,
        var wasStripes: Boolean?
    ) {
        fun hit(activity: PoolActivity) {
            if (activity.poolActivityClosing || activity.table == 0L) {
                OpenPigeonLog.w(
                    "PoolLifecycle",
                    "Skipping hitBall because activity is closing or table is destroyed"
                )
                return
            }

            if (!activity.replaying) activity.scratch = false

            activity.mode = PoolMode.Playing

            if (activity.isNineBall) {
                activity.startNineBallBarRefresh()
            }

            if (activity.poolTraceEnabled) {
                OpenPigeonLog.i(
                    "PoolShot",
                    "shot_start replaying=${activity.replaying} direction=$direction power=$power " + "spinX=$spinX spinY=$spinY wasStripes=$wasStripes first=${activity.isFirst} " + "tableBefore=${
                        activity.dumpPoolTable(activity.table)
                    }"
                )
            }
            if (activity.isNineBall) {
                activity.nineBallTargetAtShot = activity.lowestNineBallNumber() ?: 9
            }

            activity.markNativeShotStarted(this)
            activity.hitBall(
                activity.table, 0 /*white*/, direction, power, spinX, spinY, activity.isFirst
            )
            if (activity.poolTraceEnabled) {
                OpenPigeonLog.i(
                    "PoolShot",
                    "shot_after_hit tableAfter=${activity.dumpPoolTable(activity.table)}"
                )
            }
            activity.wasFirst = activity.isFirst
            activity.isFirst = false
        }
    }

    private fun winningPlayerFromWinner(
        rawWinner: String?
    ): Int? {
        val parts = rawWinner.orEmpty().split("|", limit = 2)

        if (parts.size != 2) return null

        val senderId = parts[0]
        val senderResult = parts[1].toIntOrNull()?.coerceIn(-1, 1) ?: return null

        if (senderResult == 0) {
            return 0
        }

        val senderPlayer = when (senderId) {
            uuid1 -> 1
            uuid2 -> 2
            else -> return null
        }

        return if (senderResult > 0) {
            senderPlayer
        } else {
            if (senderPlayer == 1) 2 else 1
        }
    }

    fun clampCueBallPosition(x: Float, y: Float): Pair<Float, Float> {
        val maxX = if (scratch && isFirst && !isEightBallPlus) breakLineX else cueBallMaxX
        val clampedX = min(maxX, max(cueBallMinX, x))
        val clampedY = min(cueBallMaxY, max(cueBallMinY, y))
        return Pair(clampedX, clampedY)
    }

    var replaying = false
    var isFirst = false
    var wasFirst = false
    var skipReplayRequested = false
    var replayWasSkipped = false
    var skipReplayFadeStarted = false

    private var nativeShotStartedAtMs = 0L
    private var nativeShotSeq = 0
    private var currentNativeShotDebug = ""

    var poolTraceEnabled = false

    private var poolVisualTraceLastDump = ""
    var poolVisualTraceEnabled = false
    private var poolVisualTraceEveryFrames = 6
    private var poolVisualTraceFrame = 0L

    private fun showSkipReplayButton(reason: String) {
        runOnUiThread {
            val controls = findViewById<LinearLayout>(R.id.controls)
            val skipBtn = findViewById<ImageButton>(R.id.skip_replay)

            controls.visibility = View.VISIBLE
            controls.bringToFront()
            controls.requestLayout()

            skipBtn.animate().cancel()
            skipBtn.clearAnimation()
            skipBtn.alpha = 1f
            skipBtn.visibility = View.VISIBLE
            skipBtn.isEnabled = true
            skipBtn.isClickable = true
            skipBtn.bringToFront()
            skipBtn.requestLayout()

            fun logWhenMeasured(attempt: Int) {
                skipBtn.bringToFront()

                val loc = IntArray(2)
                skipBtn.getLocationOnScreen(loc)

                OpenPigeonLog.i(
                    "PoolReplayUi",
                    "skip_show reason=$reason attempt=$attempt replaying=$replaying requested=$skipReplayRequested " + "visibility=${skipBtn.visibility} alpha=${skipBtn.alpha} " + "x=${loc[0]} y=${loc[1]} w=${skipBtn.width} h=${skipBtn.height} " + "parent=${skipBtn.parent?.javaClass?.simpleName}"
                )

                if ((skipBtn.width == 0 || skipBtn.height == 0) && attempt < 6) {
                    controls.requestLayout()
                    skipBtn.requestLayout()
                    skipBtn.postDelayed({ logWhenMeasured(attempt + 1) }, 16L)
                }
            }

            skipBtn.post {
                logWhenMeasured(0)
            }
        }
    }

    private fun hideSkipReplayButton(reason: String) {
        runOnUiThread {
            val skipBtn = findViewById<ImageButton>(R.id.skip_replay)

            skipBtn.animate().cancel()
            skipBtn.visibility = View.GONE
            skipBtn.alpha = 1f

            OpenPigeonLog.i(
                "PoolReplayUi",
                "skip_hide reason=$reason replaying=$replaying requested=$skipReplayRequested"
            )
        }
    }

    fun animateShoot(power: Float, hit: BallHit) {
        var cancelled = false
        val animator = ValueAnimator.ofFloat(power, -100f)
        animator.duration = 100L
        animator.addUpdateListener { animation ->
            setCueDrawAmount(animation.animatedValue as Float)
        }
        animator.doOnEnd {
            synchronized(this) {
                if (cancelled || skipReplayRequested || poolActivityClosing || table == 0L) return@synchronized
                val cueBall = cueBall ?: return@synchronized
                renderer.cuePos = floatArrayOf(cueBall.x, cueBall.y)
                if (scratch && !replaying) {
                    finalBalls = exportBalls(false)
                    scratch = false
                }
                poolBalls.retainAll { !it.sunk }
                hit.hit(this)
                val clearHandler = Handler(mainLooper)
                clearHandler.postDelayed({
                    renderer.setCueVisible(false)
                    setCueDrawAmount(0f)
                    resetCueSpin()
                    closeCuePopup()
                    cancelAllShots = {}
                }, 300)
                cancelAllShots = {
                    clearHandler.removeCallbacksAndMessages(null)
                }
            }
        }
        animator.start()
        cancelAllShots = {
            cancelled = true
            animator.cancel()
        }
    }

    var cancelAllShots: () -> Unit = { }
    fun playNextReplay() {
        if (restoringTurnRecovery || poolActivityClosing || table == 0L || skipReplayRequested || replayHits.isEmpty()) {
            return
        }
        mode = PoolMode.ReplayAiming
        if (!skipReplayFadeStarted) {
            skipReplayFadeStarted = true
            showSkipReplayButton("playNextReplay_start")
        }
        renderer.cueRot = replayHits[0].direction
        runOnUiThread { renderer.setCueVisible(true) }
        val handler = Handler(mainLooper)
        handler.postDelayed({
            if (poolActivityClosing || table == 0L || skipReplayRequested || replayHits.isEmpty()) return@postDelayed
            val animator = ValueAnimator.ofFloat(0f, replayHits[0].power)
            animator.duration = 300L
            animator.addUpdateListener { animation -> setCueDrawAmount(animation.animatedValue as Float) }
            animator.doOnEnd {
                if (poolActivityClosing || table == 0L || skipReplayRequested || replayHits.isEmpty()) return@doOnEnd
                val hit = replayHits.removeAt(0)
                animateShoot(hit.power, hit)
            }
            animator.start()
            cancelAllShots = {
                animator.cancel()
            }
        }, 500)
        cancelAllShots = {
            handler.removeCallbacksAndMessages(null)
        }
    }

    fun markNativeShotStarted(hit: BallHit) {
        nativeShotStartedAtMs = SystemClock.uptimeMillis()
        nativeShotSeq += 1

        currentNativeShotDebug =
            "seq=$nativeShotSeq replaying=$replaying d=${hit.direction} p=${hit.power} spinX=${hit.spinX} spinY=${hit.spinY} finalBallsLen=${finalBalls.length}"

        OpenPigeonLog.i(
            "PoolReplay",
            "native_shot_started $currentNativeShotDebug replayHitsLeft=${replayHits.size}"
        )
    }

    fun clearNativeShotWatchdog() {
        nativeShotStartedAtMs = 0L
        currentNativeShotDebug = ""
    }

    fun handleNativeStillMoving() {
        if (!replaying) return
        if (mode != PoolMode.Playing) return

        val startedAt = nativeShotStartedAtMs
        if (startedAt <= 0L) return

        val elapsed = SystemClock.uptimeMillis() - startedAt
        if (elapsed < POOL_REPLAY_SHOT_TIMEOUT_MS) return

        OpenPigeonLog.e(
            "PoolReplay",
            "watchdog_finishing_replay elapsedMs=$elapsed $currentNativeShotDebug finalBallsLen=${finalBalls.length}"
        )

        finishReplay()
    }

    var scratch = false

    fun lowestNineBallNumber(): Int? {
        return poolBalls.filter { !it.sunk && it.number in 1..9 }.minOfOrNull { it.number }
    }

    private fun alignSpectatorAvatarAnchors() {
        if (!spectatorMode) return

        runOnUiThread {
            AvatarView.configureTallAnchor(gameAvatarAnchor)
            AvatarView.configureTallAnchor(oppAvatarAnchor)
            updatePoolYouLabelLayer()
        }
    }

    fun tableIsScratch(): Boolean {
        val cueBall = cueBall ?: return false
        val cueBallScratch = cueBall.sunk || cueBall.inPocket

        if (isNineBall) {
            val result =
                cueBallScratch || !cueBall.hitBall || cueBall.ballHit != nineBallTargetAtShot

            this.scratch = result

            OpenPigeonLog.i(
                "POOL9_DEBUG",
                "SCRATCH_CHECK cueBall.sunk=${cueBall.sunk} cueBall.inPocket=${cueBall.inPocket} " + "hitBall=${cueBall.hitBall} ballHit=${cueBall.ballHit} target=$nineBallTargetAtShot scratch=$result"
            )

            return result
        }

        var result = !cueBall.hitBall || cueBallScratch

        if (cueBall.ballHit != -1) {
            val ballHit = poolBalls.find { it.number == cueBall.ballHit }
            if (ballHit == null) {
                this.scratch = result
                return result
            }
            val stripes = iAmStripes
            val hasMoreBalls = stripes == null || poolBalls.count {
                !it.sunk && ((stripes && it.isStripe) || (!stripes && it.isSolid))
            } != 0

            if (ballHit.number == 8 && !hasMoreBalls) {
                if (!cueBallScratch) {
                    result = false
                }
            } else if (iAmStripes != null && ((!ballHit.isSolid && !iAmStripes!!) || (!ballHit.isStripe && iAmStripes!!))) {
                result = true
            }
        }

        this.scratch = result

        OpenPigeonLog.i(
            "POOL_DEBUG",
            "SCRATCH_CHECK cueBall.sunk=${cueBall.sunk} cueBall.inPocket=${cueBall.inPocket} " + "blackBall.sunk=${poolBalls.find { it.number == 8 }?.sunk} " + "ballHit=${cueBall.ballHit} scratch=$result"
        )

        return result
    }

    var disableSend = false

    fun finishReplay() {
        disableSend = true
        mode = PoolMode.Disabled
        setCueUiVisible(false)
        if (isNineBall) {
            stopNineBallBarRefresh()
        }

        cancelAllShots()
        cancelAllShots = {}

        setCueDrawAmount(0.0f)
        closeCuePopup()

        if (!restoringLastShotReplay) outgoingReplayHits.clear()
        replayHits.clear()

        runOnUiThread {
            val controls = findViewById<LinearLayout>(R.id.controls)
            controls.visibility = View.VISIBLE
        }
        hideSkipReplayButton("finishReplay")
        replaying = false
        skipReplayRequested = false
        skipReplayFadeStarted = false

        OpenPigeonLog.i("Pool", "Scratch $scratch")

        clearNativeShotWatchdog()

        traceVisualRoll(
            reason = "finishReplay_before_snap", force = true
        )

        if (poolVisualTraceEnabled) {
            OpenPigeonLog.i(
                "PoolVisualRoll",
                "finishReplay_finalBalls_before_snap len=${finalBalls.length} finalBalls=$finalBalls"
            )
        }

        if (finalBalls.isBlank()) {
            OpenPigeonLog.e(
                "PoolReplay",
                "finishReplay_missing_finalBalls; falling back to current exported state"
            )
            finalBalls = exportBalls(scratch)
        }
        if (poolTraceEnabled) {
            OpenPigeonLog.i(
                "PoolReplay", "finishReplay_native_before_snap table=${dumpPoolTable(table)}"
            )

            OpenPigeonLog.i(
                "PoolReplay",
                "finishReplay_android_buffers_before_snap balls=${dumpPoolBallBuffers()}"
            )
        }

        clearBalls(table)
        poolBalls = arrayListOf()
        cueBall = null

        if (poolTraceEnabled) {
            OpenPigeonLog.i(
                "PoolReplay",
                "finishReplay_authoritative_final finalBallsLen=${finalBalls.length} finalBalls=$finalBalls"
            )
        }

        buildBalls(finalBalls, null)

        if (restoringLastShotReplay) {
            finalBalls = recoveryTurnStartBalls
            recoveryTurnStartBalls = ""
            restoringLastShotReplay = false
        }

        traceVisualRoll(
            reason = "finishReplay_after_buildBalls", force = true
        )

        poolTraceEnabled = false
        poolVisualTraceEnabled = false
        poolVisualTraceFrame = 0L
        poolVisualTraceLastDump = ""

        if (table != 0L) {
            setPoolDebugTrace(table, false, 0)
        }

        updateNineBallBar()

        if (pendingWinLossState.isNotBlank()) {
            markGameOver(pendingWinLossState)
            return
        }

        if (spectatorMode) {
            mode = PoolMode.Disabled
            applySpectatorReadOnlyUi()
            return
        }

        if (isNineBall) {
            updateNineBallBar()
            mode = PoolMode.Aiming
            runOnUiThread {
                setCueUiVisible(true)
                renderer.setCueVisible(true)
                hideStateLabel()
            }
            return
        }

        val stripes = iAmStripes
        val hasMoreBalls =
            stripes == null || poolBalls.count { !it.sunk && ((stripes && it.isStripe) || (!stripes && it.isSolid)) } != 0
        if (!hasMoreBalls) {
            call8Ball = true
            mode = PoolMode.Aiming
            runOnUiThread {
                setCueUiVisible(true)
                renderer.setCueVisible(true)
                val label = findViewById<TextView>(R.id.state_label)
                label.visibility = View.VISIBLE
                stopStateLabelAnimation()
                label.text = TEXT_CHOOSE_POCKET
            }
            return
        }

        mode = PoolMode.Aiming
        runOnUiThread {
            setCueUiVisible(true)
            renderer.setCueVisible(true)
        }
    }

    var call8Ball = false

    fun handleFinishPlay() {
        if (spectatorMode && !replaying) {
            disableSend = true
            mode = PoolMode.Disabled
            applySpectatorReadOnlyUi()
            return
        }

        traceVisualRoll(
            reason = "handleFinishPlay_entry", force = true
        )

        if (skipReplayRequested) return

        clearNativeShotWatchdog()
        cancelAllShots()
        cancelAllShots = {}

        if (replayHits.isNotEmpty()) {
            playNextReplay()
        } else if (replaying) {
            finishReplay()
        } else {
            if (disableSend) {
                OpenPigeonLog.i(
                    "PoolSpectator", "handleFinishPlay blocked local send because disableSend=true"
                )
                return
            }

            val scratch = tableIsScratch()
            val cueBall = cueBall ?: return

            mode = PoolMode.Disabled
            closeCuePopup()

            var winState: Boolean? = null

            if (isNineBall) {
                val sunkNumberedBalls =
                    poolBalls.filter { it.sunk && it.number in 1..9 }.sortedBy { it.sunkOrder }

                val nineBallSunk = sunkNumberedBalls.any { it.number == 9 }

                OpenPigeonLog.i(
                    "POOL9_DEBUG",
                    "FINAL_STATE cueBall.sunk=${cueBall.sunk} nineBallSunk=$nineBallSunk scratch=$scratch target=$nineBallTargetAtShot sunk=${sunkNumberedBalls.map { it.number }}"
                )

                if (nineBallSunk && !scratch) {
                    winState = true
                }

                if (!scratch && winState == null && sunkNumberedBalls.isNotEmpty()) {
                    updateNineBallBar()

                    savePoolTurnProgress(
                        phase = "aim",
                    )

                    mode = PoolMode.Aiming
                    runOnUiThread {
                        setCueUiVisible(true)
                        renderer.setCueVisible(true)
                    }
                    return
                }
            } else {
                val blackBall = poolBalls.find { it.number == 8 }
                val blackBallSunk = blackBall == null || blackBall.sunk

                OpenPigeonLog.i(
                    "POOL_DEBUG",
                    "FINAL_STATE cueBall.sunk=${cueBall.sunk} blackBall.sunk=$blackBallSunk scratch=$scratch wasFirst=$wasFirst"
                )

                if (blackBallSunk) {
                    winState =
                        !(wasFirst || iAmStripes == null || blackBall == null || poolBalls.count { !it.sunk && ((iAmStripes!! && it.isStripe) || (!iAmStripes!! && it.isSolid)) } != 0 || cueBall.sunk || calledPocket.isEmpty() || blackBall.holeX != calledPocket[0].toFloat() || blackBall.holeY != calledPocket[1].toFloat())
                }

                if (!scratch && winState == null) {
                    val sunkPlayableBalls =
                        poolBalls.filter { it.sunk && (it.isStripe || it.isSolid) }
                            .sortedBy { it.sunkOrder }

                    val madeTurnBall = if (iAmStripes == null) {
                        sunkPlayableBalls.isNotEmpty()
                    } else {
                        sunkPlayableBalls.any { (iAmStripes!! && it.isStripe) || (!iAmStripes!! && it.isSolid) }
                    }

                    if (madeTurnBall) {
                        if (iAmStripes == null && !wasFirst) {
                            iAmStripes = sunkPlayableBalls.first().isStripe
                            updateBallTypeUi()
                        }

                        val stripes = iAmStripes
                        val hasMoreBalls =
                            stripes == null || poolBalls.count { !it.sunk && ((stripes && it.isStripe) || (!stripes && it.isSolid)) } != 0
                        if (!hasMoreBalls) {
                            call8Ball =
                                true

                            savePoolTurnProgress(
                                phase = "aim",
                            )

                            mode = PoolMode.Aiming
                            runOnUiThread {
                                val label = findViewById<TextView>(R.id.state_label)
                                label.visibility = View.VISIBLE
                                label.text = TEXT_CHOOSE_POCKET
                            }
                            return
                        }

                        savePoolTurnProgress(
                            phase = "aim",
                        )

                        mode = PoolMode.Aiming
                        runOnUiThread {
                            setCueUiVisible(true)
                            renderer.setCueVisible(true)
                        }
                        return
                    }
                }
            }

            // send replay
            OpenPigeonLog.i(
                "PoolReplay",
                "send_replay_start outgoingHits=${outgoingReplayHits.size} finalBallsLen=${finalBalls.length}"
            )

            var replays = outgoingReplayHits.mapIndexed { index, hit ->
                val wasStripes =
                    if (hit.wasStripes == null) 0 else if (hit.wasStripes!!) player else if (player == 1) 2 else 1
                val replay =
                    "&d:${hit.direction}&x:${hit.spinX}&y:${hit.spinY}&p:${hit.power}&s:$wasStripes"
                if (index == 0) {
                    "$replay&balls:$finalBalls"
                } else {
                    replay
                }
            }.joinToString("|")
            val shouldCenterScratch = scratch && winState == null

            replays += "|balls:${exportBalls(shouldCenterScratch)}&stripes:${if (iAmStripes == null) 0 else if (iAmStripes!!) player else if (player == 1) 2 else 1}"

            if (shouldCenterScratch) {
                replays += "&move:1"
            }

            if (winState != null) {
                replays += "&win:${if (winState) 1 else -1}"
                markGameOver(if (winState) "1" else "-1")
            }

            OpenPigeonLog.i(
                "PoolReplay", "send_replay replayLen=${replays.length} replay=$replays"
            )

            val ipc = gameSessionIPC ?: return
            val currentMessage = ipc.getCurrentMessage(sessionId)
            val myId = ipc.getSenderUUID(sessionId)
            val myAvatarKey = if (player == 1) "avatar1" else "avatar2"

            val currentNum =
                currentMessage["num"]?.toIntOrNull() ?: finalBalls.takeIf { it.isNotBlank() }
                    ?.let { 1 } ?: 1

            val msgUpdates = mapOf(
                "player" to if (currentMessage["player"] == "2") "1" else "2",
                "num" to (currentNum + 1).toString(),
                "sender" to myId,
                "replay" to replays,
                myAvatarKey to AvatarView.buildAvatarString(),
            ).toMutableMap()

            if (winState != null) {
                msgUpdates["winner"] = "$myId|${if (winState) "1" else "-1"}"
            }

            if (winState == null) {
                setCueUiVisible(
                    false,
                )

                showSendingLabelImmediately()
            } else {
                showGameOverLabel()
            }

            val dispatched =
                ipc.updateSession(
                    msgUpdates,
                    sessionId,
                ) {
                    OpenPigeonLog.i(
                        "openpigeon-${baseGame.getName()}",
                        "Game session updated",
                    )

                    runOnUiThread {
                        recoveryRetryInFlight =
                            false

                        cancelPendingRecoveryCheck()

                        hideTurnRecoveryRetry()

                        if (winState == null) {
                            playSentThenWaitingAnimation()
                        } else {
                            showGameOverLabel()
                        }
                    }
                }

            if (!dispatched) {
                OpenPigeonLog.w(
                    "PoolRecovery",
                    "Automatic Pool send failed immediately",
                )

                showTurnRecoveryRetry()
            } else {
                schedulePendingSendCheck()
            }
        }
    }

    var iAmStripes: Boolean? = null

    data class PoolBall(
        val number: Int,
        val data: FloatBuffer,
        val resources: Resources,
        val density: Float,
        var visualRotationX: Float = 0f,
        var visualRotationY: Float = 0f,
        var visualRotationZ: Float = 0f
    ) {
        companion object {
            val ballOrder = listOf(
                R.drawable.ball_16,
                R.drawable.ball_1,
                R.drawable.ball_2,
                R.drawable.ball_3,
                R.drawable.ball_4,
                R.drawable.ball_5,
                R.drawable.ball_6,
                R.drawable.ball_7,
                R.drawable.ball_8,
                R.drawable.ball_9,
                R.drawable.ball_10,
                R.drawable.ball_11,
                R.drawable.ball_12,
                R.drawable.ball_13,
                R.drawable.ball_14,
                R.drawable.ball_15,
            )

            private const val BALL_RADIUS = 10f
            private const val IOS_BALL_CANCEL_TABLE_ROTATION_DEGREES = -90f

            private const val IOS_SHADOW_OFFSET_X = -4.5f
            private const val IOS_SHADOW_OFFSET_Y = 0.0f
            private const val IOS_SHADOW_RADIUS = BALL_RADIUS
            private const val IOS_ROLL_LINEAR_VELOCITY_DIVISOR = -20f
            private const val IOS_ROLL_ANGULAR_VELOCITY_DIVISOR = 10f
            private const val IOS_ROLL_SMALL_ANGULAR_DAMPING_LIMIT = 3f
            private const val IOS_ROLL_SMALL_ANGULAR_DAMPING = 0.8f
            private const val IOS_MIN_ROLL_VECTOR_LENGTH = 0.000001f

            private const val SPHERE_RENDER_SIZE = 48
            private const val SPHERE_CENTER = (SPHERE_RENDER_SIZE - 1) * 0.5f
            private const val SPHERE_RADIUS = (SPHERE_RENDER_SIZE - 2) * 0.5f

            private const val SPHERE_RENDER_FAST_FRAME_STRIDE = 2
            private const val SPHERE_RENDER_FAST_LINEAR_SPEED = 90f
            private const val SPHERE_RENDER_FAST_ANGULAR_SPEED = 4f

            private val BALL_DRAW_RECT = RectF(
                -BALL_RADIUS, -BALL_RADIUS, BALL_RADIUS, BALL_RADIUS
            )

            private val GLOSS_RECT_1 = RectF(
                -8.0f, -8.5f, 2.0f, 1.5f
            )

            private val GLOSS_RECT_2 = RectF(
                -4.5f, -5.0f, 0.8f, 0.2f
            )

            private val ballPaint = Paint(
                Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG
            )

            private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0x80000000.toInt()
            }

            private val glossPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = RadialGradient(
                    -3.0f, -4.0f, 7.5f, intArrayOf(
                        0x99FFFFFF.toInt(), 0x44FFFFFF, 0x00FFFFFF
                    ), floatArrayOf(0.0f, 0.45f, 1.0f), Shader.TileMode.CLAMP
                )
            }

            private val glossPaint2 = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = RadialGradient(
                    -1.5f, -2.5f, 4.5f, intArrayOf(
                        0x55FFFFFF, 0x18FFFFFF, 0x00FFFFFF
                    ), floatArrayOf(0.0f, 0.55f, 1.0f), Shader.TileMode.CLAMP
                )
            }

            private val previewTextureCache = HashMap<Int, Triple<IntArray, Int, Int>>()
            private val previewBitmapCache = HashMap<Int, Bitmap>()

            private fun getPreviewTextureData(
                resources: Resources, number: Int
            ): Triple<IntArray, Int, Int> {
                previewTextureCache[number]?.let { return it }

                val decoded = BitmapFactory.decodeResource(
                    resources, ballOrder[number], BitmapFactory.Options().apply {
                        inScaled = false
                        inPreferredConfig = Bitmap.Config.ARGB_8888
                    }) ?: error("Unable to decode pool ball preview bitmap: number=$number")

                val bitmap = if (decoded.config == Bitmap.Config.ARGB_8888) {
                    decoded
                } else {
                    decoded.copy(Bitmap.Config.ARGB_8888, false)
                }

                val pixels = IntArray(bitmap.width * bitmap.height)
                bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)

                val data = Triple(pixels, bitmap.width, bitmap.height)
                previewTextureCache[number] = data
                return data
            }

            private fun previewSampleSource(
                sourcePixels: IntArray,
                sourceWidth: Int,
                sourceHeight: Int,
                uFloat: Float,
                vFloat: Float
            ): Int {
                var u = uFloat.toInt() % sourceWidth
                if (u < 0) u += sourceWidth

                val v = vFloat.toInt().coerceIn(0, sourceHeight - 1)

                return sourcePixels[v * sourceWidth + u]
            }

            private fun previewApplyShade(
                color: Int, normalX: Float, normalY: Float, normalZ: Float
            ): Int {
                val a = color ushr 24
                if (a == 0) return 0

                val r = (color shr 16) and 0xff
                val g = (color shr 8) and 0xff
                val b = color and 0xff

                val lightDot =
                    (normalX * -0.35f + normalY * -0.45f + normalZ * 0.90f).coerceIn(0f, 1f)

                val edgeShade = normalZ.coerceIn(0f, 1f)

                val shade = (0.48f + lightDot * 0.42f + edgeShade * 0.10f).coerceIn(0.35f, 1.05f)

                val rr = (r * shade).toInt().coerceIn(0, 255)
                val gg = (g * shade).toInt().coerceIn(0, 255)
                val bb = (b * shade).toInt().coerceIn(0, 255)

                return (a shl 24) or (rr shl 16) or (gg shl 8) or bb
            }

            fun previewBitmap(resources: Resources, number: Int): Bitmap {
                val safeNumber = number.coerceIn(0, ballOrder.lastIndex)

                previewBitmapCache[safeNumber]?.let { return it }

                val sourceData = getPreviewTextureData(resources, safeNumber)
                val sourcePixels = sourceData.first
                val sourceWidth = sourceData.second
                val sourceHeight = sourceData.third

                val output = createBitmap(SPHERE_RENDER_SIZE, SPHERE_RENDER_SIZE)
                val outputPixels = IntArray(SPHERE_RENDER_SIZE * SPHERE_RENDER_SIZE)

                val rx = 0.0
                val ry = PI / 2.0
                val rz = 0.0

                val cosX = cos(rx)
                val sinX = sin(rx)
                val cosY = cos(ry)
                val sinY = sin(ry)
                val cosZ = cos(rz)
                val sinZ = sin(rz)

                for (py in 0 until SPHERE_RENDER_SIZE) {
                    for (px in 0 until SPHERE_RENDER_SIZE) {
                        val index = py * SPHERE_RENDER_SIZE + px

                        val nx = (px - SPHERE_CENTER) / SPHERE_RADIUS
                        val ny = (py - SPHERE_CENTER) / SPHERE_RADIUS
                        val r2 = nx * nx + ny * ny

                        if (r2 > 1f) {
                            outputPixels[index] = 0x00000000
                            continue
                        }

                        val nz = sqrt(1f - r2)

                        var vx = nx.toDouble()
                        var vy = -ny.toDouble()
                        var vz = nz.toDouble()

                        run {
                            val tx = vx * cosZ - vy * sinZ
                            val ty = vx * sinZ + vy * cosZ
                            vx = tx
                            vy = ty
                        }

                        run {
                            val tx = vx * cosY + vz * sinY
                            val tz = -vx * sinY + vz * cosY
                            vx = tx
                            vz = tz
                        }

                        run {
                            val ty = vy * cosX - vz * sinX
                            val tz = vy * sinX + vz * cosX
                            vy = ty
                            vz = tz
                        }

                        val longitude = atan2(vx, vz)
                        val latitude = asin(vy.coerceIn(-1.0, 1.0))

                        val u = ((longitude / (PI * 2.0)) + 0.5) * sourceWidth
                        val v = (0.5 - (latitude / PI)) * sourceHeight

                        val sampled = previewSampleSource(
                            sourcePixels, sourceWidth, sourceHeight, u.toFloat(), v.toFloat()
                        )

                        outputPixels[index] = previewApplyShade(sampled, nx, ny, nz)
                    }
                }

                output.setPixels(
                    outputPixels,
                    0,
                    SPHERE_RENDER_SIZE,
                    0,
                    0,
                    SPHERE_RENDER_SIZE,
                    SPHERE_RENDER_SIZE
                )

                Canvas(output).apply {
                    withSave {

                        translate(SPHERE_CENTER, SPHERE_CENTER)

                        val previewScale = SPHERE_RENDER_SIZE / (BALL_RADIUS * 2f)
                        scale(previewScale, previewScale)

                        drawOval(
                            RectF(
                                -8.0f, -8.5f, 2.0f, 1.5f
                            ), glossPaint
                        )

                        drawOval(
                            RectF(
                                -4.5f, -5.0f, 0.8f, 0.2f
                            ), glossPaint2
                        )

                    }
                }

                previewBitmapCache[safeNumber] = output
                return output
            }
        }

        private val sourceBitmapCache = HashMap<Int, Bitmap>()
        private val sourcePixelsCache =
            HashMap<Int, Triple<IntArray, Int, Int>>() // pixels, width, height

        private fun getSourceData(resources: Resources, number: Int): Triple<IntArray, Int, Int> {
            sourcePixelsCache[number]?.let { return it }

            val bitmap = BitmapFactory.decodeResource(resources, ballOrder[number]).let { decoded ->
                if (decoded.config == Bitmap.Config.ARGB_8888) decoded
                else decoded.copy(Bitmap.Config.ARGB_8888, false)
            }
            sourceBitmapCache[number] = bitmap

            val pixels = IntArray(bitmap.width * bitmap.height)
            bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)

            val data = Triple(pixels, bitmap.width, bitmap.height)
            sourcePixelsCache[number] = data
            return data
        }

        private val sourceData = getSourceData(resources, number)
        private val sourceWidth = sourceData.second
        private val sourceHeight = sourceData.third
        private val sourcePixels = sourceData.first


        private val sphereBitmap = createBitmap(SPHERE_RENDER_SIZE, SPHERE_RENDER_SIZE)

        private val spherePixels = IntArray(SPHERE_RENDER_SIZE * SPHERE_RENDER_SIZE)

        private var sphereDirty = true
        private var sphereInvalidationFrame = 0
        private val shadowRect = RectF()

        private data class IosRollQuaternion(
            val w: Double, val x: Double, val y: Double, val z: Double
        )

        private fun iosRotationVectorToQuaternion(
            rotationX: Float, rotationY: Float, rotationZ: Float
        ): IosRollQuaternion {
            val x = rotationX.toDouble()
            val y = rotationY.toDouble()
            val z = rotationZ.toDouble()

            val magnitudeDegrees = sqrt(x * x + y * y + z * z)

            if (magnitudeDegrees <= 0.0000001) {
                return IosRollQuaternion(1.0, 0.0, 0.0, 0.0)
            }

            val halfAngleRadians = magnitudeDegrees * 0.5 * PI / 180.0
            val axisScale = sin(halfAngleRadians) / magnitudeDegrees

            return IosRollQuaternion(
                w = cos(halfAngleRadians), x = x * axisScale, y = y * axisScale, z = z * axisScale
            )
        }

        private fun iosMultiplyQuaternion(
            left: IosRollQuaternion, right: IosRollQuaternion
        ): IosRollQuaternion {
            return IosRollQuaternion(
                w = left.w * right.w - left.x * right.x - left.y * right.y - left.z * right.z,
                x = left.w * right.x + left.x * right.w + left.y * right.z - left.z * right.y,
                y = left.w * right.y - left.x * right.z + left.y * right.w + left.z * right.x,
                z = left.w * right.z + left.x * right.y - left.y * right.x + left.z * right.w
            )
        }

        private fun iosConjugateQuaternion(q: IosRollQuaternion): IosRollQuaternion {
            return IosRollQuaternion(
                w = q.w, x = -q.x, y = -q.y, z = -q.z
            )
        }

        private fun iosRotateVectorByQuaternion(
            qRaw: IosRollQuaternion, x: Double, y: Double, z: Double
        ): DoubleArray {
            val q = iosNormalizeQuaternion(qRaw)

            val rotated = iosMultiplyQuaternion(
                iosMultiplyQuaternion(
                    q, IosRollQuaternion(0.0, x, y, z)
                ), iosConjugateQuaternion(q)
            )

            return doubleArrayOf(rotated.x, rotated.y, rotated.z)
        }

        private fun iosNormalizeQuaternion(q: IosRollQuaternion): IosRollQuaternion {
            val len = sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)

            if (len <= 0.0000001) {
                return IosRollQuaternion(1.0, 0.0, 0.0, 0.0)
            }

            return IosRollQuaternion(
                w = q.w / len, x = q.x / len, y = q.y / len, z = q.z / len
            )
        }

        private fun iosQuaternionToRotationVector(qRaw: IosRollQuaternion): FloatArray {
            val q = iosNormalizeQuaternion(qRaw)

            val sinHalfLen = sqrt(q.x * q.x + q.y * q.y + q.z * q.z)

            if (sinHalfLen <= 0.0000001) {
                return floatArrayOf(0f, 0f, 0f)
            }

            val angleRadians = 2.0 * atan2(sinHalfLen, q.w)
            val angleDegrees = Math.toDegrees(angleRadians)
            val scale = angleDegrees / sinHalfLen

            return floatArrayOf(
                (q.x * scale).toFloat(), (q.y * scale).toFloat(), (q.z * scale).toFloat()
            )
        }

        private fun markSphereDirtyForCurrentMotion() {
            sphereInvalidationFrame += 1

            val linearSpeedSq = vx * vx + vy * vy

            val movingFast =
                linearSpeedSq > SPHERE_RENDER_FAST_LINEAR_SPEED * SPHERE_RENDER_FAST_LINEAR_SPEED || abs(
                    av
                ) > SPHERE_RENDER_FAST_ANGULAR_SPEED

            if (!movingFast || sphereInvalidationFrame == 1 || sphereInvalidationFrame % SPHERE_RENDER_FAST_FRAME_STRIDE == 0) {
                sphereDirty = true
            }
        }

        private fun applyIosRollingVector(
            deltaRotationX: Float, deltaRotationY: Float, deltaRotationZ: Float
        ) {
            val current = iosRotationVectorToQuaternion(
                visualRotationX, visualRotationY, visualRotationZ
            )

            val delta = iosRotationVectorToQuaternion(
                deltaRotationX, deltaRotationY, deltaRotationZ
            )

            val next = iosQuaternionToRotationVector(
                iosMultiplyQuaternion(current, delta)
            )

            visualRotationX = next[0]
            visualRotationY = next[1]
            visualRotationZ = next[2]
            markSphereDirtyForCurrentMotion()
        }

        val x: Float
            get() = data.get(0)

        val y: Float
            get() = data.get(1)

        val rot: Float
            get() = data.get(2)

        private fun optionalData(index: Int): Float {
            return if (data.capacity() > index) {
                data.get(index)
            } else {
                0f
            }
        }

        val vx: Float
            get() = optionalData(7)

        val vy: Float
            get() = optionalData(8)

        val av: Float
            get() = optionalData(9)

        val sunk: Boolean
            get() = data.get(3) != -1f

        val sunkOrder: Int
            get() = data.get(3).toInt()

        val hitBall: Boolean
            get() = data.get(4) != -1f

        val ballHit: Int
            get() = data.get(4).toInt()

        val isSolid: Boolean
            get() = number in 1..7

        val isStripe: Boolean
            get() = number in 9..15

        val holeX: Float
            get() = data.get(5)

        val holeY: Float
            get() = data.get(6)

        val inPocket: Boolean
            get() = holeX != -1f && holeY != -1f && !sunk

        fun exportVisualRotationString(): String {
            return String.format(
                Locale.US, "%.6f,%.6f,%.6f", visualRotationX, visualRotationY, visualRotationZ
            )
        }

        private fun updateVisualRoll() {
            if (data.capacity() <= 9) {
                return
            }

            var angularVelocity = av

            if (abs(angularVelocity) < IOS_ROLL_SMALL_ANGULAR_DAMPING_LIMIT) {
                angularVelocity *= IOS_ROLL_SMALL_ANGULAR_DAMPING
            }

            val deltaRotationX = vx / IOS_ROLL_LINEAR_VELOCITY_DIVISOR
            val deltaRotationY = vy / IOS_ROLL_LINEAR_VELOCITY_DIVISOR
            val deltaRotationZ = angularVelocity / IOS_ROLL_ANGULAR_VELOCITY_DIVISOR

            val lenSq =
                deltaRotationX * deltaRotationX + deltaRotationY * deltaRotationY + deltaRotationZ * deltaRotationZ

            if (lenSq <= IOS_MIN_ROLL_VECTOR_LENGTH * IOS_MIN_ROLL_VECTOR_LENGTH) {
                return
            }

            applyIosRollingVector(
                deltaRotationX, deltaRotationY, deltaRotationZ
            )
        }

        private fun sampleSource(uFloat: Float, vFloat: Float): Int {
            var u = uFloat.toInt() % sourceWidth
            if (u < 0) u += sourceWidth

            val v = vFloat.toInt().coerceIn(0, sourceHeight - 1)

            return sourcePixels[v * sourceWidth + u]
        }

        private fun applyShade(color: Int, normalX: Float, normalY: Float, normalZ: Float): Int {
            val a = color ushr 24
            if (a == 0) return 0

            val r = (color shr 16) and 0xff
            val g = (color shr 8) and 0xff
            val b = color and 0xff

            val lightDot = (normalX * -0.35f + normalY * -0.45f + normalZ * 0.90f).coerceIn(0f, 1f)

            val edgeShade = normalZ.coerceIn(0f, 1f)

            val shade = (0.48f + lightDot * 0.42f + edgeShade * 0.10f).coerceIn(0.35f, 1.05f)

            val rr = (r * shade).toInt().coerceIn(0, 255)
            val gg = (g * shade).toInt().coerceIn(0, 255)
            val bb = (b * shade).toInt().coerceIn(0, 255)

            return (a shl 24) or (rr shl 16) or (gg shl 8) or bb
        }

        private fun renderSphereIfNeeded() {
            if (!sphereDirty) return
            sphereDirty = false

            val inverseTextureRotation = iosRotationVectorToQuaternion(
                -visualRotationX, -visualRotationY, -visualRotationZ
            )

            for (py in 0 until SPHERE_RENDER_SIZE) {
                for (px in 0 until SPHERE_RENDER_SIZE) {
                    val index = py * SPHERE_RENDER_SIZE + px

                    val nx = (px - SPHERE_CENTER) / SPHERE_RADIUS
                    val ny = (py - SPHERE_CENTER) / SPHERE_RADIUS
                    val r2 = nx * nx + ny * ny

                    if (r2 > 1f) {
                        spherePixels[index] = 0x00000000
                        continue
                    }

                    val nz = sqrt(1f - r2)

                    val rotated = iosRotateVectorByQuaternion(
                        inverseTextureRotation, nx.toDouble(), -ny.toDouble(), nz.toDouble()
                    )

                    val vx = rotated[0]
                    val vy = rotated[1]
                    val vz = rotated[2]

                    val longitude = atan2(vx, vz)
                    val latitude = asin(vy.coerceIn(-1.0, 1.0))

                    val u = ((longitude / (PI * 2.0)) + 0.5) * sourceWidth
                    val v = (0.5 - (latitude / PI)) * sourceHeight

                    val sampled = sampleSource(u.toFloat(), v.toFloat())
                    spherePixels[index] = applyShade(sampled, nx, ny, nz)
                }
            }

            sphereBitmap.setPixels(
                spherePixels, 0, SPHERE_RENDER_SIZE, 0, 0, SPHERE_RENDER_SIZE, SPHERE_RENDER_SIZE
            )
        }

        fun drawShadow(canvas: Canvas) {
            if (sunk || inPocket) {
                return
            }

            val sx = x + IOS_SHADOW_OFFSET_X
            val sy = y + IOS_SHADOW_OFFSET_Y

            shadowRect.set(
                sx - IOS_SHADOW_RADIUS,
                sy - IOS_SHADOW_RADIUS,
                sx + IOS_SHADOW_RADIUS,
                sy + IOS_SHADOW_RADIUS
            )

            canvas.drawOval(shadowRect, shadowPaint)
        }

        private fun drawGloss(canvas: Canvas) {
            if (sunk || inPocket) {
                return
            }

            canvas.drawOval(GLOSS_RECT_1, glossPaint)
            canvas.drawOval(GLOSS_RECT_2, glossPaint2)
        }

        fun draw(canvas: Canvas) {
            updateVisualRoll()
            renderSphereIfNeeded()

            canvas.withTranslation(x, y) {
                rotate(IOS_BALL_CANCEL_TABLE_ROTATION_DEGREES)

                drawBitmap(
                    sphereBitmap, null, BALL_DRAW_RECT, ballPaint
                )
            }

            canvas.withTranslation(x, y) {
                drawGloss(this)
            }
        }
    }

    var poolBalls = arrayListOf<PoolBall>()
    val replayHits = arrayListOf<BallHit>()
    val outgoingReplayHits = arrayListOf<BallHit>()

    private var finalBalls = ""

    private val nineBallFrontBallX = 560.000000f
    private val nineBallFrontBallY = 220.000000f
    private val nineBallCueBallX = 221.000000f
    private val nineBallCueBallMinY = 110.000000
    private val nineBallCueBallMaxY = 330.000000

    private fun buildDefaultNineBallRack(): String {
        val cueY = Random.nextDouble(nineBallCueBallMinY, nineBallCueBallMaxY)

        return "#632.746155,220.000000,0.000000,0.716767,5,6.796000,-0.621908,3.502472" + "#614.559570,209.500000,0.000000,0.863119,8,5.764651,3.187424,7.145291" + "#614.559570,230.500000,0.000000,0.666108,6,-0.455535,7.249262,-1.390415" + "#596.373047,199.000000,0.000000,0.907943,7,-6.769609,1.087264,-3.765822" + "#596.373047,220.000000,0.000000,1.264982,9,6.340362,-4.153222,-7.661037" + "#596.373047,241.000000,0.000000,1.046328,4,-6.964514,-7.698694,-1.881179" + "#578.186523,209.500000,0.000000,0.406139,2,4.660657,-4.275956,3.727190" + "#578.186523,230.500000,0.000000,1.083360,3,-3.806327,-4.462822,0.955941" + "#560.000000,220.000000,0.000000,1.000000,1,7.747318,6.809052,1.118692" + String.format(
            Locale.US,
            "#%.6f,%.6f,0.000000,0.990000,0,5.006198,-0.734911,-5.935992",
            nineBallCueBallX,
            cueY
        )
    }

    var cueBall: PoolBall? = null

    private fun setDefaultNineBallBreakCueRotation() {
        if (!isNineBall || !isFirst) return

        val cue = cueBall ?: return

        val dx = nineBallFrontBallX - cue.x
        val dy = nineBallFrontBallY - cue.y

        renderer.cuePos = floatArrayOf(cue.x, cue.y)
        renderer.cueRot = atan2(dy, dx)

        OpenPigeonLog.i(
            "POOL9_DEBUG",
            "DEFAULT_BREAK_AIM cue=(${cue.x},${cue.y}) front=($nineBallFrontBallX,$nineBallFrontBallY) dx=$dx dy=$dy cueRot=${renderer.cueRot}"
        )
    }

    private fun exportBalls(centerScratch: Boolean): String {
        val result = poolBalls.filter {
            !it.sunk || (centerScratch && it.number == 0) || (isNineBall && centerScratch && it.number == 9)
        }.map {
            val density = if (isFirst) it.density else 1

            if (centerScratch && it.number == 0) {
                OpenPigeonLog.i("White", "scratching")
                return@map "#392.000000,220.000000,0.000000,$density,0,${it.exportVisualRotationString()}"
            }

            if (isNineBall && centerScratch && it.sunk && it.number == 9) {
                OpenPigeonLog.i("POOL9_DEBUG", "Respotted fouled pocketed ball ${it.number}")
                return@map "#560.000000,220.000000,0.000000,1.000000,${it.number},${it.exportVisualRotationString()}"
            }

            "#${it.x},${it.y},${it.rot},$density,${it.number},${it.exportVisualRotationString()}"
        }.joinToString("")

        if (poolVisualTraceEnabled) {
            OpenPigeonLog.i(
                "PoolVisualRoll",
                "exportBalls centerScratch=$centerScratch result=$result live=${dumpVisualRotationState()}"
            )
        }

        return result
    }

    private fun generateRandomRack(seed: Long): String {
        val rng = Drand48()
        rng.srand48(seed)

        data class Slot(val x: Float, val y: Float)

        val slots = mutableListOf<Slot>()
        val maxAttempts = 10_000
        var attempts = 0

        while (slots.size < 30 && attempts < maxAttempts) {
            attempts++

            val rx = rng.drand48()
            val ry = rng.drand48()

            val x = String.format(
                Locale.US, "%f", rx * (cueBallMaxX - cueBallMinX).toDouble() + cueBallMinX
            ).toFloat()

            val y = String.format(
                Locale.US, "%f", ry * (cueBallMaxY - cueBallMinY).toDouble() + cueBallMinY
            ).toFloat()

            val tooClose = slots.any { s ->
                val dx = s.x - x
                val dy = s.y - y
                sqrt(dx * dx + dy * dy) < 30.0f
            }

            if (!tooClose) {
                slots.add(Slot(x, y))
            }
        }

        OpenPigeonLog.i(
            "PoolPlus", "Generated ${slots.size} slots for seed=$seed after $attempts attempts"
        )

        if (slots.size < 30) {
            OpenPigeonLog.e(
                "PoolPlus",
                "Failed to generate 30 slots after $attempts attempts; got ${slots.size}"
            )
        }

        val ballsLeft = mutableListOf(
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            9,
            10,
            11,
            12,
            13,
            14,
            15,
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            9,
            10,
            11,
            12,
            13,
            14,
            15
        )

        val builder = StringBuilder()

        for ((i, element) in slots.withIndex()) {
            val x = element.x
            val y = element.y

            val ballNum: Int = when (i) {
                0 -> 8
                1 -> 0
                else -> {
                    val pick = (rng.drand48() * ballsLeft.size).toInt()
                    val n = ballsLeft[pick]
                    ballsLeft.removeAt(pick)
                    n
                }
            }

            builder.append("#")
            builder.append(String.format(Locale.US, "%f", x))
            builder.append(",")
            builder.append(String.format(Locale.US, "%f", y))
            builder.append(",0.000000,1.000000,")
            builder.append(ballNum)
            val rotX = rng.drand48() * 64.0 - 32.0
            val rotY = rng.drand48() * 64.0 - 32.0
            val rotZ = rng.drand48() * 64.0 - 32.0

            builder.append(",")
            builder.append(String.format(Locale.US, "%.6f", rotX))
            builder.append(",")
            builder.append(String.format(Locale.US, "%.6f", rotY))
            builder.append(",")
            builder.append(String.format(Locale.US, "%.6f", rotZ))
        }

        return builder.toString()
    }

    private fun dumpPoolBallBuffers(): String {
        return poolBalls.joinToString("|") { ball ->
            "b:${ball.number}" + ",x:${ball.x}" + ",y:${ball.y}" + ",r:${ball.rot}" + ",sunk:${ball.sunkOrder}" + ",hit:${ball.ballHit}" + ",hole:${ball.holeX},${ball.holeY}" + ",vx:${ball.vx}" + ",vy:${ball.vy}" + ",av:${ball.av}"
        }
    }

    fun traceVisualRoll(
        reason: String, nativeMoving: Boolean? = null, force: Boolean = false
    ) {
        if (!poolTraceEnabled || !poolVisualTraceEnabled) return

        if (!force) {
            poolVisualTraceFrame += 1
            if (poolVisualTraceFrame % poolVisualTraceEveryFrames != 0L) return
        }

        val dump = dumpVisualRotationState()

        if (!force && dump == poolVisualTraceLastDump) {
            return
        }

        poolVisualTraceLastDump = dump

        OpenPigeonLog.i(
            "PoolVisualRoll",
            "reason=$reason mode=$mode moving=$nativeMoving replaying=$replaying " + "scratch=$scratch finalBallsLen=${finalBalls.length} balls=$dump"
        )
    }

    private fun dumpVisualRotationState(): String {
        return poolBalls.sortedWith(compareBy<PoolBall> { it.number }.thenBy { it.x }
            .thenBy { it.y }).joinToString("|") { ball ->
            String.format(
                Locale.US,
                "b:%d x:%.3f y:%.3f nativeRot:%.6f vx:%.6f vy:%.6f av:%.6f sunk:%s pocket:%s hole:%.3f,%.3f vr:%.6f,%.6f,%.6f",
                ball.number,
                ball.x,
                ball.y,
                ball.rot,
                ball.vx,
                ball.vy,
                ball.av,
                ball.sunk,
                ball.inPocket,
                ball.holeX,
                ball.holeY,
                ball.visualRotationX,
                ball.visualRotationY,
                ball.visualRotationZ
            )
        }
    }

    private fun buildBalls(balls: String, skew: String?) {
        data class FinalBall(val number: Int, val x: Float, val y: Float)

        val finalBalls: MutableList<FinalBall>? = skew?.let {
            val result = mutableListOf<FinalBall>()

            for (finalBall in it.split("#")) {
                if (finalBall == "") continue

                val details = finalBall.split(",")
                if (details.size < 5) continue

                result.add(
                    FinalBall(
                        details[4].toInt(), details[0].toFloat(), details[1].toFloat()
                    )
                )
            }

            result
        }

        for (ball in balls.split("#")) {
            if (ball == "") continue

            val details = ball.split(",")
            if (details.size < 5) continue

            val x = details[0].toFloat()
            val y = details[1].toFloat()
            val rot = details[2].toFloat()
            val density = details[3].toFloat()
            val number = details[4].toInt()
            val visualRotX = details.getOrNull(5)?.toFloatOrNull() ?: 0f
            val visualRotY = details.getOrNull(6)?.toFloatOrNull() ?: 0f
            val visualRotZ = details.getOrNull(7)?.toFloatOrNull() ?: -1f

            val buffer = ByteBuffer.allocateDirect(4 /*f32*/ * 10)
            buffer.order(ByteOrder.nativeOrder())

            val floatBuffer = buffer.asFloatBuffer()

            floatBuffer.put(0, x)
            floatBuffer.put(1, y)
            floatBuffer.put(2, rot)
            floatBuffer.put(3, -1f) // sunkOrder
            floatBuffer.put(4, -1f) // numberHit
            floatBuffer.put(5, -1f) // holeX
            floatBuffer.put(6, -1f) // holeY

            floatBuffer.put(7, 0f) // vx
            floatBuffer.put(8, 0f) // vy
            floatBuffer.put(9, 0f) // angularVelocity

            val shouldGoInMode = if (finalBalls == null) {
                0
            } else {
                var bestIndex = -1
                var bestDist = Float.POSITIVE_INFINITY

                for (i in finalBalls.indices) {
                    val finalBall = finalBalls[i]
                    if (finalBall.number != number) continue

                    val dx = finalBall.x - x
                    val dy = finalBall.y - y
                    val dist = dx * dx + dy * dy

                    if (dist < bestDist) {
                        bestDist = dist
                        bestIndex = i
                    }
                }

                if (bestIndex >= 0) {
                    finalBalls.removeAt(bestIndex)
                    2
                } else {
                    1
                }
            }

            OpenPigeonLog.i(
                "ReplayBallMode",
                "number=$number shouldGoInMode=$shouldGoInMode x=$x y=$y remainingFinalMatches=${finalBalls?.count { it.number == number } ?: -1}")

            OpenPigeonLog.i(
                "Making ball", "x: $x y: $y rot: $rot density: $density number: $number"
            )

            makeBall(
                table, x, y, rot, density, number, shouldGoInMode, floatBuffer
            )

            val poolBall = PoolBall(
                number = number,
                data = floatBuffer,
                resources = resources,
                density = density,
                visualRotationX = visualRotX,
                visualRotationY = visualRotY,
                visualRotationZ = visualRotZ
            )
            poolBalls.add(poolBall)

            if (number == 0) {
                cueBall = poolBall
            }
        }

        updateNineBallBar()
    }

    var isHard = false
    var player = 0
    var uuid1: String? = null
    var uuid2: String? = null
    var isEightBallPlus = false
    var isNineBall = false
    var nineBallTargetAtShot = 1

    private fun updateSpectatorMode(
        msg: Map<String, String>
    ) {
        val myId = gameSessionIPC?.getSenderUUID(sessionId).orEmpty()

        val player1Id = msg["player1"].orEmpty()
        val player2Id = msg["player2"].orEmpty()

        spectatorMode =
            myId.isNotBlank() && player1Id.isNotBlank() && player2Id.isNotBlank() && myId != player1Id && myId != player2Id

        if (spectatorMode) {
            disableSend = true
            mode = PoolMode.Disabled
            draggingCue = false
            call8Ball = false

            cancelCueInertia()
            closeCuePopup(force = true)

            applySpectatorAvatars(msg)
        }

        configureSettingsAvatarTarget()

        OpenPigeonLog.i(
            "PoolSpectator",
            "spectator=$spectatorMode " + "myIdBlank=${myId.isBlank()} " + "p1Blank=${player1Id.isBlank()} " + "p2Blank=${player2Id.isBlank()}"
        )
    }

    private fun findAvatarView(
        parent: View
    ): AvatarView? {
        if (parent is AvatarView) {
            return parent
        }

        if (parent is ViewGroup) {
            for (index in 0 until parent.childCount) {
                val found = findAvatarView(
                    parent.getChildAt(index)
                )

                if (found != null) {
                    return found
                }
            }
        }

        return null
    }

    private fun applyAvatarToAnchor(
        anchor: FrameLayout,
        avatarData: String,
    ) {
        val avatar = findAvatarView(anchor) ?: return

        if (avatarData.isBlank()) {
            avatar.showPlaceholder()
        } else {
            avatar.applyFromOpponentString(avatarData)
        }

        AvatarView.configureTallAnchor(anchor)

        if (anchor === gameAvatarAnchor) {
            anchor.post {
                updatePoolYouLabelLayer()
            }
        }
    }

    private fun recoveryStripesValue(
        value: Boolean?,
    ): String {
        return when (value) {
            true -> "1"
            false -> "0"
            null -> "n"
        }
    }

    private fun recoveryStripesValue(
        value: String?,
    ): Boolean? {
        return when (value) {
            "1" -> true
            "0" -> false
            else -> null
        }
    }

    private fun encodeRecoveryHit(
        hit: BallHit,
    ): String {
        return listOf(
            hit.direction.toString(),
            hit.power.toString(),
            hit.spinX.toString(),
            hit.spinY.toString(),
            recoveryStripesValue(
                hit.wasStripes,
            ),
        ).joinToString(
            ",",
        )
    }

    private fun decodeRecoveryHit(
        raw: String,
    ): BallHit? {
        val parts =
            raw.split(
                ",",
            )

        if (parts.size != 5) {
            return null
        }

        val direction =
            parts[0].toFloatOrNull()
                ?: return null

        val power =
            parts[1].toFloatOrNull()
                ?: return null

        val spinX =
            parts[2].toFloatOrNull()
                ?: return null

        val spinY =
            parts[3].toFloatOrNull()
                ?: return null

        return BallHit(
            direction = direction,
            power = power,
            spinX = spinX,
            spinY = spinY,
            wasStripes = recoveryStripesValue(
                parts[4],
            ),
        )
    }

    private fun encodeRecoveryHits(): String {
        return outgoingReplayHits.joinToString(
            ";",
        ) { hit ->
            encodeRecoveryHit(
                hit,
            )
        }
    }

    private fun decodeRecoveryHits(
        raw: String,
    ): List<BallHit> {
        if (raw.isBlank()) {
            return emptyList()
        }

        return raw
            .split(
                ";",
            )
            .mapNotNull {
                decodeRecoveryHit(
                    it,
                )
            }
    }

    private fun savePoolTurnProgress(phase: String, currentBalls: String = exportBalls(false)) {
        if (spectatorMode || sessionId.isBlank()) return
        val ipc = gameSessionIPC ?: return
        val calledPocketValue = if (calledPocket.size >= 2) "${calledPocket[0]},${calledPocket[1]}" else ""

        val saved = ipc.saveTurnProgress(
            sessionId,
            mapOf(
                "phase" to phase,
                "currentBalls" to currentBalls,
                "turnStartBalls" to finalBalls,
                "shotStartBalls" to lastShotStartBalls,
                "shotStartIsFirst" to lastShotStartIsFirst.toString(),
                "hits" to encodeRecoveryHits(),
                "stripes" to recoveryStripesValue(iAmStripes),
                "isFirst" to isFirst.toString(),
                "wasFirst" to wasFirst.toString(),
                "scratch" to scratch.toString(),
                "call8Ball" to call8Ball.toString(),
                "calledPocket" to calledPocketValue,
            ),
        )

        OpenPigeonLog.i("PoolRecovery", "Saved progress phase=$phase hits=${outgoingReplayHits.size} currentBallsLen=${currentBalls.length} saved=$saved")
    }

    private fun restorePoolTurnProgress(progress: Map<String, String>): Boolean {
        val phase = progress["phase"].orEmpty()
        val currentBalls = progress["currentBalls"].orEmpty()
        if (currentBalls.isBlank() || phase.isBlank()) return false

        val restoredHits = decodeRecoveryHits(progress["hits"].orEmpty())
        if (phase == "shot" && restoredHits.isEmpty()) return false

        val shotStartBalls = progress["shotStartBalls"].orEmpty()
        val replayLastShot = phase == "aim" && shotStartBalls.isNotBlank() && restoredHits.isNotEmpty()
        val turnStartBalls = progress["turnStartBalls"]?.takeIf { it.isNotBlank() } ?: currentBalls

        OpenPigeonLog.i("PoolRecovery", "Restoring Pool progress phase=$phase hits=${restoredHits.size} replayLastShot=$replayLastShot currentBallsLen=${currentBalls.length}")

        cancelAllShots()
        cancelAllShots = {}
        replayHits.clear()
        outgoingReplayHits.clear()
        outgoingReplayHits.addAll(restoredHits)
        replaying = false
        skipReplayRequested = false
        skipReplayFadeStarted = false
        disableSend = false

        finalBalls = turnStartBalls
        lastShotStartBalls = shotStartBalls
        lastShotStartIsFirst = progress["shotStartIsFirst"]?.toBooleanStrictOrNull() ?: false
        iAmStripes = recoveryStripesValue(progress["stripes"])
        isFirst = progress["isFirst"]?.toBooleanStrictOrNull() ?: false
        wasFirst = progress["wasFirst"]?.toBooleanStrictOrNull() ?: false
        scratch = progress["scratch"]?.toBooleanStrictOrNull() ?: false
        call8Ball = progress["call8Ball"]?.toBooleanStrictOrNull() ?: false
        calledPocket = progress["calledPocket"]?.split(",")?.mapNotNull { it.toIntOrNull() }?.takeIf { it.size == 2 } ?: emptyList()

        renderer.resetFrameReadySignal()
        clearBalls(table)
        poolBalls.clear()
        cueBall = null

        if (replayLastShot) {
            val hit = restoredHits.last()
            recoveryTurnStartBalls = turnStartBalls
            finalBalls = currentBalls
            isFirst = lastShotStartIsFirst
            replaying = true
            restoringLastShotReplay = true
            skipReplayFadeStarted = true

            buildBalls(shotStartBalls, currentBalls)
            updateBallTypeUi()

            if (!renderer.isAlive) renderer.start()

            runOnUiThread {
                hideSkipReplayButton("recovery_last_shot")
                hideStateLabel()
                setCueUiVisible(false)
                renderer.setCueVisible(false)
            }

            replayHits.add(hit)

            renderer.notifyWhenFrameReady {
                restoringTurnRecovery = false
                playNextReplay()
            }

            return true
        }

        buildBalls(currentBalls, null)
        updateBallTypeUi()

        if (!renderer.isAlive) renderer.start()

        if (phase == "shot") {
            val hit = restoredHits.last()
            mode = PoolMode.Disabled

            runOnUiThread {
                hideSkipReplayButton("recovery_shot")
                hideStateLabel()
                setCueUiVisible(false)
                renderer.setCueVisible(true)
                renderer.cueRot = hit.direction
                cueBall?.let { renderer.cuePos = floatArrayOf(it.x, it.y) }
                setSpinX = hit.spinX
                setSpinY = hit.spinY
                syncCueDots()
            }

            renderer.notifyWhenFrameReady {
                restoringTurnRecovery = false
                animateShoot(hit.power, hit)
            }

            return true
        }

        mode = PoolMode.Aiming

        renderer.notifyWhenFrameReady {
            restoringTurnRecovery = false

            runOnUiThread {
                hideSkipReplayButton("recovery_aim")
                hideStateLabel()
                setCueUiVisible(true)
                renderer.setCueVisible(true)

                if (call8Ball && calledPocket.isEmpty()) {
                    val label = findViewById<TextView>(R.id.state_label)
                    label.visibility = View.VISIBLE
                    label.text = TEXT_CHOOSE_POCKET
                }
            }
        }

        return true
    }

    private fun restorePoolRecovery(
        remoteMessage: Map<String, String>,
    ) {
        val ipc =
            gameSessionIPC

        if (
            ipc == null ||
            sessionId.isBlank()
        ) {
            handleMessage(
                remoteMessage,
            )

            return
        }

        val recovery =
            try {
                ipc.getTurnRecovery(
                    sessionId,
                )
            } catch (throwable: Throwable) {
                OpenPigeonLog.e(
                    "PoolRecovery",
                    "Unable to load Pool recovery",
                    throwable,
                )

                null
            }

        if (recovery == null) {
            hideTurnRecoveryRetry()

            handleMessage(
                remoteMessage,
            )

            return
        }

        if (recovery.sendAttempted) {
            val pendingDisplay =
                remoteMessage
                    .toMutableMap()
                    .apply {
                        putAll(
                            recovery.pendingUpdates,
                        )
                    }

            OpenPigeonLog.i(
                "PoolRecovery",
                "Restoring pending Pool send",
            )

            handleMessage(
                pendingDisplay,
            )

            showTurnRecoveryRetry()

            return
        }

        restoringTurnRecovery =
            true

        handleMessage(
            remoteMessage,
        )

        if (
            !restorePoolTurnProgress(
                recovery.progress,
            )
        ) {
            restoringTurnRecovery =
                false

            OpenPigeonLog.w(
                "PoolRecovery",
                "Saved Pool progress could not be restored; using remote state",
            )
        }
    }

    private fun configureSettingsAvatarTarget() {
        if (!::gameMenu.isInitialized) {
            return
        }

        gameMenu.sheet.setGameAvatarRefreshTarget(
            avatarView = if (spectatorMode) {
                null
            } else {
                findAvatarView(gameAvatarAnchor)
            },
        )

        gameMenu.sheet.setGameAvatarRefreshEnabled(
            enabled = !spectatorMode,
        )
    }

    private fun restoreSpectatorAvatarsAfterSettingsOpen() {
        if (!spectatorMode || lastMessage.isEmpty()) {
            return
        }

        gameAvatarAnchor.post {
            if (!spectatorMode || poolActivityClosing) {
                return@post
            }

            configureSettingsAvatarTarget()
            applySpectatorAvatars(lastMessage)
            showSpectatorLabel()
        }
    }

    private fun applySpectatorAvatars(
        msg: Map<String, String>
    ) {
        if (!spectatorMode) return

        runOnUiThread {
            applyAvatarToAnchor(
                anchor = gameAvatarAnchor, avatarData = msg["avatar1"].orEmpty()
            )

            applyAvatarToAnchor(
                anchor = oppAvatarAnchor, avatarData = msg["avatar2"].orEmpty()
            )

            updatePoolYouLabelLayer()
            alignSpectatorAvatarAnchors()
        }
    }

    private fun updatePoolYouLabelLayer() {
        val youLabel = findViewById<TextView>(R.id.youLabel)
        val labelLayer = stateLabelDp(24f).toFloat()

        youLabel.visibility = View.VISIBLE
        youLabel.alpha = if (spectatorMode) 0f else 1f

        youLabel.elevation = labelLayer
        youLabel.translationZ = labelLayer

        gameAvatarAnchor.elevation = 0f
        gameAvatarAnchor.translationZ = 0f
    }

    @SuppressLint("SetTextI18n")
    private fun showSpectatorLabel() {
        runOnUiThread {
            stopStateLabelAnimation()
            stateLabelVisual = StateLabelVisual.Hidden
            setStatusDimVisible(false)

            val label = findViewById<TextView>(R.id.state_label)

            label.animate().cancel()
            label.text = "Spectating..."
            label.visibility = View.VISIBLE
            label.alpha = 1f
            label.scaleX = 1f
            label.scaleY = 1f

            label.background = null
            label.setPadding(0, 0, 0, 0)
            label.setTextColor(Color.WHITE)
            label.setTextSize(
                TypedValue.COMPLEX_UNIT_SP, 24f
            )
            label.typeface = android.graphics.Typeface.DEFAULT_BOLD

            label.setShadowLayer(
                3f, 0f, 2f, Color.argb(145, 0, 0, 0)
            )

            val params = label.layoutParams as? FrameLayout.LayoutParams

            if (params != null) {
                params.width = WRAP_CONTENT
                params.height = WRAP_CONTENT
                params.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                params.topMargin = stateLabelDp(10f)
                label.layoutParams = params
            }

            label.bringToFront()
        }
    }

    private fun applySpectatorReadOnlyUi() {
        if (!spectatorMode) return

        disableSend = true
        mode = PoolMode.Disabled
        draggingCue = false
        call8Ball = false

        cancelCueInertia()
        closeCuePopup(force = true)

        runOnUiThread {
            setCueUiVisible(false)
            renderer.setCueVisible(false)
            hideSkipReplayButton("spectator_read_only")

            findViewById<LinearLayout>(R.id.controls).visibility = View.GONE

            updatePoolYouLabelLayer()
            alignSpectatorAvatarAnchors()
            showSpectatorLabel()
        }
    }

    private fun resolveMyPlayerSlot(msg: Map<String, String>): Int {
        val myId = gameSessionIPC?.getSenderUUID(sessionId) ?: ""
        val p1 = msg["player1"].orEmpty()
        val p2 = msg["player2"].orEmpty()
        val sender = msg["sender"].orEmpty()
        val senderPlayer = msg["player"]?.toIntOrNull() ?: 1

        if (myId.isNotEmpty()) {
            if (myId == p1) return 1
            if (myId == p2) return 2
        }

        if (sender.isNotEmpty()) {
            if (sender == p1) return 2
            if (sender == p2) return 1
        }

        return if (senderPlayer == 2) 1 else 2
    }

    fun handleMessage(msg: Map<String, String>) {
        lastMessage = msg
        lastMessageWinner = msg["winner"].orEmpty()

        if (table == 0L) return // we are dead

        renderer.resetFrameReadySignal()

        val explicitPoolTraceEnabled =
            msg["pool_trace"] == "1" || msg["debug_pool"] == "1" || msg["trace"] == "pool" || msg["pool_visual_trace"] == "1" || msg["visual_trace"] == "1" || msg["trace"] == "pool_visual" || msg["trace_visual"] == "1"

        poolTraceEnabled = explicitPoolTraceEnabled

        poolVisualTraceEnabled = poolTraceEnabled

        poolVisualTraceEveryFrames =
            msg["pool_visual_trace_every"]?.toIntOrNull()?.coerceAtLeast(1) ?: 6

        poolVisualTraceFrame = 0L
        poolVisualTraceLastDump = ""

        setPoolDebugTrace(table, poolTraceEnabled, if (poolTraceEnabled) 1 else 0)

        if (poolTraceEnabled) {
            OpenPigeonLog.i(
                "PoolVisualRoll",
                "enabled everyFrames=$poolVisualTraceEveryFrames " + "poolTrace=${true} replayLen=${msg["replay"]?.length ?: 0} " + "num=${msg["num"]} game=${msg["game"] ?: msg["name"] ?: msg["gameName"]}"
            )
        }

        disableSend = false
        skipReplayRequested = false
        replaying = false
        skipReplayFadeStarted = false
        cancelAllShots()
        cancelAllShots = {}
        call8Ball = false
        gameEnded = false
        winLossState = ""
        pendingWinLossState = ""
        if (::avatarWinBurstController.isInitialized) {
            avatarWinBurstController.clear()
        }
        stateLabelVisual = StateLabelVisual.Hidden
        setStatusDimVisible(false)
        clearBalls(table)
        poolBalls.clear()
        cueBall = null
        replayHits.clear()
        finalBalls = ""
        val gameName = msg["game"] ?: msg["name"] ?: msg["gameName"] ?: baseGame.getName()
        if (::gameMenu.isInitialized) {
            gameMenu.updateRules(
                title = currentPoolRulesTitle(),
                sections = currentPoolRulesSections(),
            )

            gameMenu.updateMusicAssetPath(
                currentMusicTrack(),
            )
        }
        isNineBall = gameName == "pool2"
        isEightBallPlus = gameName == "pool3"
        if (isNineBall) {
            iAmStripes = null
            updateBallTypeUi()
        }

        OpenPigeonLog.i(
            "PoolMode", "gameName=$gameName isNineBall=$isNineBall isEightBallPlus=$isEightBallPlus"
        )

        val ipc = gameSessionIPC ?: return

        isHard = (msg["mode"] ?: "n") != "n"
        val num = msg["num"] ?: "1"

        uuid1 = msg["player1"]
        uuid2 = msg["player2"]

        updateSpectatorMode(msg)

        player = resolveMyPlayerSlot(msg)

        if (spectatorMode) {
            applySpectatorAvatars(msg)
        } else {
            val oppAvatarKey = if (player == 1) "avatar2" else "avatar1"

            msg[oppAvatarKey]?.takeIf { it.isNotBlank() }?.let { avatarStr ->
                runOnUiThread {
                    gameMenu.sheet.applyOpponentAvatarString(
                        avatarStr,
                    )
                }
            }
        }

        OpenPigeonLog.i("number", num)

        isFirst = false
        if (num == "2") {
            isFirst = true // for replay
        }

        scratch = false

        val sender = msg["sender"].orEmpty()
        val isYourTurn = sender != ipc.getSenderUUID(sessionId)

        localWinLossStateFromWinner(msg["winner"]).takeIf { it.isNotBlank() }?.let { state ->
            setPendingWinLossState(state)
        }

        OpenPigeonLog.i(
            "PoolMsg",
            "handleMessage num=$num game=$gameName isYourTurn=$isYourTurn " + "sender=$sender player=$player replayLen=${msg["replay"]?.length ?: 0}"
        )
        var stagingBalls: String? = null
        if (msg.containsKey("replay")) {
            val replay = msg["replay"]!!
            for ((index, value) in replay.split("|").withIndex()) {
                val output = mutableMapOf<String, String>()
                for (element in value.split("&")) {
                    val parts = element.split(":", limit = 2)
                    if (parts.isEmpty() || parts[0].isEmpty()) {
                        continue // JSON will BLOW Vitalii Zlotskii's MIND
                    }
                    if (parts.size < 2) {
                        OpenPigeonLog.w(
                            "PoolReplay", "malformed_replay_element index=$index element=$element"
                        )
                        continue
                    }

                    output[parts[0]] = parts[1]
                }

                OpenPigeonLog.i(
                    "PoolReplay",
                    "segment index=$index keys=${output.keys} ballsLen=${output["balls"]?.length ?: 0} " + "d=${output["d"]} p=${output["p"]} x=${output["x"]} y=${output["y"]} s=${output["s"]}"
                )

                output["balls"]?.let { balls ->
                    if (isYourTurn) {
                        if (index > 0) {
                            finalBalls = balls
                            return@let
                        }
                        stagingBalls = balls
                    } else if (index > 0) {
                        stagingBalls = balls
                    }
                }

                if (!isNineBall && output["stripes"] != null) {
                    val stripes = output["stripes"]?.toIntOrNull()
                    if (stripes != null) {
                        iAmStripes = if (stripes == 0) null else player == stripes
                        updateBallTypeUi()
                        OpenPigeonLog.i("Me", "$iAmStripes")
                    } else {
                        OpenPigeonLog.w(
                            "PoolReplay",
                            "bad_stripes_value index=$index value=${output["stripes"]}"
                        )
                    }
                    updateBallTypeUi()
                    OpenPigeonLog.i("Me", "$iAmStripes")
                }

                if (output["move"] != null) {
                    scratch = output["move"] == "1"
                }

                if (output["win"] != null) {
                    val win = output["win"]?.toIntOrNull()
                    if (win != null) {
                        val localState = if (!isYourTurn) {
                            if (win == 1) "1" else "-1"
                        } else {
                            if (win == 1) "-1" else "1"
                        }
                        setPendingWinLossState(localState)
                    } else {
                        OpenPigeonLog.w(
                            "PoolReplay", "bad_win_value index=$index value=${output["win"]}"
                        )
                    }
                }

                if (output["d"] != null) {
                    val direction = output["d"]?.toFloatOrNull()
                    val power = output["p"]?.toFloatOrNull()
                    val spinX = output["x"]?.toFloatOrNull()
                    val spinY = output["y"]?.toFloatOrNull()

                    if (direction == null || power == null || spinX == null || spinY == null) {
                        OpenPigeonLog.e(
                            "PoolReplay",
                            "bad_hit_segment index=$index d=${output["d"]} p=${output["p"]} x=${output["x"]} y=${output["y"]}"
                        )
                    } else {
                        val hit = BallHit(
                            direction,
                            power,
                            spinX,
                            spinY,
                            output["s"]?.toIntOrNull()?.let { stripes ->
                                if (stripes == 0) null else player == stripes
                            })

                        replayHits.add(hit)

                        OpenPigeonLog.i(
                            "PoolReplay",
                            "queued_hit index=$index d=${hit.direction} p=${hit.power} " + "spinX=${hit.spinX} spinY=${hit.spinY} s=${output["s"]}"
                        )
                    }
                }
            }
            OpenPigeonLog.i(
                "PoolReplay",
                "replay_parse_done isYourTurn=$isYourTurn hits=${replayHits.size} " + "stagingLen=${stagingBalls?.length ?: 0} finalLen=${finalBalls.length}"
            )
            stagingBalls?.let {
                buildBalls(it, finalBalls)
            }
        } else {
            if (!isYourTurn) {
                if (isNineBall) {
                    finalBalls = buildDefaultNineBallRack()
                    buildBalls(finalBalls, null)
                    updateNineBallBar()
                }

                runOnUiThread {
                    hideSkipReplayButton("not_replaying")
                    setCueUiVisible(false)

                    showWaitingLabelAnimated()
                }

                mode = PoolMode.Disabled
                closeCuePopup()
                if (!renderer.isAlive) {
                    renderer.start()
                }
                return
            }
            iAmStripes = null
            updateBallTypeUi()
            if (isNineBall) {
                finalBalls = buildDefaultNineBallRack()
            } else if (isEightBallPlus) {
                val seedStr = msg["seed"]
                val seed = seedStr?.toLongOrNull()
                if (seed == null) {
                    OpenPigeonLog.e(
                        "PoolPlus",
                        "pool3 game without valid seed (got '$seedStr'); falling back to normal rack"
                    )
                    finalBalls =
                        "#632.746155,178.000000,0.000000,0.801981,9,5.632916,7.415801,5.384167#632.746155,199.000000,0.000000,0.050000,10,-1.479509,5.981912,-0.639594#632.746155,220.000000,0.000000,0.145560,7,-4.857441,-3.796834,-5.439248#632.746155,241.000000,0.000000,0.050000,6,3.548234,-7.060621,-3.771457#632.746155,262.000000,0.000000,0.964504,1,7.809305,-4.673173,7.553514#614.559570,188.500000,0.000000,0.868768,12,6.889496,7.963203,-4.292648#614.559570,209.500000,0.000000,0.759525,13,4.140916,-0.562560,-5.371364#614.559570,230.500000,0.000000,0.839745,15,-7.863293,-3.022674,-7.419384#614.559570,251.500000,0.000000,1.153367,11,-5.802108,7.468212,-7.951379#596.373047,199.000000,0.000000,1.053345,4,1.589040,2.324956,0.526632#596.373047,220.000000,0.000000,1.437710,8,3.826384,-4.029884,3.487882#596.373047,241.000000,0.000000,1.085851,3,4.912686,3.917787,5.660569#578.186523,209.500000,0.000000,1.100000,2,-5.776122,-4.926837,0.760138#578.186523,230.500000,0.000000,0.900000,5,-1.848043,-0.386153,6.410922#560.000000,220.000000,0.000000,1.000000,14,2.079596,7.069168,-7.283604#221.000000,220.000000,0.000000,0.990000,0,4.519086,0.074793,-2.054408"
                } else {
                    OpenPigeonLog.i("PoolPlus", "Generating 8 Ball+ rack with seed=$seed")
                    finalBalls = generateRandomRack(seed)
                }
            } else {
                finalBalls =
                    "#632.746155,178.000000,0.000000,0.801981,9,5.632916,7.415801,5.384167#632.746155,199.000000,0.000000,0.050000,10,-1.479509,5.981912,-0.639594#632.746155,220.000000,0.000000,0.145560,7,-4.857441,-3.796834,-5.439248#632.746155,241.000000,0.000000,0.050000,6,3.548234,-7.060621,-3.771457#632.746155,262.000000,0.000000,0.964504,1,7.809305,-4.673173,7.553514#614.559570,188.500000,0.000000,0.868768,12,6.889496,7.963203,-4.292648#614.559570,209.500000,0.000000,0.759525,13,4.140916,-0.562560,-5.371364#614.559570,230.500000,0.000000,0.839745,15,-7.863293,-3.022674,-7.419384#614.559570,251.500000,0.000000,1.153367,11,-5.802108,7.468212,-7.951379#596.373047,199.000000,0.000000,1.053345,4,1.589040,2.324956,0.526632#596.373047,220.000000,0.000000,1.437710,8,3.826384,-4.029884,3.487882#596.373047,241.000000,0.000000,1.085851,3,4.912686,3.917787,5.660569#578.186523,209.500000,0.000000,1.100000,2,-5.776122,-4.926837,0.760138#578.186523,230.500000,0.000000,0.900000,5,-1.848043,-0.386153,6.410922#560.000000,220.000000,0.000000,1.000000,14,2.079596,7.069168,-7.283604#221.000000,220.000000,0.000000,0.990000,0,4.519086,0.074793,-2.054408"
            }
            buildBalls(finalBalls, null)
            scratch = isNineBall || !isEightBallPlus

            if (pendingWinLossState.isNotBlank()) {
                markGameOver(pendingWinLossState)
                if (!renderer.isAlive) {
                    renderer.start()
                }
                return
            }

            mode = if (spectatorMode) {
                PoolMode.Disabled
            } else {
                PoolMode.Aiming
            }

            isFirst = true

            if (!renderer.isAlive) {
                renderer.start()
            }

            renderer.notifyWhenFrameReady {
                runOnUiThread {
                    if (spectatorMode) {
                        applySpectatorReadOnlyUi()
                    } else {
                        setCueUiVisible(true)
                        renderer.setCueVisible(true)
                    }

                    if (isNineBall) {
                        findViewById<SurfaceView>(R.id.surfaceView).post {
                            setDefaultNineBallBreakCueRotation()
                        }
                    }

                    val label = findViewById<TextView>(R.id.state_label)
                    label.visibility = View.GONE
                    hideSkipReplayButton("not_replaying")
                }
            }

            return
        }

        if (!renderer.isAlive) {
            renderer.start()
        }

        if (!isYourTurn) {
            runOnUiThread {
                hideSkipReplayButton("not_replaying")
                setCueUiVisible(false)

                when {
                    pendingWinLossState.isNotBlank() -> {
                        markGameOver(pendingWinLossState)
                    }

                    spectatorMode -> {
                        applySpectatorReadOnlyUi()
                    }

                    !sentWaitingSequenceActive -> {
                        showWaitingLabelAnimated()
                    }
                }
            }

            mode = PoolMode.Disabled
            closeCuePopup()
        } else {
            replaying = true

            runOnUiThread {
                setCueUiVisible(false)
                hideStateLabel()
            }

            renderer.notifyWhenFrameReady {
                showSkipReplayButton("handleMessage_before_playNextReplay")
                playNextReplay()
            }
        }
    }

    companion object {
        private const val TEXT_SENT = "Sent"
        private const val TEXT_SENT_CHECK = "Sent ✔"
        private const val TEXT_WAITING_BASE = "WAITING FOR OPPONENT"
        private const val TEXT_WAITING_ONE_DOT = "WAITING FOR OPPONENT."
        private const val TEXT_WAITING_FULL = "WAITING FOR OPPONENT..."
        private const val TEXT_CHOOSE_POCKET = "Choose a pocket"
        private const val TEXT_YOU_WIN = "You Win!"
        private const val TEXT_YOU_LOSE = "You Lose!"
        private const val TEXT_DRAW = "Draw!"
        private const val POOL_REPLAY_SHOT_TIMEOUT_MS = 12_000L
        private const val CUE_ROTATION_DRAG_GAIN = 0.5f

        private const val CUE_INERTIA_SMOOTHING = 0.65f
        private const val CUE_INERTIA_START_SPEED = 0.45f
        private const val CUE_INERTIA_STOP_SPEED = 0.035f
        private const val CUE_INERTIA_MAX_SPEED = 4.0f
        private const val CUE_INERTIA_DECAY_PER_SECOND = 12.0f

        init {
            System.loadLibrary("openbubblesextension")
        }
    }
}