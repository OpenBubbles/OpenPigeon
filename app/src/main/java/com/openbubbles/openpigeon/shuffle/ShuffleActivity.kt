package com.openbubbles.openpigeon.shuffle

import com.openbubbles.openpigeon.godot.GameSessionIPC
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.Window
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import com.openbubbles.openpigeon.settings.AvatarView
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
import android.widget.FrameLayout
import com.openbubbles.openpigeon.ui.RulesPopup
import com.openbubbles.openpigeon.ui.GameMenuController
import com.openbubbles.openpigeon.ui.GameMenuPlacement
import androidx.core.net.toUri
import androidx.core.view.isVisible
import android.graphics.Color
import android.graphics.Typeface
import android.view.ViewGroup

class ShuffleActivity : AppCompatActivity() {
    private var sessionId: String = ""
    private var gameSessionIPC: GameSessionIPC? = null
    private var lastMessage: Map<String, String> = emptyMap()

    private var localPlayer: Int = 1
    private var lastOutgoingReplay: String? = null
    private var lastPlayedQueuedReplayKey: String? = null

    private var pendingMessageAfterPlayback: Map<String, String>? = null
    private var ignoreNextOutgoingReplayEcho = false
    private val stateLabelHandler = Handler(Looper.getMainLooper())
    private var waitingDotsRunnable: Runnable? = null
    private var stateLabelAnimator: ValueAnimator? = null
    private var sentWaitingSequenceActive = false
    private lateinit var stateLabel: TextView

    private lateinit var rootFrame: FrameLayout
    private lateinit var renderer: ShuffleRenderer

    private lateinit var myAvatarAnchor: FrameLayout
    private lateinit var opponentAvatarAnchor: FrameLayout
    private lateinit var gameMenu: GameMenuController

    private lateinit var spectatorLabel: TextView

    private var spectatorMode = false

    private var gameEnded = false

    private var winLossState = ""

    private var pendingWinLossState = ""

    private var lastMessageWinner = ""

    private var statusDimView: View? = null

    @Volatile
    private var statusDimVisible = false

    private enum class StateLabelVisual {
        Hidden, Waiting, SentWaiting, GameOver,
    }

    private var stateLabelVisual = StateLabelVisual.Hidden

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestWindowFeature(Window.FEATURE_NO_TITLE)
        supportActionBar?.hide()
        enableEdgeToEdge()

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
            renderer, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        createAvatarHud()

        renderer.onTopHudAlphaChanged = { alpha ->
            myAvatarAnchor.alpha = alpha

            opponentAvatarAnchor.alpha = alpha

            if (::spectatorLabel.isInitialized) {
                spectatorLabel.alpha = alpha
            }
        }

        createStateLabel()
        createSpectatorLabel()
        hideStateLabelNow()
        setupGameMenu()
        startGameSession()
    }

    private fun setupGameMenu() {
        gameMenu = GameMenuController(
            activity = this,
            rootFrame = rootFrame,
            gameId = "shuffle",
            rulesTitle = "Shuffleboard Rules",
            rulesSections = listOf(
                RulesPopup.Section(
                    "Objective",
                    "Be the first player to reach 50 points.",
                ),
                RulesPopup.Section(
                    "How to Play",
                    "Move your puck horizontally to choose its starting position, then drag the arrow to choose its direction and power. Both players' pucks are launched together.",
                ),
                RulesPopup.Section(
                    "Scoring",
                    "After both players have used all four pucks, each puck scores the section containing most of that puck.",
                ),
                RulesPopup.Section(
                    "Board Types",
                    "Shuffleboard includes three scoring layouts. One layout also includes a center bumper that can redirect moving pucks.",
                ),
                RulesPopup.Section(
                    "Winning",
                    "Points are added after all eight pucks are counted. The first player to reach 50 points wins.",
                ),
            ),
            musicAssetPath = MUSIC_TRACK_PATH,
            placement = GameMenuPlacement.BOTTOM_START,
            onDarkModeChanged = { enabled ->
                renderer.setDarkMode(
                    enabled,
                )
            },
            onSettingsClosed = {
                if (spectatorMode) {
                    restoreSpectatorAvatarsAfterSettingsOpen()
                }
            },
        )

        gameMenu.sheet.attachGameAvatar(
            myAvatarAnchor,
        )

        gameMenu.sheet.attachOpponentAvatar(
            opponentAvatarAnchor,
        )

        configureSettingsAvatarTarget()
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
            "startGameSession sessionIdBlank=${sessionId.isBlank()} " + "extras=${
                intent.extras?.keySet()?.sorted().orEmpty()
            } " + "dataUri=${intent.data} directKeys=${directData.keys.sorted()} " + "directMode=${directData["mode"]} directMap=${directData["map"]}"
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
                "ShuffleActivity", "IPC currentMessage ${messageSummary(currentMessage)}"
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
                    OpenPigeonLog.e(
                        "ShuffleActivity", "IPC setSuppressNotifications(true) failed", t
                    )
                }

                try {
                    ipc.onMessageUpdated(sessionId) { msg ->
                        OpenPigeonLog.i(
                            "ShuffleActivity", "IPC onMessageUpdated ${messageSummary(msg)}"
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
                            "ShuffleActivity", "IPC currentMessage empty; showing local fallback"
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

        val game = message["game"]

        if (!game.isNullOrBlank() && game != "shuffle") {
            OpenPigeonLog.w(
                "ShuffleActivity",
                "Ignoring non-shuffle message " + "game=$game " + "keys=${message.keys.sorted()}",
            )

            return
        }

        val incomingReplay = message["replay"].orEmpty()

        if (ignoreNextOutgoingReplayEcho && incomingReplay == lastOutgoingReplay) {
            ignoreNextOutgoingReplayEcho = false

            OpenPigeonLog.i(
                "ShuffleActivity",
                "Ignoring own outgoing replay echo",
            )

            return
        }

        if (renderer.isPlayingRound()) {
            pendingMessageAfterPlayback = message

            OpenPigeonLog.i(
                "ShuffleActivity",
                "Queued message during shuffle playback " + messageSummary(message),
            )

            return
        }

        lastMessage = message

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
        val queuedMessage = pendingMessageAfterPlayback

        pendingMessageAfterPlayback = null

        if (queuedMessage != null) {
            OpenPigeonLog.i(
                "ShuffleActivity",
                "Applying message queued during playback " + messageSummary(queuedMessage),
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
        val rawReplay = data["replay"].orEmpty()

        OpenPigeonLog.i(
            "ShuffleActivity",
            "applyGameData " + "mode=${data["mode"]} " + "map=${data["map"]} " + "winner=${data["winner"]} " + "replay=${
                rawReplay.take(160)
            }",
        )

        lastMessageWinner = data["winner"].orEmpty()

        updateSpectatorMode(
            data,
        )

        localPlayer = if (spectatorMode) {
            1
        } else {
            resolveLocalPlayer(
                data,
            )
        }

        renderer.setLocalPlayer(
            localPlayer,
        )

        if (spectatorMode) {
            applySpectatorAvatars(
                data,
            )
        } else {
            applyOpponentAvatarFromMessage(
                data,
            )
        }

        myAvatarAnchor.bringToFront()
        opponentAvatarAnchor.bringToFront()

        if (::gameMenu.isInitialized) {
            gameMenu.bringToFront()
        }

        val markerIndex = rawReplay.indexOf(
            REPLAY_QUEUE_MARKER,
        )

        if (markerIndex >= 0) {
            val queuedRoundReplay = rawReplay.substring(
                0,
                markerIndex,
            ).trim().trimEnd(
                    '|',
                )

            val postRoundReplay = rawReplay.substring(
                markerIndex + REPLAY_QUEUE_MARKER.length,
            ).trim().trimStart(
                    '|',
                ).ifBlank {
                    DEFAULT_REPLAY
                }

            val queuedReplayKey = buildString {
                append(
                    data["id"].orEmpty(),
                )

                append(
                    "|",
                )

                append(
                    data["num"].orEmpty(),
                )

                append(
                    "|",
                )

                append(
                    rawReplay.hashCode(),
                )
            }

            val shouldPlayQueuedRound =
                queuedRoundReplay.isNotBlank() && queuedReplayKey != lastPlayedQueuedReplayKey && (spectatorMode || lastMessageWinner.isNotBlank() || isYourTurn(
                    data,
                ))

            val postRoundData = data.toMutableMap().apply {
                put(
                    "replay",
                    postRoundReplay,
                )
            }

            if (shouldPlayQueuedRound) {
                lastPlayedQueuedReplayKey = queuedReplayKey

                pendingWinLossState = localWinLossStateFromWinner(
                    data["winner"],
                )

                val roundData = data.toMutableMap().apply {
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
                    "Playing queued shuffle replay " + "key=$queuedReplayKey " + "round=${
                        queuedRoundReplay.take(260)
                    } " + "post=${postRoundReplay.take(260)}",
                )

                renderer.playRoundFromReplay(
                    roundReplay = queuedRoundReplay,
                ) {
                    lastMessage = postRoundData

                    lastMessageWinner = postRoundData["winner"].orEmpty()

                    renderer.setGameData(
                        postRoundData,
                    )

                    val forcedState = pendingWinLossState

                    pendingWinLossState = ""

                    handleRoundPlaybackFinished(
                        completedByLocalTurn = false,
                        forcedState = forcedState,
                    ) {
                        applyTurnFlow(
                            postRoundData,
                        )
                    }
                }

                return
            }

            lastMessage = postRoundData

            lastMessageWinner = postRoundData["winner"].orEmpty()

            renderer.setGameData(
                postRoundData,
            )

            val incomingWinnerState = localWinLossStateFromWinner(
                postRoundData["winner"],
            )

            val finalState = incomingWinnerState.takeIf {
                    it.isNotBlank()
                } ?: currentScoreWinLossState()

            if (finalState.isNotBlank()) {
                markGameOver(
                    finalState,
                )

                return
            }

            applyTurnFlow(
                postRoundData,
            )

            return
        }

        renderer.setGameData(
            data,
        )

        val incomingWinnerState = localWinLossStateFromWinner(
            data["winner"],
        )

        val finalState = incomingWinnerState.takeIf {
                it.isNotBlank()
            } ?: currentScoreWinLossState()

        if (finalState.isNotBlank()) {
            markGameOver(
                finalState,
            )

            return
        }

        applyTurnFlow(
            data,
        )
    }

    private fun applyTurnFlow(
        data: Map<String, String>,
    ) {
        if (isGameOver()) {
            showGameOverLabel()
            return
        }

        if (spectatorMode) {
            hideStateLabelNow()

            renderer.showSpectating()

            applySpectatorAvatars(
                data,
            )

            return
        }

        val yourTurn = isYourTurn(
            data,
        )

        OpenPigeonLog.i(
            "ShuffleActivity",
            "applyTurnFlow " + "localPlayer=$localPlayer " + "yourTurn=$yourTurn " + "p1Shot=${
                renderer.hasShotForPlayer(1)
            } " + "p2Shot=${renderer.hasShotForPlayer(2)}",
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
                roundReplay = data["replay"] ?: DEFAULT_REPLAY,
            ) {
                handleRoundPlaybackFinished(
                    completedByLocalTurn = false,
                ) {
                    enableNextLocalAimAfterPlayback()
                }
            }

            return
        }

        if (renderer.hasShotForPlayer(
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
        if (spectatorMode || isGameOver()) {
            OpenPigeonLog.w(
                "ShuffleActivity",
                "Ignoring local launch while spectating or after game over",
            )

            return
        }

        val stagedReplay = stagedReplayValue.trim()

        OpenPigeonLog.i(
            "ShuffleActivity",
            "handleLocalLaunchReplay " + "endsWithPipe=${stagedReplay.endsWith("|")} " + "rawLength=${stagedReplayValue.length} " + "formattedLength=${stagedReplay.length}",
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

        val opponentPlayer = 3 - localPlayer

        val opponentAlreadyHasShot = renderer.hasShotForPlayer(
            opponentPlayer,
        )

        OpenPigeonLog.i(
            "ShuffleActivity",
            "handleLocalLaunchReplay localPlayer=$localPlayer opponent=$opponentPlayer opponentAlreadyHasShot=$opponentAlreadyHasShot " + "replay=${
                stagedReplay.take(420)
            }",
        )

        if (opponentAlreadyHasShot) {
            hideStateLabelNow()
            renderer.showPlaying()

            renderer.playRoundFromReplay(
                roundReplay = stagedReplay,
            ) {
                handleRoundPlaybackFinished(
                    completedByLocalTurn = true,
                ) {
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
        if (isGameOver()) {
            return
        }

        if (spectatorMode) {
            hideStateLabelNow()

            renderer.showSpectating()

            applySpectatorAvatars(
                lastMessage,
            )

            return
        }

        val currentBoard = renderer.prepareNextLocalAimAfterPlayback()

        lastMessage = lastMessage.toMutableMap().apply {
            put(
                "replay",
                currentBoard,
            )
        }

        hideStateLabelNow()
        renderer.showAiming()

        myAvatarAnchor.bringToFront()
        opponentAvatarAnchor.bringToFront()
        if (::gameMenu.isInitialized) {
            gameMenu.bringToFront()
        }

        OpenPigeonLog.i(
            "ShuffleActivity",
            "Playback finished; enabling next local aim " + "currentBoard=${currentBoard.take(260)}",
        )
    }

    private fun sendReplayToOpponent(
        stagedReplay: String,
    ) {
        if (spectatorMode || isGameOver()) {
            return
        }

        val currentMessage = try {
            if (sessionId.isNotBlank()) {
                gameSessionIPC?.getCurrentMessage(sessionId).orEmpty()
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

        val sourceMessage = currentMessage.ifEmpty {
            lastMessage
        }

        val myId = localUserId(sourceMessage)

        val myAvatarKey = if (localPlayer == 1) {
            "avatar1"
        } else {
            "avatar2"
        }

        val sourceNum = sourceMessage["num"]?.toIntOrNull() ?: 0

        val cachedNum = lastMessage["num"]?.toIntOrNull() ?: 0

        val nextNum = maxOf(
            sourceNum,
            cachedNum,
        ) + 1

        val player1Id = (sourceMessage["player1"] ?: lastMessage["player1"]).orEmpty()

        val player2Id = (sourceMessage["player2"] ?: lastMessage["player2"]).orEmpty()

        val resolvedMode = (sourceMessage["mode"] ?: lastMessage["mode"])?.toIntOrNull()?.coerceIn(
                1,
                3,
            ) ?: 1

        val updates = mutableMapOf(
            "game" to "shuffle",
            "mode" to resolvedMode.toString(),

            "map" to (sourceMessage["map"] ?: lastMessage["map"] ?: defaultMapForMode(
                resolvedMode,
            )),
            "player" to localPlayer.toString(),
            "num" to nextNum.toString(),
            "sender" to myId,
            "replay" to stagedReplay,
            myAvatarKey to AvatarView.buildAvatarString(),
        )

        if (localPlayer == 1) {
            updates["player1"] = myId

            if (player2Id.isNotBlank()) {
                updates["player2"] = player2Id
            }
        } else {
            if (player1Id.isNotBlank()) {
                updates["player1"] = player1Id
            }

            updates["player2"] = myId
        }

        lastMessage = sourceMessage.toMutableMap().apply {
            putAll(updates)
        }

        lastOutgoingReplay = stagedReplay

        ignoreNextOutgoingReplayEcho = true

        renderer.showSentThenWaiting()
        showSendingLabelImmediately()

        OpenPigeonLog.i(
            "ShuffleActivity",
            "sendReplayToOpponent localPlayer=$localPlayer num=$nextNum " + "replay=${
                stagedReplay.take(420)
            }",
        )

        val ipc = gameSessionIPC

        if (ipc == null || sessionId.isBlank()) {
            OpenPigeonLog.w(
                "ShuffleActivity",
                "No IPC/session available; " + "showing sent/waiting locally",
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
                "Shuffle session updated num=$nextNum",
            )

            runOnUiThread {
                showSentCheckThenWaitingAnimation()
            }
        }
    }

    private fun sendWinnerResultIfNeeded(
        state: String,
    ) {
        if (spectatorMode || state.isBlank()) {
            return
        }

        val ipc = gameSessionIPC

        if (ipc == null || sessionId.isBlank()) {
            OpenPigeonLog.w(
                "ShuffleActivity",
                "Winner not sent because IPC or session is unavailable",
            )

            return
        }

        try {
            val current = ipc.getCurrentMessage(
                sessionId,
            ).ifEmpty {
                lastMessage
            }

            if (current["winner"].orEmpty().isNotBlank()) {
                OpenPigeonLog.i(
                    "ShuffleActivity",
                    "Winner already exists: ${current["winner"]}",
                )

                return
            }

            val myId = ipc.getSenderUUID(
                sessionId,
            ).takeIf {
                    it.isNotBlank()
                }.orEmpty()

            if (myId.isBlank()) {
                return
            }

            val resolvedMode = (current["mode"] ?: lastMessage["mode"])?.toIntOrNull()?.coerceIn(
                    1,
                    3,
                ) ?: 1

            val currentNum = current["num"]?.toIntOrNull() ?: 0

            val cachedNum = lastMessage["num"]?.toIntOrNull() ?: 0

            val finalReplay = renderer.completedRoundReplayForSend()

            val outgoing = current.toMutableMap().apply {
                put(
                    "game",
                    "shuffle",
                )

                put(
                    "game_name",
                    "Shuffleboard",
                )

                put(
                    "mode",
                    resolvedMode.toString(),
                )

                put(
                    "map",
                    current["map"] ?: lastMessage["map"] ?: defaultMapForMode(
                        resolvedMode,
                    ),
                )

                put(
                    "player",
                    localPlayer.toString(),
                )

                put(
                    "num",
                    (maxOf(
                        currentNum,
                        cachedNum,
                    ) + 1).toString(),
                )

                put(
                    "sender",
                    myId,
                )

                put(
                    "replay",
                    finalReplay,
                )

                put(
                    "winner",
                    "$myId|${
                        state.toIntOrNull()?.coerceIn(
                                -1,
                                1,
                            ) ?: 0
                    }",
                )

                put(
                    if (localPlayer == 1) {
                        "avatar1"
                    } else {
                        "avatar2"
                    },
                    AvatarView.buildAvatarString(),
                )

                if (localPlayer == 1) {
                    put(
                        "player1",
                        myId,
                    )
                } else {
                    put(
                        "player2",
                        myId,
                    )
                }

                remove(
                    "isYourTurn",
                )
            }

            lastMessage = outgoing

            lastMessageWinner = outgoing["winner"].orEmpty()

            lastOutgoingReplay = finalReplay

            ignoreNextOutgoingReplayEcho = true

            OpenPigeonLog.i(
                "ShuffleActivity",
                "Sending Shuffleboard winner " + "winner=${outgoing["winner"]} " + "scores=${renderer.currentScores()} " + "replayLen=${finalReplay.length}",
            )

            ipc.updateSession(
                outgoing,
                sessionId,
            ) {
                OpenPigeonLog.i(
                    "ShuffleActivity",
                    "Shuffleboard winner update completed",
                )
            }
        } catch (throwable: Throwable) {
            OpenPigeonLog.e(
                "ShuffleActivity",
                "Unable to send Shuffleboard winner",
                throwable,
            )
        }
    }

    private fun ensureStatusDimView(): View {
        statusDimView?.let {
            return it
        }

        val dim = View(
            this,
        ).apply {
            setBackgroundColor(
                Color.argb(
                    115,
                    0,
                    0,
                    0,
                ),
            )

            alpha = 0f

            visibility = View.GONE

            isClickable = false

            isFocusable = false
        }

        rootFrame.addView(
            dim,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        statusDimView = dim

        return dim
    }


    private fun setStatusDimVisible(
        visible: Boolean,
    ) {
        runOnUiThread {
            val dim = ensureStatusDimView()

            dim.animate().cancel()

            if (visible) {
                statusDimVisible = true

                if (dim.visibility != View.VISIBLE) {
                    dim.alpha = 0f

                    dim.visibility = View.VISIBLE
                }

                dim.bringToFront()

                dim.animate().alpha(
                        1f,
                    ).setDuration(
                        180L,
                    ).start()
            } else {
                statusDimVisible = false

                dim.animate().alpha(
                        0f,
                    ).setDuration(
                        160L,
                    ).withEndAction {
                        if (!statusDimVisible) {
                            dim.visibility = View.GONE
                        }
                    }.start()
            }
        }
    }


    private fun isGameOver(): Boolean {
        return gameEnded && winLossState.isNotBlank()
    }


    private fun winningPlayerFromWinner(
        rawWinner: String?,
    ): Int? {
        val parts = rawWinner.orEmpty().split(
                "|",
                limit = 2,
            )

        if (parts.size != 2) {
            return null
        }

        val senderId = parts[0]

        val senderResult = parts[1].toIntOrNull()?.coerceIn(
                -1,
                1,
            ) ?: return null

        if (senderResult == 0) {
            return 0
        }

        val senderPlayer = when (senderId) {
            lastMessage["player1"] -> 1
            lastMessage["player2"] -> 2
            else -> return null
        }

        return if (senderResult > 0) {
            senderPlayer
        } else {
            3 - senderPlayer
        }
    }


    private fun localWinLossStateFromWinner(
        rawWinner: String?,
    ): String {
        val winner = rawWinner.orEmpty()

        if (winner.isBlank()) {
            return ""
        }

        if (spectatorMode) {
            return when (winningPlayerFromWinner(
                winner,
            )) {
                1 -> "1"
                2 -> "-1"
                0 -> "0"
                else -> ""
            }
        }

        val parts = winner.split(
            "|",
            limit = 2,
        )

        if (parts.size != 2) {
            return ""
        }

        val senderWinnerId = parts[0]

        val senderState = parts[1].toIntOrNull()?.coerceIn(
                -1,
                1,
            ) ?: return ""

        val myId = localUserId(
            lastMessage,
        )

        val localState = when {
            senderState == 0 -> 0

            myId.isNotBlank() && senderWinnerId == myId -> {
                senderState
            }

            else -> {
                -senderState
            }
        }

        return localState.toString()
    }


    private fun gameOverText(): String {
        if (spectatorMode) {
            val winningPlayer = winningPlayerFromWinner(
                lastMessageWinner,
            ) ?: when (winLossState) {
                "1" -> 1
                "-1" -> 2
                "0" -> 0
                else -> null
            }

            return when (winningPlayer) {
                1 -> "Player 1 Wins!"
                2 -> "Player 2 Wins!"
                else -> "Draw!"
            }
        }

        return when (winLossState) {
            "1" -> "You Win!"
            "-1" -> "You Lose!"
            "0" -> "Draw!"
            else -> ""
        }
    }


    private fun gameOverTextColor(): Int {
        if (spectatorMode) {
            val winningPlayer = winningPlayerFromWinner(
                lastMessageWinner,
            ) ?: when (winLossState) {
                "1" -> 1
                "-1" -> 2
                "0" -> 0
                else -> null
            }

            return when (winningPlayer) {
                1, 2 -> {
                    Color.rgb(
                        255,
                        214,
                        0,
                    )
                }

                else -> {
                    Color.WHITE
                }
            }
        }

        return when (winLossState) {
            "1" -> {
                Color.rgb(
                    255,
                    214,
                    0,
                )
            }

            "-1" -> {
                Color.rgb(
                    255,
                    51,
                    51,
                )
            }

            else -> {
                Color.WHITE
            }
        }
    }

    private fun markGameOver(
        state: String,
    ) {
        if (state.isBlank()) {
            return
        }

        gameEnded = true

        winLossState = state

        pendingWinLossState = ""

        renderer.showGameOver()

        showGameOverLabel()
    }


    private fun showGameOverLabel() {
        runOnUiThread {
            if (!isGameOver()) {
                return@runOnUiThread
            }

            stopStateLabelAnimation()

            stateLabelVisual = StateLabelVisual.GameOver

            resetStateLabelLayout(
                stateLabel,
            )

            val text = gameOverText()

            val labelWidth = measureStateLabelWidth(
                stateLabel,
                text,
            )

            val params = stateLabel.layoutParams

            params.width = labelWidth

            stateLabel.layoutParams = params

            stateLabel.text = text

            stateLabel.setTextColor(
                gameOverTextColor(),
            )

            stateLabel.visibility = View.VISIBLE

            setStatusDimVisible(
                true,
            )

            stateLabel.bringToFront()
        }
    }

    private fun currentScoreWinLossState(): String {
        if (!renderer.hasGameEnded()) {
            return ""
        }

        val scores = renderer.currentScores()

        val player1Score = scores.first

        val player2Score = scores.second

        if (player1Score == player2Score) {
            return "0"
        }

        val viewedPlayer = if (spectatorMode) {
            1
        } else {
            localPlayer
        }

        val viewedScore = if (viewedPlayer == 1) {
            player1Score
        } else {
            player2Score
        }

        val otherScore = if (viewedPlayer == 1) {
            player2Score
        } else {
            player1Score
        }

        return if (viewedScore > otherScore) {
            "1"
        } else {
            "-1"
        }
    }


    private fun handleRoundPlaybackFinished(
        completedByLocalTurn: Boolean,
        forcedState: String = "",
        onContinue: () -> Unit,
    ) {
        val finalState = forcedState.takeIf {
                it.isNotBlank()
            } ?: currentScoreWinLossState()

        if (finalState.isNotBlank()) {
            pendingMessageAfterPlayback = null

            markGameOver(
                finalState,
            )

            if (completedByLocalTurn && !spectatorMode) {
                sendWinnerResultIfNeeded(
                    finalState,
                )
            }

            return
        }

        finishPlaybackOrApplyQueuedMessage {
            if (spectatorMode) {
                hideStateLabelNow()

                renderer.showSpectating()

                applySpectatorAvatars(
                    lastMessage,
                )

                return@finishPlaybackOrApplyQueuedMessage
            }

            onContinue()
        }
    }

    private fun isYourTurn(data: Map<String, String>): Boolean {
        if (spectatorMode) {
            return false
        }

        val raw = data["isYourTurn"]

        if (!raw.isNullOrBlank()) {
            return parseBoolean(raw)
        }

        val messagePlayer = data["player"]?.toIntOrNull()?.coerceIn(1, 2)

        return messagePlayer != null && messagePlayer != localPlayer
    }

    private fun localUserId(msg: Map<String, String>): String {
        return gameSessionIPC?.getSenderUUID(sessionId)?.takeIf { it.isNotBlank() }
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
            myAvatarAnchor, FrameLayout.LayoutParams(
                avatarSize, avatarSize, Gravity.TOP or Gravity.START
            ).apply {
                leftMargin = dp(10f).toInt()
                topMargin = dp(40f).toInt()
            })

        rootFrame.addView(
            opponentAvatarAnchor, FrameLayout.LayoutParams(
                avatarSize, avatarSize, Gravity.TOP or Gravity.END
            ).apply {
                rightMargin = dp(10f).toInt()
                topMargin = dp(40f).toInt()
            })
    }

    private fun updateSpectatorMode(
        data: Map<String, String>,
    ) {
        val myId = localUserId(
            data,
        )

        val player1Id = data["player1"].orEmpty()

        val player2Id = data["player2"].orEmpty()

        spectatorMode =
            myId.isNotBlank() && player1Id.isNotBlank() && player2Id.isNotBlank() && myId != player1Id && myId != player2Id

        renderer.setSpectatorMode(
            spectatorMode,
        )

        spectatorLabel.visibility = if (spectatorMode) {
            View.VISIBLE
        } else {
            View.GONE
        }

        if (spectatorMode) {
            localPlayer = 1

            applySpectatorAvatars(
                data,
            )

            spectatorLabel.bringToFront()
        }

        configureSettingsAvatarTarget()

        OpenPigeonLog.i(
            "ShuffleActivity",
            "updateSpectatorMode " + "spectator=$spectatorMode " + "myIdBlank=${myId.isBlank()} " + "p1Blank=${player1Id.isBlank()} " + "p2Blank=${player2Id.isBlank()}",
        )
    }


    private fun findAvatarView(
        view: View,
    ): AvatarView? {
        if (view is AvatarView) {
            return view
        }

        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                val found = findAvatarView(
                    view.getChildAt(
                        index,
                    ),
                )

                if (found != null) {
                    return found
                }
            }
        }

        return null
    }


    private fun applyAvatarToAnchor(
        anchor: FrameLayout,
        avatarData: String,
    ) {
        val avatar = findAvatarView(
            anchor,
        ) ?: return

        if (avatarData.isBlank()) {
            avatar.showPlaceholder()
        } else {
            avatar.applyFromOpponentString(
                avatarData,
            )
        }
    }


    private fun applySpectatorAvatars(
        data: Map<String, String>,
    ) {
        if (!spectatorMode) {
            return
        }

        applyAvatarToAnchor(
            anchor = myAvatarAnchor,
            avatarData = data["avatar1"].orEmpty(),
        )

        applyAvatarToAnchor(
            anchor = opponentAvatarAnchor,
            avatarData = data["avatar2"].orEmpty(),
        )

        myAvatarAnchor.bringToFront()
        opponentAvatarAnchor.bringToFront()
        spectatorLabel.bringToFront()
    }


    private fun configureSettingsAvatarTarget() {
        if (!::gameMenu.isInitialized) {
            return
        }

        gameMenu.sheet.setGameAvatarRefreshEnabled(
            enabled = !spectatorMode,
        )
    }


    private fun restoreSpectatorAvatarsAfterSettingsOpen() {
        if (!spectatorMode || lastMessage.isEmpty()) {
            return
        }

        myAvatarAnchor.post {
            if (!spectatorMode || isFinishing || isDestroyed) {
                return@post
            }

            gameMenu.sheet.setGameAvatarRefreshEnabled(
                false,
            )

            applySpectatorAvatars(
                lastMessage,
            )
        }
    }

    private fun applyOpponentAvatarFromMessage(
        data: Map<String, String>,
    ) {
        val opponentAvatarKey = if (localPlayer == 1) {
            "avatar2"
        } else {
            "avatar1"
        }

        val avatar = data[opponentAvatarKey]

        if (!avatar.isNullOrBlank()) {
            gameMenu.sheet.applyOpponentAvatarString(
                avatar,
            )
        }
    }

    private fun parseBoolean(value: String?): Boolean {
        return value.equals("true", ignoreCase = true) || value == "1" || value.equals(
            "yes", ignoreCase = true
        )
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
                when (val value = extras.get(key)) {
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
        raw: String, out: MutableMap<String, String>
    ) {
        try {
            val uri = raw.toUri()

            for (name in uri.queryParameterNames) {
                out[name] = uri.getQueryParameter(name) ?: ""
            }
        } catch (t: Throwable) {
            OpenPigeonLog.e("ShuffleActivity", "Failed to parse packed data uri=$raw", t)
        }
    }

    private fun hasUsableShuffleData(data: Map<String, String>): Boolean {
        return data["mode"] != null || data["map"] != null || data["replay"] != null
    }

    private fun messageSummary(message: Map<String, String>): String {
        val map = message["map"]
        val mapCount = map?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }?.size ?: 0

        return "keys=${message.keys.sorted()} " + "game=${message["game"]} " + "mode=${message["mode"]} " + "mapCount=$mapCount " + "map=$map " + "player=${message["player"]} " + "num=${message["num"]} " + "isYourTurn=${message["isYourTurn"]} " + "sender=${message["sender"]} " + "replayLen=${message["replay"]?.length ?: 0}"
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

        if (::gameMenu.isInitialized) {
            gameMenu.onResume()
        }

        if (sessionId.isNotBlank()) {
            try {
                gameSessionIPC?.setSuppressNotifications(
                    sessionId,
                    true,
                )
            } catch (throwable: Throwable) {
                OpenPigeonLog.e(
                    "ShuffleActivity",
                    "onResume setSuppressNotifications(true) failed",
                    throwable,
                )
            }
        }
        if (spectatorMode) {
            restoreSpectatorAvatarsAfterSettingsOpen()
        }

        if (isGameOver()) {
            showGameOverLabel()
        }
    }


    override fun onPause() {
        if (::gameMenu.isInitialized) {
            gameMenu.onPause()
        }

        if (sessionId.isNotBlank()) {
            try {
                gameSessionIPC?.setSuppressNotifications(
                    sessionId,
                    false,
                )
            } catch (throwable: Throwable) {
                OpenPigeonLog.e(
                    "ShuffleActivity",
                    "onPause setSuppressNotifications(false) failed",
                    throwable,
                )
            }
        }

        if (!isGameOver()) {
            stopStateLabelAnimation()
        }

        super.onPause()
    }


    override fun onDestroy() {
        if (::gameMenu.isInitialized) {
            gameMenu.destroy()
        }

        super.onDestroy()
    }

    private fun createStateLabel() {
        stateLabel = TextView(this).apply {
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(0xFFFFFFFF.toInt())
            typeface = Typeface.DEFAULT_BOLD
            includeFontPadding = false
            setPadding(
                stateLabelDp(14f), stateLabelDp(8f), stateLabelDp(14f), stateLabelDp(8f)
            )
            applyStateLabelBackground(this)
            visibility = View.GONE
        }

        rootFrame.addView(
            stateLabel, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, stateLabelDp(38f), Gravity.CENTER
            )
        )
    }

    private fun createSpectatorLabel() {
        spectatorLabel = TextView(
            this,
        ).apply {
            text = "Spectating..."

            visibility = View.GONE

            setTextColor(
                Color.WHITE,
            )

            textSize = 28f

            gravity = Gravity.CENTER

            textAlignment = View.TEXT_ALIGNMENT_CENTER

            typeface = Typeface.DEFAULT_BOLD

            includeFontPadding = false

            setShadowLayer(
                3f,
                0f,
                dp(
                    1.5f,
                ),
                Color.argb(
                    150,
                    0,
                    0,
                    0,
                ),
            )
        }

        rootFrame.addView(
            spectatorLabel,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.CENTER_HORIZONTAL,
            ).apply {
                topMargin = dp(
                    86f,
                ).toInt()
            },
        )
    }

    private fun stateLabelDp(value: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics
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
        label: TextView, text: CharSequence
    ): Int {
        return (label.paint.measureText(text.toString()) + label.paddingLeft + label.paddingRight).toInt()
    }

    private fun stopStateLabelAnimation() {
        waitingDotsRunnable?.let {
            stateLabelHandler.removeCallbacks(
                it,
            )
        }

        stateLabelHandler.removeCallbacksAndMessages(
            null,
        )

        waitingDotsRunnable = null

        stateLabelAnimator?.cancel()

        stateLabelAnimator = null

        sentWaitingSequenceActive = false

        stateLabelVisual = StateLabelVisual.Hidden
    }

    private fun hideStateLabelNow() {
        if (isGameOver()) {
            showGameOverLabel()
            return
        }

        stopStateLabelAnimation()

        resetStateLabelLayout(
            stateLabel,
        )

        stateLabel.text = null

        stateLabel.visibility = View.GONE

        setStatusDimVisible(
            false,
        )
    }

    private fun startWaitingDots(label: TextView) {
        var dots = 1

        waitingDotsRunnable?.let { stateLabelHandler.removeCallbacks(it) }

        val runnable = object : Runnable {
            override fun run() {
                if (waitingDotsRunnable !== this) return

                if (label.isVisible) {
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
            if (spectatorMode || isGameOver()) {
                if (isGameOver()) {
                    showGameOverLabel()
                }

                return@runOnUiThread
            }

            if (stateLabelVisual == StateLabelVisual.Waiting) {
                return@runOnUiThread
            }

            stopStateLabelAnimation()

            stateLabelVisual = StateLabelVisual.Waiting

            resetStateLabelLayout(
                stateLabel,
            )

            stateLabel.bringToFront()

            val waitingWidth = measureStateLabelWidth(
                stateLabel,
                "WAITING FOR OPPONENT...",
            )

            val params = stateLabel.layoutParams

            params.width = waitingWidth

            stateLabel.layoutParams = params

            stateLabel.visibility = View.VISIBLE

            startWaitingDots(
                stateLabel,
            )

            myAvatarAnchor.bringToFront()
            opponentAvatarAnchor.bringToFront()

            if (::gameMenu.isInitialized) {
                gameMenu.bringToFront()
            }

            stateLabel.bringToFront()
        }
    }

    private fun showSendingLabelImmediately() {
        runOnUiThread {
            stopStateLabelAnimation()
            stateLabelVisual = StateLabelVisual.SentWaiting

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
            stateLabelVisual = StateLabelVisual.SentWaiting

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
                ForegroundColorSpan(0xFF7257D8.toInt()), 5, 6, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )

            stateLabel.text = sentCheck
            stateLabel.alpha = 1f
            stateLabel.setTextColor(0xFFFFFFFF.toInt())
            stateLabel.visibility = View.VISIBLE
            stateLabel.bringToFront()

            stateLabelHandler.postDelayed({
                if (!sentWaitingSequenceActive) return@postDelayed

                if (isGameOver()) {
                    showGameOverLabel()
                    return@postDelayed
                }

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

                    addListener(object : android.animation.AnimatorListenerAdapter() {
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

                                addListener(object : android.animation.AnimatorListenerAdapter() {
                                    override fun onAnimationEnd(animation: android.animation.Animator) {
                                        if (sentWaitingSequenceActive) {
                                            stateLabel.setTextColor(0xFFFFFFFF.toInt())
                                            stateLabel.visibility = View.VISIBLE
                                            stateLabel.bringToFront()
                                            startWaitingDots(stateLabel)
                                        }
                                    }
                                })

                                start()
                            }
                        }
                    })

                    start()
                }
            }, 1000L)
        }
    }

    private fun dp(value: Float): Float {
        return value * resources.displayMetrics.density
    }

    private companion object {
        private const val DEFAULT_REPLAY =
            "board:0,0#" + "0.000000,-215.000000,1,0.000000,0.000000,0.000000#" + "0.000000,215.000000,2,0.000000,0.000000,0.000000#"

        private const val REPLAY_QUEUE_MARKER = "|shoot:1|"

        private const val MUSIC_TRACK_PATH = "shuffle/shuffle.wav"
    }
}