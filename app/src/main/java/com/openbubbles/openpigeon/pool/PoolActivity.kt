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
import android.util.Log
import android.util.TypedValue
import com.openbubbles.openpigeon.settings.AvatarView
import android.widget.ImageButton
import androidx.appcompat.widget.SwitchCompat
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.View
import android.view.Window
import android.widget.Button
import java.util.Locale
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.animation.doOnEnd
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.SettingsSheet
import com.openbubbles.openpigeon.ui.RulesPopup
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GameSessionIPC
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.min
import kotlin.math.sqrt
import kotlin.math.max
import android.content.Context
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
import kotlin.random.Random

class PoolActivity : AppCompatActivity() {
    lateinit var sessionId: String
    var gameSessionIPC: GameSessionIPC? = null
    var baseGame = PoolGame()

    private lateinit var settingsSheet: SettingsSheet
    private var darkMode = false

    private var musicEnabled = false
    private var musicTrack: AudioTrack? = null
    private var currentMusicTrackPath: String? = null
    private fun currentPoolMusicTrack(): String {
        return if (isNineBall) {
            "pool/9ball.wav"
        } else {
            "pool/8ball.wav"
        }
    }

    var table: Long = 0L

    @Volatile var poolActivityClosing = false

    lateinit var renderer: PoolRenderer

    enum class PoolMode {
        Playing,
        Aiming,
        Disabled,
        ReplayAiming,
    }


    var mode = PoolMode.Disabled

    var lastAngle = 0f

    var touchDownCueX = 0f

    private var lastCueHapticStep = -1

    private val stateLabelHandler = Handler(Looper.getMainLooper())
    private var waitingDotsRunnable: Runnable? = null
    private var stateLabelAnimator: ValueAnimator? = null
    private var sentWaitingSequenceActive = false

    fun isPoolDarkModeEnabled(): Boolean {
        return darkMode
    }

    private fun applyDarkMode(enabled: Boolean) {
        darkMode = enabled

        getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("pool/dark_mode", enabled)
            .apply()

        val root = findViewById<FrameLayout>(R.id.poolRoot)
        val bgRes = if (enabled) {
            R.drawable.background_soft_depth_dark
        } else {
            R.drawable.background_soft_depth
        }

        root.setBackgroundResource(bgRes)
    }

    private data class WavLoopData(
        val pcm: ByteArray,
        val sampleRate: Int,
        val channelMask: Int,
        val encoding: Int,
        val frameCount: Int
    )

    private fun applyMusicEnabled(enabled: Boolean) {
        musicEnabled = enabled

        getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("pool/music_enabled", enabled)
            .apply()

        if (enabled) {
            startPoolMusic()
        } else {
            stopPoolMusic()
        }
    }

    private fun startPoolMusic() {
        if (!musicEnabled || poolActivityClosing || musicTrack != null) return

        playPoolMusicTrack()
    }

    private fun playPoolMusicTrack() {
        releasePoolMusicPlayer()

        if (!musicEnabled || poolActivityClosing) return

        val trackPath = currentPoolMusicTrack()
        currentMusicTrackPath = trackPath

        try {
            val wav = loadPcm16Wav(trackPath)

            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(wav.sampleRate)
                        .setChannelMask(wav.channelMask)
                        .setEncoding(wav.encoding)
                        .build()
                )
                .setBufferSizeInBytes(wav.pcm.size)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            track.write(wav.pcm, 0, wav.pcm.size)
            track.setLoopPoints(0, wav.frameCount, -1)
            track.setVolume(0.55f)

            musicTrack = track
            track.play()
        } catch (e: Exception) {
            Log.e("PoolMusic", "Unable to play music track $trackPath", e)

            musicEnabled = false
            currentMusicTrackPath = null

            getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
                .edit()
                .putBoolean("pool/music_enabled", false)
                .apply()
        }
    }

    private fun pausePoolMusic() {
        try {
            musicTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                }
            }
        } catch (e: Exception) {
            Log.w("PoolMusic", "Unable to pause music", e)
        }
    }

    private fun resumePoolMusic() {
        if (!musicEnabled || poolActivityClosing) return

        try {
            val track = musicTrack

            if (track == null) {
                startPoolMusic()
            } else if (track.playState != AudioTrack.PLAYSTATE_PLAYING) {
                track.play()
            }
        } catch (e: Exception) {
            Log.w("PoolMusic", "Unable to resume music, restarting", e)
            releasePoolMusicPlayer()
            startPoolMusic()
        }
    }

    private fun stopPoolMusic() {
        releasePoolMusicPlayer()
    }

    private fun releasePoolMusicPlayer() {
        val track = musicTrack ?: return
        musicTrack = null
        currentMusicTrackPath = null

        try {
            track.pause()
        } catch (_: Exception) {
        }

        track.release()
    }

    private fun restartPoolMusicForCurrentMode() {
        if (!musicEnabled) return

        val trackPath = currentPoolMusicTrack()
        if (musicTrack != null && currentMusicTrackPath == trackPath) return

        releasePoolMusicPlayer()
        startPoolMusic()
    }

    private fun loadPcm16Wav(path: String): WavLoopData {
        val bytes = assets.open(path).use { it.readBytes() }

        if (bytes.size < 44 || chunkName(bytes, 0) != "RIFF" || chunkName(bytes, 8) != "WAVE") {
            throw IllegalArgumentException("Invalid WAV file: $path")
        }

        var offset = 12
        var audioFormat = 0
        var channelCount = 0
        var sampleRate = 0
        var bitsPerSample = 0
        var dataStart = -1
        var dataSize = 0

        while (offset + 8 <= bytes.size) {
            val name = chunkName(bytes, offset)
            val size = readLeInt(bytes, offset + 4)
            val start = offset + 8

            if (start + size > bytes.size) break

            when (name) {
                "fmt " -> {
                    audioFormat = readLeShort(bytes, start)
                    channelCount = readLeShort(bytes, start + 2)
                    sampleRate = readLeInt(bytes, start + 4)
                    bitsPerSample = readLeShort(bytes, start + 14)
                }
                "data" -> {
                    dataStart = start
                    dataSize = size
                }
            }

            offset = start + size + (size and 1)
        }

        if (audioFormat != 1 || bitsPerSample != 16 || channelCount !in 1..2 || dataStart < 0 || dataSize <= 0) {
            throw IllegalArgumentException("WAV must be 16-bit PCM mono/stereo: $path")
        }

        val pcm = bytes.copyOfRange(dataStart, dataStart + dataSize)
        val frameSize = channelCount * 2
        val frameCount = pcm.size / frameSize
        val channelMask = if (channelCount == 1) {
            AudioFormat.CHANNEL_OUT_MONO
        } else {
            AudioFormat.CHANNEL_OUT_STEREO
        }

        return WavLoopData(
            pcm = pcm,
            sampleRate = sampleRate,
            channelMask = channelMask,
            encoding = AudioFormat.ENCODING_PCM_16BIT,
            frameCount = frameCount
        )
    }

    private fun readLeShort(bytes: ByteArray, offset: Int): Int {
        return (bytes[offset].toInt() and 0xff) or
                ((bytes[offset + 1].toInt() and 0xff) shl 8)
    }

    private fun readLeInt(bytes: ByteArray, offset: Int): Int {
        return (bytes[offset].toInt() and 0xff) or
                ((bytes[offset + 1].toInt() and 0xff) shl 8) or
                ((bytes[offset + 2].toInt() and 0xff) shl 16) or
                ((bytes[offset + 3].toInt() and 0xff) shl 24)
    }

    private fun chunkName(bytes: ByteArray, offset: Int): String {
        return String(
            byteArrayOf(
                bytes[offset],
                bytes[offset + 1],
                bytes[offset + 2],
                bytes[offset + 3]
            )
        )
    }

    private fun updateBallTypeUi() {
        runOnUiThread {
            val playerBall = findViewById<ImageView>(R.id.playerBallType)
            val oppBall    = findViewById<ImageView>(R.id.oppBallType)

            if (isNineBall) {
                playerBall.visibility = View.GONE
                oppBall.visibility = View.GONE
                return@runOnUiThread
            }

            playerBall.visibility = View.VISIBLE
            oppBall.visibility = View.VISIBLE

            when (iAmStripes) {
                null  -> {
                    playerBall.setImageResource(R.drawable.pool_ball_empty)
                    oppBall.setImageResource(R.drawable.pool_ball_empty)
                }
                true  -> {
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
                        setImageResource(PoolBall.ballOrder[number])
                        scaleType = ImageView.ScaleType.FIT_CENTER
                        layoutParams = LinearLayout.LayoutParams(
                            stateLabelDp(20f),
                            stateLabelDp(20f)
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
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }

        if (!vibrator.hasVibrator()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(12, 180))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(6)
        }
    }

    private fun stateLabelDp(value: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value,
            resources.displayMetrics
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

        val params = label.layoutParams
        params.width = FrameLayout.LayoutParams.WRAP_CONTENT
        label.layoutParams = params
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
    }

    private fun setStateLabelText(text: CharSequence, visible: Boolean = true) {
        stopStateLabelAnimation()

        val label = findViewById<TextView>(R.id.state_label)
        resetStateLabelLayout(label)
        label.text = text
        label.visibility = if (visible) View.VISIBLE else View.GONE
    }

    private fun startWaitingDots(label: TextView) {
        var dots = 1

        waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }

        val runnable = object : Runnable {
            override fun run() {
                if (waitingDotsRunnable !== this) return

                if (label.visibility == View.VISIBLE) {
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

            val label = findViewById<TextView>(R.id.state_label)
            resetStateLabelLayout(label)

            val waitingWidth = measureStateLabelWidth(label, "WAITING FOR OPPONENT...")
            val params = label.layoutParams
            params.width = waitingWidth
            label.layoutParams = params

            label.visibility = View.VISIBLE
            startWaitingDots(label)
        }
    }

    private fun playSentThenWaitingAnimation() {
        runOnUiThread {
            stopStateLabelAnimation()
            sentWaitingSequenceActive = true

            val label = findViewById<TextView>(R.id.state_label)
            resetStateLabelLayout(label)

            val sentWidth = measureStateLabelWidth(label, "Sent ✔")
            val waitingWidth = measureStateLabelWidth(label, "WAITING FOR OPPONENT...")

            val params = label.layoutParams
            params.width = sentWidth
            label.layoutParams = params

            label.text = "Sent"
            label.alpha = 0f
            label.setTextColor(0xFFFFFFFF.toInt())
            label.visibility = View.VISIBLE

            label.animate()
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
                label.text = sentCheck
            }, 1000L)

            stateLabelHandler.postDelayed({
                if (!sentWaitingSequenceActive) return@postDelayed

                val oldWidth = label.width.takeIf { it > 0 } ?: sentWidth

                val widthParams = label.layoutParams
                widthParams.width = oldWidth
                label.layoutParams = widthParams

                label.animate().cancel()
                label.alpha = 1f
                label.text = "WAITING FOR OPPONENT."
                label.setTextColor(0x00FFFFFF)

                stateLabelAnimator = ValueAnimator.ofInt(oldWidth, waitingWidth).apply {
                    duration = 420L
                    addUpdateListener { animation ->
                        val animatedParams = label.layoutParams
                        animatedParams.width = animation.animatedValue as Int
                        label.layoutParams = animatedParams
                    }
                    doOnEnd {
                        if (!sentWaitingSequenceActive) return@doOnEnd

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
                                if (sentWaitingSequenceActive) {
                                    label.setTextColor(0xFFFFFFFF.toInt())
                                    startWaitingDots(label)
                                }
                            }
                            start()
                        }
                    }
                    start()
                }
            }, 2000L)
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

                cueOverlay.animate()
                    .alpha(1f)
                    .setDuration(180L)
                    .start()

                cuePopup.animate()
                    .x(endX)
                    .y(endY)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(220L)
                    .withEndAction {
                        cuePopupAnimating = false
                    }
                    .start()
            }
        }
    }
    private fun closeCuePopup() {
        runOnUiThread {
            if (!cuePopupOpen || cuePopupAnimating) return@runOnUiThread

            val cueView = findViewById<FrameLayout>(R.id.cueView)
            val cueOverlay = findViewById<FrameLayout>(R.id.cueOverlay)
            val cuePopup = findViewById<FrameLayout>(R.id.cuePopup)

            cuePopupAnimating = true

            val sourceLoc = IntArray(2)
            val overlayLoc = IntArray(2)
            cueView.getLocationOnScreen(sourceLoc)
            cueOverlay.getLocationOnScreen(overlayLoc)

            val endX = (sourceLoc[0] - overlayLoc[0]).toFloat()
            val endY = (sourceLoc[1] - overlayLoc[1]).toFloat()

            val endScaleX = cueView.width.toFloat() / cuePopup.width.toFloat()
            val endScaleY = cueView.height.toFloat() / cuePopup.height.toFloat()

            cueOverlay.animate()
                .alpha(0f)
                .setDuration(180L)
                .start()

            cuePopup.animate()
                .x(endX)
                .y(endY)
                .scaleX(endScaleX)
                .scaleY(endScaleY)
                .setDuration(220L)
                .withEndAction {
                    cueOverlay.visibility = View.GONE
                    cuePopup.visibility = View.INVISIBLE
                    cuePopupAnimating = false
                    cuePopupOpen = false
                }
                .start()
        }
    }
    private fun updateCueSpinFromTouch(
        touchX: Float,
        touchY: Float,
        container: FrameLayout,
        dot: ImageView
    ) {
        if (dot.width == 0 || dot.height == 0 || container.width == 0 || container.height == 0) return

        val centerX = container.width / 2f
        val centerY = container.height / 2f
        val maxRadius = min(container.width, container.height) / 2f - max(dot.width, dot.height) / 2f

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

            val maxRadius = min(container.width, container.height) / 2f - max(dot.width, dot.height) / 2f
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
                    view.animate()
                        .alpha(1f)
                        .setDuration(180L)
                        .start()
                }
            } else {
                for (view in views) {
                    view.animate().cancel()
                    view.animate()
                        .alpha(0f)
                        .setDuration(180L)
                        .withEndAction {
                            if (view.alpha == 0f) {
                                view.visibility = View.INVISIBLE
                            }
                        }
                        .start()
                }
                closeCuePopup()
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

            @Suppress("DEPRECATION")
            val isRotated = when (windowManager.defaultDisplay.rotation) {
                android.view.Surface.ROTATION_90,
                android.view.Surface.ROTATION_180,
                android.view.Surface.ROTATION_270 -> true
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
                TypedValue.COMPLEX_UNIT_DIP,
                6f,
                resources.displayMetrics
            )

            val cueAimGap = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                50f,
                resources.displayMetrics
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
    val breakLineX = 205f

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestWindowFeature(Window.FEATURE_NO_TITLE)
        supportActionBar?.hide()

        table = createPoolTable()

        enableEdgeToEdge()
        setContentView(R.layout.activity_pool)
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(android.R.id.content)) { _, insets ->
            insets
        }

        applyStateLabelBackground(findViewById(R.id.state_label))

        AvatarData.init(applicationContext)

        val rootFrame = findViewById<FrameLayout>(android.R.id.content)
        settingsSheet = SettingsSheet(this, rootFrame)

        val settingsBtn = findViewById<ImageButton>(R.id.settingsButton)
        try {
            val bm = assets.open("global/settings.png")
                .use { BitmapFactory.decodeStream(it) }
            settingsBtn.setImageBitmap(bm)
        } catch (e: Exception) { e.printStackTrace() }

        // Build dark mode switch and register it as a game control
        val darkSwitch = SwitchCompat(this)
        darkSwitch.isChecked = getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
            .getBoolean("pool/dark_mode", false)
        darkSwitch.setOnCheckedChangeListener { _, checked -> applyDarkMode(checked) }
        applyDarkMode(darkSwitch.isChecked)

        settingsSheet.addGameControl("Dark Mode", darkSwitch)

        val musicSwitch = SwitchCompat(this)
        musicSwitch.isChecked = getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
            .getBoolean("pool/music_enabled", true)
        musicEnabled = musicSwitch.isChecked
        musicSwitch.setOnCheckedChangeListener { _, checked -> applyMusicEnabled(checked) }

        settingsSheet.addGameControl("Music", musicSwitch)

        val gameAvatarAnchor = findViewById<FrameLayout>(R.id.gameAvatarAnchor)
        settingsSheet.attachGameAvatar(gameAvatarAnchor)
        val oppAvatarAnchor = findViewById<FrameLayout>(R.id.oppAvatarAnchor)
        settingsSheet.attachOpponentAvatar(oppAvatarAnchor)
        settingsBtn.setOnClickListener { settingsSheet.open() }

        val rulesBtn = findViewById<ImageButton>(R.id.rulesButton)
        try {
            val bm = assets.open("global/rules.png")
                .use { BitmapFactory.decodeStream(it) }
            rulesBtn.setImageBitmap(bm)
        } catch (e: Exception) { e.printStackTrace() }

        rulesBtn.setOnClickListener {
            val root = findViewById<FrameLayout>(android.R.id.content)

            val title = when {
                isNineBall -> "9 Ball Rules"
                isEightBallPlus -> "8 Ball+ Rules"
                else -> "8 Ball Rules"
            }

            val sections = when {
                isNineBall -> listOf(
                    RulesPopup.Section(
                        "Objective",
                        "Pocket the 9-ball legally to win."
                    ),
                    RulesPopup.Section(
                        "Ball Order",
                        "• Balls are numbered 1–9.\n" +
                                "• You must always hit the lowest-numbered ball on the table first.\n" +
                                "• Other balls may be pocketed after the lowest ball is contacted."
                    ),
                    RulesPopup.Section(
                        "How to Play",
                        "• Aim the cue by rotating it around the cue ball.\n" +
                                "• Pull back the cue strip on the left to set your power.\n" +
                                "• Tap the cue dial on the right to set spin.\n" +
                                "• Release to shoot."
                    ),
                    RulesPopup.Section(
                        "Fouls (Scratch)",
                        "• Sinking the cue ball.\n" +
                                "• Not hitting any ball.\n" +
                                "• Hitting a ball other than the lowest-numbered ball first.\n" +
                                "On a foul, your opponent gets cue ball placement."
                    ),
                    RulesPopup.Section(
                        "Winning",
                        "Legally pocket the 9-ball to win. Pocketing the 9-ball on a foul does not win the game."
                    ),
                )

                isEightBallPlus -> listOf(
                    RulesPopup.Section(
                        "Objective",
                        "Be the first player to sink all your group of balls, then pocket the 8-ball to win."
                    ),
                    RulesPopup.Section(
                        "8 Ball+ Setup",
                        "8 Ball+ uses normal 8 Ball rules, but the balls are randomized across the table instead of starting in a standard rack."
                    ),
                    RulesPopup.Section(
                        "Ball Groups",
                        "• Solids: balls 1–7\n" +
                                "• Stripes: balls 9–15\n" +
                                "• Your group is decided by the first ball you legally pocket."
                    ),
                    RulesPopup.Section(
                        "How to Play",
                        "• Aim the cue by rotating it around the cue ball.\n" +
                                "• Pull back the cue strip on the left to set your power.\n" +
                                "• Tap the cue dial on the right to set spin.\n" +
                                "• Release to shoot."
                    ),
                    RulesPopup.Section(
                        "Fouls (Scratch)",
                        "• Hitting the wrong group first.\n" +
                                "• Sinking the cue ball.\n" +
                                "• Not hitting any ball.\n" +
                                "On a foul, your opponent gets cue ball placement."
                    ),
                    RulesPopup.Section(
                        "Winning",
                        "Sink the 8-ball after clearing all your group balls. " +
                                "Sinking the 8-ball early, or on a scratch, loses the game immediately."
                    ),
                )

                else -> listOf(
                    RulesPopup.Section(
                        "Objective",
                        "Be the first player to sink all your group of balls, then pocket the 8-ball to win."
                    ),
                    RulesPopup.Section(
                        "Ball Groups",
                        "• Solids: balls 1–7\n" +
                                "• Stripes: balls 9–15\n" +
                                "• Your group is decided by the first ball you legally pocket."
                    ),
                    RulesPopup.Section(
                        "How to Play",
                        "• Aim the cue by rotating it around the cue ball.\n" +
                                "• Pull back the cue strip on the left to set your power.\n" +
                                "• Tap the cue dial on the right to set spin.\n" +
                                "• Release to shoot."
                    ),
                    RulesPopup.Section(
                        "Fouls (Scratch)",
                        "• Hitting the wrong group first.\n" +
                                "• Sinking the cue ball.\n" +
                                "• Not hitting any ball.\n" +
                                "On a foul your opponent places the cue ball anywhere behind the break line."
                    ),
                    RulesPopup.Section(
                        "Winning",
                        "Sink the 8-ball after clearing all your group balls. " +
                                "Sinking the 8-ball early, or on a scratch, loses the game immediately."
                    ),
                )
            }

            RulesPopup.show(
                context = this,
                rootView = root,
                title = title,
                sections = sections
            )
        }

        val cueView = findViewById<FrameLayout>(R.id.cueView)
        val cueOverlay = findViewById<FrameLayout>(R.id.cueOverlay)
        val cuePopup = findViewById<FrameLayout>(R.id.cuePopup)
        val cuePopupDot = findViewById<ImageView>(R.id.cuePopupDot)

        cueView.setOnClickListener {
            openCuePopup()
        }

        cueOverlay.setOnClickListener {
            closeCuePopup()
        }

        cuePopup.setOnClickListener {
            // absorb inside clicks so overlay does not close
        }

        cuePopup.setOnTouchListener { _, event ->
            if (!cuePopupOpen || mode != PoolMode.Aiming) return@setOnTouchListener true

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN,
                MotionEvent.ACTION_MOVE,
                MotionEvent.ACTION_UP -> {
                    updateCueSpinFromTouch(event.x, event.y, cuePopup, cuePopupDot)
                }
            }

            true
        }

        val skipReplayButton = findViewById<ImageButton>(R.id.skip_replay)

        try {
            val normal = assets.open("global/next.png").use { BitmapFactory.decodeStream(it) }
            val pressed = assets.open("global/next_pressed.png").use { BitmapFactory.decodeStream(it) }

            skipReplayButton.setImageBitmap(normal)
            skipReplayButton.setBackgroundColor(android.graphics.Color.TRANSPARENT)
            skipReplayButton.scaleType = ImageView.ScaleType.FIT_CENTER

            skipReplayButton.setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        skipReplayButton.setImageBitmap(pressed)
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        skipReplayButton.setImageBitmap(normal)
                        synchronized(this@PoolActivity) {
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
        container.setOnTouchListener { v, event ->
            if (mode != PoolMode.Aiming) return@setOnTouchListener true

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
                    outgoingReplayHits.add(hit)
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

        view.setOnTouchListener { v, event ->
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

                when(event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        if (scratch && abs(points[0]) < 20 && abs(points[1]) < 20) {
                            draggingCue = true
                        }
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (draggingCue) {
                            val (moveX, moveY) = clampCueBallPosition(origPoints[0], origPoints[1])
                            for (ball in poolBalls) {
                                if (ball.number == 0) continue
                                val distX = ball.x - moveX
                                val distY = ball.y - moveY
                                val distance = sqrt(distX * distX + distY * distY)
                                if (distance < 20f) {
                                    // we overslap another ball, reject this move
                                    return@setOnTouchListener true
                                }
                            }
                            synchronized(this) {
                                moveBall(table, 0, moveX, moveY, 0f)
                            }
                        } else {
                            var diff = position - lastAngle
                            if (diff > PI) {
                                diff -= PI.toFloat() * 2
                            }
                            if (diff < -PI) {
                                diff += PI.toFloat() * 2
                            }
                            renderer.cueRot += diff * 0.5f
                        }
                    }
                    MotionEvent.ACTION_UP -> {
                        draggingCue = false
                    }
                }
                lastAngle = position
                // this is our direction vector
                Log.i("Point", "${points[0]} ${points[1]}")
            }
            true
        }

        findViewById<FrameLayout>(R.id.cueView).post {
            syncCueDots()
        }

        sessionId = intent.getStringExtra("SESSION")!!

        GameSessionIPC(applicationContext) { gameSessionIPC ->
            this.gameSessionIPC = gameSessionIPC
            val currentMessage = gameSessionIPC.getCurrentMessage(sessionId)
            if (currentMessage.isNotEmpty()) {
                gameSessionIPC.lockMsgHandle(sessionId)
                gameSessionIPC.setSuppressNotifications(sessionId, true)
                gameSessionIPC.onMessageUpdated(sessionId) {
                    Log.i("what", "sdf")
                    synchronized(this) {
                        handleMessage(it)
                    }
                }
                handleMessage(currentMessage)
            } else {
                Log.e("openpigeon-${baseGame.getName()}", "$sessionId does not exist!")
                finish()
            }
        }
    }

    override fun onDestroy() {
        poolActivityClosing = true
        disableSend = true
        skipReplayRequested = true
        mode = PoolMode.Disabled
        stopStateLabelAnimation()
        stopNineBallBarRefresh()
        stopPoolMusic()

        cancelAllShots()
        cancelAllShots = {}

        if (::renderer.isInitialized) {
            renderer.running = false
        }

        if (::settingsSheet.isInitialized) settingsSheet.detach()

        Log.i("Table", "Destroying")

        synchronized(this) {
            if (table != 0L) {
                val oldTable = table
                table = 0L
                destroyPoolTable(oldTable)
            }
        }

        super.onDestroy()
    }

    override fun onResume() {
        if (gameSessionIPC != null) {
            gameSessionIPC?.setSuppressNotifications(sessionId, true)

            if (replayWasSkipped) {
                replayWasSkipped = false
                val currentMessage = gameSessionIPC!!.getCurrentMessage(sessionId)
                if (currentMessage.isNotEmpty()) {
                    synchronized(this) {
                        handleMessage(currentMessage)
                    }
                }
            }
        } else {
            Log.w("openpigeon-${baseGame.getName()}", "onResume called before gameSessionIPC was initialized!")
        }
        resumePoolMusic()
        super.onResume()
    }

    override fun onPause() {
        pausePoolMusic()
        gameSessionIPC?.setSuppressNotifications(sessionId, false)
        super.onPause()
    }

    external fun createPoolTable(): Long
    external fun destroyPoolTable(table: Long)
    external fun makeBall(table: Long, x: Float, y: Float, rot: Float, density: Float, number: Int, shouldGoIn: Int, outputs: FloatBuffer)
    external fun hitBall(table: Long, number: Int, dir: Float, power: Float, spinX: Float, spinY: Float, first: Boolean)
    external fun moveBall(table: Long, number: Int, x: Float, y: Float, rot: Float)

    external fun clearBalls(table: Long)

    data class BallHit(val direction: Float, val power: Float, val spinX: Float, val spinY: Float, var wasStripes: Boolean?) {
        fun hit(activity: PoolActivity) {
            if (activity.poolActivityClosing || activity.table == 0L) {
                Log.w("PoolLifecycle", "Skipping hitBall because activity is closing or table is destroyed")
                return
            }

            if (!activity.replaying)
                activity.scratch = false

            activity.mode = PoolMode.Playing

            if (activity.isNineBall) {
                activity.startNineBallBarRefresh()
            }

            Log.i("Hitting ball", "Direction: $direction power: $power spinX: $spinX spinY: $spinY scratch: $wasStripes first ${activity.isFirst}")
            if (activity.isNineBall) {
                activity.nineBallTargetAtShot = activity.lowestNineBallNumber() ?: 9
            }
            activity.hitBall(activity.table, 0 /*white*/, direction, power, spinX, spinY, activity.isFirst)
            activity.wasFirst = activity.isFirst
            activity.isFirst = false
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

    fun animateShoot(power: Float, hit: BallHit) {
        var cancelled = false
        val animator = ValueAnimator.ofFloat(power, -100f)
        animator.duration = 100L
        animator.addUpdateListener { animation ->
            setCueDrawAmount(animation.animatedValue as Float)
        }
        animator.doOnEnd {
            synchronized(this@PoolActivity) {
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
        if (poolActivityClosing || table == 0L || skipReplayRequested || replayHits.isEmpty()) return
        mode = PoolMode.ReplayAiming
        if (!skipReplayFadeStarted) {
            skipReplayFadeStarted = true

            val controls = findViewById<LinearLayout>(R.id.controls)
            val skipBtn = findViewById<ImageButton>(R.id.skip_replay)

            runOnUiThread {
                controls.visibility = View.VISIBLE

                skipBtn.animate().cancel()
                skipBtn.alpha = 0f
                skipBtn.visibility = View.VISIBLE
                skipBtn.bringToFront()

                skipBtn.postDelayed({
                    if (replaying && !skipReplayRequested) {
                        skipBtn.animate()
                            .alpha(1f)
                            .setDuration(300L)
                            .start()
                    }
                }, 1000L)
            }
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
    var scratch = false

    fun lowestNineBallNumber(): Int? {
        return poolBalls
            .filter { !it.sunk && it.number in 1..9 }
            .minOfOrNull { it.number }
    }

    fun tableIsScratch(): Boolean {
        val cueBall = cueBall ?: return false

        if (isNineBall) {
            val scratch =
                cueBall.sunk ||
                        !cueBall.hitBall ||
                        cueBall.ballHit != nineBallTargetAtShot

            Log.i(
                "POOL9_DEBUG",
                "SCRATCH_CHECK cueBall.sunk=${cueBall.sunk} hitBall=${cueBall.hitBall} ballHit=${cueBall.ballHit} target=$nineBallTargetAtShot scratch=$scratch"
            )

            return scratch
        }

        var scratch = !cueBall.hitBall || cueBall.sunk

        if (cueBall.ballHit != -1) {
            val ballHit = poolBalls.find { it.number == cueBall.ballHit } ?: return scratch
            val stripes = iAmStripes
            val hasMoreBalls = stripes == null || poolBalls.count { !it.sunk && ((stripes && it.isStripe) || (!stripes && it.isSolid)) } != 0

            if (ballHit.number == 8 && !hasMoreBalls) {
                if (!cueBall.sunk) {
                    scratch = false
                }
            } else if (iAmStripes != null && ((!ballHit.isSolid && !iAmStripes!!) || (!ballHit.isStripe && iAmStripes!!))) {
                scratch = true
            }
        }

        Log.i(
            "POOL_DEBUG",
            "SCRATCH_CHECK cueBall.sunk=${cueBall.sunk} blackBall.sunk=${poolBalls.find { it.number == 8 }?.sunk} ballHit=${cueBall.ballHit} scratch=$scratch"
        )

        return scratch
    }
    var didIWin: Boolean? = null
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

        outgoingReplayHits.clear()
        replayHits.clear()

        runOnUiThread {
            val controls = findViewById<LinearLayout>(R.id.controls)
            controls.visibility = View.VISIBLE
            val skipBtn = findViewById<ImageButton>(R.id.skip_replay)
            skipBtn.visibility = View.GONE
            skipBtn.alpha = 1f
        }
        replaying = false
        skipReplayRequested = false
        skipReplayFadeStarted = false

        Log.i("Pool", "Scratch $scratch")

        clearBalls(table)
        val oldBalls = poolBalls
        poolBalls = arrayListOf()

        buildBalls(finalBalls, null)
        for (ball in poolBalls) {
            val old = oldBalls.find { it.number == ball.number } ?: continue

            if (isNineBall && old.sunk) {
                continue
            }

            ball.data.put(old.data)
        }

        updateNineBallBar()

        if (didIWin != null) {
            runOnUiThread {
                val label = findViewById<TextView>(R.id.state_label)
                label.visibility = View.VISIBLE
                stopStateLabelAnimation()
                if (didIWin!!) {
                    label.text = "You won!"
                } else {
                    label.text = "They won!"
                }
            }
            return
        }

        if (isNineBall) {
            updateNineBallBar()
            mode = PoolMode.Aiming
            runOnUiThread {
                setCueUiVisible(true)
                renderer.setCueVisible(true)
                setStateLabelText("", false)
            }
            return
        }

        val stripes = iAmStripes
        val hasMoreBalls = stripes == null || poolBalls.count { !it.sunk && ((stripes && it.isStripe) || (!stripes && it.isSolid)) } != 0
        if (!hasMoreBalls) {
            call8Ball = true
            mode = PoolMode.Aiming
            runOnUiThread {
                setCueUiVisible(true)
                renderer.setCueVisible(true)
                val label = findViewById<TextView>(R.id.state_label)
                label.visibility = View.VISIBLE
                stopStateLabelAnimation()
                label.text = "Choose a pocket"
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
        if (disableSend || skipReplayRequested) return
        cancelAllShots()
        cancelAllShots = {}
        if (replayHits.isNotEmpty()) {
            playNextReplay()
        } else if (replaying) {
            finishReplay()
        } else {
            val scratch = tableIsScratch()
            val cueBall = cueBall ?: return

            mode = PoolMode.Disabled
            closeCuePopup()

            var winState: Boolean? = null

            if (isNineBall) {
                val sunkNumberedBalls = poolBalls
                    .filter { it.sunk && it.number in 1..9 }
                    .sortedBy { it.sunkOrder }

                val nineBallSunk = sunkNumberedBalls.any { it.number == 9 }

                Log.i(
                    "POOL9_DEBUG",
                    "FINAL_STATE cueBall.sunk=${cueBall.sunk} nineBallSunk=$nineBallSunk scratch=$scratch target=$nineBallTargetAtShot sunk=${sunkNumberedBalls.map { it.number }}"
                )

                if (nineBallSunk) {
                    winState = !scratch
                }

                if (!scratch && winState == null && sunkNumberedBalls.isNotEmpty()) {
                    updateNineBallBar()
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

                Log.i(
                    "POOL_DEBUG",
                    "FINAL_STATE cueBall.sunk=${cueBall.sunk} blackBall.sunk=$blackBallSunk scratch=$scratch wasFirst=$wasFirst"
                )

                if (blackBallSunk) {
                    if (
                        wasFirst ||
                        iAmStripes == null ||
                        blackBall == null ||
                        poolBalls.count { !it.sunk && ((iAmStripes!! && it.isStripe) || (!iAmStripes!! && it.isSolid)) } != 0 ||
                        cueBall.sunk ||
                        calledPocket.isEmpty() ||
                        blackBall.holeX != calledPocket[0].toFloat() ||
                        blackBall.holeY != calledPocket[1].toFloat()
                    ) {
                        winState = false
                    } else {
                        winState = true
                    }
                }

                if (!scratch && winState == null) {
                    val sunkPlayableBalls = poolBalls
                        .filter { it.sunk && (it.isStripe || it.isSolid) }
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
                        val hasMoreBalls = stripes == null || poolBalls.count { !it.sunk && ((stripes && it.isStripe) || (!stripes && it.isSolid)) } != 0
                        if (!hasMoreBalls) {
                            call8Ball = true
                            mode = PoolMode.Aiming
                            runOnUiThread {
                                val label = findViewById<TextView>(R.id.state_label)
                                label.visibility = View.VISIBLE
                                label.text = "Choose a pocket"
                            }
                            return
                        }

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
            Log.i("sending replay", "here")
            var replays = outgoingReplayHits.mapIndexed { index, hit ->
                val wasStripes = if (hit.wasStripes == null) 0 else if (hit.wasStripes!!) player else if (player == 1) 2 else 1
                val replay = "&d:${hit.direction}&x:${hit.spinX}&y:${hit.spinY}&p:${hit.power}&s:$wasStripes"
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
                runOnUiThread {
                    val label = findViewById<TextView>(R.id.state_label)
                    label.visibility = View.VISIBLE
                    if (winState) {
                        label.text = "You won!"
                    } else {
                        label.text = "They won!"
                    }
                }
            }

            val currentMessage = gameSessionIPC!!.getCurrentMessage(sessionId)
            val myId      = gameSessionIPC!!.getSenderUUID(sessionId)
            val myAvatarKey = if (player == 1) "avatar1" else "avatar2"

            val msgUpdates = mapOf(
                "player"      to if (currentMessage["player"] == "2") "1" else "2",
                "num"         to (currentMessage["num"]?.toInt()!! + 1).toString(),
                "sender"      to myId,
                "replay"      to replays,
                myAvatarKey   to AvatarView.buildAvatarString(),
            ).toMutableMap()

            if (winState != null) {
                msgUpdates["winner"] = "${gameSessionIPC!!.getSenderUUID(sessionId)}|${if (winState) "1" else "-1"}"
            }

            gameSessionIPC!!.updateSession(msgUpdates, sessionId) {
                Log.i("openpigeon-${baseGame.getName()}", "Game session updated")

                if (winState == null) {
                    runOnUiThread {
                        setCueUiVisible(false)
                        playSentThenWaitingAnimation()
                    }
                }
            }
        }
    }
    var iAmStripes: Boolean? = null

    data class PoolBall(val number: Int, val data: FloatBuffer, val resources: Resources, val density: Float) {
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
        }

        val bitmap: Bitmap = BitmapFactory.decodeResource(resources, ballOrder[number])

        val x: Float
            get() = data.get(0)
        val y: Float
            get() = data.get(1)
        val rot: Float
            get() = data.get(2)

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

        fun draw(canvas: Canvas) {
            canvas.save()
            canvas.translate(x, y)
            canvas.rotate(Math.toDegrees(rot.toDouble()).toFloat())
            canvas.drawBitmap(bitmap, null, RectF(-10.0f, -10.0f, 10.0f, 10.0f), null)
            canvas.restore()
        }
    }

    var poolBalls = arrayListOf<PoolBall>()
    val replayHits = arrayListOf<BallHit>()
    val outgoingReplayHits = arrayListOf<BallHit>()

    private var finalBalls = ""

    private val nineBallFrontBallX = 560.000000f
    private val nineBallFrontBallY = 220.000000f
    private val nineBallCueBallX = 205.000000f
    private val nineBallCueBallMinY = 110.000000
    private val nineBallCueBallMaxY = 330.000000

    private fun buildDefaultNineBallRack(): String {
        val cueY = Random.nextDouble(nineBallCueBallMinY, nineBallCueBallMaxY)

        return "#632.746155,220.000000,0.000000,0.716767,5,6.796000,-0.621908,3.502472" +
                "#614.559570,209.500000,0.000000,0.863119,8,5.764651,3.187424,7.145291" +
                "#614.559570,230.500000,0.000000,0.666108,6,-0.455535,7.249262,-1.390415" +
                "#596.373047,199.000000,0.000000,0.907943,7,-6.769609,1.087264,-3.765822" +
                "#596.373047,220.000000,0.000000,1.264982,9,6.340362,-4.153222,-7.661037" +
                "#596.373047,241.000000,0.000000,1.046328,4,-6.964514,-7.698694,-1.881179" +
                "#578.186523,209.500000,0.000000,0.406139,2,4.660657,-4.275956,3.727190" +
                "#578.186523,230.500000,0.000000,1.083360,3,-3.806327,-4.462822,0.955941" +
                "#560.000000,220.000000,0.000000,1.000000,1,7.747318,6.809052,1.118692" +
                String.format(
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

        Log.i(
            "POOL9_DEBUG",
            "DEFAULT_BREAK_AIM cue=(${cue.x},${cue.y}) front=($nineBallFrontBallX,$nineBallFrontBallY) dx=$dx dy=$dy cueRot=${renderer.cueRot}"
        )
    }

    private fun exportBalls(centerScratch: Boolean): String {
        return poolBalls.filter {
            !it.sunk ||
                    (centerScratch && it.number == 0) ||
                    (isNineBall && centerScratch && it.number in 1..9)
        }.map {
            val density = if (isFirst) it.density else 1

            if (centerScratch && it.number == 0) {
                Log.i("White", "scratching")
                return@map "#392.000000,220.000000,0.000000,$density,0,5.632916,7.415801,5.384167"
            }

            if (isNineBall && centerScratch && it.sunk && it.number in 1..9) {
                Log.i("POOL9_DEBUG", "Respotted fouled pocketed ball ${it.number}")
                return@map "#560.000000,220.000000,0.000000,1.000000,${it.number},5.632916,7.415801,5.384167"
            }

            "#${it.x},${it.y},${it.rot},$density,${it.number},5.632916,7.415801,5.384167"
        }.joinToString("")
    }

    private fun generateRandomRack(seed: Int): String {
        val rng = Drand48()

        data class Slot(val x: Float, val y: Float)

        val slots = mutableListOf<Slot>()
        val maxAttempts = 10_000
        var attempts = 0

        while (slots.size < 30 && attempts < maxAttempts) {
            attempts++

            val rx = rng.drand48()
            val ry = rng.drand48()

            val x = String.format(
                Locale.US,
                "%f",
                rx * (cueBallMaxX - cueBallMinX).toDouble() + cueBallMinX
            ).toFloat()

            val y = String.format(
                Locale.US,
                "%f",
                ry * (cueBallMaxY - cueBallMinY).toDouble() + cueBallMinY
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

        Log.i("PoolPlus", "Generated ${slots.size} slots for seed=$seed after $attempts attempts")

        if (slots.size < 30) {
            Log.e("PoolPlus", "Failed to generate 30 slots after $attempts attempts; got ${slots.size}")
        }

        val ballsLeft = mutableListOf(
            1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15,
            1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15
        )

        val builder = StringBuilder()

        for (i in 0 until slots.size) {
            rng.srand48(seed.toLong())

            val x = slots[i].x
            val y = slots[i].y

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

    private fun buildBalls(balls: String, skew: String?) {
        data class FinalBall(val number: Int, val x: Float, val y: Float)

        val finalBalls: MutableList<FinalBall>? = skew?.let {
            val result = mutableListOf<FinalBall>()

            for (finalBall in it.split("#")) {
                if (finalBall == "")
                    continue

                val details = finalBall.split(",")
                if (details.size < 5)
                    continue

                result.add(
                    FinalBall(
                        details[4].toInt(),
                        details[0].toFloat(),
                        details[1].toFloat()
                    )
                )
            }

            result
        }

        for (ball in balls.split("#")) {
            if (ball == "")
                continue

            val details = ball.split(",")
            if (details.size < 5)
                continue

            val x = details[0].toFloat()
            val y = details[1].toFloat()
            val rot = details[2].toFloat()
            val density = details[3].toFloat()
            val number = details[4].toInt()

            val buffer = ByteBuffer.allocateDirect(4 /*f32*/ * 7)
            buffer.order(ByteOrder.nativeOrder())

            val floatBuffer = buffer.asFloatBuffer()

            val shouldGoInMode = if (finalBalls == null) {
                0
            } else {
                var bestIndex = -1
                var bestDist = Float.POSITIVE_INFINITY

                for (i in finalBalls.indices) {
                    val finalBall = finalBalls[i]
                    if (finalBall.number != number)
                        continue

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

            Log.i(
                "ReplayBallMode",
                "number=$number shouldGoInMode=$shouldGoInMode x=$x y=$y remainingFinalMatches=${finalBalls?.count { it.number == number } ?: -1}"
            )

            Log.i("Making ball", "x: $x y: $y rot: $rot density: $density number: $number")

            makeBall(
                table,
                x,
                y,
                rot,
                density,
                number,
                shouldGoInMode,
                floatBuffer
            )

            floatBuffer.put(3, -1f)
            floatBuffer.put(4, -1f)

            val poolBall = PoolBall(number, floatBuffer, resources, density)
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
        if (table == 0L) return; // we are dead
        disableSend = false
        skipReplayRequested = false
        replaying = false
        skipReplayFadeStarted = false
        cancelAllShots()
        cancelAllShots = {}
        didIWin = null
        call8Ball = false
        clearBalls(table)
        poolBalls.clear()
        cueBall = null
        replayHits.clear()
        val gameName = msg["game"] ?: msg["name"] ?: msg["gameName"] ?: baseGame.getName()
        isNineBall = gameName == "pool2"
        isEightBallPlus = gameName == "pool3"
        if (isNineBall) {
            iAmStripes = null
            updateBallTypeUi()
        }

        restartPoolMusicForCurrentMode()

        Log.i("PoolMode", "gameName=$gameName isNineBall=$isNineBall isEightBallPlus=$isEightBallPlus")
        isHard = msg["mode"]!! != "n"

        renderer.bitmap = BitmapFactory.decodeResource(
            resources,
            when {
                isEightBallPlus && isHard -> R.drawable.pool_transparent_plus_hard
                isEightBallPlus -> R.drawable.pool_transparent_plus
                isHard -> R.drawable.pool_transparent_hard
                else -> R.drawable.pool_transparent
            }
        )

        val num = msg["num"]!!
        uuid1 = msg["player1"]
        uuid2 = msg["player2"]

        player = resolveMyPlayerSlot(msg)

        val oppAvatarKey = if (player == 1) "avatar2" else "avatar1"
        msg[oppAvatarKey]?.takeIf { it.isNotBlank() }?.let { avatarStr ->
            runOnUiThread { settingsSheet.applyOpponentAvatarString(avatarStr) }
        }

        Log.i("number", "$num")
        if (num == "2") {
            isFirst = true // for replay
        }

        scratch = false

        runOnUiThread {
            val label = findViewById<TextView>(R.id.state_label)
            label.visibility = View.VISIBLE
        }

        val isYourTurn = msg["sender"]!! != gameSessionIPC!!.getSenderUUID(sessionId)
        var stagingBalls: String? = null
        if (msg.containsKey("replay")) {
            val replay = msg["replay"]!!
            for ((index, value) in replay.split("|").withIndex()) {
                val output = mutableMapOf<String, String>()
                for (element in value.split("&")) {
                    val parts = element.split(":")
                    if (parts[0] == "")
                        continue // JSON will BLOW Vitalii Zlotskii's MIND
                    output[parts[0]] = parts[1]
                }

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
                    val stripes = output["stripes"]!!.toInt()
                    iAmStripes = if(stripes == 0) null else player == stripes
                    updateBallTypeUi()
                    Log.i("Me", "$iAmStripes")
                }

                if (output["move"] != null) {
                    scratch = output["move"] == "1"
                }

                if (output["win"] != null) {
                    val win = output["win"]!!.toInt()
                    didIWin = if (!isYourTurn) win == 1 else win != 1
                }

                if (output["d"] != null) {
                    replayHits.add(
                        BallHit(
                            output["d"]!!.toFloat(),
                            output["p"]!!.toFloat(),
                            output["x"]!!.toFloat(),
                            output["y"]!!.toFloat(),
                            output["s"]?.toIntOrNull()?.let { stripes ->
                                if (stripes == 0) null else player == stripes
                            }
                        )
                    )
                }
            }
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
                    findViewById<ImageButton>(R.id.skip_replay).visibility = View.GONE
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
                val seed = seedStr?.toIntOrNull()
                if (seed == null) {
                    Log.e("PoolPlus", "pool3 game without valid seed (got '$seedStr'); falling back to normal rack")
                    finalBalls = "#632.746155,178.000000,0.000000,0.801981,9,5.632916,7.415801,5.384167#632.746155,199.000000,0.000000,0.050000,10,-1.479509,5.981912,-0.639594#632.746155,220.000000,0.000000,0.145560,7,-4.857441,-3.796834,-5.439248#632.746155,241.000000,0.000000,0.050000,6,3.548234,-7.060621,-3.771457#632.746155,262.000000,0.000000,0.964504,1,7.809305,-4.673173,7.553514#614.559570,188.500000,0.000000,0.868768,12,6.889496,7.963203,-4.292648#614.559570,209.500000,0.000000,0.759525,13,4.140916,-0.562560,-5.371364#614.559570,230.500000,0.000000,0.839745,15,-7.863293,-3.022674,-7.419384#614.559570,251.500000,0.000000,1.153367,11,-5.802108,7.468212,-7.951379#596.373047,199.000000,0.000000,1.053345,4,1.589040,2.324956,0.526632#596.373047,220.000000,0.000000,1.437710,8,3.826384,-4.029884,3.487882#596.373047,241.000000,0.000000,1.085851,3,4.912686,3.917787,5.660569#578.186523,209.500000,0.000000,1.100000,2,-5.776122,-4.926837,0.760138#578.186523,230.500000,0.000000,0.900000,5,-1.848043,-0.386153,6.410922#560.000000,220.000000,0.000000,1.000000,14,2.079596,7.069168,-7.283604#205.000000,220.000000,0.000000,0.990000,0,4.519086,0.074793,-2.054408"
                } else {
                    Log.i("PoolPlus", "Generating 8 Ball+ rack with seed=$seed")
                    finalBalls = generateRandomRack(seed)
                }
            } else {
                finalBalls = "#632.746155,178.000000,0.000000,0.801981,9,5.632916,7.415801,5.384167#632.746155,199.000000,0.000000,0.050000,10,-1.479509,5.981912,-0.639594#632.746155,220.000000,0.000000,0.145560,7,-4.857441,-3.796834,-5.439248#632.746155,241.000000,0.000000,0.050000,6,3.548234,-7.060621,-3.771457#632.746155,262.000000,0.000000,0.964504,1,7.809305,-4.673173,7.553514#614.559570,188.500000,0.000000,0.868768,12,6.889496,7.963203,-4.292648#614.559570,209.500000,0.000000,0.759525,13,4.140916,-0.562560,-5.371364#614.559570,230.500000,0.000000,0.839745,15,-7.863293,-3.022674,-7.419384#614.559570,251.500000,0.000000,1.153367,11,-5.802108,7.468212,-7.951379#596.373047,199.000000,0.000000,1.053345,4,1.589040,2.324956,0.526632#596.373047,220.000000,0.000000,1.437710,8,3.826384,-4.029884,3.487882#596.373047,241.000000,0.000000,1.085851,3,4.912686,3.917787,5.660569#578.186523,209.500000,0.000000,1.100000,2,-5.776122,-4.926837,0.760138#578.186523,230.500000,0.000000,0.900000,5,-1.848043,-0.386153,6.410922#560.000000,220.000000,0.000000,1.000000,14,2.079596,7.069168,-7.283604#205.000000,220.000000,0.000000,0.990000,0,4.519086,0.074793,-2.054408"
            }
            buildBalls(finalBalls, null)
            scratch = isNineBall || !isEightBallPlus

            mode = PoolMode.Aiming
            isFirst = true

            runOnUiThread {
                setCueUiVisible(true)
                renderer.setCueVisible(true)

                if (isNineBall) {
                    findViewById<SurfaceView>(R.id.surfaceView).post {
                        setDefaultNineBallBreakCueRotation()
                    }
                }

                val label = findViewById<TextView>(R.id.state_label)
                label.visibility = View.GONE
                findViewById<ImageButton>(R.id.skip_replay).visibility = View.GONE
            }

            if (!renderer.isAlive) {
                renderer.start()
            }

            return
        }

        if (!renderer.isAlive) {
            renderer.start()
        }

        if (!isYourTurn) {
            runOnUiThread {
                findViewById<ImageButton>(R.id.skip_replay).visibility = View.GONE
                setCueUiVisible(false)

                if (didIWin != null) {
                    setStateLabelText(if (didIWin!!) "You won!" else "They won!")
                } else if (!sentWaitingSequenceActive) {
                    showWaitingLabelAnimated()
                }
            }
            mode = PoolMode.Disabled
            closeCuePopup()
        } else {
            runOnUiThread {
                setCueUiVisible(false)
                setStateLabelText("", false)
                val controls = findViewById<LinearLayout>(R.id.controls)
                controls.visibility = View.VISIBLE
                val skipBtn = findViewById<ImageButton>(R.id.skip_replay)
                skipBtn.animate().cancel()
                skipBtn.visibility = View.INVISIBLE
                skipBtn.alpha = 0f
            }

            replaying = true
            playNextReplay()
        }
    }

    companion object {
        init {
            System.loadLibrary("openbubblesextension")
        }
    }
}