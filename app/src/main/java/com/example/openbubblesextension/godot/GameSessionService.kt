package com.example.openbubblesextension.godot

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.DeadObjectException
import android.os.IBinder
import android.util.Log
import com.example.openbubblesextension.GameSession
import com.example.openbubblesextension.IGameSession
import com.example.openbubblesextension.IUpdateGameSessionCallback
import com.example.openbubblesextension.IMessageUpdatedCallback
import com.example.openbubblesextension.MadridExtension

class GameSessionService : Service() {
    private var onMessageUpdatedCB: IMessageUpdatedCallback? = null

    private val binder = object : IGameSession.Stub() {
        override fun getCurrentMessage(id: String?): Bundle {
            val gameSession: GameSession = MadridExtension.activeSessions[id!!] ?: return Bundle()

            return Bundle().apply {
                for ((key, value) in gameSession.currentMessage) {
                    putString(key, value)
                }
            }
        }

        override fun updateSession(updates: Bundle, mySession: String, callback: IUpdateGameSessionCallback?) {
            val gameSession: GameSession = MadridExtension.activeSessions[mySession] ?: return
            val updateMap = updates.toStringMap()
            gameSession.updateSession(applicationContext, updateMap, mySession) {
                try {
                    callback?.onFinished()
                } catch(e: DeadObjectException) {
                    Log.e("openpigeon-checkers", "Callback object is dead!")
                }
            }
        }

        override fun registerCallback(id: String, callback: IMessageUpdatedCallback?) {
            val gameSession: GameSession = MadridExtension.activeSessions[id] ?: return
            onMessageUpdatedCB = callback

            gameSession.messageUpdated = { new: MutableMap<String, String> ->
                try {
                    callback?.onMessageUpdated(Bundle().apply {
                        for ((key, value) in new) {
                            putString(key, value)
                        }
                    })
                } catch (e: DeadObjectException) {
                    Log.e("openpigeon-checkers", "Callback object is dead!")
                    gameSession.messageUpdated = {}
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    private fun Bundle.toStringMap(): Map<String, String> {
        return keySet().mapNotNull { key ->
            getString(key)?.let { key to it }
        }.toMap()
    }
}