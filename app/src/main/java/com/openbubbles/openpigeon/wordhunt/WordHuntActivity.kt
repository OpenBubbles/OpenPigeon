package com.openbubbles.openpigeon.wordhunt

import androidx.activity.addCallback
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
import android.widget.FrameLayout
import com.openbubbles.openpigeon.ui.GameMenuController
import com.openbubbles.openpigeon.ui.GameMenuPlacement
import com.openbubbles.openpigeon.ui.RulesPopup
import com.openbubbles.openpigeon.wordgames.WordGameLanguage
import com.openbubbles.openpigeon.wordgames.WordGameLanguages
import kotlin.random.Random
import android.view.View
import android.view.ViewGroup
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.openbubbles.openpigeon.wordhunt.WordHuntSolver.encodeCell

class WordHuntActivity : AppCompatActivity() {
    private val baseGame: Game = WordHuntGame()

    private var gameSessionIPC: GameSessionIPC? = null
    lateinit var sessionId: String
    private lateinit var currentMessage: Map<String, String>
    private lateinit var currentMessageState: MutableState<Map<String, String>>
    private lateinit var dictionary: WordDictionary
    private lateinit var gameState: WordHuntGameState
    private lateinit var gameMenu: GameMenuController

    private var gameTimer: CountDownTimer? = null

    private val gameUI = GameUI()
    private lateinit var navController: NavHostController

    private var gameOpenedLogged = false
    private var localPlayer: Int? = null
    private var spectatorMode: Boolean = false

    private fun logGameOpened(
        msg: Map<String, String>,
        player: Int?,
        startDestination: String,
    ) {
        if (gameOpenedLogged) {
            return
        }

        gameOpenedLogged = true

        OpenPigeonLog.title(
            "WordHunt",
            "Word Hunt",
            "mode=${msg["mode"].orEmpty()} " + "lang=${msg["lang"].orEmpty()} " + "letters=${msg["letters"]?.length ?: 0} " + "player=${player?.toString() ?: "spectator"} " + "spectator=$spectatorMode " + "start=$startDestination " + "score1=${!msg["score1"].isNullOrBlank()} " + "score2=${!msg["score2"].isNullOrBlank()}",
        )
    }

    enum class GameMode(
        val gridSize: Int, val invalidPositions: List<Pair<Int, Int>>, val drawable: Int
    ) {
        MODE1(4, emptyList(), R.drawable.wordhunt_board_mode1), MODE2(
            5, listOf(
                Pair(0, 0), Pair(0, 4), Pair(2, 2), Pair(4, 0), Pair(4, 4)
            ), R.drawable.wordhunt_board_mode2
        ),
        MODE3(
            5, listOf(
                Pair(0, 2), Pair(2, 0), Pair(2, 4), Pair(4, 2)
            ), R.drawable.wordhunt_board_mode3
        ),
        MODE4(5, emptyList(), R.drawable.wordhunt_board_mode1)
    }


    // Game constants
    companion object {
        const val GAME_DURATION = 80000L // 80 seconds
        const val MIN_WORD_LENGTH = 3
        const val LOCAL_AVATAR_VIEW_TAG = "wordhunt_local_avatar"

        fun generateLetterPool(
            context: Context,
            mode: GameMode,
            language: WordGameLanguage,
        ): List<Char> {
            val totalLetters = mode.gridSize * mode.gridSize

            val dictionary = WordGameLanguages.loadDictionary(
                context = context,
                language = language,
            )

            /*
             * Build letter frequencies directly from the selected dictionary.
             * This avoids using English frequencies for Spanish, French,
             * German, Russian, or Italian.
             */
            val frequencies = linkedMapOf<Char, Int>()

            dictionary.forEach { word ->
                if (word.length !in 3..12) {
                    return@forEach
                }

                word.forEach { character ->
                    if (character.isLetter()) {
                        frequencies[character] = frequencies.getOrDefault(
                            character,
                            0,
                        ) + 1
                    }
                }
            }

            if (frequencies.isEmpty()) {
                OpenPigeonLog.w(
                    "WordHunt",
                    "No dictionary frequencies for " + "language=${language.code}; using alphabet fallback",
                )

                return WordGameLanguages.randomLetters(
                    language = language,
                    count = totalLetters,
                ).toList()
            }

            val totalWeight = frequencies.values.sum()
            val random = Random(System.currentTimeMillis())

            fun chooseWeightedLetter(): Char {
                var target = random.nextInt(totalWeight)

                for ((character, weight) in frequencies) {
                    if (target < weight) {
                        return character
                    }

                    target -= weight
                }

                return frequencies.keys.first()
            }

            val letters = MutableList(totalLetters) {
                chooseWeightedLetter()
            }

            letters.shuffle(random)

            OpenPigeonLog.i(
                "WordHunt",
                "generated letters language=${language.code} " + "mode=${mode.name} count=${letters.size} " + "dictionaryWords=${dictionary.size}",
            )

            return letters
        }

        fun mode(mode: Int): GameMode {
            return when (mode) {
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

    private fun refreshWordHuntLocalAvatar() {
        val contentRoot = findViewById<View>(
            android.R.id.content,
        )

        contentRoot.post {
            fun refreshInside(view: View) {
                if (view is AvatarView && view.tag == LOCAL_AVATAR_VIEW_TAG) {
                    view.applyFromAvatarData()
                }

                if (view is ViewGroup) {
                    for (index in 0 until view.childCount) {
                        refreshInside(
                            view.getChildAt(index),
                        )
                    }
                }
            }

            refreshInside(contentRoot)
        }
    }

    private fun setupWordHuntMenu() {
        val rootFrame = findViewById<FrameLayout>(
            android.R.id.content,
        )

        gameMenu = GameMenuController(
            activity = this,
            rootFrame = rootFrame,
            gameId = "wordhunt",
            rulesTitle = "Word Hunt Rules",
            rulesSections = listOf(
                RulesPopup.Section(
                    "Objective",
                    "Find as many valid words as possible before the timer expires.",
                ),
                RulesPopup.Section(
                    "How to Play",
                    "Trace through adjacent letters to form a word. A board position cannot be reused within the same word.",
                ),
                RulesPopup.Section(
                    "Valid Words",
                    "Words must contain at least three letters and must exist in the selected language dictionary.",
                ),
                RulesPopup.Section(
                    "Scoring",
                    "Accepted words add to your score. Longer words are generally more valuable.",
                ),
                RulesPopup.Section(
                    "Winning",
                    "After both players finish, the player with the higher score wins.",
                ),
            ),
            musicAssetPath = "wordhunt/wordhunt.wav",
            placement = GameMenuPlacement.BOTTOM_END,

            fallbackDarkOverlayAlpha = 0.18f,

            onSettingsClosed = {
                AvatarData.refreshFromGodot()
                refreshWordHuntLocalAvatar()
            },
        )
    }

    private fun resolveLocalPlayer(
        message: Map<String, String>,
        senderId: String,
    ): Int? {
        val player1Id = message["player1"].orEmpty()
        val player2Id = message["player2"].orEmpty()

        return when {
            player1Id == senderId -> 1
            player2Id == senderId -> 2

            player1Id.isBlank() -> 1
            player2Id.isBlank() -> 2

            else -> null
        }
    }

    private fun isSpectator(
        message: Map<String, String>,
        senderId: String,
    ): Boolean {
        val player1Id = message["player1"].orEmpty()

        val player2Id = message["player2"].orEmpty()

        return (senderId.isNotBlank() && player1Id.isNotBlank() && player2Id.isNotBlank() && senderId != player1Id && senderId != player2Id)
    }

    private fun hasPlayerSubmitted(
        message: Map<String, String>,
        player: Int,
    ): Boolean {
        return !message["score$player"].isNullOrBlank()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        onBackPressedDispatcher.addCallback(this) {
            finish()
        }

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

        AvatarData.init(this)
        lateinit var startDestination: String
        GameSessionIPC(applicationContext) ipcReady@{ gameSessionIPC ->
            // This is called when the service is bound
            this.gameSessionIPC = gameSessionIPC
            currentMessage = gameSessionIPC.getCurrentMessage(sessionId)
            OpenPigeonLog.i(
                "WordHunt", "currentMessage loaded keys=${currentMessage.keys.sorted()}"
            )

            if (currentMessage.isNotEmpty()) {
                gameSessionIPC.lockMsgHandle(sessionId)
                gameSessionIPC.setSuppressNotifications(sessionId, true)
                gameSessionIPC.onMessageUpdated(
                    sessionId,
                ) {
                    synchronized(this) {
                        OpenPigeonLog.i(
                            "WordHunt",
                            "Message updated in background",
                        )

                        runOnUiThread {
                            val updatedMessage = (gameSessionIPC.getCurrentMessage(
                                sessionId,
                            ))

                            currentMessage = updatedMessage

                            if (::currentMessageState.isInitialized) {
                                currentMessageState.value = (updatedMessage)
                            }

                            if (spectatorMode && ::navController.isInitialized && navController.currentDestination?.route != GameUI.Screen.Score.route) {
                                navController.navigate(
                                    GameUI.Screen.Score.route,
                                ) {
                                    launchSingleTop = true
                                }
                            }
                        }
                    }
                }

                val senderId = gameSessionIPC.getSenderUUID(
                    sessionId,
                )

                spectatorMode = isSpectator(
                    message = currentMessage,
                    senderId = senderId,
                )

                val player: Int? = if (spectatorMode) {
                    null
                } else {
                    resolveLocalPlayer(
                        message = currentMessage,
                        senderId = senderId,
                    )
                }

                if (!spectatorMode && player == null) {
                    OpenPigeonLog.w(
                        "WordHunt",
                        "Unable to resolve player slot. " + "sender=$senderId " + "player1=${currentMessage["player1"].orEmpty()} " + "player2=${currentMessage["player2"].orEmpty()}",
                    )

                    finish()
                    return@ipcReady
                }

                localPlayer = player

                setupGame()

                startDestination = when {
                    spectatorMode -> {
                        GameUI.Screen.Score.route
                    }

                    player != null && hasPlayerSubmitted(
                        message = currentMessage,
                        player = player,
                    ) -> {
                        GameUI.Screen.Score.route
                    }

                    else -> {
                        GameUI.Screen.Intro.route
                    }
                }

                logGameOpened(
                    msg = currentMessage,
                    player = player,
                    startDestination = startDestination,
                )

                setContent {
                    currentMessageState = remember { mutableStateOf(currentMessage) }

                    navController = rememberNavController()
                    gameUI.WordHuntNavigation(
                        navController = navController,
                        startDestination = startDestination,
                        gameState = gameState,
                        spectatorMode = spectatorMode,
                        onGameStart = {
                            startGameTimer()
                        },
                        score = {
                            getScoreData(
                                currentMessageState.value,
                            )
                        },
                    )
                }

                setupWordHuntMenu()
            } else {
                OpenPigeonLog.e("openpigeon-${baseGame.getName()}", "$sessionId does not exist!")
                finish()
            }
        }
    }

    private fun setupGame() {
        val selectedLanguage = WordGameLanguages.fromCode(
            currentMessage["lang"],
        )

        dictionary = WordDictionary(
            context = this,
            language = selectedLanguage,
        )

        val selectedMode = mode(
            currentMessage["mode"]?.toIntOrNull() ?: 1,
        )

        gameState = WordHuntGameState(
            dictionary = dictionary,
            mode = selectedMode,
        )

        val letters = currentMessage["letters"].orEmpty()

        val expectedLetterCount = selectedMode.gridSize * selectedMode.gridSize

        if (letters.length < expectedLetterCount) {
            OpenPigeonLog.e(
                "WordHunt",
                "Invalid board letters: " + "language=${selectedLanguage.code} " + "expected=$expectedLetterCount " + "actual=${letters.length}",
            )

            val fallbackLetters = generateLetterPool(
                context = this,
                mode = selectedMode,
                language = selectedLanguage,
            ).joinToString("")

            gameState.setBoard(
                populatedBoard(fallbackLetters),
            )
        } else {
            gameState.setBoard(
                populatedBoard(letters),
            )
        }

        lifecycleScope.launch(Dispatchers.Default) {
            val words = WordHuntSolver.solve(
                board = gameState.board(),
                gridSize = selectedMode.gridSize,
                invalidPositions = selectedMode.invalidPositions,
                dictionary = dictionary,
                minLength = MIN_WORD_LENGTH,
            )

            withContext(Dispatchers.Main) {
                gameState.setAllWords(words)
            }
        }

        gameState.isGameActive = !spectatorMode

        OpenPigeonLog.i(
            "WordHunt",
            "setupGame language=${selectedLanguage.code} " + "dictionaryWords=${dictionary.size()} " + "mode=${selectedMode.name}",
        )
    }

    private fun startGameTimer() {
        if (spectatorMode) {
            OpenPigeonLog.i(
                "WordHunt",
                "startGameTimer skipped for spectator",
            )

            gameState.isGameActive = false
            gameTimer?.cancel()

            if (::navController.isInitialized && navController.currentDestination?.route != GameUI.Screen.Score.route) {
                navController.navigate(
                    GameUI.Screen.Score.route,
                ) {
                    launchSingleTop = true
                }
            }

            return
        }

        val ipc = gameSessionIPC ?: return

        val player = localPlayer ?: return

        val latestMessage = ipc.getCurrentMessage(
            sessionId,
        )

        currentMessage = latestMessage

        if (::currentMessageState.isInitialized) {
            currentMessageState.value = latestMessage
        }

        val senderId = ipc.getSenderUUID(
            sessionId,
        )

        val registeredPlayerId = latestMessage["player$player"].orEmpty()

        /*
         * The empty slot may have been claimed while this activity was open.
         */
        if (registeredPlayerId.isNotBlank() && registeredPlayerId != senderId) {
            OpenPigeonLog.w(
                "WordHunt",
                "Blocked game start because player slot $player " + "belongs to another ID.",
            )

            finish()
            return
        }

        if (hasPlayerSubmitted(
                message = latestMessage,
                player = player,
            )
        ) {
            OpenPigeonLog.w(
                "WordHunt",
                "Blocked duplicate attempt for player=$player sender=$senderId",
            )

            if (::navController.isInitialized) {
                navController.navigate(
                    GameUI.Screen.Score.route,
                ) {
                    launchSingleTop = true

                    popUpTo(
                        GameUI.Screen.Intro.route,
                    ) {
                        inclusive = true
                    }
                }
            }

            return
        }

        gameState.isGameActive = true

        gameTimer?.cancel()

        gameTimer = object : CountDownTimer(
            GAME_DURATION,
            1000,
        ) {
            override fun onTick(
                millisUntilFinished: Long,
            ) {
                val secondsLeft = (millisUntilFinished / 1000).toInt()

                gameState.setSecondsLeft(
                    secondsLeft,
                )
            }

            override fun onFinish() {
                endGame()
            }
        }.start()
    }

    private fun populatedBoard(letterPool: String): Array<CharArray> {
        val gridSize = gameState.mode.gridSize
        val boardArray = Array(gridSize) { CharArray(gridSize) }
        var poolIndex = 0
        for (i in gridSize - 1 downTo 0) {
            for (j in 0 until gridSize) {
                boardArray[i][j] = letterPool[poolIndex++]
            }
        }
        return boardArray
    }

    private fun endGame() {
        if (spectatorMode) {
            OpenPigeonLog.w(
                "WordHunt",
                "endGame blocked for spectator",
            )

            gameTimer?.cancel()

            if (::gameState.isInitialized) {
                gameState.isGameActive = false
            }

            return
        }

        val ipc = gameSessionIPC ?: return

        val player = localPlayer ?: run {
            OpenPigeonLog.e(
                "WordHunt",
                "Cannot finish game because localPlayer was not resolved.",
            )

            return
        }

        gameState.isGameActive = false
        gameTimer?.cancel()

        currentMessage = ipc.getCurrentMessage(
            sessionId,
        )

        val senderId = ipc.getSenderUUID(
            sessionId,
        )

        val registeredPlayerId = currentMessage["player$player"].orEmpty()

        if (registeredPlayerId.isNotBlank() && registeredPlayerId != senderId) {
            OpenPigeonLog.e(
                "WordHunt",
                "Refusing to submit player=$player because the slot belongs " + "to another ID.",
            )

            return
        }

        if (hasPlayerSubmitted(
                message = currentMessage,
                player = player,
            )
        ) {
            OpenPigeonLog.w(
                "WordHunt",
                "Duplicate submission blocked for player=$player sender=$senderId",
            )

            currentMessageState.value = currentMessage

            navController.navigate(
                GameUI.Screen.Score.route,
            ) {
                launchSingleTop = true
            }

            return
        }

        val opponent = if (player == 1) {
            2
        } else {
            1
        }
        val score1 = currentMessage["score1"]
        val score2 = currentMessage["score2"]
        val scores = arrayOf(score1, score2)

        val updates = mutableMapOf(
            "sender" to senderId,
            "player$player" to senderId,
            "avatar$player" to AvatarView.buildAvatarString(),
            "score$player" to gameState.score.toString(),
            "words$player" to gameState.wordCount.toString(),
            "words_list$player" to gameState.sortedWords().joinToString("|"),
        )

        currentMessage["lang"]?.takeIf { it.isNotBlank() }?.let { languageCode ->
            updates["lang"] = languageCode
        }

        currentMessage["subcaption"]?.takeIf { it.isNotBlank() }?.let { subcaption ->
            updates["subcaption"] = subcaption
        }

        if (!score2.isNullOrBlank() || !score1.isNullOrBlank()) {
            updates["winner"] = "$senderId|${
                if (gameState.score < scores[opponent - 1]!!.toInt()) {
                    "-1"
                } else if (gameState.score > scores[opponent - 1]!!.toInt()) {
                    "1"
                } else {
                    "0"
                }
            }"
        }

        OpenPigeonLog.i("Word List", gameState.sortedWords().joinToString("|"))
        ipc.updateSession(
            updates,
            sessionId,
        ) {
            runOnUiThread {
                val refreshedMessage = runCatching {
                    ipc.getCurrentMessage(
                        sessionId,
                    )
                }.getOrElse { error ->
                    OpenPigeonLog.e(
                        "WordHunt",
                        "Failed to refresh the message after submitting the score.",
                        error,
                    )

                    currentMessage + updates
                }

                currentMessage = refreshedMessage

                if (::currentMessageState.isInitialized) {
                    currentMessageState.value = refreshedMessage
                }

                runCatching {
                    ipc.unlockMsgHandle(
                        sessionId,
                    )
                }.onFailure { error ->
                    OpenPigeonLog.e(
                        "WordHunt",
                        "Could not unlock the message handle after submitting the score.",
                        error,
                    )
                }

                if (
                    !isFinishing &&
                    !isDestroyed &&
                    ::navController.isInitialized &&
                    navController.currentDestination?.route != GameUI.Screen.Score.route
                ) {
                    navController.navigate(
                        GameUI.Screen.Score.route,
                    ) {
                        launchSingleTop = true
                    }
                }
            }
        }
    }

    private fun getScoreData(
        msg: Map<String, String>,
    ): MutableMap<String, String> {
        if (spectatorMode) {
            val player1Score = msg["score1"]?.toIntOrNull()

            val player2Score = msg["score2"]?.toIntOrNull()

            val winnerSlot = if (player1Score != null && player2Score != null) {
                when {
                    player1Score > player2Score -> {
                        "local"
                    }

                    player1Score < player2Score -> {
                        "opponent"
                    }

                    else -> {
                        "draw"
                    }
                }
            } else {
                ""
            }

            return mutableMapOf(
                "score1" to msg["score1"].orEmpty(),
                "score2" to msg["score2"].orEmpty(),

                "words1" to msg["words1"].orEmpty(),
                "words2" to msg["words2"].orEmpty(),

                "words_list1" to (msg["words_list1"].orEmpty()),

                "words_list2" to (msg["words_list2"].orEmpty()),

                "avatar1" to msg["avatar1"].orEmpty(),
                "avatar2" to msg["avatar2"].orEmpty(),
                "winner_slot" to winnerSlot,
                "all_words" to gameState.allWords.joinToString("|"),
                "all_paths" to gameState.allWordPaths.joinToString("|"),
                "board" to gameState.board().joinToString("") { String(it) },
                "grid_size" to gameState.mode.gridSize.toString(),
                "invalid_cells" to String(
                    CharArray(gameState.mode.invalidPositions.size) {
                        val cell = gameState.mode.invalidPositions[it]

                        encodeCell(cell.first * gameState.mode.gridSize + cell.second)
                    },
                ),
            )
        }

        val scores = arrayOf(
            msg["score1"],
            msg["score2"],
        )

        val client = localPlayer ?: if (msg["player1"] == gameSessionIPC!!.getSenderUUID(
                sessionId,
            )
        ) {
            1
        } else {
            2
        }

        val opponent = if (client == 1) {
            2
        } else {
            1
        }

        val localScore = scores[client - 1] ?: gameState.score.toString()

        val opponentScore = scores[opponent - 1]

        val winnerSlot = opponentScore?.toIntOrNull()?.let { parsedOpponentScore ->
            val parsedLocalScore = localScore.toIntOrNull() ?: 0

            when {
                parsedLocalScore > parsedOpponentScore -> {
                    "local"
                }

                parsedLocalScore < parsedOpponentScore -> {
                    "opponent"
                }

                else -> {
                    "draw"
                }
            }
        }.orEmpty()

        return mutableMapOf(
            "score1" to localScore,

            "score2" to (opponentScore ?: "????"),

            "words1" to (msg["words$client"] ?: gameState.wordCount.toString()),

            "words2" to msg["words$opponent"].orEmpty(),

            "words_list1" to (msg["words_list$client"] ?: gameState.sortedWords().joinToString(
                "|",
            )),

            "words_list2" to msg["words_list$opponent"].orEmpty(),

            "opponent_avatar" to msg["avatar$opponent"].orEmpty(),

            "winner_slot" to winnerSlot,

            "all_words" to gameState.allWords.joinToString("|"),
            "all_paths" to gameState.allWordPaths.joinToString("|"),
            "board" to gameState.board().joinToString("") { String(it) },
            "grid_size" to gameState.mode.gridSize.toString(),
            "invalid_cells" to String(
                CharArray(gameState.mode.invalidPositions.size) {
                    val cell = gameState.mode.invalidPositions[it]

                    encodeCell(cell.first * gameState.mode.gridSize + cell.second)
                },
            ),
        )
    }

    override fun onResume() {
        super.onResume()

        if (::gameMenu.isInitialized) {
            gameMenu.onResume()
        }

        if (gameSessionIPC != null) {
            gameSessionIPC?.setSuppressNotifications(
                sessionId,
                true,
            )
        } else {
            OpenPigeonLog.w(
                "openpigeon-${baseGame.getName()}",
                "onResume called before gameSessionIPC was initialized!",
            )
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

        gameTimer?.cancel()

        super.onPause()
    }

    override fun onDestroy() {
        gameTimer?.cancel()

        if (::gameMenu.isInitialized) {
            gameMenu.destroy()
        }

        super.onDestroy()
    }
}