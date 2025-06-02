package com.openbubbles.openpigeon.wordhunt

import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.ui.Modifier
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.godot.GameSessionIPC

class WordHuntActivity : AppCompatActivity() {
    private val baseGame: Game = WordHuntGame()

    private var gameSessionIPC: GameSessionIPC? = null
    lateinit var sessionId: String
    private lateinit var currentMessage: Map<String, String>
    private lateinit var dictionary: WordDictionary
    private lateinit var gameState: WordHuntGameState

    private var gameTimer: CountDownTimer? = null

    private val gameUI = GameUI()

    enum class GameMode(val gridSize: Int, val invalidPositions: List<Pair<Int, Int>>){
        MODE1(4, emptyList()),
        MODE2(5, listOf(
            Pair(0,0), Pair(0,4), Pair(2,2), Pair(4,0), Pair(4,4)
        )),
        MODE3(5, listOf(
            Pair(0,2), Pair(2,0), Pair(2,4), Pair(4,2)
        )),
        MODE4(5, emptyList())
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
                    Log.e("WordHunt", "Mode does not exist")
                    GameMode.MODE1
                }
            }
        }
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

        gameSessionIPC = GameSessionIPC(this) { ipc ->
            // This is called when the service is bound
            currentMessage = ipc.getCurrentMessage(sessionId)
            Log.i("message", "currentMessage: $currentMessage")

            if (currentMessage.isNotEmpty()) {

                val score1 = currentMessage["score1"]
                val score2 = currentMessage["score2"]

                if (!score1.isNullOrBlank() && !score2.isNullOrBlank()) {
                    val client = if(currentMessage["player1"] == gameSessionIPC!!.getSenderUUID(sessionId)) 1 else 2
                    val opponent = if(client - 1 == 0) 2 else 1
                    val scores = intArrayOf(score1.toInt(), score2.toInt())
                    setContent {
                        gameUI.ScoreScreen(
                            Modifier, mutableMapOf(
                                "score1" to scores[client-1].toString(),
                                "score2" to scores[opponent-1].toString(),
                                "words1" to currentMessage["words$client"]!!,
                                "words2" to currentMessage["words$opponent"]!!,
                                "words_list1" to currentMessage["words_list$client"]!!,
                                "words_list2" to currentMessage["words_list$opponent"]!!
                            ))
                    }
                } else {
                    ipc.lockMsgHandle(sessionId)
                    setupGame()
                    setContent {
                        gameUI.GameScreen(gameState)
                    }
                }
            } else {
                Log.e("openpigeon-${baseGame.getName()}", "$sessionId does not exist!")
                finish()
            }
        }
    }

    private fun setupGame() {
        gameState = WordHuntGameState(dictionary, mode(currentMessage["mode"]!!.toInt()))
        gameState.setBoard(populatedBoard(currentMessage["letters"]!!))
        gameState.isGameActive = true
        startGameTimer()
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
        gameTimer?.cancel()
        val player: Int = if (currentMessage["score2"].isNullOrBlank()) 2 else 1
        val opponent = if(player - 1 == 0) 2 else 1
        val score1 = currentMessage["score1"]
        val score2 = currentMessage["score2"]
        val scores = arrayOf(score1, score2)
        
        val updates = mutableMapOf(
            "sender" to gameSessionIPC!!.getSenderUUID(sessionId),
            "player$player" to gameSessionIPC!!.getSenderUUID(sessionId),
            "score$player" to gameState.score.toString(),
            "words$player" to gameState.wordCount.toString(),
            "words_list$player" to gameState.sortedWords().joinToString("|"),
        )

        if (!score2.isNullOrBlank() || !score1.isNullOrBlank()){
            updates["winner"] = "${if(player == 1) currentMessage["player1"] else currentMessage["player2"]}|${
                if (gameState.score < scores[opponent-1]!!.toInt()) {
                    "-1"
                } else if (gameState.score > scores[opponent-1]!!.toInt()) {
                    "1"
                } else {
                    "0"
                }
            }"
        }

        Log.i("Word List", gameState.sortedWords().joinToString("|"))
        gameSessionIPC!!.updateSession(updates, sessionId) {
            runOnUiThread {
                gameSessionIPC!!.unlockMsgHandle(sessionId)
                finish()
            }
        }
    }

    override fun onPause() {
        gameSessionIPC!!.setSuppressNotifications(sessionId, false)
        gameTimer?.cancel()
        super.onPause()
    }
}