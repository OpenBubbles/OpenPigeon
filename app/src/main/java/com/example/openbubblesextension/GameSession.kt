package com.example.openbubblesextension

import android.content.Context
import android.net.Uri
import com.bluebubbles.messaging.IMessageViewHandle
import com.bluebubbles.messaging.MadridMessage
import java.net.URL
import androidx.core.net.toUri
import com.bluebubbles.messaging.ITaskCompleteCallback

class GameSession(var handle: IMessageViewHandle) {

    var messageUpdated: (new: MutableMap<String, String>) -> Unit = {}
    var currentMessage: MutableMap<String, String> = mutableMapOf()



    fun handleNewMessage(message: MadridMessage) {
        val url = message.url.toUri()
        val data = url.getQueryParameter("data")!!
        val decrypted = Cryption.decrypt(data)
        val parsed = decrypted.toUri()
        val newMessage: MutableMap<String, String> = mutableMapOf()
        for (key in parsed.queryParameterNames) {
            newMessage[key] = parsed.getQueryParameter(key)!!
        }

        messageUpdated(newMessage)
        currentMessage = newMessage
    }

    fun updateSession(context: Context, updates: Map<String, String>, mySession: String, finished: () -> Unit) {
        val modifiedUpdated = currentMessage.toMutableMap()
        for (update in updates) {
            modifiedUpdated[update.key] = update.value
        }

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
        }
    }
}