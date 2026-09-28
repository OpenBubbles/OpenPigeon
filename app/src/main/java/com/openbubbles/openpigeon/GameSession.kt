package com.openbubbles.openpigeon

import android.content.Context
import com.openbubbles.openpigeon.util.OpenPigeonLog
import com.bluebubbles.messaging.IMessageViewHandle
import com.bluebubbles.messaging.MadridMessage
import androidx.core.net.toUri
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import com.bluebubbles.messaging.ITaskCompleteCallback
import android.os.Process

private data class PendingSessionUpdate(
    val context: Context,
    val updates: Map<String, String>,
    val mySession: String,
    val finished: () -> Unit,
)

class GameSession(var handle: IMessageViewHandle) {

    var messageUpdated: (new: MutableMap<String, String>) -> Unit = {}
    private var latestMessageKey: String = ""
    private var handleMessageKey: String = ""
    private var pendingUpdate: PendingSessionUpdate? = null
    var currentMessage: MutableMap<String, String> = mutableMapOf()
    private var outcomeRecorded: Boolean = false
    @OptIn(ExperimentalGlanceRemoteViewsApi::class)
    var liveRemoteViews = GlanceRemoteViews()

    fun handleNewMessage(message: MadridMessage): Boolean {
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
                OpenPigeonLog.e(
                    "openpigeon-gamesession",
                    "Exception parsing $key: $exc",
                )
            }
        }

        OpenPigeonLog.event(
            "DiagSelfTest",
            "ANDROID_HANDLE_NEW_MESSAGE pid=${Process.myPid()} keys=${newMessage.keys.sorted().joinToString(",")}",
        )

        val incomingMessageKey = messageKey(message)

        var previousMessage: Map<String, String> = emptyMap()
        var accepted = false
        var changed = false

        synchronized(this) {
            val currentNum = currentMessage["num"]?.toIntOrNull()
            val incomingNum = newMessage["num"]?.toIntOrNull()

            if (
                currentMessage.isNotEmpty() &&
                currentNum != null &&
                incomingNum != null &&
                incomingNum < currentNum
            ) {
                OpenPigeonLog.w(
                    "GameSession",
                    "Ignoring stale message currentNum=$currentNum incomingNum=$incomingNum",
                )
            } else {
                previousMessage = currentMessage.toMap()
                changed = currentMessage != newMessage

                latestMessageKey = incomingMessageKey
                currentMessage = newMessage
                accepted = true
            }
        }

        if (!accepted) {
            return false
        }

        val isFirstMessage = previousMessage.isEmpty()
        val hadWinnerBefore = previousMessage["winner"] != null
        val hasWinnerNow = newMessage["winner"] != null

        if (isFirstMessage && hasWinnerNow) {
            outcomeRecorded = true
        } else if (!outcomeRecorded && !hadWinnerBefore && hasWinnerNow) {
            outcomeRecorded = true
            recordWinIfApplicable(newMessage)
        }

        if (changed) {
            messageUpdated(newMessage)
        } else {
            OpenPigeonLog.i(
                "GameSession",
                "Ignoring duplicate message num=${newMessage["num"]}",
            )
        }

        return true
    }

    private fun messageKey(message: MadridMessage): String {
        val url = message.url.orEmpty()

        if (url.isNotBlank()) {
            return "url:$url"
        }

        return "guid:${message.messageGuid.orEmpty()}"
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

    fun updateSession(
        context: Context,
        updates: Map<String, String>,
        mySession: String,
        finished: () -> Unit,
    ) {
        dispatchUpdate(
            PendingSessionUpdate(
                context = context.applicationContext,
                updates = updates.toMap(),
                mySession = mySession,
                finished = finished,
            )
        )
    }

    private fun dispatchUpdate(request: PendingSessionUpdate, retried: Boolean = false) {
        val state = synchronized(this) {
            if (
                !locked &&
                latestMessageKey.isNotBlank() &&
                handleMessageKey.isNotBlank() &&
                latestMessageKey != handleMessageKey
            ) {
                pendingUpdate = request
                null
            } else {
                Triple(
                    latestHostHandle?.takeIf { it.asBinder().isBinderAlive && handleMessageKey == latestMessageKey } ?: handle,
                    currentMessage.toMap(),
                    latestMessageKey,
                )
            }
        }

        if (state == null) {
            OpenPigeonLog.w(
                "GameSession",
                "Deferring send for fresh handle session=${request.mySession} locked=$locked handleKey=${handleMessageKey.hashCode()} latestKey=${latestMessageKey.hashCode()}",
            )
            return
        }

        val sendHandle = state.first
        diag("send")
        val baseMessage = state.second
        val baseMessageKey = state.third
        val targetNum = request.updates["num"]?.toIntOrNull()
        val baseNum = baseMessage["num"]?.toIntOrNull()
        if (targetNum != null && baseNum != null && baseNum >= targetNum) {
            OpenPigeonLog.w("GameSession", "Dropping stale send session=${request.mySession} base=$baseNum target=$targetNum")
            if (baseMessage["sender"] == request.updates["sender"]) request.finished()
            return
        }
        val game = MadridExtension.findByName(baseMessage["game"].orEmpty())

        if (game == null) {
            OpenPigeonLog.e(
                "GameSession",
                "Cannot send session=${request.mySession}: game not found",
            )
            return
        }

        val modifiedUpdated = baseMessage.toMutableMap()

        for (update in request.updates) {
            modifiedUpdated[update.key] = update.value
        }

        val myUUID = game.getSenderUUID(request.context)

        if (
            modifiedUpdated["player2"] != myUUID &&
            !modifiedUpdated.containsKey("player1")
        ) {
            modifiedUpdated["player1"] = myUUID
        }

        if (
            game.getName() != "questions" ||
            modifiedUpdated["caption"].isNullOrBlank()
        ) {
            modifiedUpdated["caption"] = game.getSubtitle(
                request.context,
                modifiedUpdated,
            )
        }

        val update = game.buildGameMessage(
            request.context,
            modifiedUpdated,
            currentSession = request.mySession,
        )

        val outgoingMessageKey = messageKey(update)

        OpenPigeonLog.i(
            "GameSession",
            "Sending session=${request.mySession} locked=$locked handleKey=${handleMessageKey.hashCode()} latestKey=${latestMessageKey.hashCode()}",
        )

        try {
            val done = java.util.concurrent.atomic.AtomicBoolean(false)
            sendTimeout.postDelayed({
                if (done.get()) return@postDelayed
                val fresh = synchronized(this) {
                    staleHandle = sendHandle.asBinder()
                    latestHostHandle?.takeIf { it.asBinder() != sendHandle.asBinder() && it.asBinder().isBinderAlive }
                        ?.also { handle = it; if (locked) { it.lock(); hostLocked = it } }
                }
                OpenPigeonLog.w("OPDiag", "send TIMEOUT session=${request.mySession} stale=${sendHandle.asBinder().hashCode()} fresh=${fresh?.asBinder()?.hashCode()} retried=$retried")
                if (fresh != null && !retried && done.compareAndSet(false, true)) dispatchUpdate(request, true)
            }, 8000)
            sendHandle.updateMessage(
                update,
                object : ITaskCompleteCallback.Stub() {
                    override fun complete() {
                        if (!done.compareAndSet(false, true)) return
                        var appliedOutgoingState = false

                        synchronized(this@GameSession) {
                            if (
                                latestMessageKey.isBlank() ||
                                latestMessageKey == baseMessageKey ||
                                latestMessageKey == outgoingMessageKey
                            ) {
                                currentMessage = modifiedUpdated
                                latestMessageKey = outgoingMessageKey
                                handleMessageKey = outgoingMessageKey
                                appliedOutgoingState = true
                            }
                        }

                        if (!appliedOutgoingState) {
                            OpenPigeonLog.i(
                                "GameSession",
                                "Send completed after newer message arrived; preserving newer state session=${request.mySession}",
                            )
                        }

                        request.finished()
                    }
                },
            )
        } catch (throwable: Throwable) {
            OpenPigeonLog.e(
                "GameSession",
                "updateMessage failed session=${request.mySession}; keeping recovery",
                throwable,
            )
        }
    }

    fun getGame(): Game? {
        return MadridExtension.findByName(currentMessage["game"]!!)
    }

    var locked = false

    private var hostLocked: IMessageViewHandle? = null
    private var latestHostHandle: IMessageViewHandle? = null
    private var staleHandle: android.os.IBinder? = null
    private val sendTimeout = android.os.Handler(android.os.Looper.getMainLooper())

    fun diag(step: String) = OpenPigeonLog.i("OPDiag", "$step locked=$locked handle=${handle.asBinder().hashCode()} alive=${handle.asBinder().isBinderAlive} hostLocked=${hostLocked?.asBinder()?.hashCode()} latest=${latestMessageKey.hashCode()} handleKey=${handleMessageKey.hashCode()} cb=${messageUpdated.hashCode()}")

    fun lock() {
        synchronized(this) {
            if (locked && hostLocked?.asBinder() == handle.asBinder()) return
            if (hostLocked?.asBinder() != handle.asBinder()) runCatching { hostLocked?.unlock() }
            handle.lock()
            hostLocked = handle
            locked = true
            OpenPigeonLog.i("GameSession", "Handle LOCKED ${handle.asBinder().hashCode()}")
            diag("lock")
        }
    }

    fun unlock() {
        synchronized(this) {
            if (!locked) return
            locked = false
            OpenPigeonLog.i("GameSession", "Handle UNLOCKED (kept alive ${hostLocked?.asBinder()?.hashCode()})")
            diag("unlock")
        }
    }

    fun updateHandle(
        newHandle: IMessageViewHandle,
        message: MadridMessage,
    ) {
        val newMessageKey = messageKey(message)
        var deferredUpdate: PendingSessionUpdate? = null

        synchronized(this) {
            latestHostHandle = newHandle
            handle = hostLocked?.takeIf { it.asBinder().isBinderAlive && it.asBinder() != staleHandle } ?: newHandle
            handleMessageKey = newMessageKey

            if (latestMessageKey == handleMessageKey) {
                deferredUpdate = pendingUpdate
                pendingUpdate = null
            }
            diag("updateHandle")
        }

        OpenPigeonLog.i(
            "GameSession",
            "Handle updated key=${newMessageKey.hashCode()} guidPresent=${!message.messageGuid.isNullOrBlank()} locked=$locked deferred=${deferredUpdate != null}",
        )

        deferredUpdate?.let {
            dispatchUpdate(it)
        }
    }
}