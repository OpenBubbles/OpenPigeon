package com.openbubbles.openpigeon.knockout

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.View
import android.view.Window
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.SwitchCompat
import androidx.core.view.ViewCompat
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GameSessionIPC
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.settings.SettingsSheet
import com.openbubbles.openpigeon.util.OpenPigeonLog
import java.nio.FloatBuffer
import android.view.animation.OvershootInterpolator
import android.os.Handler
import android.os.Looper
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.util.TypedValue
import kotlin.math.ceil
import android.widget.ImageView
import kotlin.math.PI
import android.os.Build
import android.view.ViewOutlineProvider
import android.view.ViewGroup
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack

class KnockoutActivity : AppCompatActivity() {
    enum class Mode { Disabled, Aiming, Playing }
    private enum class PlaySource { None, AutoReplay, LocalLaunch }

    lateinit var sessionId: String
    var gameSessionIPC: GameSessionIPC? = null
    private lateinit var settingsSheet: SettingsSheet

    var table: Long = 0L
    var closing = false
    @Volatile var mode = Mode.Disabled
    var player = 1
    var myPlayerId = ""
    var player1Id = ""
    var player2Id = ""
    var mapMode = 1
    var boardIndex = 0
    @Volatile var visualBoardIndex = 0f
    var darkMode = false

    private var musicEnabled = false
    private var musicTrack: AudioTrack? = null
    private var currentMusicTrackPath: String? = null

    val pieces = mutableListOf<KnockoutPiece>()
    lateinit var renderer: KnockoutRenderer
    private var waterView: KnockoutWaterView? = null

    private var selectedPiece: KnockoutPiece? = null
    val selectedAimPiece: KnockoutPiece?
        get() = selectedPiece
    private var p1Bitmap: Bitmap? = null
    private var p2Bitmap: Bitmap? = null
    private var lastMessage: Map<String, String> = emptyMap()

    private var pendingTokens = mutableListOf<KnockoutReplayToken>()
    private var currentBoard: KnockoutBoard? = null
    private var playSource = PlaySource.None
    private var localOutgoingTokens = mutableListOf<KnockoutReplayToken>()
    private var shrinkAnimator: ValueAnimator? = null

    private var introPopupDismissed = false
    @Volatile private var gateAimingForIntro = false
    @Volatile private var launchButtonVisible = false
    @Volatile var showAllReplayArrows = false
    @Volatile var replayArrowAlpha = 1f
    @Volatile private var lastPlacementWidth = -1
    @Volatile private var lastPlacementHeight = -1
    @Volatile private var lastPlacementLaunchVisible = false
    @Volatile private var lastPlacementHintVisible = false
    @Volatile private var gameEnded = false
    @Volatile private var winLossState = ""
    @Volatile private var pendingReplayWinLossState = ""
    @Volatile private var initialGameDataApplied = false
    @Volatile private var gameShownToPlayer = false

    private var statusDimView: View? = null
    @Volatile private var statusDimVisible = false

    private val stateLabelHandler = Handler(Looper.getMainLooper())
    private val playHandler = Handler(Looper.getMainLooper())

    private var waitingDotsRunnable: Runnable? = null
    private var stateLabelAnimator: ValueAnimator? = null
    private var sentWaitingSequenceActive = false
    private var replayArrowAnimator: ValueAnimator? = null

    private var lastOutgoingReplay: String? = null
    private var ignoreNextOutgoingReplayEcho = false
    @Volatile private var powerHintVisible = false

    private enum class StateLabelVisual { Hidden, Waiting, SentWaiting, GameOver }
    private var stateLabelVisual = StateLabelVisual.Hidden

    external fun createKnockoutTable(): Long
    external fun destroyKnockoutTable(table: Long)
    external fun clearKnockoutPieces(table: Long)
    external fun makeKnockoutPiece(table: Long, x: Float, y: Float, angle: Float, traceId: Int, player: Int, outputs: FloatBuffer)
    external fun fireKnockoutPiece(table: Long, traceId: Int, shootDirRadians: Float, power: Float)
    external fun moveKnockoutPiece(table: Long, traceId: Int, x: Float, y: Float, angle: Float)
    external fun setKnockoutMap(table: Long, mapMode: Int, boardScale: Float)
    external fun consumeKnockoutMushroomHits(table: Long): Int

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        supportActionBar?.hide()
        enableEdgeToEdge()
        setContentView(R.layout.activity_knockout)
        findViewById<FrameLayout>(R.id.knockoutRoot)?.apply {
            alpha = 0f
            visibility = View.VISIBLE
        }
        applyStateLabelBackground(findViewById(R.id.knockoutStateLabel))
        hideStateLabel()
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(android.R.id.content)) { _, insets -> insets }

        AvatarData.init(applicationContext)
        table = createKnockoutTable()
        p1Bitmap = loadAssetBitmap("knockout/bw_penguin.png")
        p2Bitmap = loadAssetBitmap("knockout/gw_penguin.png")

        ensureIntroPopup()

        val surface = findViewById<SurfaceView>(R.id.knockoutSurface)
        surface.setZOrderMediaOverlay(true)
        surface.holder.setFormat(android.graphics.PixelFormat.TRANSLUCENT)
        renderer = KnockoutRenderer(surface.holder, this)

        val rootFrame = findViewById<FrameLayout>(R.id.knockoutRoot)
        waterView = KnockoutWaterView(this).apply {
            setWaterTexture("knockout/water.png")
        }
        rootFrame.addView(
            waterView, 0,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        waterView?.visibility = if (darkMode) View.GONE else View.VISIBLE
        settingsSheet = SettingsSheet(this, rootFrame)
        settingsSheet.attachGameAvatar(findViewById(R.id.knockoutGameAvatarAnchor))
        settingsSheet.attachOpponentAvatar(findViewById(R.id.knockoutOpponentAvatarAnchor))
        updateAvatarHud()
        val darkSwitch = SwitchCompat(this)
        darkSwitch.isChecked = getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
            .getBoolean("knockout/dark_mode", false)
        darkMode = darkSwitch.isChecked
        darkSwitch.setOnCheckedChangeListener { _, checked ->
            darkMode = checked
            getSharedPreferences("avatar_settings", Context.MODE_PRIVATE).edit()
                .putBoolean("knockout/dark_mode", checked)
                .apply()
            waterView?.visibility = if (checked) View.GONE else View.VISIBLE
        }
        settingsSheet.addGameControl("Dark Mode", darkSwitch)

        val musicSwitch = SwitchCompat(this)
        musicSwitch.isChecked = getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
            .getBoolean("global/music_enabled", true)

        musicEnabled = musicSwitch.isChecked
        musicSwitch.setOnCheckedChangeListener { _, checked ->
            applyMusicEnabled(checked)
        }

        settingsSheet.addGameControl("Music", musicSwitch)

        if (musicEnabled) {
            startMusic()
        }

        applyMapButtonColors()
        stylePowerHint(findViewById(R.id.knockoutPowerHintLabel))

        val settingsBtn = findViewById<ImageButton>(R.id.knockoutSettingsButton)
        settingsBtn?.apply {
            visibility = View.VISIBLE
            alpha = 0.8f
            scaleType = ImageView.ScaleType.FIT_CENTER
            background = null
            setPadding(dp(6f).toInt(), dp(6f).toInt(), dp(6f).toInt(), dp(6f).toInt())

            val settingsBitmap = loadAssetBitmap("global/settings.png")
            if (settingsBitmap != null) {
                setImageBitmap(settingsBitmap)
            } else {
                OpenPigeonLog.w("KnockoutNative", "Missing asset: global/settings.png")
            }

            setOnClickListener {
                settingsSheet.open()
            }
            bringToFront()
        }
        findViewById<Button>(R.id.knockoutLaunchButton)?.setOnClickListener { launchCurrentAims() }
        findViewById<Button>(R.id.knockoutIntroButton)?.setOnClickListener { dismissIntroPopupAndEnableAiming() }
        surface.setOnTouchListener { _, event -> handleTouch(event) }

        sessionId = intent.getStringExtra("SESSION") ?: ""
        GameSessionIPC(applicationContext) { ipc ->
            gameSessionIPC = ipc
            val currentMessage = if (sessionId.isNotEmpty()) ipc.getCurrentMessage(sessionId) else emptyMap()
            if (currentMessage.isNotEmpty()) {
                ipc.lockMsgHandle(sessionId)
                ipc.setSuppressNotifications(sessionId, true)
                ipc.onMessageUpdated(sessionId) { msg ->
                    runOnUiThread {
                        synchronized(this) {
                            handleMessage(msg)
                        }
                    }
                }
                synchronized(this) { handleMessage(currentMessage) }
            } else {
                synchronized(this) {
                    handleMessage(mapOf("replay" to KnockoutReplayParser.emptyDefault(), "isYourTurn" to "true", "player" to "1"))
                }
            }
        }
        playHandler.postDelayed({
            synchronized(this) {
                if (!gameShownToPlayer && !closing && (currentBoard != null || pieces.isNotEmpty())) {
                    OpenPigeonLog.w(
                        "KnockoutNative",
                        "Fallback reveal triggered. initialGameDataApplied=$initialGameDataApplied " +
                                "currentBoard=${currentBoard != null} pieces=${pieces.size}"
                    )

                    markInitialGameDataApplied()
                }
            }
        }, 1200L)
    }

    private data class WavLoopData(
        val pcm: ByteArray,
        val sampleRate: Int,
        val channelMask: Int,
        val encoding: Int,
        val frameCount: Int
    )

    private fun currentMusicTrack(): String {
        return "knockout/knockout.wav"
    }

    private fun applyMusicEnabled(enabled: Boolean) {
        musicEnabled = enabled

        getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("global/music_enabled", enabled)
            .apply()

        if (enabled) {
            startMusic()
        } else {
            stopMusic()
        }
    }

    private fun startMusic() {
        if (!musicEnabled || closing || musicTrack != null) return
        playMusicTrack()
    }

    private fun playMusicTrack() {
        releaseMusicPlayer()

        if (!musicEnabled || closing) return

        val trackPath = currentMusicTrack()
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
            OpenPigeonLog.e("Music", "Unable to play music track $trackPath", e)

            musicEnabled = false
            currentMusicTrackPath = null

            getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
                .edit()
                .putBoolean("global/music_enabled", false)
                .apply()
        }
    }

    private fun pauseMusic() {
        try {
            musicTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                }
            }
        } catch (e: Exception) {
            OpenPigeonLog.w("Music", "Unable to pause music", e)
        }
    }

    private fun resumeMusic() {
        if (!musicEnabled || closing) return

        try {
            val track = musicTrack

            if (track == null) {
                startMusic()
            } else if (track.playState != AudioTrack.PLAYSTATE_PLAYING) {
                track.play()
            }
        } catch (e: Exception) {
            OpenPigeonLog.w("Music", "Unable to resume music, restarting", e)
            releaseMusicPlayer()
            startMusic()
        }
    }

    private fun stopMusic() {
        releaseMusicPlayer()
    }

    private fun releaseMusicPlayer() {
        val track = musicTrack ?: return
        musicTrack = null
        currentMusicTrackPath = null

        try {
            track.pause()
        } catch (_: Exception) {
        }

        track.release()
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

    private fun handleMessage(msg: Map<String, String>) {
        if (mode == Mode.Playing && msg["winner"].isNullOrBlank()) {
            OpenPigeonLog.w(
                "KnockoutNative",
                "Ignoring message update while native replay is playing"
            )
            return
        }

        lastMessage = msg
        logIncomingGameData(msg)
        OpenPigeonLog.i(
            "KnockoutNative",
            "handleMessage replayLen=${msg["replay"]?.length ?: 0} turn=${msg["isYourTurn"]}"
        )

        mapMode = msg["map"]?.toIntOrNull() ?: msg["mode"]?.toIntOrNull() ?: mapMode
        applyWaterTintForMap()
        applyMapButtonColors()
        syncNativeMap()
        player1Id = msg["player1"] ?: player1Id
        player2Id = msg["player2"] ?: player2Id
        myPlayerId = localUserId(msg)
        player = resolvePlayer(msg)
        applyOpponentAvatarFromMessage(msg)
        updateAvatarHud()

        val incomingWinner = applyIncomingWinner(msg)

        gateAimingForIntro = shouldShowIntroPopupFor(msg) && !introPopupDismissed

        val replay = msg["replay"]?.takeIf { it.isNotBlank() }

        if (replay == null) {
            OpenPigeonLog.w(
                "KnockoutNative",
                "Ignoring message without replay. Keeping currentBoard=${currentBoard != null}"
            )

            currentBoard?.let { setModeForBoard(it) }
            markInitialGameDataApplied()
            return
        }

        if (ignoreNextOutgoingReplayEcho && replay == lastOutgoingReplay) {
            ignoreNextOutgoingReplayEcho = false

            OpenPigeonLog.i(
                "KnockoutNative",
                "Ignoring own outgoing replay echo so we do not replay the round we just sent"
            )

            markInitialGameDataApplied()
            return
        }

        val parsed = KnockoutReplayParser.parse(replay)

        if (parsed.tokens.isEmpty() || parsed.boards.isEmpty()) {
            OpenPigeonLog.w("KnockoutNative", "Ignoring invalid replay. replay=$replay")
            currentBoard?.let { setModeForBoard(it) }
            markInitialGameDataApplied()
            return
        }

        pendingTokens = parsed.tokens.toMutableList()
        playSource = PlaySource.None
        localOutgoingTokens.clear()
        processPendingReplayQueue()
        markInitialGameDataApplied()
    }

    private fun applyWaterTintForMap() {
        val wv = waterView ?: return

        when (mapMode) {
            2 -> wv.setTint(0.82f, 0.64f, 0.26f)  // slightly lighter map-2 yellow
            3 -> wv.setTint(0.40f, 0.70f, 0.46f)  // slightly lighter map-3 green
            else -> wv.clearTint()
        }
    }

    private fun logLong(prefix: String, value: String) {
        if (value.isBlank()) {
            OpenPigeonLog.i("KnockoutNative", "$prefix <blank>")
            return
        }

        val chunks = value.chunked(2800)
        chunks.forEachIndexed { index, chunk ->
            OpenPigeonLog.i(
                "KnockoutNative",
                "$prefix [${index + 1}/${chunks.size}] $chunk"
            )
        }
    }

    private fun logIncomingGameData(msg: Map<String, String>) {
        val replay = msg["replay"].orEmpty()
        val nonReplay = msg.entries
            .filter { it.key != "replay" }
            .sortedBy { it.key }
            .joinToString(" | ") { "${it.key}=${it.value}" }

        OpenPigeonLog.i("KnockoutNative", "========== incoming game data ==========")
        logLong("incoming nonReplay", nonReplay)

        OpenPigeonLog.i(
            "KnockoutNative",
            "incoming replay length=${replay.length} isBlank=${replay.isBlank()}"
        )
        logLong("incoming replay raw", replay)

        val rawTokens = replay
            .split("|")
            .filter { it.isNotBlank() }

        OpenPigeonLog.i("KnockoutNative", "incoming replay tokenCount=${rawTokens.size}")

        rawTokens.forEachIndexed { tokenIndex, token ->
            val type = token.substringBefore(":", missingDelimiterValue = token)
            val body = token.substringAfter(":", missingDelimiterValue = "")

            OpenPigeonLog.i(
                "KnockoutNative",
                "replay token[$tokenIndex] type=$type bodyLength=${body.length}"
            )

            if (type == "board") {
                val parts = body
                    .split("#")
                    .filter { it.isNotBlank() }

                val explicitBoardIndex = parts.firstOrNull()?.toIntOrNull()
                val pieceParts = if (explicitBoardIndex != null) {
                    parts.drop(1)
                } else {
                    parts
                }

                val p1Count = pieceParts.count { piece ->
                    piece.split(",").getOrNull(2) == "1"
                }
                val p2Count = pieceParts.count { piece ->
                    piece.split(",").getOrNull(2) == "2"
                }

                OpenPigeonLog.i(
                    "KnockoutNative",
                    "board token[$tokenIndex] explicitBoardIndex=${explicitBoardIndex ?: "missing"} " +
                            "rawPartCount=${parts.size} pieceCount=${pieceParts.size} p1=$p1Count p2=$p2Count"
                )

                if (pieceParts.size != 8) {
                    OpenPigeonLog.w(
                        "KnockoutNative",
                        "Expected 8 pieces but replay board has ${pieceParts.size}. This likely explains the missing piece."
                    )
                }

                pieceParts.forEachIndexed { pieceIndex, piece ->
                    val fields = piece.split(",")
                    OpenPigeonLog.i(
                        "KnockoutNative",
                        "board token[$tokenIndex] piece[$pieceIndex] " +
                                "fieldCount=${fields.size} raw=$piece"
                    )
                }
            }
        }

        runCatching {
            val parsed = KnockoutReplayParser.parse(replay)
            OpenPigeonLog.i(
                "KnockoutNative",
                "parsed replay tokens=${parsed.tokens.size} boards=${parsed.boards.size}"
            )

            parsed.boards.forEachIndexed { index, board ->
                val p1 = board.pieces.count { it.player == 1 }
                val p2 = board.pieces.count { it.player == 2 }

                OpenPigeonLog.i(
                    "KnockoutNative",
                    "parsed board[$index] index=${board.index} pieces=${board.pieces.size} p1=$p1 p2=$p2"
                )

                if (board.pieces.size != 8) {
                    OpenPigeonLog.w(
                        "KnockoutNative",
                        "Parsed board[$index] has ${board.pieces.size} pieces, not 8."
                    )
                }
            }
        }.onFailure { error ->
            OpenPigeonLog.e("KnockoutNative", "Replay parse failed while logging incoming game data", error)
        }

        OpenPigeonLog.i("KnockoutNative", "======== end incoming game data ========")
    }

    private fun localUserId(msg: Map<String, String>): String {
        return gameSessionIPC?.getSenderUUID(sessionId)?.takeIf { it.isNotBlank() }
            ?: msg["myPlayerId"].orEmpty()
    }

    override fun onResume() {
        super.onResume()
        waterView?.onResume()
        resumeMusic()
    }

    override fun onPause() {
        pauseMusic()
        waterView?.onPause()
        super.onPause()
    }

    private fun shouldShowIntroPopupFor(msg: Map<String, String>): Boolean {
        val myId = localUserId(msg)
        val p1 = msg["player1"].orEmpty()
        val p2 = msg["player2"].orEmpty()

        val hasOpenSeat = p1.isBlank() || p2.isBlank()
        val alreadyAssigned = myId.isNotBlank() && (myId == p1 || myId == p2)

        return hasOpenSeat && !alreadyAssigned
    }

    private fun isJoiningOpenSeat(msg: Map<String, String>): Boolean {
        val myId = localUserId(msg)
        val p1 = msg["player1"].orEmpty()
        val p2 = msg["player2"].orEmpty()

        val hasOpenSeat = p1.isBlank() || p2.isBlank()
        val alreadyAssigned = myId.isNotBlank() && (myId == p1 || myId == p2)

        return hasOpenSeat && !alreadyAssigned
    }

    private fun resolvePlayer(msg: Map<String, String>): Int {
        val myId = localUserId(msg)
        val p1 = msg["player1"].orEmpty()
        val p2 = msg["player2"].orEmpty()
        val sender = msg["sender"].orEmpty()
        val dataPlayer = msg["player"]?.toIntOrNull()?.coerceIn(1, 2) ?: 1

        if (myId.isNotEmpty()) {
            if (myId == p1) return 1
            if (myId == p2) return 2
        }

        if (p1.isBlank() && p2.isNotBlank()) return 1
        if (p2.isBlank() && p1.isNotBlank()) return 2
        if (p1.isBlank() && p2.isBlank()) return dataPlayer
        if (sender.isNotEmpty()) {
            if (sender == p1) return 2
            if (sender == p2) return 1
        }

        return dataPlayer
    }

    private fun applyOpponentAvatarFromMessage(msg: Map<String, String>) {
        val oppAvatarKey = if (player == 1) "avatar2" else "avatar1"

        msg[oppAvatarKey]?.takeIf { it.isNotBlank() }?.let { avatarStr ->
            runOnUiThread {
                settingsSheet.applyOpponentAvatarString(avatarStr)
            }
        }
    }

    private fun updateAvatarHud() {
        runOnUiThread {
            val myPreserver = findViewById<ImageView>(R.id.knockoutMyPreserver)
            val opponentPreserver = findViewById<ImageView>(R.id.knockoutOpponentPreserver)

            val myPath = if (player == 1) {
                "knockout/life_prev_black.png"
            } else {
                "knockout/life_prev_gray.png"
            }

            val opponentPath = if (player == 1) {
                "knockout/life_prev_gray.png"
            } else {
                "knockout/life_prev_black.png"
            }

            val myBitmap = loadAssetBitmap(myPath)
            val opponentBitmap = loadAssetBitmap(opponentPath)

            setPreserverBitmap(myPreserver, myBitmap, myPath)
            setPreserverBitmap(opponentPreserver, opponentBitmap, opponentPath)

            findViewById<View>(R.id.knockoutAvatarHud)?.let { hud ->
                val lp = hud.layoutParams as? FrameLayout.LayoutParams

                if (lp != null) {
                    val topPadding = dp(32f).toInt()

                    if (lp.topMargin != topPadding) {
                        lp.topMargin = topPadding
                        hud.layoutParams = lp
                    }
                }

                hud.bringToFront()
            }

            findViewById<View>(R.id.knockoutSettingsButton)?.bringToFront()
        }
    }

    private fun setPreserverBitmap(imageView: ImageView?, bitmap: Bitmap?, path: String) {
        if (imageView == null) return

        if (bitmap == null) {
            OpenPigeonLog.w("KnockoutNative", "Missing asset: $path")
            imageView.visibility = View.GONE
            return
        }

        val targetHeight = dp(52f).toInt()
        val aspectWidth = if (bitmap.height > 0) {
            (targetHeight.toFloat() * bitmap.width.toFloat() / bitmap.height.toFloat()).toInt()
        } else {
            targetHeight
        }

        val params = imageView.layoutParams
        params.width = aspectWidth
        params.height = targetHeight
        imageView.layoutParams = params

        imageView.adjustViewBounds = true
        imageView.scaleType = ImageView.ScaleType.FIT_CENTER
        imageView.setImageBitmap(bitmap)
        imageView.visibility = View.VISIBLE
    }

    private fun processPendingReplayQueue() {
        if (mode == Mode.Playing) return

        val boardIndexInTokens = pendingTokens.indexOfFirst { it is KnockoutReplayToken.BoardToken }
        if (boardIndexInTokens < 0) {
            val fallback = currentBoard ?: KnockoutReplayParser.parse(KnockoutReplayParser.emptyDefault()).boards.first()
            buildBoard(fallback)
            setModeForBoard(fallback)
            return
        }

        if (boardIndexInTokens > 0) {
            pendingTokens = pendingTokens.drop(boardIndexInTokens).toMutableList()
        }

        val board = (pendingTokens.first() as KnockoutReplayToken.BoardToken).board
        currentBoard = board
        buildBoard(board)

        val missingPlayers = KnockoutReplayParser.missingPowerPlayers(board)
        if (missingPlayers.isNotEmpty()) {
            setModeForBoard(board)
            return
        }

        pendingTokens.removeAt(0) // consume preboard
        if (pendingTokens.firstOrNull() is KnockoutReplayToken.ShootToken) {
            pendingTokens.removeAt(0)
        }

        playBoard(board, PlaySource.AutoReplay)
    }

    private fun setModeForBoard(board: KnockoutBoard) {
        if (isGameOver()) {
            mode = Mode.Disabled
            setPowerHintVisible(false)
            setLaunchButtonVisible(false)
            showGameOverLabel()
            return
        }

        if (pendingReplayWinLossState.isNotBlank() && playSource == PlaySource.AutoReplay) {
            mode = Mode.Disabled
            setPowerHintVisible(false)
            setLaunchButtonVisible(false)
            return
        }

        val boardWinLossState = winLossStateForBoard(board)
        if (boardWinLossState.isNotBlank()) {
            markGameOver(boardWinLossState)
            return
        }

        val missingPlayers = KnockoutReplayParser.missingPowerPlayers(board)

        val messagePlayer = lastMessage["player"]?.toIntOrNull()

        val isYourTurn =
            lastMessage["isYourTurn"] == "true" ||
                    lastMessage["isYourTurn"] == "1" ||
                    lastMessage["isYourTurn"]?.equals("yes", ignoreCase = true) == true ||
                    (
                            lastMessage["isYourTurn"].isNullOrBlank() &&
                                    messagePlayer != null &&
                                    messagePlayer != player
                            )

        val joiningOpenSeat = isJoiningOpenSeat(lastMessage)

        val canAim = (
                missingPlayers.contains(player) &&
                        (isYourTurn || introPopupDismissed || joiningOpenSeat)
                )

        OpenPigeonLog.i(
            "KnockoutNative",
            "setModeForBoard player=$player missing=$missingPlayers isYourTurn=$isYourTurn " +
                    "introDismissed=$introPopupDismissed joiningOpenSeat=$joiningOpenSeat canAim=$canAim"
        )

        if (gateAimingForIntro) {
            mode = Mode.Disabled
            showIntroPopup()
        } else {
            mode = if (canAim) Mode.Aiming else Mode.Disabled
            hideIntroPopup()

            if (canAim) {
                sentWaitingSequenceActive = false
                stateLabelVisual = StateLabelVisual.Hidden
                waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }
                waitingDotsRunnable = null
            }
        }

        updateStateLabel()
    }

    private fun buildBoard(board: KnockoutBoard) {
        synchronized(this) {
            if (closing || table == 0L) return

            boardIndex = board.index
            visualBoardIndex = board.index.toFloat()
            syncNativeMap()

            clearKnockoutPieces(table)
            pieces.clear()

            board.pieces.forEachIndexed { idx, state ->
                val piece = KnockoutPiece(idx, state.player, state, p1Bitmap, p2Bitmap)
                pieces += piece
                makeKnockoutPiece(table, state.x, state.y, state.rotation, idx, state.player, piece.buffer)
            }
        }
    }

    private fun markInitialGameDataApplied() {
        if (initialGameDataApplied) return

        initialGameDataApplied = true

        OpenPigeonLog.i(
            "KnockoutNative",
            "Initial game data applied. mapMode=$mapMode boardIndex=$boardIndex pieces=${pieces.size}"
        )
    }

    fun revealGameAfterCorrectFrameDrawn() {
        if (!initialGameDataApplied || gameShownToPlayer || closing) return

        gameShownToPlayer = true

        runOnUiThread {
            val root = findViewById<FrameLayout>(R.id.knockoutRoot) ?: return@runOnUiThread

            root.animate().cancel()
            root.visibility = View.VISIBLE

            root.animate()
                .alpha(1f)
                .setDuration(120L)
                .start()
        }
    }

    private fun playBoard(board: KnockoutBoard, source: PlaySource) {
        hideIntroPopup()

        runOnUiThread {
            replayArrowAnimator?.cancel()
            replayArrowAnimator = null
            playHandler.removeCallbacksAndMessages(null)
        }

        buildBoard(board)

        playSource = source
        revealArrowsThenFire(board, source)
    }

    fun updateKillZonesFromRenderer() {
        if (closing || table == 0L || mode != Mode.Playing) return

        val now = System.currentTimeMillis()

        pieces.forEach { piece ->
            if (piece.dying) {
                if (piece.isDeathAnimationDone(now)) {
                    piece.finishKillAnimation()
                }
                return@forEach
            }

            if (!piece.alive) return@forEach

            if (isPieceInKillZone(piece)) {
                OpenPigeonLog.i(
                    "KnockoutNative",
                    "KILL trace=${piece.traceId} player=${piece.player} " +
                            "map=$mapMode x=${piece.x} y=${piece.y} board=$boardIndex " +
                            "visualBoardIndex=$visualBoardIndex limit=${currentKillLimit()}"
                )

                piece.startKillAnimation(now)

                moveKnockoutPiece(
                    table,
                    piece.traceId,
                    10000f + piece.traceId * 100f,
                    10000f,
                    0f
                )
            }
        }
    }

    private fun meltScale(index: Int): Float =
        (1f - 0.1f * index.coerceIn(0, 7)).coerceAtLeast(0.3f)

    private fun scaleBoardPositions(board: KnockoutBoard, factor: Float): KnockoutBoard =
        board.copy(pieces = board.pieces.map { it.copy(x = it.x * factor, y = it.y * factor) })

    private fun currentBoardScaleForKill(): Float {
        return (1f - visualBoardIndex.coerceAtLeast(0f) * 0.1f)
            .coerceAtLeast(0.3f)
    }

    private fun syncNativeMap() {
        if (closing || table == 0L) return

        setKnockoutMap(
            table,
            mapMode,
            currentBoardScaleForKill()
        )
    }

    fun consumeNativeMushroomHits(): Int {
        if (closing || table == 0L) return 0
        return consumeKnockoutMushroomHits(table)
    }

    private fun currentKillLimit(): Float {
        return KILL_LIMIT_BASE * currentBoardScaleForKill()
    }

    private fun isPieceInKillZone(piece: KnockoutPiece): Boolean {
        val limit = currentKillLimit()

        return piece.x < -limit ||
                piece.x > limit ||
                piece.y < -limit ||
                piece.y > limit ||
                isPieceInMap2CenterHole(piece)
    }

    private fun currentMap2CenterHoleRadius(): Float {
        return MAP_2_CENTER_HOLE_RADIUS_BASE * currentBoardScaleForKill()
    }

    private fun isPieceInMap2CenterHole(piece: KnockoutPiece): Boolean {
        if (mapMode != 2) return false

        val radius = currentMap2CenterHoleRadius()
        val dx = piece.x
        val dy = piece.y

        return dx * dx + dy * dy < radius * radius
    }

    private fun firePreparedBoard(
        board: KnockoutBoard,
        source: PlaySource,
        fireStates: List<Pair<Int, KnockoutPieceState>>
    ) {
        if (closing || table == 0L) return

        synchronized(this) {
            for ((idx, state) in fireStates) {
                if (state.power <= KnockoutConstants.READY_POWER_EPS) continue

                val fireRotation = bodyRotationForShootDir(state.shootDir)

                pieces.getOrNull(idx)?.rotation = fireRotation
                moveKnockoutPiece(table, idx, state.x, state.y, fireRotation)

                fireKnockoutPiece(table, idx, state.shootDir, state.power * FIRE_POWER_MULTIPLIER)
            }

            playSource = source
            mode = Mode.Playing
            updateStateLabel()
        }

        fadeReplayArrowsOut()
    }

    private fun fadeReplayArrowsOut() {
        runOnUiThread {
            replayArrowAnimator?.cancel()

            replayArrowAnimator = ValueAnimator.ofFloat(replayArrowAlpha, 0f).apply {
                duration = 180L

                addUpdateListener { animation ->
                    replayArrowAlpha = animation.animatedValue as Float
                }

                doOnEndCompat {
                    showAllReplayArrows = false
                    replayArrowAlpha = 0f
                }

                start()
            }
        }
    }

    private fun revealArrowsThenFire(board: KnockoutBoard, source: PlaySource) {
        val fireStates = board.pieces
            .mapIndexedNotNull { idx, state ->
                if (state.power > KnockoutConstants.READY_POWER_EPS) idx to state else null
            }

        if (fireStates.isEmpty()) {
            showAllReplayArrows = false
            replayArrowAlpha = 0f
            playSource = source
            mode = Mode.Playing
            updateStateLabel()
            return
        }

        val startRotations = fireStates.associate { (idx, state) ->
            idx to (pieces.getOrNull(idx)?.rotation ?: state.rotation)
        }

        showAllReplayArrows = true
        replayArrowAlpha = 0f
        mode = Mode.Disabled
        setLaunchButtonVisible(false)
        hideStateLabel()

        runOnUiThread {
            replayArrowAnimator?.cancel()

            replayArrowAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 500L

                addUpdateListener { animation ->
                    val t = animation.animatedValue as Float
                    replayArrowAlpha = t

                    synchronized(this@KnockoutActivity) {
                        for ((idx, state) in fireStates) {
                            val piece = pieces.getOrNull(idx) ?: continue
                            val startRotation = startRotations[idx] ?: piece.rotation
                            val targetRotation = bodyRotationForShootDir(state.shootDir)

                            piece.rotation = lerpAngle(startRotation, targetRotation, t)
                        }
                    }
                }

                doOnEndCompat {
                    playHandler.postDelayed({
                        firePreparedBoard(board, source, fireStates)
                    }, 1000L)
                }

                start()
            }
        }
    }

    private fun bodyRotationForShootDir(shootDir: Float): Float {
        return normalizeAngle(shootDir - KnockoutConstants.PIECE_HEADING_OFFSET)
    }

    private fun normalizeAngle(angle: Float): Float {
        val twoPi = (PI * 2.0).toFloat()
        var a = angle % twoPi

        while (a > PI.toFloat()) {
            a -= twoPi
        }

        while (a <= -PI.toFloat()) {
            a += twoPi
        }

        return a
    }

    private fun shortestAngleDelta(start: Float, end: Float): Float {
        val twoPi = (PI * 2.0).toFloat()
        var delta = (end - start) % twoPi

        while (delta > PI.toFloat()) {
            delta -= twoPi
        }

        while (delta <= -PI.toFloat()) {
            delta += twoPi
        }

        return delta
    }

    private fun lerpAngle(start: Float, end: Float, t: Float): Float {
        return normalizeAngle(start + shortestAngleDelta(start, end) * t)
    }

    private fun launchCurrentAims() {
        if (isGameOver() || mode != Mode.Aiming || closing || table == 0L) return

        val baseBoard = currentBoard
            ?: KnockoutReplayParser.boardFromLivePieces(boardIndex, pieces, zeroPower = false)

        val launchBoard = KnockoutReplayParser.applyLiveAimsToBoard(baseBoard, player, pieces)
        currentBoard = launchBoard

        OpenPigeonLog.i(
            "KnockoutNative",
            "launchCurrentAims player=$player boardIndex=${launchBoard.index} " +
                    "complete=${KnockoutReplayParser.isBoardComplete(launchBoard)} " +
                    "stagedTokens=${localOutgoingTokens.size}"
        )

        if (!KnockoutReplayParser.isBoardComplete(launchBoard)) {
            val tokensToSend = mutableListOf<KnockoutReplayToken>()
            tokensToSend += localOutgoingTokens
            tokensToSend += KnockoutReplayToken.BoardToken(launchBoard)

            sendReplayTokens(tokensToSend)
            localOutgoingTokens.clear()
            return
        }

        val stagedPrefix = localOutgoingTokens.toList()
        localOutgoingTokens.clear()
        localOutgoingTokens += stagedPrefix
        localOutgoingTokens += KnockoutReplayToken.BoardToken(launchBoard)
        localOutgoingTokens += KnockoutReplayToken.ShootToken

        playBoard(launchBoard, PlaySource.LocalLaunch)
    }

    fun onNativePlayFinished() {
        if (mode != Mode.Playing) return

        pieces.forEach { it.syncFromNative() }
        val inferredPost = KnockoutReplayParser.boardFromLivePieces(boardIndex + 1, pieces, zeroPower = true)

        when (playSource) {
            PlaySource.AutoReplay -> finishAutoReplayRound(inferredPost)
            PlaySource.LocalLaunch -> finishLocalLaunchRound(inferredPost)
            PlaySource.None -> {
                mode = Mode.Aiming
                updateStateLabel()
            }
        }
    }

    private fun finishAutoReplayRound(inferredPost: KnockoutBoard) {
        val firstQueuedBoard = if (pendingTokens.firstOrNull() is KnockoutReplayToken.BoardToken) {
            (pendingTokens.removeAt(0) as KnockoutReplayToken.BoardToken).board
        } else {
            null
        }

        val hasAnotherQueuedBoard = pendingTokens.any { it is KnockoutReplayToken.BoardToken }

        OpenPigeonLog.i(
            "KnockoutNative",
            "finishAutoReplayRound firstQueued=${firstQueuedBoard != null} " +
                    "hasAnotherQueued=$hasAnotherQueuedBoard inferredIndex=${inferredPost.index}"
        )

        if (firstQueuedBoard != null && hasAnotherQueuedBoard) {
            applyPostBoardAndShrink(firstQueuedBoard) {
                playSource = PlaySource.None
                currentBoard = firstQueuedBoard

                if (finishPendingReplayGameOverIfNeeded(firstQueuedBoard)) {
                    pendingTokens.clear()
                    return@applyPostBoardAndShrink
                }

                processPendingReplayQueue()
                markInitialGameDataApplied()
            }
            return
        }

        val nextAimBoard = when {
            firstQueuedBoard == null -> {
                KnockoutReplayParser.clearAims(inferredPost)
            }

            KnockoutReplayParser.missingPowerPlayers(firstQueuedBoard).isNotEmpty() -> {
                firstQueuedBoard
            }

            else -> {
                KnockoutReplayParser.clearAims(firstQueuedBoard)
            }
        }

        applyPostBoardAndShrink(nextAimBoard) {
            playSource = PlaySource.None
            currentBoard = nextAimBoard

            showAllReplayArrows = false
            replayArrowAlpha = 0f

            if (finishPendingReplayGameOverIfNeeded(nextAimBoard)) {
                return@applyPostBoardAndShrink
            }

            setModeForBoard(nextAimBoard)
        }
    }

    private fun finishLocalLaunchRound(inferredPost: KnockoutBoard) {
        val nextIndex = (boardIndex + 1).coerceAtMost(7)
        val factor = meltScale(nextIndex) / meltScale(boardIndex)
        val postBoard = scaleBoardPositions(inferredPost, factor).copy(index = nextIndex)
        val nextSetup = KnockoutReplayParser.clearAims(postBoard)

        localOutgoingTokens += KnockoutReplayToken.BoardToken(postBoard)
        val finalWinLossState = winLossStateForBoard(postBoard)

        if (finalWinLossState.isNotBlank()) {
            OpenPigeonLog.i(
                "KnockoutNative",
                "Game ended locally. winnerState=$finalWinLossState postIndex=${postBoard.index}"
            )

            gameEnded = true
            winLossState = finalWinLossState
            mode = Mode.Disabled

            applyPostBoardAndShrink(postBoard) {
                playSource = PlaySource.None
                currentBoard = postBoard

                showAllReplayArrows = false
                replayArrowAlpha = 0f

                setPowerHintVisible(false)
                setLaunchButtonVisible(false)

                sendReplayTokens(
                    tokens = localOutgoingTokens.toList(),
                    winnerState = finalWinLossState,
                    showSentLabel = false
                )

                localOutgoingTokens.clear()
                showGameOverLabel()
            }

            return
        }

        OpenPigeonLog.i(
            "KnockoutNative",
            "finishLocalLaunchRound stagedTokens=${localOutgoingTokens.size} " +
                    "postIndex=${postBoard.index} nextSetupPieces=${nextSetup.pieces.size}"
        )

        applyPostBoardAndShrink(nextSetup) {
            playSource = PlaySource.None
            currentBoard = nextSetup

            showAllReplayArrows = false
            replayArrowAlpha = 0f

            setModeForBoard(nextSetup)
        }
    }

    private fun applyPostBoardAndShrink(postBoard: KnockoutBoard, afterShrink: () -> Unit) {
        val startIndex = visualBoardIndex
        val targetIndex = postBoard.index.toFloat()
        val startScale = (1f - 0.1f * startIndex).coerceAtLeast(0.3f)

        val slide = pieces.filter { it.alive }
        val sx = slide.map { it.x }
        val sy = slide.map { it.y }

        mode = Mode.Disabled
        setPowerHintVisible(false)
        setLaunchButtonVisible(false)
        hideStateLabel()

        runOnUiThread {
            shrinkAnimator?.cancel()
            shrinkAnimator = ValueAnimator.ofFloat(startIndex, targetIndex).apply {
                duration = 420L
                addUpdateListener { anim ->
                    val vi = anim.animatedValue as Float
                    visualBoardIndex = vi
                    val factor = ((1f - 0.1f * vi).coerceAtLeast(0.3f)) / startScale
                    synchronized(this@KnockoutActivity) {
                        for (i in slide.indices) {
                            slide[i].x = sx[i] * factor
                            slide[i].y = sy[i] * factor
                        }
                    }
                }
                doOnEndCompat {
                    synchronized(this@KnockoutActivity) {
                        boardIndex = postBoard.index
                        visualBoardIndex = targetIndex
                        buildBoard(postBoard)
                        currentBoard = postBoard
                        afterShrink()
                    }
                }
                start()
            }
        }
    }

    private fun sendReplayTokens(
        tokens: List<KnockoutReplayToken>,
        winnerState: String? = null,
        showSentLabel: Boolean = true
    ) {
        val replay = KnockoutReplayParser.serializeTokens(tokens)
        val currentMessage = gameSessionIPC?.getCurrentMessage(sessionId).orEmpty()
        val myId = localUserId(currentMessage.ifEmpty { lastMessage })
        val myAvatarKey = if (player == 1) "avatar1" else "avatar2"
        val nextNum = ((currentMessage["num"] ?: lastMessage["num"])?.toIntOrNull() ?: 0) + 1

        val p1 = (currentMessage["player1"] ?: player1Id).orEmpty()
        val p2 = (currentMessage["player2"] ?: player2Id).orEmpty()

        val msg = mutableMapOf(
            "game" to "knock",
            "player" to player.toString(),
            "num" to nextNum.toString(),
            "sender" to myId,
            "replay" to replay,
            myAvatarKey to AvatarView.buildAvatarString()
        )

        if (player == 1) {
            msg["player1"] = myId
            if (p2.isNotBlank()) msg["player2"] = p2
        } else {
            if (p1.isNotBlank()) msg["player1"] = p1
            msg["player2"] = myId
        }

        val cleanWinnerState = winnerState?.takeIf { it.isNotBlank() }

        if (cleanWinnerState != null) {
            msg["winner"] = "$myId|$cleanWinnerState"
        }

        OpenPigeonLog.i("KnockoutNative", "send replay=$replay")

        lastOutgoingReplay = replay
        ignoreNextOutgoingReplayEcho = true

        mode = Mode.Disabled

        setLaunchButtonVisible(false)
        setPowerHintVisible(false)

        if (cleanWinnerState != null || isGameOver()) {
            showAllReplayArrows = false
            replayArrowAlpha = 0f

            if (cleanWinnerState != null) {
                gameEnded = true
                winLossState = cleanWinnerState
            }

            showGameOverLabel()
        } else {
            showAllReplayArrows = true
            replayArrowAlpha = 1f

            if (showSentLabel) {
                showSendingLabelImmediately()
            }
        }

        val ipc = gameSessionIPC
        if (ipc == null) {
            OpenPigeonLog.w("KnockoutNative", "No IPC available")

            if (showSentLabel && cleanWinnerState == null) {
                showSentCheckThenWaitingAnimation()
            } else {
                showGameOverLabel()
            }

            return
        }

        ipc.updateSession(msg, sessionId) {
            OpenPigeonLog.i("KnockoutNative", "Session updated")

            if (showSentLabel && cleanWinnerState == null) {
                showSentCheckThenWaitingAnimation()
            } else {
                showGameOverLabel()
            }
        }
    }

    private fun handleTouch(event: MotionEvent): Boolean {
        if (isGameOver()) {
            return true
        }
        if (mode != Mode.Aiming || gateAimingForIntro) {
            if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                OpenPigeonLog.i(
                    "KnockoutNative",
                    "touch ignored mode=$mode gateAimingForIntro=$gateAimingForIntro player=$player"
                )
            }
            return true
        }

        val world = renderer.screenToWorld(event.x, event.y)
        val wx = world[0]
        val wy = world[1]

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                selectedPiece = pieces
                    .filter { it.player == player && it.alive }
                    .minByOrNull { p ->
                        val dx = p.x - wx
                        val dy = p.y - wy
                        dx * dx + dy * dy
                    }
                    ?.takeIf { it.containsWorldPoint(wx, wy) }

                OpenPigeonLog.i(
                    "KnockoutNative",
                    "touch down world=($wx,$wy) selected=${selectedPiece?.traceId} " +
                            "player=$player mine=${pieces.count { it.player == player && it.alive }}"
                )

                selectedPiece?.setAimFromWorld(wx, wy)
            }

            MotionEvent.ACTION_MOVE -> {
                selectedPiece?.setAimFromWorld(wx, wy)
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                selectedPiece = null
            }
        }

        updateStateLabel()
        return true
    }

    private fun allMyPiecesPowered(): Boolean {
        val mine = pieces.filter { it.player == player && it.alive }
        return mine.isNotEmpty() && mine.all { it.power > KnockoutConstants.READY_POWER_EPS }
    }

    private fun currentBoardWithLiveAims(): KnockoutBoard {
        val base = currentBoard ?: KnockoutReplayParser.boardFromLivePieces(boardIndex, pieces, zeroPower = false)
        return KnockoutReplayParser.applyLiveAimsToBoard(base, player, pieces)
    }

    private fun currentReadyActionText(): String {
        return if (KnockoutReplayParser.isBoardComplete(currentBoardWithLiveAims())) "Launch" else "Send"
    }

    private fun ensureStatusDimView(): View? {
        statusDimView?.let { return it }

        val root = findViewById<FrameLayout>(R.id.knockoutRoot) ?: return null

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
            dim,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
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

                dim.animate()
                    .alpha(1f)
                    .setDuration(180L)
                    .start()
            } else {
                statusDimVisible = false

                dim.animate()
                    .alpha(0f)
                    .setDuration(160L)
                    .withEndAction {
                        if (!statusDimVisible) {
                            dim.visibility = View.GONE
                        }
                    }
                    .start()
            }
        }
    }

    private fun isGameOver(): Boolean {
        return gameEnded && winLossState.isNotBlank()
    }

    private fun winLossStateForBoard(board: KnockoutBoard): String {
        val alivePlayers = board.pieces
            .map { it.player }
            .toSet()

        return when {
            alivePlayers.isEmpty() -> "0" // draw
            alivePlayers.size == 1 -> {
                if (alivePlayers.first() == player) "1" else "-1"
            }
            else -> ""
        }
    }

    private fun gameOverText(): String {
        return when (winLossState) {
            "1" -> "You Win!"
            "-1" -> "You Lose!"
            "0" -> "Draw!"
            else -> ""
        }
    }

    private fun gameOverTextColor(): Int {
        return when (winLossState) {
            "1" -> Color.rgb(255, 214, 0)   // Color(1, 0.84, 0)
            "-1" -> Color.rgb(255, 51, 51)  // Color(1, 0.2, 0.2)
            "0" -> Color.WHITE
            else -> Color.WHITE
        }
    }

    private fun markGameOver(state: String) {
        if (state.isBlank()) return

        gameEnded = true
        winLossState = state
        mode = Mode.Disabled

        setPowerHintVisible(false)
        setLaunchButtonVisible(false)

        showAllReplayArrows = false
        replayArrowAlpha = 0f

        showGameOverLabel()
    }

    private fun showGameOverLabel() {
        runOnUiThread {
            if (!isGameOver()) return@runOnUiThread

            stopStateLabelAnimation()
            stateLabelVisual = StateLabelVisual.GameOver

            val label = findViewById<TextView>(R.id.knockoutStateLabel)

            resetStateLabelLayout(label)

            val text = gameOverText()
            val labelWidth = measureStateLabelWidth(label, text)

            val params = label.layoutParams
            params.width = labelWidth
            label.layoutParams = params

            label.text = text
            label.setTextColor(gameOverTextColor())
            label.visibility = View.VISIBLE

            setStatusDimVisible(true)
            label.bringToFront()
        }
    }

    private fun applyIncomingWinner(msg: Map<String, String>): Boolean {
        val rawWinner = msg["winner"].orEmpty()
        if (rawWinner.isBlank()) return false

        val parts = rawWinner.split("|", limit = 2)
        if (parts.size != 2) return false

        val senderWinnerId = parts[0]
        val senderState = parts[1].toIntOrNull()?.coerceIn(-1, 1) ?: return false

        val myId = localUserId(msg)

        val localState = when {
            senderState == 0 -> 0
            myId.isNotBlank() && senderWinnerId == myId -> senderState
            else -> -senderState
        }

        pendingReplayWinLossState = localState.toString()

        OpenPigeonLog.i(
            "KnockoutNative",
            "Incoming winner stored pending until replay shrink finishes. state=$pendingReplayWinLossState"
        )

        return true
    }

    private fun finishPendingReplayGameOverIfNeeded(board: KnockoutBoard): Boolean {
        val state = pendingReplayWinLossState
            .takeIf { it.isNotBlank() }
            ?: winLossStateForBoard(board).takeIf { it.isNotBlank() }
            ?: return false

        pendingReplayWinLossState = ""

        gameEnded = true
        winLossState = state
        mode = Mode.Disabled

        showAllReplayArrows = false
        replayArrowAlpha = 0f

        setPowerHintVisible(false)
        setLaunchButtonVisible(false)

        showGameOverLabel()
        return true
    }

    private fun updateStateLabel() {
        runOnUiThread {
            if (isGameOver()) {
                showGameOverLabel()
                return@runOnUiThread
            }

            val button = findViewById<Button>(R.id.knockoutLaunchButton)
            val label = findViewById<TextView>(R.id.knockoutStateLabel)

            when (mode) {
                Mode.Aiming -> {
                    val mine = pieces.filter { it.player == player && it.alive }
                    val allMinePowered = mine.isNotEmpty() &&
                            mine.all { it.power > KnockoutConstants.READY_POWER_EPS }

                    val ready = allMinePowered && !gateAimingForIntro
                    val showPowerHint = mine.isNotEmpty() &&
                            !allMinePowered &&
                            !gateAimingForIntro &&
                            !sentWaitingSequenceActive

                    button.text = currentReadyActionText()

                    setPowerHintVisible(showPowerHint)
                    setLaunchButtonVisible(ready)

                    if (!sentWaitingSequenceActive) {
                        hideStateLabelNow()
                    }
                }

                Mode.Playing -> {
                    setPowerHintVisible(false)
                    setLaunchButtonVisible(false)

                    if (!sentWaitingSequenceActive) {
                        hideStateLabelNow()
                    }
                }

                Mode.Disabled -> {
                    setPowerHintVisible(false)
                    setLaunchButtonVisible(false)

                    if (sentWaitingSequenceActive) {
                        label.visibility = View.VISIBLE
                        label.bringToFront()
                        return@runOnUiThread
                    }

                    if (gateAimingForIntro) {
                        hideStateLabelNow()
                    } else {
                        showWaitingLabelAnimated()
                    }
                }
            }
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

        val params = label.layoutParams as? FrameLayout.LayoutParams ?: return
        params.width = FrameLayout.LayoutParams.WRAP_CONTENT
        params.height = FrameLayout.LayoutParams.WRAP_CONTENT
        params.gravity = Gravity.CENTER
        params.topMargin = 0
        params.bottomMargin = 0
        params.leftMargin = 0
        params.rightMargin = 0
        label.layoutParams = params

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

    private fun hideStateLabelNow() {
        if (stateLabelVisual == StateLabelVisual.GameOver && isGameOver()) {
            return
        }

        stopStateLabelAnimation()
        setStatusDimVisible(false)

        val label = findViewById<TextView>(R.id.knockoutStateLabel)
        resetStateLabelLayout(label)
        label.text = ""
        label.visibility = View.GONE
    }

    private fun hideStateLabel() {
        runOnUiThread {
            hideStateLabelNow()
        }
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
            if (isGameOver()) {
                showGameOverLabel()
                return@runOnUiThread
            }

            if (stateLabelVisual == StateLabelVisual.Waiting) return@runOnUiThread

            stopStateLabelAnimation()
            stateLabelVisual = StateLabelVisual.Waiting

            val label = findViewById<TextView>(R.id.knockoutStateLabel)
            resetStateLabelLayout(label)
            label.bringToFront()

            val waitingWidth = measureStateLabelWidth(label, "WAITING FOR OPPONENT...")
            val params = label.layoutParams
            params.width = waitingWidth
            label.layoutParams = params

            label.visibility = View.VISIBLE
            startWaitingDots(label)
        }
    }

    private fun showSendingLabelImmediately() {
        runOnUiThread {
            stopStateLabelAnimation()
            sentWaitingSequenceActive = true
            stateLabelVisual = StateLabelVisual.SentWaiting

            val label = findViewById<TextView>(R.id.knockoutStateLabel)
            resetStateLabelLayout(label)

            val sentWidth = measureStateLabelWidth(label, "Sent ✔")

            val params = label.layoutParams
            params.width = sentWidth
            label.layoutParams = params

            label.text = "Sent"
            label.alpha = 1f
            label.setTextColor(0xFFFFFFFF.toInt())
            label.visibility = View.VISIBLE
            label.bringToFront()
        }
    }

    private fun showSentCheckThenWaitingAnimation() {
        runOnUiThread {
            sentWaitingSequenceActive = true
            stateLabelVisual = StateLabelVisual.SentWaiting

            waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }
            waitingDotsRunnable = null
            stateLabelAnimator?.cancel()
            stateLabelAnimator = null

            val label = findViewById<TextView>(R.id.knockoutStateLabel)
            resetStateLabelLayout(label)

            val sentWidth = measureStateLabelWidth(label, "Sent ✔")
            val waitingWidth = measureStateLabelWidth(label, "WAITING FOR OPPONENT...")

            val params = label.layoutParams
            params.width = sentWidth
            label.layoutParams = params

            val sentCheck = SpannableString("Sent ✔")
            sentCheck.setSpan(
                ForegroundColorSpan(0xFF7257D8.toInt()),
                5,
                6,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )

            label.text = sentCheck
            label.alpha = 1f
            label.setTextColor(0xFFFFFFFF.toInt())
            label.visibility = View.VISIBLE
            label.bringToFront()

            stateLabelHandler.postDelayed({
                if (!sentWaitingSequenceActive || closing) return@postDelayed

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
                label.text = "WAITING FOR OPPONENT."
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

                    doOnEndCompat {
                        if (!sentWaitingSequenceActive || closing) return@doOnEndCompat

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

                            doOnEndCompat {
                                if (sentWaitingSequenceActive && !closing) {
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

    private fun setPowerHintVisible(visible: Boolean) {
        val label = findViewById<TextView>(R.id.knockoutPowerHintLabel) ?: return

        if (visible) {
            if (powerHintVisible && label.visibility == View.VISIBLE) return

            powerHintVisible = true
            label.animate().cancel()
            label.alpha = 0f
            label.visibility = View.VISIBLE
            label.bringToFront()

            label.animate()
                .alpha(1f)
                .setDuration(220L)
                .start()
        } else {
            powerHintVisible = false
            label.animate().cancel()
            label.alpha = 0f
            label.visibility = View.GONE
        }
    }

    private fun setLaunchButtonVisible(visible: Boolean) {
        val button = findViewById<Button>(R.id.knockoutLaunchButton) ?: return

        if (launchButtonVisible == visible) return
        launchButtonVisible = visible

        button.animate().cancel()

        if (visible) {
            val startTranslation = if (button.height > 0) {
                button.height.toFloat() + dp(48f)
            } else {
                dp(96f)
            }

            button.alpha = 0f
            button.translationY = startTranslation
            button.visibility = View.VISIBLE
            button.bringToFront()

            button.post {
                if (!launchButtonVisible) return@post

                val postedStartTranslation = if (button.height > 0) {
                    button.height.toFloat() + dp(48f)
                } else {
                    dp(96f)
                }

                button.translationY = postedStartTranslation
                button.alpha = 1f

                button.animate()
                    .translationY(0f)
                    .alpha(1f)
                    .setDuration(280L)
                    .start()
            }
        } else if (button.visibility == View.VISIBLE) {
            button.animate()
                .translationY(button.height.toFloat() + dp(48f))
                .alpha(0f)
                .setDuration(220L)
                .withEndAction {
                    if (!launchButtonVisible) {
                        button.visibility = View.GONE
                        button.translationY = 0f
                        button.alpha = 1f
                    }
                }
                .start()
        } else {
            button.visibility = View.GONE
            button.translationY = 0f
            button.alpha = 1f
        }
    }

    fun updateLaunchButtonPlacement(width: Int, height: Int) {
        val launchVisible = launchButtonVisible
        val hintVisible = powerHintVisible

        if (!launchVisible && !hintVisible) {
            lastPlacementWidth = -1
            lastPlacementHeight = -1
            lastPlacementLaunchVisible = false
            lastPlacementHintVisible = false
            return
        }

        if (
            lastPlacementWidth == width &&
            lastPlacementHeight == height &&
            lastPlacementLaunchVisible == launchVisible &&
            lastPlacementHintVisible == hintVisible
        ) {
            return
        }

        lastPlacementWidth = width
        lastPlacementHeight = height
        lastPlacementLaunchVisible = launchVisible
        lastPlacementHintVisible = hintVisible

        runOnUiThread {
            val button = findViewById<Button>(R.id.knockoutLaunchButton)
            val hint = findViewById<TextView>(R.id.knockoutPowerHintLabel)

            val bottomMargin = dp(34f).toInt()

            if (button != null && button.visibility == View.VISIBLE) {
                val lp = button.layoutParams as? FrameLayout.LayoutParams
                if (
                    lp != null &&
                    (
                            lp.gravity != (Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL) ||
                                    lp.bottomMargin != bottomMargin ||
                                    lp.topMargin != 0
                            )
                ) {
                    lp.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                    lp.bottomMargin = bottomMargin
                    lp.topMargin = 0
                    button.layoutParams = lp
                }

                button.bringToFront()
            }

            if (hint != null && hint.visibility == View.VISIBLE) {
                val lp = hint.layoutParams as? FrameLayout.LayoutParams
                if (
                    lp != null &&
                    (
                            lp.gravity != (Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL) ||
                                    lp.bottomMargin != bottomMargin ||
                                    lp.topMargin != 0
                            )
                ) {
                    lp.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                    lp.bottomMargin = bottomMargin
                    lp.topMargin = 0
                    hint.layoutParams = lp
                }

                hint.bringToFront()
            }
        }
    }

    private fun allowIntroPopupShadows() {
        val root = findViewById<FrameLayout>(R.id.knockoutRoot)
        val overlay = findViewById<FrameLayout>(R.id.knockoutIntroOverlay)
        val card = findViewById<LinearLayout>(R.id.knockoutIntroCard)
        val startButton = findViewById<Button>(R.id.knockoutIntroButton)

        root?.clipChildren = false
        root?.clipToPadding = false

        overlay?.clipChildren = false
        overlay?.clipToPadding = false

        card?.clipChildren = false
        card?.clipToPadding = false
        card?.clipToOutline = false

        (overlay?.parent as? ViewGroup)?.clipChildren = false
        (overlay?.parent as? ViewGroup)?.clipToPadding = false

        (card?.parent as? ViewGroup)?.clipChildren = false
        (card?.parent as? ViewGroup)?.clipToPadding = false

        (startButton?.parent as? ViewGroup)?.clipChildren = false
        (startButton?.parent as? ViewGroup)?.clipToPadding = false
    }

    private fun ensureIntroPopup() {
        val overlay = findViewById<FrameLayout>(R.id.knockoutIntroOverlay) ?: return
        val card = findViewById<LinearLayout>(R.id.knockoutIntroCard) ?: return

        allowIntroPopupShadows()

        overlay.setBackgroundColor(Color.argb(128, 0, 0, 0))
        overlay.isClickable = true
        overlay.isFocusable = true
        overlay.clipChildren = false
        overlay.clipToPadding = false

        val cardStyle = GradientDrawable().apply {
            setColor(Color.WHITE)
            cornerRadius = dp(16f)
        }

        card.background = cardStyle
        card.stateListAnimator = null
        card.elevation = dp(20f)
        card.translationZ = dp(0f)
        card.outlineProvider = ViewOutlineProvider.BACKGROUND
        card.clipToOutline = false
        card.clipChildren = false
        card.clipToPadding = false

        val pad = dp(24f).toInt()
        card.setPadding(pad, pad, pad, pad)
        card.gravity = Gravity.CENTER_HORIZONTAL
        card.orientation = LinearLayout.VERTICAL

        findViewById<TextView>(R.id.knockoutIntroTitle)?.apply {
            text = "Goal:"
            gravity = Gravity.CENTER
            setTextColor(Color.BLACK)
            textSize = 30f
            includeFontPadding = false

            typeface = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                Typeface.create(Typeface.DEFAULT, 900, false) // heaviest/black weight
            } else {
                Typeface.create("sans-serif-black", Typeface.NORMAL)
            }
        }

        findViewById<TextView>(R.id.knockoutIntroBody)?.apply {
            text = "Push your opponent out into the water before they push you out."
            gravity = Gravity.CENTER
            setTextColor(Color.BLACK)
            textSize = 18f
            includeFontPadding = true
            setTypeface(typeface, Typeface.BOLD)
        }

        styleIntroButton(findViewById(R.id.knockoutIntroButton))

        card.post {
            val popupWidth = (resources.displayMetrics.widthPixels * 0.8f).toInt()
            val popupHeight = dp(260f).toInt()

            val lp = card.layoutParams as FrameLayout.LayoutParams
            lp.width = popupWidth
            lp.height = popupHeight
            lp.gravity = Gravity.CENTER
            card.layoutParams = lp

            card.pivotX = popupWidth / 2f
            card.pivotY = popupHeight / 2f

            findViewById<TextView>(R.id.knockoutIntroBody)?.maxWidth =
                (popupWidth - dp(96f)).toInt()
        }
    }

    private fun showIntroPopup() {
        runOnUiThread {
            val overlay = findViewById<View>(R.id.knockoutIntroOverlay) ?: return@runOnUiThread
            val card = findViewById<View>(R.id.knockoutIntroCard) ?: return@runOnUiThread

            ensureIntroPopup()

            overlay.bringToFront()
            overlay.visibility = View.VISIBLE
            overlay.alpha = 1f

            card.animate().cancel()
            card.scaleX = 0f
            card.scaleY = 0f
            card.alpha = 1f

            card.animate()
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(400L)
                .setInterpolator(OvershootInterpolator(1.05f))
                .start()
        }
    }

    private fun hideIntroPopup() {
        runOnUiThread {
            val overlay = findViewById<View>(R.id.knockoutIntroOverlay) ?: return@runOnUiThread
            val card = findViewById<View>(R.id.knockoutIntroCard)

            card?.animate()?.cancel()
            card?.scaleX = 1f
            card?.scaleY = 1f
            overlay.visibility = View.GONE
        }
    }

    fun isIntroPopupShowing(): Boolean = gateAimingForIntro

    private fun dismissIntroPopupAndEnableAiming() {
        introPopupDismissed = true
        gateAimingForIntro = false
        hideIntroPopup()

        OpenPigeonLog.i(
            "KnockoutNative",
            "Intro dismissed. player=$player currentBoard=${currentBoard != null}"
        )

        currentBoard?.let { board ->
            setModeForBoard(board)
        } ?: run {
            mode = Mode.Aiming
            updateStateLabel()
        }
    }

    private fun styleActionButton(button: Button?) {
        button ?: return

        val backgroundColor = actionButtonBackgroundColorForMap()
        val textColor = actionButtonTextColorForMap()

        button.textSize = 18f
        button.setTextColor(textColor)
        button.setTypeface(button.typeface, Typeface.BOLD)
        button.isAllCaps = false
        button.gravity = Gravity.CENTER
        button.includeFontPadding = false
        button.minHeight = dp(30f).toInt()
        button.minWidth = dp(100f).toInt()
        button.minimumHeight = dp(30f).toInt()
        button.minimumWidth = dp(100f).toInt()

        button.backgroundTintList = null
        button.backgroundTintMode = null

        button.background = GradientDrawable().apply {
            setColor(backgroundColor)
            cornerRadius = dp(12f)

            if (mapMode == 1) {
                setStroke(dp(1.5f).toInt(), colorForMap())
            }
        }

        button.backgroundTintList = null
        button.backgroundTintMode = null
    }

    private fun map1BlueColor(): Int {
        return Color.parseColor("#aad9f7")
    }

    private fun map2YellowColor(): Int {
        return Color.parseColor("#ffd84d")
    }

    private fun map2DarkRedColor(): Int {
        return Color.parseColor("#a82a2a")
    }

    private fun map3GreenColor(): Int {
        return Color.parseColor("#6fd68b")
    }

    private fun map3DarkGreenColor(): Int {
        return Color.parseColor("#2e7d32")
    }

    private fun colorForMap(): Int {
        return when (mapMode) {
            2 -> map2YellowColor()
            3 -> map3GreenColor()
            else -> map1BlueColor()
        }
    }

    private fun introButtonBackgroundColorForMap(): Int {
        return when (mapMode) {
            2 -> map2DarkRedColor()
            3 -> map3DarkGreenColor()
            else -> colorForMap()
        }
    }

    private fun introButtonTextColorForMap(): Int {
        return when (mapMode) {
            2 -> map2YellowColor()
            3 -> Color.WHITE
            else -> Color.BLACK
        }
    }

    private fun actionButtonBackgroundColorForMap(): Int {
        return when (mapMode) {
            2 -> map2DarkRedColor()
            3 -> map3DarkGreenColor()
            else -> Color.WHITE
        }
    }

    private fun actionButtonTextColorForMap(): Int {
        return when (mapMode) {
            2 -> map2YellowColor()
            3 -> Color.WHITE
            else -> colorForMap()
        }
    }

    private fun powerHintTextColorForMap(): Int {
        return when (mapMode) {
            2 -> map2DarkRedColor()
            3 -> map3DarkGreenColor()
            else -> Color.WHITE
        }
    }

    private fun applyMapButtonColors() {
        runOnUiThread {
            val color = colorForMap()

            OpenPigeonLog.i(
                "KnockoutNative",
                "applyMapButtonColors mapMode=$mapMode color=#${Integer.toHexString(color)}"
            )

            styleActionButton(findViewById(R.id.knockoutLaunchButton))
            styleIntroButton(findViewById(R.id.knockoutIntroButton))
            stylePowerHint(findViewById(R.id.knockoutPowerHintLabel))
        }
    }

    private fun stylePowerHint(label: TextView?) {
        label ?: return

        label.background = null
        label.gravity = Gravity.CENTER
        label.textAlignment = View.TEXT_ALIGNMENT_CENTER
        label.setTextColor(powerHintTextColorForMap())
        label.textSize = 17f
        label.setTypeface(label.typeface, Typeface.BOLD)
        label.alpha = if (powerHintVisible) 1f else 0f
        label.visibility = if (powerHintVisible) View.VISIBLE else View.GONE
    }

    private fun styleIntroButton(button: Button?) {
        button ?: return

        val backgroundColor = introButtonBackgroundColorForMap()
        val textColor = introButtonTextColorForMap()

        button.text = "Start"
        button.textSize = 18f
        button.setTextColor(textColor)
        button.setTypeface(button.typeface, Typeface.BOLD)
        button.isAllCaps = false
        button.gravity = Gravity.CENTER
        button.includeFontPadding = false
        button.minWidth = dp(50f).toInt()
        button.minHeight = dp(30f).toInt()
        button.minimumWidth = dp(50f).toInt()
        button.minimumHeight = dp(30f).toInt()

        button.backgroundTintList = null
        button.backgroundTintMode = null

        button.background = GradientDrawable().apply {
            setColor(backgroundColor)
            cornerRadius = dp(6f)
        }

        button.backgroundTintList = null
        button.backgroundTintMode = null

        button.stateListAnimator = null
        button.elevation = dp(12f)
        button.translationZ = dp(0f)
        button.outlineProvider = ViewOutlineProvider.BACKGROUND
        button.clipToOutline = false

        (button.parent as? ViewGroup)?.clipChildren = false
        (button.parent as? ViewGroup)?.clipToPadding = false
    }

    private fun dp(value: Float): Float = value * resources.displayMetrics.density

    fun loadAssetBitmap(path: String): Bitmap? = try {
        assets.open(path).use { BitmapFactory.decodeStream(it) }
    } catch (_: Exception) {
        null
    }

    override fun onDestroy() {
        closing = true
        stopMusic()

        runCatching {
            shrinkAnimator?.cancel()
            shrinkAnimator = null

            stopStateLabelAnimation()
            playHandler.removeCallbacksAndMessages(null)

            replayArrowAnimator?.cancel()
            replayArrowAnimator = null

            showAllReplayArrows = false
            replayArrowAlpha = 0f
        }.onFailure {
            OpenPigeonLog.w("KnockoutNative", "Animation cleanup failed during destroy", it)
        }

        if (::renderer.isInitialized) {
            renderer.shutdown()
        }

        runCatching {
            if (::settingsSheet.isInitialized) {
                settingsSheet.detach()
            }
        }.onFailure {
            OpenPigeonLog.w("KnockoutNative", "SettingsSheet detach failed during destroy", it)
        }

        synchronized(this) {
            if (table != 0L) {
                val old = table
                table = 0L

                runCatching {
                    destroyKnockoutTable(old)
                }.onFailure {
                    OpenPigeonLog.w("KnockoutNative", "Native table destroy failed", it)
                }
            }
        }

        runCatching {
            gameSessionIPC?.setSuppressNotifications(sessionId, false)
        }.onFailure {
            OpenPigeonLog.w("KnockoutNative", "Unable to unsuppress notifications during destroy", it)
        }

        gameSessionIPC = null

        super.onDestroy()
    }

    companion object {
        private const val FIRE_POWER_MULTIPLIER = 1.0f
        private const val KILL_LIMIT_BASE = 183.0f
        private const val MAP_2_CENTER_HOLE_RADIUS_BASE = 56.0f

        init {
            System.loadLibrary("openbubblesextension")
        }
    }
}

private fun ValueAnimator.doOnEndCompat(block: () -> Unit) {
    addListener(object : android.animation.Animator.AnimatorListener {
        override fun onAnimationStart(animation: android.animation.Animator) = Unit
        override fun onAnimationEnd(animation: android.animation.Animator) = block()
        override fun onAnimationCancel(animation: android.animation.Animator) = Unit
        override fun onAnimationRepeat(animation: android.animation.Animator) = Unit
    })
}
