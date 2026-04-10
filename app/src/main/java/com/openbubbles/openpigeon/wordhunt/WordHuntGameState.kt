package com.openbubbles.openpigeon.wordhunt

import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.Color
import com.openbubbles.openpigeon.wordhunt.WordHuntActivity.Companion.MIN_WORD_LENGTH

class WordHuntGameState(private val dictionary: WordDictionary, val mode: WordHuntActivity.GameMode) {
    var isGameActive: Boolean = false
    private val _selectedPositions = mutableStateListOf<Pair<Int, Int>>()
    val selectedPositions: List<Pair<Int, Int>> = _selectedPositions

    private val _currentWord = mutableStateOf("")
    val currentWord: String get() = _currentWord.value

    private val _wordStatus = mutableStateOf("VALID")
    val wordStatus: String get() = _wordStatus.value
    private val _wordStatusColor = mutableStateOf(Color.Gray)
    val wordStatusColor get() = _wordStatusColor.value

    private val _score = mutableIntStateOf(0)
    val score get() = _score.intValue

    private val _lastAwardedText = mutableStateOf<String?>(null)
    val lastAwardedText: String? get() = _lastAwardedText.value

    private val _validWordTrigger = mutableIntStateOf(0)
    val validWordTrigger: Int get() = _validWordTrigger.intValue

    private var lastBuzzedValidWord: String? = null

    private val _lastAwardedTrigger = mutableIntStateOf(0)
    val lastAwardedTrigger: Int get() = _lastAwardedTrigger.intValue

    private val _secondsLeft = mutableIntStateOf(80)
    val secondsLeft: Int get() = _secondsLeft.intValue

    private val _foundWords = mutableStateListOf<String>()
    val wordCount: Int get() = _foundWords.size

    fun sortedWords(): List<String> {
        return _foundWords.sortedWith(compareByDescending<String> { it.length }
            .thenBy { it.lowercase() })
    }

    fun clearLastAwardedText() {
        _lastAwardedText.value = null
    }

    private fun checkWord(word: String): String {
        if (word.length >= MIN_WORD_LENGTH && dictionary.isValidWord(word) && !_foundWords.contains(word)) {
            return "VALID"
        } else {
            // Word is either invalid or already found
            return if (_foundWords.contains(word)) "FOUND" else "INVALID"
        }
    }

    private var isSelecting = false

    private lateinit var board: Array<CharArray>

    fun setBoard(gameBoard: Array<CharArray>) {
        board = gameBoard
    }

    fun board(): Array<CharArray> {
        return board
    }

    fun startSelection(row: Int, col: Int) {
//        Log.d("Selection Started", "Row: $row, Column: $col")
        isSelecting = true
        lastBuzzedValidWord = null
        _selectedPositions.clear()
        _selectedPositions.add(Pair(row, col))
        updateCurrentWord()
    }

    // Add to selection if valid
    fun addToSelection(row: Int, col: Int) {
        if (!isSelecting) return

        val position = Pair(row, col)
        val lastPosition = _selectedPositions.lastOrNull() ?: return

        // Ignore any tile that is already part of the current path
        if (position in _selectedPositions) {
            return
        }

        // Only allow adding adjacent new tiles
        if (isAdjacent(lastPosition, position)) {
            _selectedPositions.add(position)
            updateCurrentWord()
            updateWordStatus()
        }
    }

    // End selection and return the formed word
    fun endSelection() {
        val word = currentWord
        isSelecting = false
        _selectedPositions.clear()
        _currentWord.value = ""

        if (checkWord(word) == "VALID") {
            val points = calculatePoints(word)
            _foundWords.add(word)
            _score.intValue += points
            _lastAwardedText.value = "$word +$points"
            _lastAwardedTrigger.intValue += 1
        }

        updateWordStatus()
    }

    // Check if two positions are adjacent
    private fun isAdjacent(p1: Pair<Int, Int>, p2: Pair<Int, Int>): Boolean {
        val (r1, c1) = p1
        val (r2, c2) = p2
        val rowDiff = kotlin.math.abs(r1 - r2)
        val colDiff = kotlin.math.abs(c1 - c2)

        return rowDiff <= 1 && colDiff <= 1 && !(rowDiff == 0 && colDiff == 0)
    }

    // Update the current word based on selected positions
    private fun updateCurrentWord() {
        _currentWord.value = _selectedPositions.joinToString("") { (row, col) ->
            board[row][col].toString()
        }
    }

    private fun updateWordStatus() {
        _wordStatus.value = checkWord(_currentWord.value)

        _wordStatusColor.value = when (_wordStatus.value) {
            "INVALID" -> Color(0xFFEAEAEA)
            "VALID" -> Color(0xFF86FE8C)
            "FOUND" -> Color(0xFFFFE95E)
            else -> Color.Cyan
        }

        if (_wordStatus.value == "VALID" && _currentWord.value != lastBuzzedValidWord) {
            lastBuzzedValidWord = _currentWord.value
            _validWordTrigger.intValue += 1
        }
    }

    fun setSecondsLeft(seconds: Int) {
        _secondsLeft.intValue = seconds
    }

    companion object {
        fun calculatePoints(word: String): Int {
            return when (word.length) {
                3 -> 100
                4 -> 400
                5 -> 800
                6 -> 1400
                7 -> 1800
                else -> 2200
            }
        }
    }
}