package com.example.openbubblesextension.wordhunt

import com.example.openbubblesextension.Cryption
import org.json.JSONObject

class WordHuntData() {
    val cryption = Cryption()
    private val jsonString: String = """{
        "sender" : "F9C3BCE3-3BD9-4051-95D9-57C1263FA5A1nf4vkU",
        "tver":"5",
        "ios":"18.3.2",
        "start":"",
        "caption":"Let's play Word Hunt!",
        "version":"47",
        "id":"YFxftsOVoQyiYnq7",
        "player":"2",
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
        gameData.put("sender", "A1B2C3D4-E5F6-7890-ABCD-EF1234567890XZ7Q1R") // TODO: figure out how to get the sender
        gameData.put("player2", "A1B2C3D4-E5F6-7890-ABCD-EF1234567890XZ7Q1R") // TODO: ^^
        gameData.put("letters", WordHuntActivity.generateLetterPool().joinToString(""))
        gameData.put("id", cryption.getId())
        return gameData
    }
    data class GameState(
        val letters: List<String>,
        val foundWords: Set<String> = emptySet(),
        val score: Int = 0,
        val timeRemaining: Int = 60
    )
} 