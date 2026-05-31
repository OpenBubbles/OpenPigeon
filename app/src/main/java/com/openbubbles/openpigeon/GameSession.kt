package com.openbubbles.openpigeon

import android.content.Context
import com.openbubbles.openpigeon.util.OpenPigeonLog
import com.bluebubbles.messaging.IMessageViewHandle
import com.bluebubbles.messaging.MadridMessage
import androidx.core.net.toUri
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import com.bluebubbles.messaging.ITaskCompleteCallback

class GameSession(var handle: IMessageViewHandle) {

    var messageUpdated: (new: MutableMap<String, String>) -> Unit = {}
    var currentMessage: MutableMap<String, String> = mutableMapOf()
    private var outcomeRecorded: Boolean = false
    @OptIn(ExperimentalGlanceRemoteViewsApi::class)
    var liveRemoteViews = GlanceRemoteViews()

    fun handleNewMessage(message: MadridMessage) {
        val url = message.url.replace("data:", "data://").toUri()
        val data = url.getQueryParameter("data")!!
        val decrypted = Cryption.decrypt(data)
        val parsed = "data://$decrypted".toUri()
        val newMessage: MutableMap<String, String> = mutableMapOf()
        OpenPigeonLog.i("openpigeon", "New game! $parsed")
        for (key in parsed.queryParameterNames) {
            try {
                newMessage[key] = parsed.getQueryParameter(key)!!
            } catch (exc: Exception) {
                OpenPigeonLog.e("openpigeon-gamesession", "Exception parsing $key: $exc")
            }
        }

        // Detect win transition: winner field newly appeared in this session.
        // First-message-with-winner means we're opening an already-finished game;
        // seed outcomeRecorded=true so we don't count it as a fresh win.
        val isFirstMessage = currentMessage.isEmpty()
        val hasWinnerNow = newMessage["winner"] != null
        if (isFirstMessage && hasWinnerNow) {
            outcomeRecorded = true
        } else if (!outcomeRecorded && hasWinnerNow) {
            outcomeRecorded = true
            recordWinIfApplicable(newMessage)
        }

        messageUpdated(newMessage)
        currentMessage = newMessage
    }

    private fun recordWinIfApplicable(message: Map<String, String>) {
        val context = MadridExtensionService.extension?.context ?: return
        val game = MadridExtension.findByName(message["game"] ?: return) ?: return
        val myId = game.getSenderUUID(context)
        val winnerField = message["winner"] ?: return

        // winner format: "<sender_uuid>|<flag>" where flag -1 inverts who won, 0 = draw
        val parts = winnerField.split("|")
        if (parts.size < 2) return

        val claimedWinner = parts[0]
        val flag = parts[1]

        if (flag == "0") return // Draw, no win to record

        var iWon = myId == claimedWinner
        if (flag == "-1") iWon = !iWon

        // Spectator check: don't record wins for games we aren't in
        val player1 = message["player1"]
        val player2 = message["player2"]
        if (player1 != null && player2 != null && myId != player1 && myId != player2) return

        if (iWon) {
            com.openbubbles.openpigeon.settings.GameStats.init(context)
            com.openbubbles.openpigeon.settings.GameStats.incrementWins(game.getName())
            OpenPigeonLog.i("GameStats", "Recorded win for ${game.getName()}, total=${com.openbubbles.openpigeon.settings.GameStats.getWins(game.getName())}")
        }
    }

    fun updateSession(context: Context, updates: Map<String, String>, mySession: String, finished: () -> Unit) {
        val modifiedUpdated = currentMessage.toMutableMap()
        for (update in updates) {
            modifiedUpdated[update.key] = update.value
        }

        val myUUID = getGame()!!.getSenderUUID(context)
        if (modifiedUpdated["player2"] != myUUID && !modifiedUpdated.containsKey("player1")) {
            modifiedUpdated["player1"] = myUUID
        }

        modifiedUpdated["caption"] = getGame()!!.getSubtitle(context, modifiedUpdated)

        val update = getGame()!!.buildGameMessage(context, modifiedUpdated, currentSession = mySession)

        handle.updateMessage(update, object : ITaskCompleteCallback.Stub() {
            override fun complete() {
                currentMessage = modifiedUpdated
                finished()
            }
        })
    }

    fun getGame(): Game? {
        return MadridExtension.findByName(currentMessage["game"]!!)
    }

    var locked = false

    fun lock() {
        synchronized(this) {
            if (locked) return;
            handle.lock()
            locked = true
        }
    }

    fun unlock() {
        synchronized(this) {
            if (!locked) return;
            handle.unlock()
            locked = false
        }
    }

    fun dispose() {
        synchronized(this) {
            if (locked) {
                handle.unlock()
                locked = false
            }
        }
    }

    fun updateHandle(newHandle: IMessageViewHandle) {
        synchronized(this) {
            if (locked) {
                handle.unlock()
                newHandle.lock()
            }
            handle = newHandle
        }
    }
}