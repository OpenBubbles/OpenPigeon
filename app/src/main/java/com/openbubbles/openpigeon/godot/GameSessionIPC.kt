package com.openbubbles.openpigeon.godot

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import com.openbubbles.openpigeon.IGameSession
import com.openbubbles.openpigeon.IMessageUpdatedCallback
import com.openbubbles.openpigeon.IUpdateGameSessionCallback

class GameSessionIPC(val context: Context, private val onBind: (GameSessionIPC) -> Unit) {
    private var gameSession: IGameSession? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            gameSession = IGameSession.Stub.asInterface(service)
            onBind(this@GameSessionIPC)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            gameSession = null
        }
    }

    init {
        val intent = Intent(".IGameSession")
        intent.setPackage("com.openbubbles.openpigeon")
        context.bindService(intent, connection, Context.BIND_AUTO_CREATE)
    }

    fun getCurrentMessage(id: String): Map<String, String> {
        return gameSession!!.getCurrentMessage(id).toStringMap()
    }

    fun updateSession(updates: Map<String, String>, mySession: String, callback: () -> Unit) {
        val updatesBundle = Bundle().apply {
            for ((key, value) in updates) {
                putString(key, value)
            }
        }
        val ipcCallback = object : IUpdateGameSessionCallback.Stub() {
            override fun onFinished() {
                callback()
            }
        }
        gameSession!!.updateSession(updatesBundle, mySession, ipcCallback)
    }

    fun setSuppressNotifications(id: String, suppress: Boolean) {
        gameSession!!.setSuppressNotifications(id, suppress)
    }

    fun lockMsgHandle(id: String) {
        gameSession!!.lockMsgHandle(id)
    }

    fun unlockMsgHandle(id: String) {
        gameSession!!.unlockMsgHandle(id)
    }

    fun getSenderUUID(id: String): String {
        return gameSession!!.getSenderUUID(id)
    }

    fun onMessageUpdated(id: String, callback: (Map<String, String>) -> Unit) {
        val ipcCallback = object : IMessageUpdatedCallback.Stub() {
            override fun onMessageUpdated(data: Bundle?) {
                callback(data!!.toStringMap())
            }
        }
        gameSession!!.registerCallback(id, ipcCallback)
    }

    private fun Bundle.toStringMap(): Map<String, String> {
        return keySet().mapNotNull { key ->
            getString(key)?.let { key to it }
        }.toMap()
    }
}