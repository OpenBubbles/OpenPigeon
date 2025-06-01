package com.openbubbles.openpigeon

import android.content.Context
import android.util.Log
import com.bluebubbles.messaging.IMessageViewHandle
import com.bluebubbles.messaging.MadridMessage
import androidx.core.net.toUri
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import com.bluebubbles.messaging.ITaskCompleteCallback

class GameSession(var handle: IMessageViewHandle) {

    var messageUpdated: (new: MutableMap<String, String>) -> Unit = {}
    var currentMessage: MutableMap<String, String> = mutableMapOf()
    @OptIn(ExperimentalGlanceRemoteViewsApi::class)
    var liveRemoteViews = GlanceRemoteViews()

    fun handleNewMessage(message: MadridMessage) {
        val url = message.url.replace("data:", "data://").toUri()
        val data = url.getQueryParameter("data")!!
        val decrypted = Cryption.decrypt(data)
        val parsed = "data://$decrypted".toUri()
        val newMessage: MutableMap<String, String> = mutableMapOf()
        Log.i("openpigeon", "New game! $parsed")
        for (key in parsed.queryParameterNames) {
            try {
                newMessage[key] = parsed.getQueryParameter(key)!!
            } catch (exc: Exception) {
                Log.e("openpigeon-gamesession", "Exception parsing $key: $exc")
            }
        }

        messageUpdated(newMessage)
        currentMessage = newMessage
    }

    fun updateSession(context: Context, updates: Map<String, String>, mySession: String, finished: () -> Unit) {
        val modifiedUpdated = currentMessage.toMutableMap()
        for (update in updates) {
            modifiedUpdated[update.key] = update.value
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