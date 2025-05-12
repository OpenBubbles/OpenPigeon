package com.example.openbubblesextension

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.util.Log
import android.widget.RemoteViews
import com.bluebubbles.messaging.IKeyboardHandle
import com.bluebubbles.messaging.IMadridExtension
import com.bluebubbles.messaging.IMessageViewHandle
import com.bluebubbles.messaging.IViewUpdateCallback
import com.bluebubbles.messaging.MadridMessage
import com.example.openbubblesextension.basketball.BasketballGame
import com.example.openbubblesextension.checkers.CheckersGame
import com.example.openbubblesextension.connect.ConnectGame
import com.example.openbubblesextension.wordhunt.WordHuntGame
import org.json.JSONObject


class MadridExtension(private val context: Context) : IMadridExtension.Stub() {

    companion object {
        var currentKeyboardHandle: IKeyboardHandle? = null
        var broadcastReceiver: BroadcastReceiver? = null

        val activeSessions: MutableMap<String, GameSession> = mutableMapOf()

        val games: List<Game> = listOf(
            CheckersGame(),
            WordHuntGame(),
            ConnectGame(),
            BasketballGame()
        )

        fun getSessionFor(id: String, handle: IMessageViewHandle): GameSession {
            if (activeSessions.containsKey(id)) {
                activeSessions[id]!!.updateHandle(handle)
            } else {
                activeSessions[id] = GameSession(handle)
            }
            return activeSessions[id]!!
        }

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
        // no need to handle, we only have live messages
    }

    override fun getLiveView(
        callback: IViewUpdateCallback?,
        message: MadridMessage?,
        handle: IMessageViewHandle?
    ): RemoteViews {
        if (message == null) { return RemoteViews(context.packageName, R.layout.livemsg) }
        Log.i("live view", "init")
        var view = RemoteViews(context.packageName, R.layout.livemsg)

        val session = getSessionFor(message.session, handle!!)
        session.handleNewMessage(message)

        val game = session.getGame()

        val bitmap = BitmapFactory.decodeResource(context.resources, game?.gamePoster() ?: R.drawable.empty)
        view.setImageViewBitmap(R.id.gameImage, bitmap)
        view.setTextViewText(R.id.gameNameTextView, message.caption)

        if (game != null) {
            var intent = Intent(context, game.gameClass())
                .apply {
                    putExtra("SESSION", message.session)
                }
            val requestCode = System.currentTimeMillis().toInt()
            var pendingIntent = PendingIntent.getActivity(context, requestCode, intent, PendingIntent.FLAG_IMMUTABLE)
            view.setOnClickPendingIntent(R.id.gameImage, pendingIntent)
        }
        return view
    }

    override fun messageUpdated(message: MadridMessage?) {
        if (message == null) return
        activeSessions[message.session]?.handleNewMessage(message)
        Log.i("update", "message")
    }

}