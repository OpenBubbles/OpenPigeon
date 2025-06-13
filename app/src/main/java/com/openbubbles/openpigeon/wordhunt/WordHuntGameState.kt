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

    private val _secondsLeft = mutableIntStateOf(80)
    val secondsLeft: Int get() = _secondsLeft.intValue

    private val _foundWords = mutableStateListOf<String>()
    val wordCount: Int get() = _foundWords.size

    fun sortedWords(): List<String> {
        return _foundWords.sortedWith(compareByDescending<String> { it.length }
            .thenBy { it.lowercase() })
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
        _selectedPositions.clear()
        _selectedPositions.add(Pair(row, col))
        updateCurrentWord()
    }

    // Add to selection if valid
    fun addToSelection(row: Int, col: Int) {
        if (!isSelecting) return

        val position = Pair(row, col)
        val lastPosition = _selectedPositions.lastOrNull() ?: return

        // Check if already selected
        if (position in _selectedPositions) {
            // If going back to the second-last position, remove the last position
            if (_selectedPositions.size >= 2 && position == _selectedPositions[_selectedPositions.size - 2]) {
                _selectedPositions.removeAt(_selectedPositions.size - 1)
                updateCurrentWord()
                updateWordStatus()
            }
            return
        }

        // Check if adjacent
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
            _foundWords.add(word)
            _score.intValue += calculatePoints(word)
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
        _wordStatusColor.value = when(_wordStatus.value) {
            "INVALID" -> Color(0xFFEAEAEA)
            "VALID" -> Color(0xFF86FE8C)
            "FOUND" -> Color(0xFFFFE95E)
            else -> {Color.Cyan}
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