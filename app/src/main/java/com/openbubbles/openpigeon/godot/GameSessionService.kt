package com.openbubbles.openpigeon.godot

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.DeadObjectException
import android.os.IBinder
import com.openbubbles.openpigeon.util.OpenPigeonLog
import com.openbubbles.openpigeon.GameSession
import com.openbubbles.openpigeon.IGameSession
import com.openbubbles.openpigeon.IUpdateGameSessionCallback
import com.openbubbles.openpigeon.IMessageUpdatedCallback
import com.openbubbles.openpigeon.MadridExtension

class GameSessionService : Service() {
    private var onMessageUpdatedCB: IMessageUpdatedCallback? = null

    private val binder = object : IGameSession.Stub() {
        override fun getCurrentMessage(id: String?): Bundle {
            OpenPigeonLog.i("openpigeon-GameSessionService", "${MadridExtension.activeSessions}")
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
                    OpenPigeonLog.e("openpigeon-GameSessionService", "Callback object is dead!")
                }
            }
        }

        override fun getSenderUUID(id: String): String {
            val gameSession: GameSession = MadridExtension.activeSessions[id] ?: return ""
            return gameSession.getGame()!!.getSenderUUID(applicationContext)
        }

        override fun setSuppressNotifications(id: String, suppress: Boolean) {
            val gameSession: GameSession = MadridExtension.activeSessions[id] ?: return
            gameSession.handle.setSuppressNotifications(suppress)
        }

        override fun lockMsgHandle(id: String?) {
            val gameSession: GameSession = MadridExtension.activeSessions[id] ?: return
            gameSession.handle.lock()
        }

        override fun unlockMsgHandle(id: String?) {
            val gameSession: GameSession = MadridExtension.activeSessions[id] ?: return
            gameSession.handle.unlock()
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
                    OpenPigeonLog.e("openpigeon-GameSessionService", "Callback object is dead!")
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