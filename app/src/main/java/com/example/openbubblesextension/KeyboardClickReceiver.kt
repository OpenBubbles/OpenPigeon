package com.example.openbubblesextension

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.Image
import android.util.Base64
import com.bluebubbles.messaging.MadridMessage
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.UUID


class KeyboardClickReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // This method is called when the BroadcastReceiver is receiving an Intent broadcast.
        val wordHunt = WordHunt()

        val gameName: String
        val gameImage: Int
        val baseGameData: JSONObject
        when (intent.getStringExtra("game_name")) {
            "hunt" -> {
                gameName = "Word Hunt"
                gameImage = R.drawable.wordhunt
                baseGameData = wordHunt.newGameData()
            }
            "basketball" -> {
                gameName = "Basketball"
                gameImage = R.drawable.basketball
                baseGameData = JSONObject()
            }
            else -> {
                gameName = "Invalid game_name"
                gameImage = R.drawable.my_image
                baseGameData = JSONObject()
            }
        }

        val cryption: Cryption = Cryption()
        val bm = BitmapFactory.decodeResource(context.resources, gameImage)
        val baos = ByteArrayOutputStream()
        bm.compress(Bitmap.CompressFormat.JPEG, 70, baos)
        val b = baos.toByteArray()
        val imageEncoded: String = Base64.encodeToString(b, Base64.NO_WRAP)

        val message = MadridMessage().apply {
            messageGuid = UUID.randomUUID().toString()
            ldText = gameName
            url = cryption.encryptUrl(cryption.jsonToDataUrl(baseGameData))
            session = UUID.randomUUID().toString()

            imageBase64 = imageEncoded
            caption = "Let's Play $gameName!"

            isLive = false
        }

        MadridExtension.currentKeyboardHandle?.addMessage(message)
    }
}