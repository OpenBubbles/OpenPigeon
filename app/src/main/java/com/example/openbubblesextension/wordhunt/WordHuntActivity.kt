package com.example.openbubblesextension.wordhunt

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Bundle
import android.os.CountDownTimer
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.widget.GridLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.res.ResourcesCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.example.openbubblesextension.R
import kotlin.random.Random
import androidx.core.graphics.toColorInt
import com.bluebubbles.messaging.MadridMessage
import com.example.openbubblesextension.MadridExtension.Companion.cryption
import org.json.JSONObject

class WordHuntActivity : AppCompatActivity(), View.OnTouchListener {

    // Game constants
    companion object {
        const val GRID_SIZE = 4
        const val GAME_DURATION = 80000L // 60 seconds
        const val MIN_WORD_LENGTH = 3

        // Generates a pool of letters for the board.
        fun generateLetterPool(): List<Char> {
            val totalLetters = GRID_SIZE * GRID_SIZE
            val letterPool = mutableListOf<Char>()

            repeat(totalLetters) {
                letterPool.add(('A'..'Z').random())
            }

            return letterPool
        }
    }

    private lateinit var gameData: JSONObject

    // UI components
    private lateinit var scoreLabel: TextView
    private lateinit var timerLabel: TextView
    private lateinit var currentWordDisplay: TextView
    private lateinit var letterGrid: GridLayout
    private lateinit var selectionPathView: SelectionPathView
    private lateinit var foundWordsRecyclerView: RecyclerView

    // Game state
    private val board = Array(GRID_SIZE) { CharArray(GRID_SIZE) }
    private val selectedCells = Array(GRID_SIZE) { BooleanArray(GRID_SIZE) }
    private val currentPath = mutableListOf<Int>()
    private val currentWord = StringBuilder()
    private val foundWords = mutableSetOf<String>()
    private val foundWordsList = mutableListOf<String>()
    private var currentScore = 0
    private var gameTimer: CountDownTimer? = null
    private var gameActive = false

    // Cell positions for drawing
    private val cellCenters = Array(GRID_SIZE * GRID_SIZE) { FloatArray(2) }

    // Path drawing
    private val pathPaint = Paint().apply {
        color = "#4682B4".toColorInt()
        strokeWidth = 20f
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }
    private val selectionPath = Path()

    // Dictionary for word validation
    private lateinit var dictionary: WordDictionary

    // Adapter for the RecyclerView
    private lateinit var wordsAdapter: FoundWordsAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.wordhunt_activity)

        // Initialize UI components
        scoreLabel = findViewById(R.id.scoreLabel)
        timerLabel = findViewById(R.id.timerLabel)
        currentWordDisplay = findViewById(R.id.currentWordDisplay)
        letterGrid = findViewById(R.id.letterGrid)
        selectionPathView = findViewById(R.id.selectionPathView)
        foundWordsRecyclerView = findViewById(R.id.foundWordsList)

        // Initialize the dictionary
        dictionary = WordDictionary(this)

        // Set up the RecyclerView
        wordsAdapter = FoundWordsAdapter(foundWordsList)
        foundWordsRecyclerView.layoutManager = LinearLayoutManager(this)
        foundWordsRecyclerView.adapter = wordsAdapter

        // Set touch listener
        selectionPathView.setOnTouchListener(this)

        // Initialize the game
        setupGame()
    }

    private fun setupGame() {
        // Generate and populate the board
        val gameDataString = intent.getStringExtra("GAME_DATA")!!
        if (gameDataString.isNotEmpty()) {
            gameData = JSONObject(gameDataString)
            populateBoard(gameData.getString("letters"))
        } else {
            populateBoard(generateLetterPool().joinToString(""))
        }

        // Create the letter grid UI
        createLetterGrid()

        // Reset game state
        currentScore = 0
        foundWords.clear()
        foundWordsList.clear()
        wordsAdapter.notifyDataSetChanged()

        // Update UI
        scoreLabel.text = "Score: 0"
        currentWordDisplay.text = ""

        // Start the game timer
        startGameTimer()

        gameActive = true
    }

    // Populates the board using the generated letter pool
    private fun populateBoard(letterPool: String) {
        var poolIndex = 0
        for (i in GRID_SIZE - 1 downTo  0) {
            for (j in 0 until GRID_SIZE) {
                board[i][j] = letterPool[poolIndex++]
            }
        }
    }

    private fun createLetterGrid() {
        // Clear existing views
        letterGrid.removeAllViews()

        // Set up grid parameters
        letterGrid.rowCount = GRID_SIZE
        letterGrid.columnCount = GRID_SIZE

        // Create letter cells
        for (i in 0 until GRID_SIZE) {
            for (j in 0 until GRID_SIZE) {
                val cell = TextView(this).apply {
                    text = board[i][j].toString()
                    textSize = 38f
                    typeface = resources.getFont(R.font.lexend_medium)
                    setTextColor(Color.BLACK)
                    background = ResourcesCompat.getDrawable(context.resources, R.drawable.letter_cell_background, theme)
                    gravity = android.view.Gravity.CENTER
                }

                // Set layout parameters
                val params = GridLayout.LayoutParams().apply {
                    rowSpec = GridLayout.spec(i, 1, 1f)
                    columnSpec = GridLayout.spec(j, 1, 1f)
                    width = 0
                    height = 0
                    setMargins(10, 10, 10, 10)
                }

                cell.layoutParams = params
                letterGrid.addView(cell)

                // Calculate cell position for drawing (will be updated in onLayout)
                val index = i * GRID_SIZE + j
                cell.tag = index

                // We'll update cell centers after layout
                cell.post {
                    val location = IntArray(2)
                    cell.getLocationOnScreen(location)

                    // Store center coordinates
                    val centerX = location[0] + cell.width / 2f
                    val centerY = location[1] + cell.height / 2f

                    // Assign to cell centers array
                    cellCenters[index][0] = centerX
                    cellCenters[index][1] = centerY

                    // Adjust for the position of selectionPathView
                    val pathViewLocation = IntArray(2)
                    selectionPathView.getLocationOnScreen(pathViewLocation)
                    cellCenters[index][0] -= pathViewLocation[0].toFloat()
                    cellCenters[index][1] -= pathViewLocation[1].toFloat()
                }
            }
        }
    }

    private fun startGameTimer() {
        gameTimer?.cancel()

        gameTimer = object : CountDownTimer(GAME_DURATION, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                val secondsLeft = millisUntilFinished / 1000
                timerLabel.text = "Time: ${secondsLeft}s"
//                Log.i("WordHuntActivity", selectionPath.isEmpty.toString())
            }

            override fun onFinish() {
                timerLabel.text = "Time: 0s"
                endGame()
            }
        }.start()
    }

    private fun endGame() {
        gameActive = false
        Toast.makeText(this, "Game Over! Final Score: $currentScore", Toast.LENGTH_LONG).show()

        val player: Int = if (gameData.isNull("score2")) 2 else 1
        Log.i("player", player.toString())
        gameData.remove("player")
        val sortedWordList = foundWordsList.sortedWith(compareByDescending<String> { it.length }
            .thenBy { it.lowercase() })

        gameData.put("sender", "A1B2C3D4-E5F6-7890-ABCD-EF1234567890XZ7Q1R")
        gameData.put("player$player", "A1B2C3D4-E5F6-7890-ABCD-EF1234567890XZ7Q1R")
        gameData.put("score$player", currentScore)
        Log.i("game data", "foundWordsList: $foundWordsList")
        gameData.put("words$player", foundWordsList.size)
        gameData.put("words_list$player", sortedWordList.joinToString("|"))

        // Return game data
        val intent = Intent("com.example.openbubblesextension.GAME_DATA")
        intent.putExtra("GAME_DATA", gameData.toString())

        var caption = "Your turn."
        if (!gameData.isNull("score1") && !gameData.isNull("score2")) {
            val score1 = gameData.getString("score1")
            val score2 = gameData.getString("score2")
            val winner = if (score1 > score2) 1 else 2
            if (player == 2) {
                caption = if (winner == 2) "You Lost!" else "You Win!"
            } else {
                caption = if (winner == 2) "You Win!" else "You Lost!"
            }
        }
        intent.putExtra("CAPTION", caption)
        sendBroadcast(intent)
        Log.i("message","new game data sent")
        finish()
    }

    override fun onTouch(view: View, event: MotionEvent): Boolean {
        if (!gameActive) return false

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                // Start a new selection
                clearSelection()
                processTouchAtPoint(event.x, event.y)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                processTouchAtPoint(event.x, event.y)
                return true
            }
            MotionEvent.ACTION_UP -> {
                // Check if the selected word is valid
                checkWord()
                clearSelection()
                return true
            }
        }
        return false
    }

    private fun processTouchAtPoint(x: Float, y: Float) {
        // Find the cell that was touched
        val cellIndex = findCellAtPoint(x, y)
        if (cellIndex != -1) {
            val row = cellIndex / GRID_SIZE
            val col = cellIndex % GRID_SIZE

            // Check if this is a valid new selection
            if (!selectedCells[row][col] && isAdjacentToLastSelected(row, col)) {
                // Add to selection
                selectedCells[row][col] = true
                currentPath.add(cellIndex)

                // Update current word
                currentWord.append(board[row][col])
                currentWordDisplay.text = currentWord.toString()
            }
        }
        // Update the drawn path
        updateSelectionPath(x,y)
    }

    private fun findCellAtPoint(x: Float, y: Float): Int {
        // Find the nearest cell to the touch point
        for (i in cellCenters.indices) {
            val centerX = cellCenters[i][0]
            val centerY = cellCenters[i][1]

            // Calculate distance from touch to cell center
            val distance = Math.sqrt(Math.pow((x - centerX).toDouble(), 2.0) +
                    Math.pow((y - centerY).toDouble(), 2.0))

            // If within the cell's radius, consider it a match
            if (distance < 100) {
                return i
            }
        }
        return -1 // No cell found
    }

    private fun isAdjacentToLastSelected(row: Int, col: Int): Boolean {
        // First selection is always valid
        if (currentPath.isEmpty()) return true

        val lastCellIndex = currentPath.last()
        val lastRow = lastCellIndex / GRID_SIZE
        val lastCol = lastCellIndex % GRID_SIZE

        // Check if new cell is adjacent (horizontally, vertically, or diagonally)
        val rowDiff = Math.abs(row - lastRow)
        val colDiff = Math.abs(col - lastCol)

        return rowDiff <= 1 && colDiff <= 1 && !(rowDiff == 0 && colDiff == 0)
    }

    private fun updateSelectionPath(x: Float,y: Float) {
        // Clear previous path
        selectionPath.reset()

        if (currentPath.isNotEmpty()) {
            // Move to first point
            val firstIndex = currentPath[0]
            val firstX = cellCenters[firstIndex][0]
            val firstY = cellCenters[firstIndex][1]
            selectionPath.moveTo(firstX, firstY)

            // Add lines to all other points
            for (i in 1 until currentPath.size) {
                val index = currentPath[i]
                val nextX = cellCenters[index][0]
                val nextY = cellCenters[index][1]
                selectionPath.lineTo(nextX, nextY)
            }
            selectionPath.lineTo(x,y)
            // Force redraw
            selectionPathView.path = selectionPath
            selectionPathView.invalidate()
        }
    }

    private fun checkWord() {
        val word = currentWord.toString()

        if (word.length >= MIN_WORD_LENGTH && dictionary.isValidWord(word) && !foundWords.contains(word)) {
            // Valid new word found
            foundWords.add(word)
            foundWordsList.add(0, word) // Add to beginning of list
            wordsAdapter.notifyItemInserted(0)

            // Calculate score based on word length
            val points = calculatePoints(word)
            currentScore += points
            scoreLabel.text = "Score: $currentScore"

            // Show feedback
            Toast.makeText(this, "+$points points!", Toast.LENGTH_SHORT).show()
        } else if (word.length >= MIN_WORD_LENGTH) {
            // Word is either invalid or already found
            val message = if (foundWords.contains(word)) "Already found!" else "Not in dictionary!"
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        }
    }

    private fun calculatePoints(word: String): Int {
        return when (word.length) {
            3 -> 100
            4 -> 400
            5 -> 800
            6 -> 1400
            7 -> 1800
            else -> 2200
        }
    }

    private fun clearSelection() {
        // Reset selection
        for (i in 0 until GRID_SIZE) {
            for (j in 0 until GRID_SIZE) {
                selectedCells[i][j] = false
            }
        }

        currentPath.clear()
        currentWord.clear()
        currentWordDisplay.text = ""

        // Clear the drawn path
        selectionPath.reset()
        selectionPathView.invalidate()
    }

    override fun onDestroy() {
        super.onDestroy()
        gameTimer?.cancel()
    }
}