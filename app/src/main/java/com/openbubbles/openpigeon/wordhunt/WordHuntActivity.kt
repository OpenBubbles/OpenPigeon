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

    private fun logGameOpened(msg: Map<String, String>, player: Int, startDestination: String) {
        if (gameOpenedLogged) return
        gameOpenedLogged = true

        OpenPigeonLog.title(
            "WordHunt",
            "Word Hunt",
            "mode=${msg["mode"].orEmpty()} " + "lang=${msg["lang"].orEmpty()} " + "letters=${msg["letters"]?.length ?: 0} " + "player=$player " + "start=$startDestination " + "score1=${!msg["score1"].isNullOrBlank()} " + "score2=${!msg["score2"].isNullOrBlank()}",
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
        )
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
        GameSessionIPC(applicationContext) { gameSessionIPC ->
            // This is called when the service is bound
            this.gameSessionIPC = gameSessionIPC
            currentMessage = gameSessionIPC.getCurrentMessage(sessionId)
            OpenPigeonLog.i(
                "WordHunt", "currentMessage loaded keys=${currentMessage.keys.sorted()}"
            )

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

                val player =
                    if (currentMessage["player2"] == gameSessionIPC.getSenderUUID(sessionId)) 2 else 1
                setupGame()
                startDestination = if (!currentMessage["score$player"].isNullOrBlank()) {
                    GameUI.Screen.Score.route
                } else {
                    GameUI.Screen.Intro.route
                }

                logGameOpened(currentMessage, player, startDestination)

                setContent {
                    currentMessageState = remember { mutableStateOf(currentMessage) }

                    navController = rememberNavController()
                    gameUI.WordHuntNavigation(
                        navController,
                        startDestination,
                        gameState,
                        { startGameTimer() },
                        { getScoreData(currentMessageState.value) })
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

        gameState.isGameActive = true

        OpenPigeonLog.i(
            "WordHunt",
            "setupGame language=${selectedLanguage.code} " + "dictionaryWords=${dictionary.size()} " + "mode=${selectedMode.name}",
        )
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
        currentMessage = gameSessionIPC!!.getCurrentMessage(sessionId)
        gameTimer?.cancel()
        val player: Int = if (currentMessage["score2"].isNullOrBlank()) 2 else 1
        val opponent = if (player - 1 == 0) 2 else 1
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

        currentMessage["lang"]?.takeIf { it.isNotBlank() }?.let { languageCode ->
            updates["lang"] = languageCode
        }

        currentMessage["subcaption"]?.takeIf { it.isNotBlank() }?.let { subcaption ->
            updates["subcaption"] = subcaption
        }

        if (!score2.isNullOrBlank() || !score1.isNullOrBlank()) {
            updates["winner"] = "${gameSessionIPC!!.getSenderUUID(sessionId)}|${
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
        gameSessionIPC!!.updateSession(updates, sessionId) {
            runOnUiThread {
                currentMessage = gameSessionIPC!!.getCurrentMessage(sessionId)
                gameSessionIPC!!.unlockMsgHandle(sessionId)
                navController.navigate(GameUI.Screen.Score.route)
            }
        }
    }

    private fun getScoreData(
        msg: Map<String, String>,
    ): MutableMap<String, String> {
        val scores = arrayOf(
            msg["score1"],
            msg["score2"],
        )

        val client = if (msg["player1"] == gameSessionIPC!!.getSenderUUID(
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