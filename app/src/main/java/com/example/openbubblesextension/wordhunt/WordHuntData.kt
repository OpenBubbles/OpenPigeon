package com.example.openbubblesextension.wordhunt

import org.json.JSONObject

class WordHuntData() {
    private val jsonString: String = """{
        "sender" : "F9C3BCE3-3BD9-4051-95D9-57C1263FA5A1nf4vkU",
        "tver":"5",
        "ios":"18.3.2",
        "start":"",
        "caption":"Let's play Word Hunt!",
        "version":"47",
        "id":"YFxftsOVoQyiYnq7",
        "player":"2",
        "player2":"F9C3BCE3-3BD9-4051-95D9-57C1263FA5A1nf4vkU",
        "letters":"ELEOHAHCIACTSNIT",
        "lang":"en",
        "mode":"1",
        "avatar2":"body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021",
        "game":"hunt",
        "game_name":"Word Hunt",
        "num":"1",
        "build":"HeO3hkh1UZH8IaVCaV"
        }"""
    val baseData: JSONObject = JSONObject(jsonString)

    fun newGameData(): JSONObject {
        val gameData = baseData
        gameData.put("sender", "placeholder-sender") // TODO: figure out how to get the sender
        gameData.put("player2", "placeholder-sender") // TODO: ^^
        gameData.put("letters", generateLetters())
        return gameData
    }
    data class GameState(
        val letters: List<String>,
        val foundWords: Set<String> = emptySet(),
        val score: Int = 0,
        val timeRemaining: Int = 60
    )

    private var state = GameState(
        letters = listOf(
            "world", "android", "kotlin", "game",
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

    val letterFrequencies = listOf( "E", "T", "A", "O", "I", "N", "S", "H", "R", "D", "L", "U", "C", "M", "W", "F", "G", "Y", "P", "B", "V", "K", "J", "X", "Q", "Z" )
    private fun generateLetters(): String {
        val vowels = listOf('A', 'E', 'I', 'O', 'U')
        val consonants = letterFrequencies.map { it[0] }.filter { it !in vowels }

        val selectedLetters = mutableListOf<Char>()

        repeat(5) { selectedLetters.add(vowels.random()) }
        repeat(11) { selectedLetters.add(consonants.random()) }

        selectedLetters.shuffle()
        return selectedLetters.toString().replace(", ", "").removeSurrounding("[", "]").uppercase()
    }

    fun generateGrid(letters: String): Array<CharArray> {
        val grid = Array(4) { CharArray(4) }
        var index = 0
        for (i in 0 until 4) {
            for (j in 0 until 4) {
                grid[i][j] = letters[index++]
            }
        }
        return grid
    }
} 