package com.openbubbles.openpigeon

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.runtime.Composable
import com.bluebubbles.messaging.MadridMessage
import java.io.ByteArrayOutputStream
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.UUID
import androidx.core.content.edit

interface Game {

    fun getName(): String
    fun gameClass(): Class<*>

    fun gamePoster(config: Map<String, String>?): Int
    fun displayName(): String

    fun getVersion(): String
    fun getDefaultReplay(): String

    fun isConfigurable(): Boolean {
        return false
    }

    @Composable
    fun Configuration(context: Context?) { }

    fun setConfigOption(name: String, value: String) { }

    fun minPlayerRequirement(): Int {
        return 0
    }

    private fun encodeQuery(params: Map<String, String>): String {
        return params.map { (key, value) ->
            val encodedKey = URLEncoder.encode(key, StandardCharsets.UTF_8.toString())
            val encodedValue = URLEncoder.encode(value, StandardCharsets.UTF_8.toString())
            "$encodedKey=$encodedValue"
        }.joinToString("&", prefix = "?")
    }

    fun getSenderUUID(context: Context): String {
        val sharedPrefs = context.getSharedPreferences("openpigeon", Context.MODE_PRIVATE)
        val sender: String? = sharedPrefs.getString("sender_uuid", null)
        if (sender.isNullOrEmpty()) {
            val newSender = UUID.randomUUID().toString()
            sharedPrefs.edit { putString("sender_uuid", newSender) }
            return newSender
        }
        return sender
    }

    fun buildGameMessage(context: Context, message: Map<String, String>, currentSession: String?): MadridMessage {
        val data = encodeQuery(mapOf(
            "ver" to "52",
            "data" to Cryption.encrypt(encodeQuery(message).replace("+", "%20"))
        ))

        var imageEncoded: String? = null
        if (currentSession == null) {
            val bm = BitmapFactory.decodeResource(context.resources, gamePoster(message))
            val baos = ByteArrayOutputStream()
            bm.compress(Bitmap.CompressFormat.JPEG, 70, baos)
            val b = baos.toByteArray()
            imageEncoded = Base64.encodeToString(b, Base64.NO_WRAP)
        }

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

    fun getNewGameData(context: Context): MutableMap<String, String> {
        val sender = getSenderUUID(context)
        return mutableMapOf(
            "sender" to sender,
            "tver" to "5",
            "ios" to "18.3.2",
            "start" to "",
            "caption" to "Let's play ${displayName()}!",
            "version" to getVersion(),
            "player" to "2",
            "id" to Cryption.getId(),
            "game" to getName(),
            "game_name" to displayName(),
            "num" to "1",
            "build" to "HeO3hkh1UZH8IaVCaV",
            "player2" to sender,
        )
    }

}