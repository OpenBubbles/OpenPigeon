package com.example.openbubblesextension.checkers

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.GameSession
import com.example.openbubblesextension.IGameSession
import com.example.openbubblesextension.IMessageUpdatedCallback
import com.example.openbubblesextension.IUpdateGameSessionCallback

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
        val intent = Intent("com.example.openbubblesextension.IGameSession")
        intent.setPackage("com.example.openbubblesextension")
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