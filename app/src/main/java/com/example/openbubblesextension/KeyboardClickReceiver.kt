package com.example.openbubblesextension

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import com.bluebubbles.messaging.MadridMessage
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.UUID


class KeyboardClickReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // This method is called when the BroadcastReceiver is receiving an Intent broadcast.

        val game = intent.getStringExtra("game_name")?.let { MadridExtension.findByName(it) } ?: return

        val message = game.buildGameMessage(context, game.getNewGameData(), null)

        MadridExtension.currentKeyboardHandle?.addMessage(message)
    }
}