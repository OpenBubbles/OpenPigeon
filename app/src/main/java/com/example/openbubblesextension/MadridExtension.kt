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
import com.example.openbubblesextension.wordhunt.WordHuntGame
import org.json.JSONObject


class MadridExtension(private val context: Context) : IMadridExtension.Stub() {

    companion object {
        var currentKeyboardHandle: IKeyboardHandle? = null
        var broadcastReceiver: BroadcastReceiver? = null

        val games: List<Game> = listOf(
            WordHuntGame()
        )

        fun whichGame(game: JSONObject): Game? {
            return findByName(game.getString("game"))
        }

        fun findByName(name: String): Game? {
            return games.find { it.getName() == name }
        }
    }

    private var callback: IViewUpdateCallback? = null

    override fun keyboardClosed() {
        currentKeyboardHandle = null
    }

    override fun keyboardOpened(callback: IViewUpdateCallback?, handle: IKeyboardHandle?): RemoteViews {
        this.callback = callback
        var view = RemoteViews(context.packageName, R.layout.keyboard)

        currentKeyboardHandle = handle

        for (game in games) {
            val intentWithData = Intent(
                context,
                KeyboardClickReceiver::class.java
            ).apply {
                putExtra("game_name", game.getName())
            }

            val pendingIntent = PendingIntent.getBroadcast(context, game.getName().hashCode(), intentWithData,
                PendingIntent.FLAG_IMMUTABLE)
            view.setOnClickPendingIntent(game.buttonId(), pendingIntent)
        }

        return view
    }

    override fun didTapTemplate(message: MadridMessage?, handle: IMessageViewHandle?) {
        if (message == null) {
            return
        }
        Log.i("Message", message.url)
        Log.i("Tapped Message", Cryption.decryptUrl(message.url))

        val gameData = Cryption.parseDataUrlToJson(message.url)

        val game = whichGame(gameData) ?: return
        val intent = Intent(context, game.gameClass())
            .apply {
                putExtra("GAME_DATA", gameData.toString())
            }

        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        handle?.lock()

        broadcastReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val newGameData = JSONObject(intent.getStringExtra("GAME_DATA")!!)
                val newCaption = intent.getStringExtra("CAPTION")
                val newUrl = Cryption.jsonToDataUrl(newGameData)

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

        val gameData = Cryption.parseDataUrlToJson(message.url)
        val game = whichGame(gameData)

        val bitmap = BitmapFactory.decodeResource(context.resources, game?.gamePoster() ?: R.drawable.empty)
        view.setImageViewBitmap(R.id.gameImage, bitmap)
        view.setTextViewText(R.id.gameNameTextView, message.ldText)

        if (game != null) {
            var intent = Intent(context, game.gameClass())
                .apply {
                    putExtra("GAME_DATA", gameData.toString())
                }
            var pendingIntent = PendingIntent.getBroadcast(context, 9, intent, PendingIntent.FLAG_IMMUTABLE)
            view.setOnClickPendingIntent(R.id.gameImage, pendingIntent)
        }
        return view
    }

    override fun messageUpdated(message: MadridMessage?) {
        Log.i("update", "message")
    }

}