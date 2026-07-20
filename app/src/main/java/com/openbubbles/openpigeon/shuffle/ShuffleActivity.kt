package com.openbubbles.openpigeon.shuffle

import android.content.Context
import com.openbubbles.openpigeon.godot.GameSessionIPC
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import android.view.Gravity
import android.view.Window
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.settings.SettingsSheet
import com.openbubbles.openpigeon.util.OpenPigeonLog
import android.animation.ValueAnimator
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.util.TypedValue
import android.view.View
import android.widget.TextView

class ShuffleActivity : AppCompatActivity() {
    private var sessionId: String = ""
    private var gameSessionIPC: GameSessionIPC? = null
    private var lastMessage: Map<String, String> = emptyMap()

    private var localPlayer: Int = 1
    private var lastOutgoingReplay: String? = null
    private var lastPlayedQueuedReplayKey: String? = null

    private var pendingMessageAfterPlayback:
            Map<String, String>? = null
    private var ignoreNextOutgoingReplayEcho = false
    private val stateLabelHandler = Handler(Looper.getMainLooper())
    private var waitingDotsRunnable: Runnable? = null
    private var stateLabelAnimator: ValueAnimator? = null
    private var sentWaitingSequenceActive = false
    private lateinit var stateLabel: TextView

    private lateinit var rootFrame: FrameLayout
    private lateinit var renderer: ShuffleRenderer
    private lateinit var settingsSheet: SettingsSheet

    private lateinit var myAvatarAnchor: FrameLayout
    private lateinit var opponentAvatarAnchor: FrameLayout
    private lateinit var settingsButton: ImageButton

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestWindowFeature(Window.FEATURE_NO_TITLE)
        supportActionBar?.hide()
        enableEdgeToEdge()

        AvatarData.init(applicationContext)

        rootFrame = FrameLayout(this)
        setContentView(rootFrame)

        ViewCompat.setOnApplyWindowInsetsListener(findViewById(android.R.id.content)) { _, insets ->
            insets
        }

        renderer = ShuffleRenderer(this).apply {
            onLaunchReplayReady = { stagedReplay ->
                handleLocalLaunchReplay(stagedReplay)
            }
        }

        rootFrame.addView(
            renderer,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        settingsSheet = SettingsSheet(this, rootFrame)

        createAvatarHud()
        createSettingsButton()

        createStateLabel()
        hideStateLabelNow()

        settingsSheet.attachGameAvatar(myAvatarAnchor)
        settingsSheet.attachOpponentAvatar(opponentAvatarAnchor)

        startGameSession()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        setIntent(intent)

        val directData = extractMessageData(intent)

        OpenPigeonLog.i(
            "ShuffleActivity",
            "onNewIntent directKeys=${directData.keys.sorted()} mode=${directData["mode"]} map=${directData["map"]}"
        )

        if (directData.isNotEmpty()) {
            handleMessage(directData)
        } else if (lastMessage.isNotEmpty()) {
            handleMessage(lastMessage)
        }
    }

    private fun startGameSession() {
        sessionId = intent.getStringExtra("SESSION") ?: ""

        val directData = extractMessageData(intent)

        OpenPigeonLog.i(
            "ShuffleActivity",
            "startGameSession sessionIdBlank=${sessionId.isBlank()} " +
                    "extras=${intent.extras?.keySet()?.sorted().orEmpty()} " +
                    "dataUri=${intent.data} directKeys=${directData.keys.sorted()} " +
                    "directMode=${directData["mode"]} directMap=${directData["map"]}"
        )

        if (directData.isNotEmpty() && hasUsableShuffleData(directData)) {
            handleMessage(directData)
        }

        if (sessionId.isBlank()) {
            if (directData.isEmpty()) {
                OpenPigeonLog.w(
                    "ShuffleActivity",
                    "No SESSION and no direct shuffle data; showing local fallback"
                )

                handleMessage(defaultLocalMessage())
            }

            return
        }

        GameSessionIPC(applicationContext) { ipc ->
            gameSessionIPC = ipc

            val currentMessage = try {
                OpenPigeonLog.i(
                    "ShuffleActivity",
                    "IPC getCurrentMessage start sessionIdBlank=${sessionId.isBlank()}"
                )

                ipc.getCurrentMessage(sessionId)
            } catch (t: Throwable) {
                OpenPigeonLog.e("ShuffleActivity", "IPC getCurrentMessage failed", t)
                emptyMap()
            }

            OpenPigeonLog.i(
                "ShuffleActivity",
                "IPC currentMessage ${messageSummary(currentMessage)}"
            )

            if (currentMessage.isNotEmpty()) {
                try {
                    ipc.lockMsgHandle(sessionId)
                } catch (t: Throwable) {
                    OpenPigeonLog.e("ShuffleActivity", "IPC lockMsgHandle failed", t)
                }

                try {
                    ipc.setSuppressNotifications(sessionId, true)
                } catch (t: Throwable) {
                    OpenPigeonLog.e("ShuffleActivity", "IPC setSuppressNotifications(true) failed", t)
                }

                try {
                    ipc.onMessageUpdated(sessionId) { msg ->
                        OpenPigeonLog.i(
                            "ShuffleActivity",
                            "IPC onMessageUpdated ${messageSummary(msg)}"
                        )

                        runOnUiThread {
                            handleMessage(msg)
                        }
                    }
                } catch (t: Throwable) {
                    OpenPigeonLog.e("ShuffleActivity", "IPC onMessageUpdated failed", t)
                }

                runOnUiThread {
                    handleMessage(currentMessage)
                }
            } else {
                runOnUiThread {
                    if (lastMessage.isEmpty()) {
                        OpenPigeonLog.w(
                            "ShuffleActivity",
                            "IPC currentMessage empty; showing local fallback"
                        )

                        handleMessage(defaultLocalMessage())
                    }
                }
            }
        }
    }

    private fun handleMessage(
        message: Map<String, String>,
    ) {
        if (message.isEmpty()) {
            return
        }

        val game =
            message["game"]

        if (
            !game.isNullOrBlank() &&
            game != "shuffle"
        ) {
            OpenPigeonLog.w(
                "ShuffleActivity",
                "Ignoring non-shuffle message " +
                        "game=$game " +
                        "keys=${message.keys.sorted()}",
            )

            return
        }

        val incomingReplay =
            message["replay"].orEmpty()

        if (
            ignoreNextOutgoingReplayEcho &&
            incomingReplay ==
            lastOutgoingReplay
        ) {
            ignoreNextOutgoingReplayEcho =
                false

            OpenPigeonLog.i(
                "ShuffleActivity",
                "Ignoring own outgoing replay echo",
            )

            return
        }

        if (renderer.isPlayingRound()) {
            pendingMessageAfterPlayback =
                message

            OpenPigeonLog.i(
                "ShuffleActivity",
                "Queued message during shuffle playback " +
                        messageSummary(message),
            )

            return
        }

        lastMessage =
            message

        OpenPigeonLog.i(
            "ShuffleActivity",
            "handleMessage ${messageSummary(message)}",
        )

        applyGameData(
            message,
        )
    }

    private fun finishPlaybackOrApplyQueuedMessage(
        onNoQueuedMessage: () -> Unit,
    ) {
        val queuedMessage =
            pendingMessageAfterPlayback

        pendingMessageAfterPlayback =
            null

        if (queuedMessage != null) {
            OpenPigeonLog.i(
                "ShuffleActivity",
                "Applying message queued during playback " +
                        messageSummary(queuedMessage),
            )

            handleMessage(
                queuedMessage,
            )

            return
        }

        onNoQueuedMessage()
    }

    private fun applyGameData(
        data: Map<String, String>,
    ) {
        val rawReplay =
            data["replay"].orEmpty()

        OpenPigeonLog.i(
            "ShuffleActivity",
            "applyGameData " +
                    "mode=${data["mode"]} " +
                    "map=${data["map"]} " +
                    "replay=${rawReplay.take(160)}",
        )

        localPlayer =
            resolveLocalPlayer(
                data,
            )

        renderer.setLocalPlayer(
            localPlayer,
        )

        applyOpponentAvatarFromMessage(
            data,
        )

        myAvatarAnchor.bringToFront()
        opponentAvatarAnchor.bringToFront()
        settingsButton.bringToFront()

        val markerIndex =
            rawReplay.indexOf(
                REPLAY_QUEUE_MARKER,
            )

        if (markerIndex >= 0) {
            val queuedRoundReplay =
                rawReplay
                    .substring(
                        0,
                        markerIndex,
                    )
                    .trim()
                    .trimEnd('|')

            val postRoundReplay =
                rawReplay
                    .substring(
                        markerIndex +
                                REPLAY_QUEUE_MARKER.length,
                    )
                    .trim()
                    .trimStart('|')
                    .ifBlank {
                        DEFAULT_REPLAY
                    }

            val queuedReplayKey =
                buildString {
                    append(
                        data["id"].orEmpty(),
                    )

                    append("|")

                    append(
                        data["num"].orEmpty(),
                    )

                    append("|")

                    append(
                        rawReplay.hashCode(),
                    )
                }

            val shouldPlayQueuedRound =
                isYourTurn(data) &&
                        queuedRoundReplay.isNotBlank() &&
                        queuedReplayKey !=
                        lastPlayedQueuedReplayKey

            val postRoundData =
                data
                    .toMutableMap()
                    .apply {
                        put(
                            "replay",
                            postRoundReplay,
                        )
                    }

            if (shouldPlayQueuedRound) {
                lastPlayedQueuedReplayKey =
                    queuedReplayKey

                val roundData =
                    data
                        .toMutableMap()
                        .apply {
                            put(
                                "replay",
                                queuedRoundReplay,
                            )
                        }

                renderer.setGameData(
                    roundData,
                )

                hideStateLabelNow()

                OpenPigeonLog.i(
                    "ShuffleActivity",
                    "Playing queued shuffle replay " +
                            "key=$queuedReplayKey " +
                            "round=${queuedRoundReplay.take(260)} " +
                            "post=${postRoundReplay.take(260)}",
                )

                renderer.playRoundFromReplay(
                    roundReplay =
                        queuedRoundReplay,
                ) {
                    finishPlaybackOrApplyQueuedMessage {
                        lastMessage =
                            postRoundData

                        renderer.setGameData(
                            postRoundData,
                        )

                        applyTurnFlow(
                            postRoundData,
                        )
                    }
                }

                return
            }

            lastMessage =
                postRoundData

            renderer.setGameData(
                postRoundData,
            )

            applyTurnFlow(
                postRoundData,
            )

            return
        }

        renderer.setGameData(
            data,
        )

        applyTurnFlow(
            data,
        )
    }

    private fun applyTurnFlow(
        data: Map<String, String>,
    ) {
        val yourTurn =
            isYourTurn(
                data,
            )

        OpenPigeonLog.i(
            "ShuffleActivity",
            "applyTurnFlow " +
                    "localPlayer=$localPlayer " +
                    "yourTurn=$yourTurn " +
                    "p1Shot=${renderer.hasShotForPlayer(1)} " +
                    "p2Shot=${renderer.hasShotForPlayer(2)}",
        )

        if (!yourTurn) {
            renderer.showWaitingForOpponent()
            showWaitingLabelAnimated()
            return
        }

        if (renderer.hasBothPlayerShots()) {
            hideStateLabelNow()

            renderer.showPlaying()

            renderer.playRoundFromReplay(
                roundReplay =
                    data["replay"]
                        ?: DEFAULT_REPLAY,
            ) {
                finishPlaybackOrApplyQueuedMessage {
                    enableNextLocalAimAfterPlayback()
                }
            }

            return
        }

        if (
            renderer.hasShotForPlayer(
                localPlayer,
            )
        ) {
            renderer.showWaitingForOpponent()
            showWaitingLabelAnimated()
            return
        }

        hideStateLabelNow()
        renderer.showAiming()
    }

    private fun handleLocalLaunchReplay(
        stagedReplayValue: String,
    ) {
        val stagedReplay =
            stagedReplayValue.trim()

        OpenPigeonLog.i(
            "ShuffleActivity",
            "handleLocalLaunchReplay " +
                    "endsWithPipe=${stagedReplay.endsWith("|")} " +
                    "rawLength=${stagedReplayValue.length} " +
                    "formattedLength=${stagedReplay.length}",
        )

        if (!isYourTurn(lastMessage)) {
            OpenPigeonLog.w(
                "ShuffleActivity",
                "Ignoring local launch because it is not our turn",
            )

            renderer.showWaitingForOpponent()
            showWaitingLabelAnimated()
            return
        }

        val opponentPlayer =
            3 - localPlayer

        val opponentAlreadyHasShot =
            renderer.hasShotForPlayer(
                opponentPlayer,
            )

        OpenPigeonLog.i(
            "ShuffleActivity",
            "handleLocalLaunchReplay " +
                    "localPlayer=$localPlayer " +
                    "opponent=$opponentPlayer " +
                    "opponentAlreadyHasShot=$opponentAlreadyHasShot " +
                    "replay=${stagedReplay.take(420)}",
        )

        if (opponentAlreadyHasShot) {
            hideStateLabelNow()
            renderer.showPlaying()

            renderer.playRoundFromReplay(
                roundReplay = stagedReplay,
            ) {
                finishPlaybackOrApplyQueuedMessage {
                    enableNextLocalAimAfterPlayback()
                }
            }

            return
        }

        sendReplayToOpponent(
            stagedReplay,
        )
    }

    private fun enableNextLocalAimAfterPlayback() {
        val currentBoard =
            renderer.prepareNextLocalAimAfterPlayback()

        lastMessage =
            lastMessage
                .toMutableMap()
                .apply {
                    put(
                        "replay",
                        currentBoard,
                    )
                }

        hideStateLabelNow()
        renderer.showAiming()

        myAvatarAnchor.bringToFront()
        opponentAvatarAnchor.bringToFront()
        settingsButton.bringToFront()

        OpenPigeonLog.i(
            "ShuffleActivity",
            "Playback finished; enabling next local aim " +
                    "currentBoard=${currentBoard.take(260)}",
        )
    }

    private fun sendReplayToOpponent(
        stagedReplay: String,
    ) {
        val currentMessage =
            try {
                if (sessionId.isNotBlank()) {
                    gameSessionIPC
                        ?.getCurrentMessage(sessionId)
                        .orEmpty()
                } else {
                    emptyMap()
                }
            } catch (throwable: Throwable) {
                OpenPigeonLog.e(
                    "ShuffleActivity",
                    "getCurrentMessage before send failed",
                    throwable,
                )

                emptyMap()
            }

        val sourceMessage =
            currentMessage.ifEmpty {
                lastMessage
            }

        val myId =
            localUserId(sourceMessage)

        val myAvatarKey =
            if (localPlayer == 1) {
                "avatar1"
            } else {
                "avatar2"
            }

        val sourceNum =
            sourceMessage["num"]
                ?.toIntOrNull()
                ?: 0

        val cachedNum =
            lastMessage["num"]
                ?.toIntOrNull()
                ?: 0

        val nextNum =
            maxOf(
                sourceNum,
                cachedNum,
            ) + 1

        val player1Id =
            (
                    sourceMessage["player1"]
                        ?: lastMessage["player1"]
                    ).orEmpty()

        val player2Id =
            (
                    sourceMessage["player2"]
                        ?: lastMessage["player2"]
                    ).orEmpty()

        val updates =
            mutableMapOf(
                "game" to "shuffle",
                "mode" to (
                        sourceMessage["mode"]
                            ?: lastMessage["mode"]
                            ?: "1"
                        ),
                "map" to (
                        sourceMessage["map"]
                            ?: lastMessage["map"]
                            ?: defaultMapForMode(1)
                        ),
                "player" to
                        localPlayer.toString(),
                "num" to
                        nextNum.toString(),
                "sender" to
                        myId,
                "replay" to
                        stagedReplay,
                myAvatarKey to
                        AvatarView.buildAvatarString(),
            )

        if (localPlayer == 1) {
            updates["player1"] = myId

            if (player2Id.isNotBlank()) {
                updates["player2"] =
                    player2Id
            }
        } else {
            if (player1Id.isNotBlank()) {
                updates["player1"] =
                    player1Id
            }

            updates["player2"] = myId
        }

        lastMessage =
            sourceMessage
                .toMutableMap()
                .apply {
                    putAll(updates)
                }

        lastOutgoingReplay =
            stagedReplay

        ignoreNextOutgoingReplayEcho =
            true

        renderer.showSentThenWaiting()
        showSendingLabelImmediately()

        OpenPigeonLog.i(
            "ShuffleActivity",
            "sendReplayToOpponent " +
                    "localPlayer=$localPlayer " +
                    "num=$nextNum " +
                    "replay=${stagedReplay.take(420)}",
        )

        val ipc =
            gameSessionIPC

        if (
            ipc == null ||
            sessionId.isBlank()
        ) {
            OpenPigeonLog.w(
                "ShuffleActivity",
                "No IPC/session available; " +
                        "showing sent/waiting locally",
            )

            showSentCheckThenWaitingAnimation()
            return
        }

        ipc.updateSession(
            updates,
            sessionId,
        ) {
            OpenPigeonLog.i(
                "ShuffleActivity",
                "Shuffle session updated " +
                        "num=$nextNum",
            )

            runOnUiThread {
                showSentCheckThenWaitingAnimation()
            }
        }
    }

    private fun isYourTurn(data: Map<String, String>): Boolean {
        val raw = data["isYourTurn"]

        if (!raw.isNullOrBlank()) {
            return parseBoolean(raw)
        }

        val messagePlayer = data["player"]?.toIntOrNull()?.coerceIn(1, 2)

        return messagePlayer != null && messagePlayer != localPlayer
    }

    private fun localUserId(msg: Map<String, String>): String {
        return gameSessionIPC
            ?.getSenderUUID(sessionId)
            ?.takeIf { it.isNotBlank() }
            ?: msg["myPlayerId"].orEmpty()
    }

    private fun resolveLocalPlayer(data: Map<String, String>): Int {
        val myId = localUserId(data)
        val p1 = data["player1"].orEmpty()
        val p2 = data["player2"].orEmpty()
        val sender = data["sender"].orEmpty()
        val dataPlayer = data["player"]?.toIntOrNull()?.coerceIn(1, 2) ?: 1

        if (myId.isNotBlank()) {
            if (myId == p1) return 1
            if (myId == p2) return 2
        }

        if (p1.isBlank() && p2.isNotBlank()) return 1
        if (p2.isBlank() && p1.isNotBlank()) return 2
        if (p1.isBlank() && p2.isBlank()) return dataPlayer

        if (sender.isNotBlank()) {
            if (sender == p1) return 2
            if (sender == p2) return 1
        }

        return dataPlayer
    }

    private fun createAvatarHud() {
        myAvatarAnchor = FrameLayout(this)
        opponentAvatarAnchor = FrameLayout(this)

        val avatarSize = dp(46f).toInt()

        rootFrame.addView(
            myAvatarAnchor,
            FrameLayout.LayoutParams(
                avatarSize,
                avatarSize,
                Gravity.TOP or Gravity.START
            ).apply {
                leftMargin = dp(10f).toInt()
                topMargin = dp(40f).toInt()
            }
        )

        rootFrame.addView(
            opponentAvatarAnchor,
            FrameLayout.LayoutParams(
                avatarSize,
                avatarSize,
                Gravity.TOP or Gravity.END
            ).apply {
                rightMargin = dp(10f).toInt()
                topMargin = dp(40f).toInt()
            }
        )
    }

    private fun createSettingsButton() {
        settingsButton = ImageButton(this).apply {
            background = null
            alpha = 0.86f
            scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(
                dp(4f).toInt(),
                dp(4f).toInt(),
                dp(4f).toInt(),
                dp(4f).toInt()
            )

            val settingsBitmap = loadAssetBitmap("global/settings.png")

            if (settingsBitmap != null) {
                setImageBitmap(settingsBitmap)
            } else {
                OpenPigeonLog.w("ShuffleActivity", "Missing asset: global/settings.png")
            }

            setOnClickListener {
                settingsSheet.open()
            }
        }

        val size = dp(48f).toInt()

        rootFrame.addView(
            settingsButton,
            FrameLayout.LayoutParams(
                size,
                size,
                Gravity.BOTTOM or Gravity.START
            ).apply {
                leftMargin = dp(0f).toInt()
                bottomMargin = dp(16f).toInt()
            }
        )
    }

    private fun applyOpponentAvatarFromMessage(data: Map<String, String>) {
        val opponentAvatarKey = if (localPlayer == 1) {
            "avatar2"
        } else {
            "avatar1"
        }

        val avatar = data[opponentAvatarKey]

        if (!avatar.isNullOrBlank()) {
            settingsSheet.applyOpponentAvatarString(avatar)
        }
    }

    private fun parseBoolean(value: String?): Boolean {
        return value.equals("true", ignoreCase = true) ||
                value == "1" ||
                value.equals("yes", ignoreCase = true)
    }

    private fun extractMessageData(intent: Intent?): Map<String, String> {
        val out = mutableMapOf<String, String>()

        val dataUri = intent?.data

        if (dataUri != null) {
            try {
                for (name in dataUri.queryParameterNames) {
                    out[name] = dataUri.getQueryParameter(name) ?: ""
                }
            } catch (t: Throwable) {
                OpenPigeonLog.e("ShuffleActivity", "Failed to parse intent.data=$dataUri", t)
            }
        }

        val extras = intent?.extras

        if (extras != null) {
            for (key in extras.keySet()) {
                val value = extras.get(key)

                when (value) {
                    is String -> {
                        out[key] = value

                        if (value.startsWith("data://")) {
                            parsePackedDataUri(value, out)
                        }
                    }

                    is ArrayList<*> -> {
                        val first = value.firstOrNull()
                        if (first != null) {
                            out[key] = first.toString()
                        }
                    }

                    is Array<*> -> {
                        val first = value.firstOrNull()
                        if (first != null) {
                            out[key] = first.toString()
                        }
                    }

                    else -> {
                        if (value != null) {
                            out[key] = value.toString()
                        }
                    }
                }
            }
        }

        return out
    }

    private fun parsePackedDataUri(
        raw: String,
        out: MutableMap<String, String>
    ) {
        try {
            val uri = android.net.Uri.parse(raw)

            for (name in uri.queryParameterNames) {
                out[name] = uri.getQueryParameter(name) ?: ""
            }
        } catch (t: Throwable) {
            OpenPigeonLog.e("ShuffleActivity", "Failed to parse packed data uri=$raw", t)
        }
    }

    private fun hasUsableShuffleData(data: Map<String, String>): Boolean {
        return data["mode"] != null ||
                data["map"] != null ||
                data["replay"] != null
    }

    private fun messageSummary(message: Map<String, String>): String {
        val map = message["map"]
        val mapCount = map
            ?.split(",")
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?.size
            ?: 0

        return "keys=${message.keys.sorted()} " +
                "game=${message["game"]} " +
                "mode=${message["mode"]} " +
                "mapCount=$mapCount " +
                "map=$map " +
                "player=${message["player"]} " +
                "num=${message["num"]} " +
                "isYourTurn=${message["isYourTurn"]} " +
                "sender=${message["sender"]} " +
                "replayLen=${message["replay"]?.length ?: 0}"
    }

    private fun defaultLocalMessage(): Map<String, String> {
        return mapOf(
            "game" to "shuffle",
            "mode" to "1",
            "map" to defaultMapForMode(1),
            "player" to "1",
            "num" to "1",
            "isYourTurn" to "true",
            "replay" to DEFAULT_REPLAY
        )
    }

    private fun defaultMapForMode(mode: Int): String {
        return when (mode) {
            2 -> "6,5,8,10,10,8,5,6,6,5,6,2,5,2,7,3"
            3 -> "3,2,5,10,7,7,6,5,6,4,7,8,6,10,4,4,4,8,5,3,5"
            else -> "5,10,5,2,3,10,6,3,2,5,3,6"
        }
    }

    override fun onResume() {
        super.onResume()

        if (sessionId.isNotBlank()) {
            try {
                gameSessionIPC?.setSuppressNotifications(sessionId, true)
            } catch (t: Throwable) {
                OpenPigeonLog.e("ShuffleActivity", "onResume setSuppressNotifications(true) failed", t)
            }
        }
    }

    override fun onPause() {
        if (sessionId.isNotBlank()) {
            try {
                gameSessionIPC?.setSuppressNotifications(sessionId, false)
            } catch (t: Throwable) {
                OpenPigeonLog.e("ShuffleActivity", "onPause setSuppressNotifications(false) failed", t)
            }
        }

        stopStateLabelAnimation()
        super.onPause()
    }

    private fun createStateLabel() {
        stateLabel = TextView(this).apply {
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(0xFFFFFFFF.toInt())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            includeFontPadding = false
            setPadding(
                stateLabelDp(14f),
                stateLabelDp(8f),
                stateLabelDp(14f),
                stateLabelDp(8f)
            )
            applyStateLabelBackground(this)
            visibility = View.GONE
        }

        rootFrame.addView(
            stateLabel,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                stateLabelDp(38f),
                Gravity.CENTER
            )
        )
    }

    private fun stateLabelDp(value: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value,
            resources.displayMetrics
        ).toInt()
    }

    private fun applyStateLabelBackground(label: TextView) {
        label.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = stateLabelDp(14f).toFloat()
            setColor(0xBE000000.toInt())
        }
    }

    private fun resetStateLabelLayout(label: TextView) {
        label.alpha = 1f
        label.translationX = 0f
        label.translationY = 0f
        label.scaleX = 1f
        label.scaleY = 1f
        label.setTextColor(0xFFFFFFFF.toInt())
        applyStateLabelBackground(label)
    }

    private fun measureStateLabelWidth(
        label: TextView,
        text: CharSequence
    ): Int {
        return (
                label.paint.measureText(text.toString()) +
                        label.paddingLeft +
                        label.paddingRight
                ).toInt()
    }

    private fun stopStateLabelAnimation() {
        waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }
        stateLabelHandler.removeCallbacksAndMessages(null)
        waitingDotsRunnable = null
        stateLabelAnimator?.cancel()
        stateLabelAnimator = null
        sentWaitingSequenceActive = false
    }

    private fun hideStateLabelNow() {
        stopStateLabelAnimation()

        if (::stateLabel.isInitialized) {
            resetStateLabelLayout(stateLabel)
            stateLabel.text = ""
            stateLabel.visibility = View.GONE
        }
    }

    private fun startWaitingDots(label: TextView) {
        var dots = 1

        waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }

        val runnable = object : Runnable {
            override fun run() {
                if (waitingDotsRunnable !== this) return

                if (label.visibility == View.VISIBLE) {
                    label.text = "WAITING FOR OPPONENT" + ".".repeat(dots)
                    dots = if (dots >= 3) 1 else dots + 1
                }

                stateLabelHandler.postDelayed(this, 900L)
            }
        }

        waitingDotsRunnable = runnable
        stateLabelHandler.post(runnable)
    }

    private fun showWaitingLabelAnimated() {
        runOnUiThread {
            stopStateLabelAnimation()

            resetStateLabelLayout(stateLabel)
            stateLabel.bringToFront()

            val waitingWidth = measureStateLabelWidth(
                stateLabel,
                "WAITING FOR OPPONENT..."
            )

            val params = stateLabel.layoutParams
            params.width = waitingWidth
            stateLabel.layoutParams = params

            stateLabel.visibility = View.VISIBLE
            startWaitingDots(stateLabel)

            myAvatarAnchor.bringToFront()
            opponentAvatarAnchor.bringToFront()
            settingsButton.bringToFront()
            stateLabel.bringToFront()
        }
    }

    private fun showSendingLabelImmediately() {
        runOnUiThread {
            stopStateLabelAnimation()
            sentWaitingSequenceActive = true

            resetStateLabelLayout(stateLabel)

            val sentWidth = measureStateLabelWidth(stateLabel, "Sent ✔")

            val params = stateLabel.layoutParams
            params.width = sentWidth
            stateLabel.layoutParams = params

            stateLabel.text = "Sent"
            stateLabel.alpha = 1f
            stateLabel.setTextColor(0xFFFFFFFF.toInt())
            stateLabel.visibility = View.VISIBLE
            stateLabel.bringToFront()
        }
    }

    private fun showSentCheckThenWaitingAnimation() {
        runOnUiThread {
            sentWaitingSequenceActive = true

            waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }
            waitingDotsRunnable = null

            stateLabelAnimator?.cancel()
            stateLabelAnimator = null

            resetStateLabelLayout(stateLabel)

            val sentWidth = measureStateLabelWidth(stateLabel, "Sent ✔")
            val waitingWidth = measureStateLabelWidth(stateLabel, "WAITING FOR OPPONENT...")

            val params = stateLabel.layoutParams
            params.width = sentWidth
            stateLabel.layoutParams = params

            val sentCheck = SpannableString("Sent ✔")
            sentCheck.setSpan(
                ForegroundColorSpan(0xFF7257D8.toInt()),
                5,
                6,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )

            stateLabel.text = sentCheck
            stateLabel.alpha = 1f
            stateLabel.setTextColor(0xFFFFFFFF.toInt())
            stateLabel.visibility = View.VISIBLE
            stateLabel.bringToFront()

            stateLabelHandler.postDelayed({
                if (!sentWaitingSequenceActive) return@postDelayed

                stateLabel.bringToFront()

                val oldWidth = stateLabel.width.takeIf { it > 0 } ?: sentWidth

                val widthParams = stateLabel.layoutParams
                widthParams.width = oldWidth
                stateLabel.layoutParams = widthParams

                stateLabel.animate().cancel()
                stateLabel.alpha = 1f
                stateLabel.text = "WAITING FOR OPPONENT."
                stateLabel.setTextColor(0x00FFFFFF)
                stateLabel.visibility = View.VISIBLE
                stateLabel.bringToFront()

                stateLabelAnimator = ValueAnimator.ofInt(oldWidth, waitingWidth).apply {
                    duration = 420L

                    addUpdateListener { animation ->
                        val animatedParams = stateLabel.layoutParams
                        animatedParams.width = animation.animatedValue as Int
                        stateLabel.layoutParams = animatedParams
                    }

                    addListener(
                        object : android.animation.AnimatorListenerAdapter() {
                            override fun onAnimationEnd(animation: android.animation.Animator) {
                                if (!sentWaitingSequenceActive) return

                                stateLabelAnimator = null

                                val finalParams = stateLabel.layoutParams
                                finalParams.width = waitingWidth
                                stateLabel.layoutParams = finalParams

                                ValueAnimator.ofInt(0, 255).apply {
                                    duration = 180L

                                    addUpdateListener { textAnimation ->
                                        val alpha = textAnimation.animatedValue as Int
                                        stateLabel.setTextColor((alpha shl 24) or 0x00FFFFFF)
                                    }

                                    addListener(
                                        object : android.animation.AnimatorListenerAdapter() {
                                            override fun onAnimationEnd(animation: android.animation.Animator) {
                                                if (sentWaitingSequenceActive) {
                                                    stateLabel.setTextColor(0xFFFFFFFF.toInt())
                                                    stateLabel.visibility = View.VISIBLE
                                                    stateLabel.bringToFront()
                                                    startWaitingDots(stateLabel)
                                                }
                                            }
                                        }
                                    )

                                    start()
                                }
                            }
                        }
                    )

                    start()
                }
            }, 1000L)
        }
    }

    private fun loadAssetBitmap(path: String): Bitmap? {
        return try {
            assets.open(path).use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun dp(value: Float): Float {
        return value * resources.displayMetrics.density
    }

    private companion object {
        private const val DEFAULT_REPLAY =
            "board:0,0#" +
                    "0.000000,-215.000000,1,0.000000,0.000000,0.000000#" +
                    "0.000000,215.000000,2,0.000000,0.000000,0.000000#"

        private const val REPLAY_QUEUE_MARKER =
            "|shoot:1|"
    }
}