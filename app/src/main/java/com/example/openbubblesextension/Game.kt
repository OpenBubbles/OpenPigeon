package com.example.openbubblesextension

import org.json.JSONObject

interface Game {

    fun getName(): String
    fun buttonId(): Int
    fun gameClass(): Class<*>

    fun gamePoster(): Int
    fun displayName(): String

    fun getVersion(): String
    fun getNewGameData(): JSONObject {
        val obj = JSONObject()
        val sender = "F9C3BCE3-3BD9-4051-95D9-57C1263FA5A1nf4vkU"
        obj.apply {
            put("sender", sender)
            put("tver", "5")
            put("ios", "18.3.2")
            put("start", "")
            put("caption", "Let's play ${displayName()}!")
            put("version", getVersion())
            put("player", "2")
            put("id", Cryption.getId())
            put("avatar2", "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021")
            put("game", getName())
            put("game_name", displayName())
            put("num", "1")
            put("build", "HeO3hkh1UZH8IaVCaV")
            put("player2", sender)
        }
        return obj
    }

}