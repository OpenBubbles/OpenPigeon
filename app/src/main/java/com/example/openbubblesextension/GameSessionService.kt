package com.example.openbubblesextension

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.IBinder
import com.example.openbubblesextension.IGameSession
import com.example.openbubblesextension.IUpdateGameSessionCallback

class GameSessionService : Service() {

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
                callback?.onFinished()
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