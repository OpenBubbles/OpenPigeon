package com.openbubbles.openpigeon.wordhunt

import android.annotation.SuppressLint
import android.os.Bundle
import android.os.CountDownTimer
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GameSessionIPC
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.util.OpenPigeonLog
import android.content.Context
import android.graphics.BitmapFactory
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.util.TypedValue
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageButton
import androidx.appcompat.widget.SwitchCompat
import com.openbubbles.openpigeon.settings.SettingsSheet

class WordHuntActivity : AppCompatActivity() {
    private val baseGame: Game = WordHuntGame()

    private var gameSessionIPC: GameSessionIPC? = null
    lateinit var sessionId: String
    private lateinit var currentMessage: Map<String, String>
    private lateinit var currentMessageState: MutableState<Map<String, String>>
    private lateinit var dictionary: WordDictionary
    private lateinit var gameState: WordHuntGameState
    private lateinit var settingsSheet: SettingsSheet

    private var wordHuntActivityClosing = false
    private var musicEnabled = false
    private var musicTrack: AudioTrack? = null
    private val wordHuntMusicTrack = "wordhunt/wordhunt.wav"

    private var gameTimer: CountDownTimer? = null

    private val gameUI = GameUI()
    private lateinit var navController: NavHostController

    enum class GameMode(val gridSize: Int, val invalidPositions: List<Pair<Int, Int>>, val drawable: Int){
        MODE1(4, emptyList(), R.drawable.wordhunt_board_mode1),
        MODE2(5, listOf(
            Pair(0,0), Pair(0,4), Pair(2,2), Pair(4,0), Pair(4,4)
        ), R.drawable.wordhunt_board_mode2),
        MODE3(5, listOf(
            Pair(0,2), Pair(2,0), Pair(2,4), Pair(4,2)
        ), R.drawable.wordhunt_board_mode3),
        MODE4(5, emptyList(), R.drawable.wordhunt_board_mode1)
    }



    // Game constants
    companion object {
        const val GAME_DURATION = 80000L // 80 seconds
        const val MIN_WORD_LENGTH = 3

        fun generateLetterPool(mode: GameMode): List<Char> {
            val totalLetters = mode.gridSize * mode.gridSize

            // Define letter frequencies
            val scrabbleFrequencyMap = mapOf(
                'E' to 12,
                'A' to 9, 'I' to 9,
                'O' to 8,
                'N' to 6, 'R' to 6, 'T' to 6,
                'L' to 4, 'S' to 4, 'U' to 4, 'D' to 4,
                'G' to 3,
                'B' to 2, 'C' to 2, 'M' to 2, 'P' to 2, 'F' to 2, 'H' to 2, 'V' to 2, 'W' to 2, 'Y' to 2,
                'K' to 1, 'J' to 1, 'X' to 1, 'Q' to 1, 'Z' to 1
            )

            // Build full frequency list
            val fullPool = scrabbleFrequencyMap.flatMap { (char, count) -> List(count) { char } }.toMutableList()

            // Shuffle and select as many as needed
            fullPool.shuffle()
            return fullPool.take(totalLetters)
        }

        fun mode(mode: Int): GameMode {
            return when(mode) {
                1 -> GameMode.MODE1
                2 -> GameMode.MODE2
                3 -> GameMode.MODE3
                4 -> GameMode.MODE4
                else -> {
                    OpenPigeonLog.e("WordHunt", "Mode does not exist")
                    GameMode.MODE1
                }
            }
        }
    }

    private data class WavLoopData(
        val pcm: ByteArray,
        val sampleRate: Int,
        val channelMask: Int,
        val encoding: Int,
        val frameCount: Int
    )

    private fun dp(value: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value,
            resources.displayMetrics
        ).toInt()
    }

    private fun setupWordHuntSettingsSheet() {
        val rootFrame = findViewById<FrameLayout>(android.R.id.content)
        settingsSheet = SettingsSheet(this, rootFrame)

        val settingsBtn = ImageButton(this).apply {
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER

            try {
                val bm = assets.open("global/settings.png")
                    .use { BitmapFactory.decodeStream(it) }
                setImageBitmap(bm)
            } catch (e: Exception) {
                e.printStackTrace()
            }

            setOnClickListener {
                settingsSheet.open()
            }
        }

        rootFrame.addView(
            settingsBtn,
            FrameLayout.LayoutParams(
                dp(60f),
                dp(60f),
                Gravity.BOTTOM or Gravity.END
            ).apply {
                rightMargin = dp(10f)
                bottomMargin = dp(10f)
            }
        );

        val musicSwitch = SwitchCompat(this)
        musicSwitch.isChecked = getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
            .getBoolean("wordhunt/music_enabled", true)

        musicEnabled = musicSwitch.isChecked
        musicSwitch.setOnCheckedChangeListener { _, checked ->
            applyMusicEnabled(checked)
        }

        settingsSheet.addGameControl("Music", musicSwitch)

        if (musicEnabled) {
            startWordHuntMusic()
        }
    }

    private fun applyMusicEnabled(enabled: Boolean) {
        musicEnabled = enabled

        getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("wordhunt/music_enabled", enabled)
            .apply()

        if (enabled) {
            startWordHuntMusic()
        } else {
            stopWordHuntMusic()
        }
    }

    private fun startWordHuntMusic() {
        if (!musicEnabled || wordHuntActivityClosing || musicTrack != null) return

        try {
            val wav = loadPcm16Wav(wordHuntMusicTrack)

            @Suppress("DEPRECATION")
            val track = AudioTrack(
                AudioManager.STREAM_MUSIC,
                wav.sampleRate,
                wav.channelMask,
                wav.encoding,
                wav.pcm.size,
                AudioTrack.MODE_STATIC
            )

            if (track.state != AudioTrack.STATE_INITIALIZED) {
                track.release()
                throw IllegalStateException("AudioTrack failed to initialize")
            }

            track.write(wav.pcm, 0, wav.pcm.size)
            track.setLoopPoints(0, wav.frameCount, -1)
            track.setVolume(0.55f)

            musicTrack = track
            track.play()
        } catch (e: Exception) {
            OpenPigeonLog.e("WordHuntMusic", "Unable to play music track $wordHuntMusicTrack", e)

            musicEnabled = false
            getSharedPreferences("avatar_settings", Context.MODE_PRIVATE)
                .edit()
                .putBoolean("wordhunt/music_enabled", false)
                .apply()
        }
    }

    private fun pauseWordHuntMusic() {
        try {
            musicTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                }
            }
        } catch (e: Exception) {
            OpenPigeonLog.w("WordHuntMusic", "Unable to pause music", e)
        }
    }

    private fun resumeWordHuntMusic() {
        if (!musicEnabled || wordHuntActivityClosing) return

        try {
            val track = musicTrack

            if (track == null) {
                startWordHuntMusic()
            } else if (track.playState != AudioTrack.PLAYSTATE_PLAYING) {
                track.play()
            }
        } catch (e: Exception) {
            OpenPigeonLog.w("WordHuntMusic", "Unable to resume music, restarting", e)
            stopWordHuntMusic()
            startWordHuntMusic()
        }
    }

    private fun stopWordHuntMusic() {
        val track = musicTrack ?: return
        musicTrack = null

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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        enableEdgeToEdge()
        supportActionBar?.hide()

//        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
//            val controller = window.insetsController
//            controller?.hide(WindowInsets.Type.systemBars())
//            controller?.systemBarsBehavior =
//                WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
//        } else {
//            @Suppress("DEPRECATION")
//            window.decorView.systemUiVisibility =
//                (View.SYSTEM_UI_FLAG_FULLSCREEN
//                        or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
//                        or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
//                        or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
//                        or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
//                        or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
//        }

        sessionId = intent.getStringExtra("SESSION")!!

        dictionary = WordDictionary(this)
        com.openbubbles.openpigeon.settings.AvatarData.init(this)
        lateinit var startDestination: String
        GameSessionIPC(applicationContext) { gameSessionIPC ->
            // This is called when the service is bound
            this.gameSessionIPC = gameSessionIPC
            currentMessage = gameSessionIPC.getCurrentMessage(sessionId)
            OpenPigeonLog.i("message", "currentMessage: $currentMessage")

            if (currentMessage.isNotEmpty()) {
                gameSessionIPC.lockMsgHandle(sessionId)
                gameSessionIPC.setSuppressNotifications(sessionId, true)
                gameSessionIPC.onMessageUpdated(sessionId) {
                    synchronized(this) {
                        OpenPigeonLog.i("message", "updated in background")
                        runOnUiThread {
                            val updatedMessage = gameSessionIPC.getCurrentMessage(sessionId)
                            currentMessage = updatedMessage
                            currentMessageState.value = updatedMessage
                        }
                    }
                }

                val player = if (currentMessage["player2"] == gameSessionIPC.getSenderUUID(sessionId)) 2 else 1
                setupGame()
                startDestination = if (!currentMessage["score$player"].isNullOrBlank()) {
                    GameUI.Screen.Score.route
                } else {
                    GameUI.Screen.Intro.route
                }

                setContent {
                    currentMessageState = remember { mutableStateOf(currentMessage) }

                    navController = rememberNavController()
                    gameUI.WordHuntNavigation(navController, startDestination, gameState, { startGameTimer() }, { getScoreData(currentMessageState.value) })
                }

                setupWordHuntSettingsSheet()
            } else {
                OpenPigeonLog.e("openpigeon-${baseGame.getName()}", "$sessionId does not exist!")
                finish()
            }
        }
    }

    private fun setupGame() {
        gameState = WordHuntGameState(dictionary, mode(currentMessage["mode"]!!.toInt()))
        gameState.setBoard(populatedBoard(currentMessage["letters"]!!))
        gameState.isGameActive = true
    }

    private fun startGameTimer() {
        gameTimer?.cancel()

        gameTimer = object : CountDownTimer(GAME_DURATION, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                val secondsLeft = (millisUntilFinished / 1000).toInt()
                gameState.setSecondsLeft(secondsLeft)
//                Log.i("WordHuntActivity", selectionPath.isEmpty.toString())
            }

            override fun onFinish() {
                endGame()
            }
        }.start()
    }

    private fun populatedBoard(letterPool: String): Array<CharArray> {
        val gridSize = gameState.mode.gridSize
        val boardArray= Array(gridSize) { CharArray(gridSize) }
        var poolIndex = 0
        for (i in gridSize - 1 downTo  0) {
            for (j in 0 until gridSize) {
                boardArray[i][j] = letterPool[poolIndex++]
            }
        }
        return boardArray
    }

    private fun endGame() {
        currentMessage = gameSessionIPC!!.getCurrentMessage(sessionId)
        gameTimer?.cancel()
        val player: Int = if (currentMessage["score2"].isNullOrBlank()) 2 else 1
        val opponent = if(player - 1 == 0) 2 else 1
        val score1 = currentMessage["score1"]
        val score2 = currentMessage["score2"]
        val scores = arrayOf(score1, score2)

        val updates = mutableMapOf(
            "sender" to gameSessionIPC!!.getSenderUUID(sessionId),
            "player$player" to gameSessionIPC!!.getSenderUUID(sessionId),
            "avatar$player" to AvatarView.buildAvatarString(),
            "score$player" to gameState.score.toString(),
            "words$player" to gameState.wordCount.toString(),
            "words_list$player" to gameState.sortedWords().joinToString("|"),
        )

        if (!score2.isNullOrBlank() || !score1.isNullOrBlank()){
            updates["winner"] = "${gameSessionIPC!!.getSenderUUID(sessionId)}|${
                if (gameState.score < scores[opponent-1]!!.toInt()) {
                    "-1"
                } else if (gameState.score > scores[opponent-1]!!.toInt()) {
                    "1"
                } else {
                    "0"
                }
            }"
        }

        OpenPigeonLog.i("Word List", gameState.sortedWords().joinToString("|"))
        gameSessionIPC!!.updateSession(updates, sessionId) {
            runOnUiThread {
                currentMessage = gameSessionIPC!!.getCurrentMessage(sessionId)
                gameSessionIPC!!.unlockMsgHandle(sessionId)
                navController.navigate(GameUI.Screen.Score.route)
            }
        }
    }

    private fun getScoreData(msg: Map<String, String>): MutableMap<String, String> {
        val scores = arrayOf(msg["score1"], msg["score2"])

        val client = if(msg["player1"] == gameSessionIPC!!.getSenderUUID(sessionId)) 1 else 2
        val opponent = if(client - 1 == 0) 2 else 1

        val scoreData = mutableMapOf(
            "score1" to (scores[client - 1] ?: gameState.score.toString()),
            "score2" to (scores[opponent - 1] ?: "????"),
            "words1" to (msg["words$client"] ?: gameState.wordCount.toString()),
            "words2" to (msg["words$opponent"] ?: ""),
            "words_list1" to (msg["words_list$client"] ?: gameState.sortedWords().joinToString("|")),
            "words_list2" to (msg["words_list$opponent"] ?: ""),
            // Opponent avatar string so the score screen can display it
            "opponent_avatar" to (msg["avatar$opponent"] ?: ""),
        )
        return scoreData
    }

    @SuppressLint("MissingSuperCall")
    override fun onBackPressed() {
        finish()
    }

    override fun onResume() {
        if (gameSessionIPC != null) {
            gameSessionIPC?.setSuppressNotifications(sessionId, true)
        } else {
            OpenPigeonLog.w("openpigeon-${baseGame.getName()}", "onResume called before gameSessionIPC was initialized!")
        }

        resumeWordHuntMusic()
        super.onResume()
    }

    override fun onPause() {
        pauseWordHuntMusic()
        gameSessionIPC?.setSuppressNotifications(sessionId, false)
        gameTimer?.cancel()
        super.onPause()
    }

    override fun onDestroy() {
        wordHuntActivityClosing = true
        stopWordHuntMusic()
        gameTimer?.cancel()

        if (::settingsSheet.isInitialized) {
            settingsSheet.detach()
        }

        super.onDestroy()
    }
}