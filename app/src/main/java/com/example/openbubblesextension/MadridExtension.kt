package com.example.openbubblesextension

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.BitmapFactory
import android.util.Log
import android.widget.RemoteViews
import androidx.core.content.ContextCompat.RECEIVER_EXPORTED
import androidx.core.content.ContextCompat.registerReceiver
import com.bluebubbles.messaging.IKeyboardHandle
import com.bluebubbles.messaging.IMadridExtension
import com.bluebubbles.messaging.IMessageViewHandle
import com.bluebubbles.messaging.ITaskCompleteCallback
import com.bluebubbles.messaging.IViewUpdateCallback
import com.bluebubbles.messaging.MadridMessage
import com.example.openbubblesextension.wordhunt.WordHuntActivity
import com.example.openbubblesextension.Cryption.Companion.GAME
import org.json.JSONObject


class MadridExtension(private val context: Context) : IMadridExtension.Stub() {

    companion object {
        var currentKeyboardHandle: IKeyboardHandle? = null
        var broadcastReceiver: BroadcastReceiver? = null
        val cryption = Cryption()
    }

    private var callback: IViewUpdateCallback? = null

    override fun keyboardClosed() {
        currentKeyboardHandle = null
    }

    override fun keyboardOpened(callback: IViewUpdateCallback?, handle: IKeyboardHandle?): RemoteViews {
        this.callback = callback
        var view = RemoteViews(context.packageName, R.layout.keyboard)

        currentKeyboardHandle = handle

        val wordHuntIntentWithData = Intent(
            context,
            KeyboardClickReceiver::class.java
        ).apply {
            putExtra("game_name", "hunt")
        }

        val basketballIntentWithData = Intent(
            context,
            KeyboardClickReceiver::class.java
        ).apply {
            putExtra("game_name", "basketball")
        }

        val wordHuntPendingIntent = PendingIntent.getBroadcast(context, 7, wordHuntIntentWithData,
            PendingIntent.FLAG_IMMUTABLE)
        val basketballPendingIntent = PendingIntent.getBroadcast(context, 8, basketballIntentWithData,
            PendingIntent.FLAG_IMMUTABLE)

        view.setOnClickPendingIntent(R.id.btn_wordhunt, wordHuntPendingIntent)
        view.setOnClickPendingIntent(R.id.btn_basketball, basketballPendingIntent)

        return view
    }

    override fun didTapTemplate(message: MadridMessage?, handle: IMessageViewHandle?) {
        if (message == null) {
            return
        }
        Log.i("Message", message.url)
        Log.i("Tapped Message", cryption.decryptUrl(message.url))

        val gameData = cryption.parseDataUrlToJson(message.url)
        val game = cryption.whichGame(message)
        val gameClass: Class<*> = when (game) {
            GAME.WORDHUNT -> WordHuntActivity::class.java
            GAME.BASKETBALL -> WordHuntActivity::class.java
        }
        val intent = Intent(context, gameClass)
            .apply {
                putExtra("GAME_ENUM", game)
                putExtra("GAME_DATA", gameData.toString())
            }

        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        handle?.lock()

        broadcastReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val newGameData = JSONObject(intent.getStringExtra("GAME_DATA")!!)
                val newCaption = intent.getStringExtra("CAPTION")
                val newUrl = cryption.jsonToDataUrl(newGameData)

                message.url = newUrl
                message.caption = newCaption

                handle!!.updateMessage(message, object : ITaskCompleteCallback.Stub() {
                    override fun complete() {
                        Log.i("sent!", "done")
                        context.unregisterReceiver(broadcastReceiver)
                        handle.unlock()
                    }
                })
            }
        }

        val filter = IntentFilter("com.example.openbubblesextension.GAME_DATA")
        registerReceiver(context, broadcastReceiver, filter, RECEIVER_EXPORTED)
    }

    override fun getLiveView(
        callback: IViewUpdateCallback?,
        message: MadridMessage?,
        handle: IMessageViewHandle?
    ): RemoteViews {
        if (message == null) { return RemoteViews(context.packageName, R.layout.livemsg) }
        Log.i("live view", "init")
        var view = RemoteViews(context.packageName, R.layout.livemsg)
        val gameImage: Int

        when (cryption.whichGame(message)) {
            GAME.WORDHUNT -> {
                gameImage = R.drawable.wordhunt
            }
            GAME.BASKETBALL -> {
                gameImage = R.drawable.basketball
            }
        }
        val bitmap = BitmapFactory.decodeResource(context.resources, gameImage)
        view.setImageViewBitmap(R.id.gameImage, bitmap)
        view.setTextViewText(R.id.gameNameTextView, message.ldText)

        var intent = Intent(context, WordHuntActivity::class.java)
            .apply {
                putExtra("GAME_ENUM", cryption.whichGame(message))
            }
        var pendingIntent = PendingIntent.getBroadcast(context, 9, intent, PendingIntent.FLAG_IMMUTABLE)
        view.setOnClickPendingIntent(R.id.gameImage, pendingIntent)
        return view
    }

    override fun messageUpdated(message: MadridMessage?) {
        Log.i("update", "message")
    }

}