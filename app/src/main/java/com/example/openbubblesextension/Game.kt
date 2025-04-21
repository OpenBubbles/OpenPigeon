package com.example.openbubblesextension

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import com.bluebubbles.messaging.MadridMessage
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.UUID

interface Game {

    fun getName(): String
    fun buttonId(): Int
    fun gameClass(): Class<*>

    fun gamePoster(): Int
    fun displayName(): String

    fun getVersion(): String

    private fun encodeQuery(params: Map<String, String>): String {
        return params.map { (key, value) ->
            val encodedKey = URLEncoder.encode(key, StandardCharsets.UTF_8.toString())
            val encodedValue = URLEncoder.encode(value, StandardCharsets.UTF_8.toString())
            "$encodedKey=$encodedValue"
        }.joinToString("&", prefix = "?")
    }

    fun buildGameMessage(context: Context, message: Map<String, String>, currentSession: String?): MadridMessage {
        val data = encodeQuery(mapOf(
            "ver" to "52",
            "data" to Cryption.encrypt(encodeQuery(message))
        ))

        val bm = BitmapFactory.decodeResource(context.resources, gamePoster())
        val baos = ByteArrayOutputStream()
        bm.compress(Bitmap.CompressFormat.JPEG, 70, baos)
        val b = baos.toByteArray()
        val imageEncoded: String = Base64.encodeToString(b, Base64.NO_WRAP)

        return MadridMessage().apply {
            messageGuid = UUID.randomUUID().toString()
            ldText = displayName()
            url = "data:$data"
            session = currentSession ?: UUID.randomUUID().toString()

            imageBase64 = imageEncoded
            caption = message["caption"]

            isLive = true
        }
    }

    fun getNewGameData(): MutableMap<String, String> {
        val sender = "F9C3BCE3-3BD9-4051-95D9-57C1263FA5A1nf4vkU"
        return mutableMapOf(
            "sender" to sender,
            "tver" to "5",
            "ios" to "18.3.2",
            "start" to "",
            "caption" to "Let's play ${displayName()}!",
            "version" to getVersion(),
            "player" to "2",
            "id" to Cryption.getId(),
            "avatar2" to "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021",
            "game" to getName(),
            "game_name" to displayName(),
            "num" to "1",
            "build" to "HeO3hkh1UZH8IaVCaV",
            "player2" to sender,
        )
    }

}