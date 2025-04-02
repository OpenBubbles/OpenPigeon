package com.example.openbubblesextension

import org.json.JSONObject

class WordHunt(gamePigeonData: JSONObject) {
    data class GameState(
        val letters: List<String>,
        val foundWords: Set<String> = emptySet(),
        val score: Int = 0,
        val timeRemaining: Int = 60
    )

    private var state = GameState(
        letters = listOf(
            gamePigeonData.getString("letters"), "world", "android", "kotlin", "game",
            "play", "fun", "word", "hunt", "test"
        )
    )

    fun getInitialState(): JSONObject {
        return JSONObject().apply {
            put("words", state.letters)
            put("foundWords", state.foundWords)
            put("score", state.score)
            put("timeRemaining", state.timeRemaining)
        }
    }

    fun checkWord(word: String): Boolean {
        return state.letters.contains(word.lowercase())
    }

    fun addFoundWord(word: String) {
        if (checkWord(word) && !state.foundWords.contains(word)) {
            state = state.copy(
                foundWords = state.foundWords + word,
                score = state.score + word.length
            )
        }
    }

    fun getCurrentState(): GameState = state
} 