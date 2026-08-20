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
import com.openbubbles.openpigeon.TurnRecoveryRecord
import com.openbubbles.openpigeon.TurnRecoveryStore
import com.openbubbles.openpigeon.util.OpenPigeonLog
import java.util.concurrent.ConcurrentHashMap

class GameSessionIPC(
    val context: Context,
    private val onBind: (GameSessionIPC) -> Unit,
) {
    private var gameSession: IGameSession? = null

    private val lastMessages =
        ConcurrentHashMap<String, Map<String, String>>()

    @Volatile
    private var cachedSenderUuid: String = ""

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(
            name: ComponentName?,
            service: IBinder?,
        ) {
            gameSession = IGameSession.Stub.asInterface(
                service,
            )

            onBind(this@GameSessionIPC)
        }

        override fun onServiceDisconnected(
            name: ComponentName?,
        ) {
            gameSession = null

            OpenPigeonLog.w(
                "GameSessionIPC",
                "Game session service disconnected",
            )
        }
    }

    init {
        val intent = Intent(
            ".IGameSession",
        )

        intent.setPackage(
            "com.openbubbles.openpigeon",
        )

        context.bindService(
            intent,
            connection,
            Context.BIND_AUTO_CREATE,
        )
    }

    fun getCurrentMessage(
        id: String,
    ): Map<String, String> {
        val remote = try {
            gameSession
                ?.getCurrentMessage(id)
                ?.toStringMap()
                .orEmpty()
        } catch (throwable: Throwable) {
            OpenPigeonLog.e(
                "GameSessionIPC",
                "getCurrentMessage failed session=$id",
                throwable,
            )

            emptyMap()
        }

        val message = if (remote.isNotEmpty()) {
            lastMessages[id] = remote
            remote
        } else {
            lastMessages[id].orEmpty()
        }

        if (message.isNotEmpty()) {
            TurnRecoveryStore.loadForMessage(
                context,
                id,
                message,
            )
        }

        return message
    }

    fun saveTurnProgress(
        id: String,
        progress: Map<String, String>,
    ): Boolean {
        val current = getCurrentMessage(
            id,
        )

        if (current.isEmpty()) {
            OpenPigeonLog.w(
                "GameSessionIPC",
                "Cannot save turn progress without base message session=$id",
            )

            return false
        }

        return TurnRecoveryStore.saveProgress(
            context = context,
            sessionId = id,
            game = current["game"].orEmpty(),
            baseMessage = current,
            progress = progress,
        )
    }

    fun getTurnRecovery(
        id: String,
    ): TurnRecoveryRecord? {
        val current = getCurrentMessage(
            id,
        )

        return if (current.isNotEmpty()) {
            TurnRecoveryStore.loadForMessage(
                context,
                id,
                current,
            )
        } else {
            TurnRecoveryStore.load(
                context,
                id,
            )
        }
    }

    fun getTurnProgress(
        id: String,
    ): Map<String, String> {
        return getTurnRecovery(
            id,
        )?.progress.orEmpty()
    }

    fun hasPendingSend(
        id: String,
    ): Boolean {
        return getTurnRecovery(
            id,
        )?.sendAttempted == true
    }

    fun updateSession(
        updates: Map<String, String>,
        mySession: String,
        callback: () -> Unit,
    ): Boolean {
        val current = getCurrentMessage(
            mySession,
        )

        val gameName = current["game"].orEmpty()

        if (gameName.isNotBlank()) {
            TurnRecoveryStore.markSendAttempted(
                context = context,
                sessionId = mySession,
                game = gameName,
                baseMessage = current,
                updates = updates,
            )
        }

        val service = gameSession

        if (service == null) {
            OpenPigeonLog.w(
                "GameSessionIPC",
                "SEND FAILED service unavailable session=$mySession",
            )

            return false
        }

        val updatesBundle = Bundle().apply {
            for ((key, value) in updates) {
                putString(
                    key,
                    value,
                )
            }
        }

        val ipcCallback =
            object : IUpdateGameSessionCallback.Stub() {
                override fun onFinished() {
                    TurnRecoveryStore.clear(
                        context,
                        mySession,
                        "ipc_send_confirmed",
                    )

                    callback()
                }
            }

        return try {
            service.updateSession(
                updatesBundle,
                mySession,
                ipcCallback,
            )

            true
        } catch (throwable: Throwable) {
            OpenPigeonLog.e(
                "GameSessionIPC",
                "SEND FAILED session=$mySession",
                throwable,
            )

            false
        }
    }

    fun retryPendingSend(
        mySession: String,
        callback: () -> Unit,
    ): Boolean {
        val recovery = getTurnRecovery(
            mySession,
        )

        /*
         * getTurnRecovery() may have discovered that the remote message
         * already contains our payload and cleared the record. Treat that
         * as success rather than presenting another failure.
         */
        if (recovery == null) {
            callback()
            return true
        }

        if (
            !recovery.sendAttempted ||
            recovery.pendingUpdates.isEmpty()
        ) {
            return false
        }

        OpenPigeonLog.i(
            "GameSessionIPC",
            "Retrying pending send session=$mySession " +
                    "game=${recovery.game}",
        )

        return updateSession(
            recovery.pendingUpdates,
            mySession,
            callback,
        )
    }

    fun setSuppressNotifications(
        id: String,
        suppress: Boolean,
    ) {
        try {
            gameSession?.setSuppressNotifications(
                id,
                suppress,
            )
        } catch (throwable: Throwable) {
            OpenPigeonLog.w(
                "GameSessionIPC",
                "setSuppressNotifications failed",
                throwable,
            )
        }
    }

    fun lockMsgHandle(
        id: String,
    ) {
        try {
            gameSession?.lockMsgHandle(
                id,
            )
        } catch (throwable: Throwable) {
            OpenPigeonLog.w(
                "GameSessionIPC",
                "lockMsgHandle failed",
                throwable,
            )
        }
    }

    fun unlockMsgHandle(
        id: String,
    ) {
        try {
            gameSession?.unlockMsgHandle(
                id,
            )
        } catch (throwable: Throwable) {
            OpenPigeonLog.w(
                "GameSessionIPC",
                "unlockMsgHandle failed",
                throwable,
            )
        }
    }

    fun getSenderUUID(
        id: String,
    ): String {
        return try {
            val sender = gameSession
                ?.getSenderUUID(id)
                .orEmpty()

            if (sender.isNotBlank()) {
                cachedSenderUuid = sender
            }

            sender.ifBlank {
                cachedSenderUuid
            }
        } catch (throwable: Throwable) {
            OpenPigeonLog.w(
                "GameSessionIPC",
                "getSenderUUID failed",
                throwable,
            )

            cachedSenderUuid
        }
    }

    fun onMessageUpdated(
        id: String,
        callback: (Map<String, String>) -> Unit,
    ) {
        val service = gameSession ?: return

        val ipcCallback =
            object : IMessageUpdatedCallback.Stub() {
                override fun onMessageUpdated(
                    data: Bundle?,
                ) {
                    val message = data
                        ?.toStringMap()
                        .orEmpty()

                    if (message.isNotEmpty()) {
                        lastMessages[id] = message

                        TurnRecoveryStore.loadForMessage(
                            context,
                            id,
                            message,
                        )
                    }

                    callback(message)
                }
            }

        try {
            service.registerCallback(
                id,
                ipcCallback,
            )
        } catch (throwable: Throwable) {
            OpenPigeonLog.e(
                "GameSessionIPC",
                "registerCallback failed session=$id",
                throwable,
            )
        }
    }

    private fun Bundle.toStringMap():
            Map<String, String> {
        return keySet().mapNotNull { key ->
            getString(key)?.let {
                key to it
            }
        }.toMap()
    }
}