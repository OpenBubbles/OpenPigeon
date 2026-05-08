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
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView

interface Game {

    fun getName(): String
    fun gameClass(): Class<*>

    fun gamePoster(config: Map<String, String>?): Int

    fun gamePreviewBitmap(context: Context, message: Map<String, String>): Bitmap? {
        return null
    }

    fun displayName(): String

    fun getVersion(): String
    fun getDefaultReplay(): String

    fun playName(): String {
        return displayName()
    }

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

    fun isSupported(message: Map<String, String>): Boolean {
        return true
    }

    fun getSubtitle(context: Context, message: Map<String, String>): String {
        message["winner"]?.let {
            val parts = it.split("|")
            var iWon = message["sender"]!! == parts[0]
            if (parts[1] == "-1") {
                iWon = !iWon
            }
            if (parts[1] == "0") {
                return "Draw!"
            }
            return if (iWon) "I won!" else "You Won!"
        }
        return "Your Move."
    }

    fun getDisplaySubtitle(context: Context, message: Map<String, String>): String {
        message["winner"]?.let {
            val myId = getSenderUUID(context)
            val player1 = message["player1"]
            val player2 = message["player2"]

            // Spectator override
            if (player1 != null && player2 != null && myId != player1 && myId != player2) {
                return "Game Over"
            }

            val parts = it.split("|")
            var iWon = myId == parts[0]
            if (parts[1] == "-1") {
                iWon = !iWon
            }
            if (parts[1] == "0") {
                return "Draw!"
            }
            return if (iWon) "You Won!" else "You Lost!"
        }
        return if (message["caption"]?.startsWith("Let's") == true) {
            message["caption"]!!
        } else {
            val myId = getSenderUUID(context)
            val player1 = message["player1"]
            val player2 = message["player2"]

            if (player1 != null && player2 != null && myId != player1 && myId != player2) {
                "Spectating Game"
            } else if (message["sender"] == myId) {
                "Opponent's Move."
            } else {
                "Your Move."
            }
        }
    }

    fun getWinStateImage(context: Context, message: Map<String, String>): Int? {
        message["winner"]?.let {
            val myId = getSenderUUID(context)
            val player1 = message["player1"]
            val player2 = message["player2"]

            // Spectator override
            if (player1 != null && player2 != null && myId != player1 && myId != player2) {
                return R.drawable.game_end
            }

            val parts = it.split("|")
            var iWon = myId == parts[0]
            if (parts[1] == "-1") {
                iWon = !iWon
            }
            if (parts[1] == "0") {
                return R.drawable.sync_alt_24px
            }
            return if (iWon) R.drawable.crown_24px else R.drawable.close_24px
        }
        return null
    }

    fun buildGameMessage(context: Context, message: Map<String, String>, currentSession: String?): MadridMessage {
        val data = encodeQuery(mapOf(
            "ver" to "52",
            "data" to Cryption.encrypt(encodeQuery(message).replace("+", "%20"))
        ))

        val bm = gamePreviewBitmap(context, message)
            ?: if (currentSession == null) BitmapFactory.decodeResource(context.resources, gamePoster(message)) else null

        var imageEncoded: String? = null
        if (bm != null) {
            val baos = ByteArrayOutputStream()
            bm.compress(Bitmap.CompressFormat.PNG, 90, baos)
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

    fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)
        val sender = getSenderUUID(context)
        return mutableMapOf(
            "sender" to sender,
            "tver" to "5",
            "ios" to "18.3.2",
            "start" to "",
            "caption" to "Let's play ${playName()}!",
            "version" to getVersion(),
            "player" to "2",
            "id" to Cryption.getId(),
            "game" to getName(),
            "game_name" to displayName(),
            "num" to "1",
            "build" to "HeO3hkh1UZH8IaVCaV",
            "player2" to sender,
            "avatar2" to AvatarView.buildAvatarString(),
        )
    }

}