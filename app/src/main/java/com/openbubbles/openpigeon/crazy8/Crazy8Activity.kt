package com.openbubbles.openpigeon.crazy8

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.os.SystemClock
import android.util.Log
import androidx.core.content.edit
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.blur
import androidx.compose.ui.unit.dp
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.VectorConverter
import androidx.compose.ui.graphics.BlendMode
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import kotlin.math.sqrt
import kotlinx.coroutines.delay
import com.openbubbles.openpigeon.godot.GameSessionIPC
import com.playerio.Callback
import com.playerio.Client
import com.playerio.Connection
import com.playerio.DisconnectListener
import com.playerio.Message
import com.playerio.MessageListener
import com.playerio.PlayerIO
import com.playerio.PlayerIOError
import kotlin.math.min
import androidx.core.graphics.drawable.toDrawable
import com.google.android.vending.licensing.util.Base64
import androidx.compose.runtime.snapshots.SnapshotStateMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import com.openbubbles.openpigeon.BuildConfig
import android.graphics.BitmapFactory
import android.widget.FrameLayout
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.IconButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.viewinterop.AndroidView
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.settings.SettingsSheet
import kotlin.apply
import kotlin.toString
import androidx.compose.ui.res.painterResource
import com.openbubbles.openpigeon.R
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.zIndex
import com.openbubbles.openpigeon.ui.RulesPopup
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

class CrazyParticipant(
    name: String,
    val id: Int,
    val isMe: Boolean,
    ready: Boolean,
    avatar: String = "",
) {
    var name by mutableStateOf(name)
    var ready by mutableStateOf(ready)
    var cardCount by mutableIntStateOf(0)
    var avatar by mutableStateOf(avatar)
}

data class CrazyMessage(val message: String, val sender: CrazyParticipant)

data class CrazyCard(val rank: Int, val file: Int) {
    companion object {
        private fun normalizeFile(file: Int): Int {
            return when (file) {
                20 -> 11
                21 -> 12
                22 -> 13
                23 -> 14
                else -> file
            }
        }

        fun parse(data: String): CrazyCard {
            val parts = data.split(",")
            return CrazyCard(parts[0].toInt(), normalizeFile(parts[1].toInt()))
        }
    }

    fun isCompatibleWith(other: CrazyCard): Boolean {
        // equal rank
        if (other.rank == rank) return true
        // equal file
        if (other.file == file) return true
        // wildcard
        if (other.rank == 5 || rank == 5) return true
        return false
    }

    fun displayName(): String {
        return when(file) {
            8 -> "0"
            10 -> "8"
            11 -> "Ø"
            12 -> "⟳"
            13 -> "+2"
            14 -> "+4"
            else -> file.toString()
        }
    }

    fun extraName(): String {
        return displayName().slice(0..<1)
    }

    fun encode(): String {
        return "$rank,$file"
    }
}

class CrazyGame(
    val participants: List<CrazyParticipant>,
    turn: CrazyParticipant,
    card: CrazyCard,
    val hand: SnapshotStateList<CrazyCard>,
    clockwise: Boolean = true,
    directionKnown: Boolean = true
) {
    var turn by mutableStateOf(turn)
    var card by mutableStateOf(card)
    var clockwise by mutableStateOf(clockwise)
    var directionKnown by mutableStateOf(directionKnown)
}

private const val CRAZY8_VERBOSE_LOGS = false

private data class CrazyPerfProfile(
    val lightweightCards: Boolean,
    val lightweightCenterCard: Boolean,
    val lightweightTurnFx: Boolean,
    val skipOwnFlightAnims: Boolean,
    val skipOpponentFlightAnims: Boolean,
    val maxVisibleOpponentCards: Int
)

private fun buildCrazyPerfProfile(game: CrazyGame): CrazyPerfProfile {
    val opponentCards = game.participants
        .filter { !it.isMe }
        .sumOf { it.cardCount }

    val totalCards = game.hand.size + opponentCards
    val manyPlayers = game.participants.size >= 5
    val largeHand = game.hand.size >= 11

    return CrazyPerfProfile(
        lightweightCards = totalCards >= 24 || largeHand || manyPlayers,
        lightweightCenterCard = totalCards >= 18 || manyPlayers,
        lightweightTurnFx = totalCards >= 18 || manyPlayers,
        skipOwnFlightAnims = totalCards >= 28 || game.hand.size >= 13 || manyPlayers,
        skipOpponentFlightAnims = totalCards >= 22 || manyPlayers,
        maxVisibleOpponentCards = when {
            totalCards >= 40 -> 5
            totalCards >= 28 -> 7
            else -> 10
        }
    )
}

private fun Offset.isNear(other: Offset, epsilon: Float = 0.5f): Boolean {
    return abs(x - other.x) <= epsilon && abs(y - other.y) <= epsilon
}

private fun <K> SnapshotStateMap<K, Offset>.putOffsetIfChanged(
    key: K,
    value: Offset,
    epsilon: Float = 0.5f
) {
    val current = this[key]
    if (current == null || !current.isNear(value, epsilon)) {
        this[key] = value
    }
}

private fun centerOf(coords: LayoutCoordinates): Offset {
    val pos = coords.positionInRoot()
    return Offset(
        x = pos.x + coords.size.width / 2f,
        y = pos.y + coords.size.height / 2f
    )
}

private fun <K> SnapshotStateMap<K, Offset>.putCenterIfChanged(
    key: K,
    coords: LayoutCoordinates,
    epsilon: Float = 0.5f
) {
    putOffsetIfChanged(key, centerOf(coords), epsilon)
}

private fun updatedCenter(current: Offset?, coords: LayoutCoordinates): Offset {
    val newCenter = centerOf(coords)
    return if (current == null || !current.isNear(newCenter)) newCenter else current
}

private fun parseCrazyHand(section: String?): SnapshotStateList<CrazyCard> {
    if (section.isNullOrBlank()) return mutableStateListOf()

    val cards = section
        .split("&")
        .filter { it.isNotBlank() }
        .map { CrazyCard.parse(it) }
        .toMutableStateList()

    sortCrazyHandInPlace(cards)
    return cards
}

private fun applyCrazyCardCounts(
    gameParticipants: List<CrazyParticipant>,
    section: String
) {
    for (cardCount in section.split("&")) {
        val parts = cardCount.split(":")
        val participant = gameParticipants.find { it.id == parts[0].toInt() } ?: continue
        participant.cardCount = parts[1].toInt()
    }
}

private fun buildCrazyGameFromSections(
    allParticipants: List<CrazyParticipant>,
    participantIdsSection: String,
    cardStateSection: String,
    turnId: Int,
    clockwise: Boolean,
    directionKnown: Boolean = true
): CrazyGame {
    val participantIds = participantIdsSection
        .split(",")
        .mapNotNull { it.toIntOrNull() }

    val gameParticipants = participantIds
        .mapNotNull { id -> allParticipants.firstOrNull { it.id == id } }

    val cardState = cardStateSection.split("|")
    val turn = gameParticipants.find { it.id == turnId }
        ?: error("Missing turn participant for id=$turnId")
    val currentCard = CrazyCard.parse(cardState[0])

    if (cardState.size > 1) {
        applyCrazyCardCounts(gameParticipants, cardState[1])
    }

    val myCards = parseCrazyHand(cardState.getOrNull(2))

    return CrazyGame(
        participants = gameParticipants,
        turn = turn,
        card = currentCard,
        hand = myCards,
        clockwise = clockwise,
        directionKnown = directionKnown
    )
}

private fun <T> showTimedFx(
    fx: T,
    durationMs: Long,
    getCurrent: () -> T?,
    setCurrent: (T?) -> Unit,
    keyOf: (T) -> Int
) {
    setCurrent(fx)
    Handler(Looper.getMainLooper()).postDelayed({
        val current = getCurrent()
        if (current != null && keyOf(current) == keyOf(fx)) {
            setCurrent(null)
        }
    }, durationMs)
}

class Crazy8Activity : ComponentActivity() {
    var gameSessionIPC: GameSessionIPC? = null
    lateinit var sessionId: String
    var baseGame = Crazy8Game()
    var currentConnection: Connection? = null
    var name by mutableStateOf<String?>(null)

    private var isConnecting = false
    private var reconnectHandler = Handler(Looper.getMainLooper())
    private var reconnectRunnable: Runnable? = null

    lateinit var settingsSheet: SettingsSheet
    private var settingsConfigured = false
    private var settingsIdentityBeforeOpen: String? = null

    fun getPrefs(): SharedPreferences {
        return getSharedPreferences("crazy_prefs", MODE_PRIVATE)
    }

    private fun refreshSettingsSheetValues() {
        val current = name ?: getPrefs().getString("name", "") ?: ""
        settingsSheet.setHeaderNameValue(current)
        settingsSheet.refreshHeaderAvatar()
    }

    private fun setupSettingsSheet() {
        if (settingsConfigured) return
        settingsConfigured = true

        settingsSheet.configureHeaderNameField(
            enabled = true,
            value = name ?: getPrefs().getString("name", "") ?: "",
            hint = "Player name"
        ) { rawName ->
            val newName = rawName.trim()
            getPrefs().edit {
                putString("name", newName)
            }
            name = newName
        }
    }

    fun openSettings() {
        if (::settingsSheet.isInitialized) {
            settingsIdentityBeforeOpen = legacyAvatarStringForCrazy8(name ?: "Player")
            refreshSettingsSheetValues()
            settingsSheet.open()
        }
    }

    fun onSettingsClosed() {
        refreshSettingsSheetValues()

        val currentPacked = legacyAvatarStringForCrazy8(name ?: "Player")
        if (currentPacked != settingsIdentityBeforeOpen) {
            sendAvatarUpdate()
        }

        settingsIdentityBeforeOpen = null
    }

    fun openRules() {
        val root = findViewById<FrameLayout>(android.R.id.content)
        RulesPopup.show(
            context = this,
            rootView = root,
            title = "Crazy 8 Rules",
            sections = listOf(
                RulesPopup.Section(
                    "Objective",
                    "Be the first player to get rid of all your cards."
                ),
                RulesPopup.Section(
                    "How to Play",
                    "On your turn, play a card that matches the current card by color or symbol. If you cannot play, draw a card."
                ),
                RulesPopup.Section(
                    "Wild Cards",
                    "8 cards are wild. When you play one, you choose the new color."
                ),
                RulesPopup.Section(
                    "Action Cards",
                    "Special cards can skip, reverse, or force draws depending on the game rules in this version."
                ),
                RulesPopup.Section(
                    "Winning",
                    "The first player to play all of their cards wins the round."
                )
            )
        )
    }

    private fun cancelReconnect() {
        reconnectRunnable?.let { reconnectHandler.removeCallbacks(it) }
        reconnectRunnable = null
    }

    private fun scheduleReconnect(delayMs: Long = 1200L) {
        if (currentRoom.isBlank()) return
        if (name.isNullOrBlank()) return
        if (isConnecting) return
        if (currentConnection != null && connected) return

        cancelReconnect()

        reconnectRunnable = Runnable {
            if (isFinishing || isDestroyed) return@Runnable
            if (currentRoom.isBlank()) return@Runnable
            if (name.isNullOrBlank()) return@Runnable
            if (isConnecting) return@Runnable
            if (currentConnection != null && connected) return@Runnable

            Log.i("Crazy8", "Attempting reconnect to room=$currentRoom")
            connectedError = null
            joinRoom(currentRoom)
        }

        reconnectHandler.postDelayed(reconnectRunnable!!, delayMs)
    }

    private val networkExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private val pingRunnable = object : Runnable {
        override fun run() {
            sendAsync {
                currentConnection?.send("p")
            }
            reconnectHandler.postDelayed(this, 120000L)
        }
    }

    private fun sendAsync(block: () -> Unit) {
        networkExecutor.execute {
            try {
                block()
            } catch (e: Exception) {
                Log.e("Crazy8", "Async operation failed", e)
            }
        }
    }

    @SuppressLint("UseKtx")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        enableEdgeToEdge()

        val savedName = getPrefs().getString("name", "")?.trim().orEmpty()
        if (savedName.isNotEmpty() && name == null) {
            name = savedName
        }

        AvatarData.init(applicationContext)
        val rootFrame = window.decorView.findViewById<FrameLayout>(android.R.id.content)
        settingsSheet = SettingsSheet(this, rootFrame)
        settingsSheet.onClosed = {
            onSettingsClosed()
        }
        setupSettingsSheet()

        reconnectHandler.post(pingRunnable)

        window.setBackgroundDrawable(0xFFc5302a.toInt().toDrawable())

        sessionId = intent.getStringExtra("SESSION")!!

        GameSessionIPC(applicationContext) { gameSessionIPC ->
            this.gameSessionIPC = gameSessionIPC
            val currentMessage = gameSessionIPC.getCurrentMessage(sessionId)
            if (currentMessage.isNotEmpty()) {
                gameSessionIPC.lockMsgHandle(sessionId)
                gameSessionIPC.setSuppressNotifications(sessionId, true)

                val room = currentMessage["room"]!!
                joinRoom(room)
            } else {
                Log.e("openpigeon-${baseGame.getName()}", "$sessionId does not exist!")
                finish()
            }
        }

        PlayerIO.setUseSecureApiRequests(true)

        setContent {
            val prefs = remember { getPrefs() }

            if (CRAZY8_VERBOSE_LOGS) {
                Log.i("name", prefs.getString("name", "")!!)
            }
            var thisName by remember { mutableStateOf(prefs.getString("name", "") ?: "") }
            if (name == null) {
                Box(
                    modifier = Modifier.fillMaxSize()
                        .safeContentPadding()
                ) {
                    Image(
                        painter = painterResource(id = R.drawable.crazybg),
                        contentDescription = null,
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Crop
                    )

                    Column(modifier = Modifier.align(Alignment.Center),
                        horizontalAlignment = Alignment.CenterHorizontally) {
                        OutlinedTextField(
                            value = thisName,
                            onValueChange = { thisName = it },
                            label = { Text("Name") },
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = Color.White,
                                unfocusedBorderColor = Color.White,
                                focusedTextColor = Color.White,
                                unfocusedTextColor = Color.White,
                                cursorColor = Color.White,
                                focusedLabelColor = Color.White,
                                unfocusedLabelColor = Color.White,
                            ),
                            keyboardOptions = KeyboardOptions(
                                imeAction = ImeAction.Go,
                                capitalization = KeyboardCapitalization.Words
                            ),
                            keyboardActions = KeyboardActions(
                                onGo = {
                                    prefs.edit().putString("name", thisName).apply()
                                    name = thisName
                                    refreshSettingsSheetValues()
                                    joinRoom(currentRoom)
                                }
                            )
                        )
                        Button(onClick = {
                            prefs.edit().putString("name", thisName).apply()
                            name = thisName
                            refreshSettingsSheetValues()
                            joinRoom(currentRoom)
                        }, modifier = Modifier.padding(top = 16.dp)) {
                            Text("Join")
                        }
                    }
                }
            } else if (connectedError != null) {
                Box(
                    modifier = Modifier.fillMaxSize()
                ) {
                    Image(
                        painter = painterResource(id = R.drawable.crazybg),
                        contentDescription = null,
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Crop
                    )

                    Column(modifier = Modifier.align(Alignment.Center),
                        horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("Failed to connect: $connectedError",
                            fontSize = 20.sp,
                            color = Color.White,
                            modifier = Modifier.padding(10.dp),
                            textAlign = TextAlign.Center)
                        Button(onClick = {
                            connectedError = null
                            refreshSettingsSheetValues()
                            joinRoom(currentRoom)
                        }, modifier = Modifier.padding(top = 16.dp)) {
                            Text("Retry")
                        }
                    }
                }
            } else if (!connected) {
                Box(
                    modifier = Modifier.fillMaxSize()
                ) {
                    Image(
                        painter = painterResource(id = R.drawable.crazybg),
                        contentDescription = null,
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Crop
                    )

                    Text("Connecting...",
                        modifier = Modifier.align(Alignment.Center),
                        fontSize = 20.sp,
                        color = Color.White)
                }
            } else if (game != null) {
                RenderGame(game!!, this, messages)
            } else {
                RenderWaiting(participants, this)
            }
        }
    }

    var currentRoom = ""

    fun joinRoom(room: String) {
        currentRoom = room
        if (name == null) return
        if (isConnecting) return
        if (currentConnection != null && connected) return

        isConnecting = true
        connected = false
        connectedError = null

        val userid = gameSessionIPC!!.getSenderUUID(sessionId)
        val auth = PlayerIO.calcAuth256(userid, BuildConfig.PIO_SHARED_SECRET)
        val authParams = hashMapOf(
            "userId" to userid,
            "auth" to auth
        )

        PlayerIO.authenticate(this, BuildConfig.PIO_GAME_ID, "mobile", authParams, null, object : Callback<Client>() {
            override fun onSuccess(p0: Client?) {
                Log.i("PlayerIO", "Authenticated with playerIO!")
                val joinData = mapOf(
                    "id" to userid,
                    "name" to legacyAvatarStringForCrazy8(name ?: "Player"),
                    "version" to "52"
                )
                p0!!.multiplayer.createJoinRoom(room, "Chat", true, mapOf(), joinData, object : Callback<Connection>() {
                    override fun onSuccess(connection: Connection?) {
                        isConnecting = false
                        cancelReconnect()
                        setupConnection(connection!!)
                    }

                    override fun onError(p0: PlayerIOError?) {
                        isConnecting = false
                        Log.e("PlayerIO", "Error joining $p0")
                        connectedError = p0.toString()
                        scheduleReconnect()
                    }
                })
            }

            override fun onError(p0: PlayerIOError?) {
                isConnecting = false
                Log.e("PlayerIO", "Error $p0")
                connectedError = p0.toString()
                scheduleReconnect()
            }
        })

        Log.i("Godot room", room)
    }

    fun sendMessage(message: String) {
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(ByteArray(32) { 0x00 }, "AES"),
            IvParameterSpec(ByteArray(16) { 0x00 })
        )
        val encrypted = cipher.doFinal(message.encodeToByteArray())

        sendAsync {
            currentConnection?.send("emsg", encrypted)
        }
    }

    fun setReady(ready: Boolean) {
        sendAsync {
            currentConnection?.send(if (ready) "ready" else "notready")
        }
    }

    fun playCard(card: CrazyCard) {
        sendAsync {
            currentConnection?.send("move", card.encode(), "", 0)
        }
    }

    fun drawCard() {
        sendAsync {
            currentConnection?.send("move", "-1,-1", "", 0)
        }
    }

    fun performCardSnapHaptic() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibrator = (getSystemService(VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                    ?.defaultVibrator
                    ?: return

                if (!vibrator.hasVibrator()) return

                vibrator.vibrate(
                    VibrationEffect.createOneShot(28L, 220)
                )
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator ?: return

                if (!vibrator.hasVibrator()) return

                vibrator.vibrate(
                    VibrationEffect.createOneShot(28L, 220)
                )
            }
        } catch (_: Exception) {
        }
    }

    // Tracks the avatar string most recently broadcast to other players so we
    // don't spam the network when the polling loop re-reads the same value.
    @Volatile
    var lastBroadcastedAvatar: String? = null

    fun applyPackedIdentityUpdate(senderId: Int, packed: String, includeSelf: Boolean = false) {
        val updatedAvatar = avatarStringForLobby(packed)
        val updatedName = extractCrazy8DisplayName(packed)

        participants.find { it.id == senderId }?.let { participant ->
            if (includeSelf || !participant.isMe) {
                participant.avatar = updatedAvatar
                participant.name = updatedName
            }
        }

        game?.participants?.find { it.id == senderId }?.let { participant ->
            if (includeSelf || !participant.isMe) {
                participant.avatar = updatedAvatar
                participant.name = updatedName
            }
        }
    }

    fun sendAvatarUpdate() {
        val connection = currentConnection ?: return
        val packed = legacyAvatarStringForCrazy8(name ?: "Player")
        if (packed == lastBroadcastedAvatar) return

        lastBroadcastedAvatar = packed

        if (myId != 0) {
            applyPackedIdentityUpdate(myId, packed, includeSelf = true)
        }

        sendAsync {
            try {
                connection.send("name", packed)
                connection.send("avatar", packed)
            } catch (e: Exception) {
                Log.e("Crazy8", "Failed to send avatar update", e)
            }
        }
    }

    fun parseParticipant(id: Int, data: String, ready: Boolean): CrazyParticipant {
        return CrazyParticipant(
            name = extractCrazy8DisplayName(data),
            id = id,
            isMe = id == myId,
            ready = ready,
            avatar = avatarStringForLobby(data),
        )
    }

    fun upsertParticipant(id: Int, data: String, ready: Boolean) {
        val incoming = parseParticipant(id, data, ready)
        val existingIndex = participants.indexOfFirst { it.id == id }

        if (existingIndex == -1) {
            participants.add(incoming)
        } else {
            val existing = participants[existingIndex]
            existing.name = incoming.name
            existing.avatar = incoming.avatar
            existing.ready = incoming.ready
        }
    }

    val messages = mutableStateListOf<CrazyMessage>()

    val participants = mutableStateListOf<CrazyParticipant>()
    var game by mutableStateOf<CrazyGame?>(null)
    var label by mutableStateOf<String?>(null)
    var connected by mutableStateOf(false)
    var showLobbyChat by mutableStateOf(false)
    val lobbySpeechBubbles = mutableStateMapOf<Int, String>()
    var showBurgerMenu by mutableStateOf(false)

    var connectedError by mutableStateOf<String?>(null)

    var myId by mutableIntStateOf(0)
    private var fxCounter = 0

    var headFx by mutableStateOf<CrazyHeadFx?>(null)
    var reverseFx by mutableStateOf<CrazyReverseFx?>(null)
    var turnConeForceAroundKey by mutableIntStateOf(0)
    var pendingAutoWildDraw by mutableStateOf<CrazyCard?>(null)
    var pendingAutoPlayDraw by mutableStateOf<CrazyCard?>(null)

    private fun nextFxKey(): Int {
        fxCounter += 1
        return fxCounter
    }

    fun showSkipFx(playerId: Int) {
        val fx = CrazyHeadFx(
            key = nextFxKey(),
            playerId = playerId,
            skip = true
        )

        showTimedFx(
            fx = fx,
            durationMs = 780,
            getCurrent = { headFx },
            setCurrent = { headFx = it },
            keyOf = { it.key }
        )
    }

    fun showPenaltyFx(playerId: Int, text: String) {
        val fx = CrazyHeadFx(
            key = nextFxKey(),
            playerId = playerId,
            text = text
        )

        showTimedFx(
            fx = fx,
            durationMs = 1150,
            getCurrent = { headFx },
            setCurrent = { headFx = it },
            keyOf = { it.key }
        )
    }

    fun showReverseFx(clockwise: Boolean) {
        val fx = CrazyReverseFx(
            key = nextFxKey(),
            clockwise = clockwise
        )

        showTimedFx(
            fx = fx,
            durationMs = 860,
            getCurrent = { reverseFx },
            setCurrent = { reverseFx = it },
            keyOf = { it.key }
        )
    }

    fun setupConnection(connection: Connection) {
        currentConnection = connection
        isConnecting = false
        connectedError = null
        connection.send("p")
        lastBroadcastedAvatar = null

        if (myId != 0) {
            val packed = legacyAvatarStringForCrazy8(name ?: "Player")
            applyPackedIdentityUpdate(myId, packed, includeSelf = true)
        }

        sendAvatarUpdate()
        connection.addMessageListener("*", object : MessageListener() {
            override fun onMessage(message: Message?) {
                if (CRAZY8_VERBOSE_LOGS) {
                    Log.i("PlayerIO", "message $message")
                }
                when (message!!.type) {
                    "join_list", "game_list" -> {
                        connected = true
                        myId = message.getInt(1)
                        participants.clear()
                        participants.addAll(
                            message.getString(0)
                                .split("|")
                                .map {
                                    val parts = it.split("&")
                                    parseParticipant(parts[0].toInt(), parts[1], parts[2] == "1")
                                }
                                .distinctBy { it.id }
                        )
                        val currentPacked = legacyAvatarStringForCrazy8(name ?: "Player")
                        applyPackedIdentityUpdate(myId, currentPacked, includeSelf = true)
                        if (message.type == "game_list") {
                            label = null
                            val reverse = message.getBoolean(5)
                            val chain = message.getInt(6)

                            if (CRAZY8_VERBOSE_LOGS) {
                                Log.i("Crazy8", "game_list reverse=$reverse chain=$chain")
                            }

                            game = buildCrazyGameFromSections(
                                allParticipants = participants,
                                participantIdsSection = message.getString(2),
                                cardStateSection = message.getString(3),
                                turnId = message.getInt(4),
                                clockwise = !reverse,
                                directionKnown = true
                            )
                        }
                    }
                    "join" -> {
                        upsertParticipant(message.getInt(0), message.getString(1), false)
                    }
                    "ready" -> {
                        participants.find { it.id == message.getInt(0) }?.ready = true
                    }
                    "notready" -> {
                        participants.find { it.id == message.getInt(0) }?.ready = false
                    }
                    "left" -> {
                        participants.removeIf { it.id == message.getInt(0) }
                    }
                    "game_start" -> {
                        label = null
                        game = buildCrazyGameFromSections(
                            allParticipants = participants,
                            participantIdsSection = message.getString(0),
                            cardStateSection = message.getString(1),
                            turnId = message.getInt(2),
                            clockwise = true,
                            directionKnown = true
                        )
                    }
                    "move" -> {
                        game?.let { game ->
                            val moved = game.participants.find { it.id == message.getInt(0) }!!
                            val wasClockwise = game.clockwise
                            val nextTurn = game.participants.find { it.id == message.getInt(2) }!!
                            game.turn = nextTurn

                            val move = message.getString(1).split("|")
                            var playedFile = -1

                            if (move[0] != "-1,-1") {
                                val playedCard = CrazyCard.parse(move[0])
                                playedFile = playedCard.file
                                game.card = playedCard

                                if (playedFile == 11) {
                                    skippedPlayerId(
                                        participants = game.participants,
                                        movedId = moved.id,
                                        nextTurnId = nextTurn.id,
                                        clockwise = wasClockwise
                                    )?.let { skippedId ->
                                        this@Crazy8Activity.turnConeForceAroundKey += 1
                                        this@Crazy8Activity.showSkipFx(skippedId)
                                    }
                                }

                                if (playedFile == 12) {
                                    game.clockwise = !game.clockwise
                                    game.directionKnown = true
                                    this@Crazy8Activity.showReverseFx(game.clockwise)
                                }

                                moved.cardCount -= 1
                                if (moved.cardCount == 0) {
                                    label = "${if (moved.isMe) "You" else moved.name} won!"
                                    Handler(Looper.getMainLooper()).postDelayed({
                                        for (participant in participants) {
                                            participant.ready = false
                                        }
                                        this@Crazy8Activity.game = null
                                        label = null
                                    }, 6000)
                                }
                            }
                            if (move.size == 1) {
                                // handled
                            } else if (move[1] == "d") {
                                moved.cardCount += move.size - 2 // card, d
                                if (moved.isMe) {
                                    val drawnCards = move.slice(2..<move.size).map { CrazyCard.parse(it) }
                                    game.hand.addAll(drawnCards)
                                    sortCrazyHandInPlace(game.hand)

                                    val firstDrawnCard = drawnCards.firstOrNull()

                                    if (
                                        firstDrawnCard != null &&
                                        shouldAutoPlayDrawnCard(firstDrawnCard, game.card)
                                    ) {
                                        if (firstDrawnCard.rank == 5) {
                                            pendingAutoWildDraw = firstDrawnCard
                                        } else {
                                            pendingAutoPlayDraw = firstDrawnCard
                                        }
                                    }
                                }
                            } else if (move[1] == "c") {
                                val added = game.participants.find { it.id == move[2].toInt() }!!
                                val addedCount = move.size - 3 // card, c, id
                                added.cardCount += addedCount

                                if (addedCount > 0 && (playedFile == 13 || playedFile == 14)) {
                                    this@Crazy8Activity.turnConeForceAroundKey += 1
                                    this@Crazy8Activity.showPenaltyFx(
                                        playerId = added.id,
                                        text = "+$addedCount"
                                    )
                                }

                                if (added.isMe) {
                                    game.hand.addAll(move.slice(3..<move.size).map { CrazyCard.parse(it) })
                                    sortCrazyHandInPlace(game.hand)
                                }
                            }
                        }
                    }
                    "emsg" -> {
                        val sender = participants.find { it.id == message.getInt(0) }
                        if (sender == null) return

                        val bytes = message.getByteArray(1)
                        if (CRAZY8_VERBOSE_LOGS) {
                            Log.i("bytes", Base64.encode(bytes))
                        }
                        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
                        // Vitalii Zlotskii is very good at cryptography, as showed off here...
                        // this encryption is very effective
                        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(ByteArray(32) { 0x00 }, "AES"), IvParameterSpec(
                            ByteArray(16) { 0x00 }))
                        val decrypted = String(cipher.doFinal(bytes))

                        messages.add(0, CrazyMessage(decrypted, sender))
                        lobbySpeechBubbles[sender.id] = decrypted.take(80)

                        Handler(Looper.getMainLooper()).postDelayed({
                            if (lobbySpeechBubbles[sender.id] == decrypted.take(80)) {
                                lobbySpeechBubbles.remove(sender.id)
                            }
                        }, 3000)

                        if (CRAZY8_VERBOSE_LOGS) {
                            Log.i("Got message", decrypted)
                        }
                    }
                    "name", "avatar" -> {
                        val senderId = message.getInt(0)
                        val packed = message.getString(1)
                        applyPackedIdentityUpdate(senderId, packed)
                    }
                    else -> { }
                }
            }
        })
        connection.addDisconnectListener(object : DisconnectListener() {
            override fun onDisconnect() {
                Log.i("PlayerIO", "disconnected")
                connected = false
                currentConnection = null
                isConnecting = false
                lastBroadcastedAvatar = null
                scheduleReconnect()
            }
        })
    }

    override fun onDestroy() {
        cancelReconnect()
        reconnectHandler.removeCallbacks(pingRunnable)
        networkExecutor.shutdownNow()
        currentConnection?.disconnect()
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()

        if (gameSessionIPC != null) {
            gameSessionIPC?.setSuppressNotifications(sessionId, true)
        } else {
            Log.w("openpigeon-${baseGame.getName()}", "onResume called before gameSessionIPC was initialized!")
        }

        if (currentConnection == null && currentRoom.isNotBlank() && !name.isNullOrBlank()) {
            scheduleReconnect(200L)
        }
    }

    override fun onPause() {
        gameSessionIPC!!.setSuppressNotifications(sessionId, false)
        super.onPause()
    }
}

@SuppressLint("UnrememberedMutableState")
@Preview
@Composable
fun RenderWaitingPreview() {
    RenderWaiting(
        mutableStateListOf(
            CrazyParticipant("Testing", 0, true, false),
            CrazyParticipant("Testing", 1, false, true),
        )
        ,  null)
}

@SuppressLint("UnrememberedMutableState")
@Preview
@Composable
fun RenderGamePreview() {
    val participants = listOf(
        CrazyParticipant("Testing", 0, true, false),
        CrazyParticipant("Testing", 1, false, true),
        CrazyParticipant("Testing", 2, false, true),
        CrazyParticipant("Testing", 3, false, false),
        CrazyParticipant("Testing", 4, false, true),
        CrazyParticipant("Testing", 5, false, true),
    )
    participants[1].cardCount = 7
    participants[2]. cardCount = 7
    participants[3]. cardCount = 7
    participants[4]. cardCount = 7
    participants[5]. cardCount = 7
    RenderGame(CrazyGame(
        participants,
        participants[1],
        CrazyCard(3, 10),
        mutableStateListOf(
            CrazyCard(2, 1),
            CrazyCard(2, 2),
            CrazyCard(5, 3),
            CrazyCard(2, 4),
            CrazyCard(2, 2),
        )
    ), null, mutableStateListOf()
    )
}

@Composable
fun RenderCard(
    card: CrazyCard?,
    modifier: Modifier = Modifier,
    lightweight: Boolean = false
) {
    val shape = RoundedCornerShape(7.dp)
    val label = card?.displayName().orEmpty()

    val bgColor = when (card?.rank ?: -1) {
        0 -> Color(0xFFE53935)
        1 -> Color(0xFF1e88e5)
        2 -> Color(0xFFFDD835)
        3 -> Color(0xFF43A047)
        5 -> Color(0xFF2B2B2B)
        else -> Color(0xFF555555)
    }

    Box(
        modifier = modifier
            .size(80.dp, 110.dp)
            .background(bgColor, shape)
            .border(2.dp, Color.White, shape),
        contentAlignment = Alignment.Center
    ) {
        if (card != null) {
            val isWildLook = card.rank == 5 || card.file == 14
            val isIconCard = card.file == 11 || card.file == 12

            if (isWildLook) {
                Canvas(modifier = Modifier.size(54.dp)) {
                    val colors = listOf(
                        Color(0xFFE53935),
                        Color(0xFF1E88E5),
                        Color(0xFFFDD835),
                        Color(0xFF43A047)
                    )

                    for (i in colors.indices) {
                        drawArc(
                            color = colors[i],
                            startAngle = i * 90f,
                            sweepAngle = 90f,
                            useCenter = true,
                            size = Size(size.width, size.height)
                        )
                    }

                    drawCircle(
                        color = Color.White.copy(alpha = 0.18f),
                        radius = size.minDimension * 0.28f
                    )
                }
            }

            if (isIconCard) {
                Image(
                    painter = painterResource(
                        id = if (card.file == 11) R.drawable.skip_white else R.drawable.reverse
                    ),
                    contentDescription = null,
                    modifier = Modifier.size(if (card.file == 11) 46.dp else 52.dp),
                    contentScale = ContentScale.Fit
                )

                Image(
                    painter = painterResource(
                        id = if (card.file == 11) R.drawable.skip_white else R.drawable.reverse
                    ),
                    contentDescription = null,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(start = 6.dp, top = 4.dp)
                        .size(if (card.file == 11) 24.dp else 20.dp),
                    contentScale = ContentScale.Fit
                )

                Image(
                    painter = painterResource(
                        id = if (card.file == 11) R.drawable.skip_white else R.drawable.reverse
                    ),
                    contentDescription = null,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(end = 6.dp, bottom = 4.dp)
                        .size(if (card.file == 11) 24.dp else 20.dp)
                        .rotate(180f),
                    contentScale = ContentScale.Fit
                )
            } else {
                Text(
                    text = label,
                    color = Color.White,
                    fontSize = if (lightweight) 30.sp else 34.sp,
                    fontWeight = FontWeight.ExtraBold,
                    style = TextStyle(
                        shadow = Shadow(
                            color = Color.Black.copy(alpha = if (isWildLook) 0.45f else 0.35f),
                            offset = Offset(1.5f, 2f),
                            blurRadius = if (isWildLook) 2f else 1.5f
                        )
                    )
                )

                Text(
                    text = label,
                    color = Color.White,
                    fontSize = 21.sp,
                    fontWeight = FontWeight.ExtraBold,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(start = 6.dp, top = 4.dp)
                )

                Text(
                    text = label,
                    color = Color.White,
                    fontSize = 21.sp,
                    fontWeight = FontWeight.ExtraBold,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(end = 6.dp, bottom = 4.dp)
                        .rotate(180f)
                )
            }

            Box(
                modifier = Modifier
                    .matchParentSize()
                    .padding(5.dp)
                    .border(1.dp, Color.White.copy(alpha = 0.28f), RoundedCornerShape(5.dp))
            )
        }
    }
}

@Composable
fun RenderCardBack(
    modifier: Modifier = Modifier,
    lightweight: Boolean = false
) {
    val shape = RoundedCornerShape(4.dp)

    Box(
        modifier = modifier
            .size(80.dp, 110.dp)
            .background(Color(0xFF444444), shape)
            .border(2.dp, Color.White, shape),
        contentAlignment = Alignment.Center
    ) {
        if (!lightweight) {
            Text(
                "CRAZY 8",
                color = Color.White.copy(alpha = 0.18f),
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

@Composable
fun rememberAssetBitmap(context: Context, path: String): androidx.compose.ui.graphics.ImageBitmap? {
    val imageState = remember(path) { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }

    LaunchedEffect(path) {
        try {
            context.assets.open(path).use { stream ->
                val bmp = BitmapFactory.decodeStream(stream)
                imageState.value = bmp?.asImageBitmap()
            }
        } catch (e: Exception) {
            Log.e("Crazy8", "Failed to load asset $path", e)
        }
    }

    return imageState.value
}

@Composable
fun RenderLobbyAvatar(avatarData: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(Color.White)
            .border(1.dp, Color(0x22000000), RoundedCornerShape(percent = 50)),
        contentAlignment = Alignment.Center
    ) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                AvatarView(context).apply {
                    setBackgroundColor(android.graphics.Color.TRANSPARENT)
                    alpha = 1f
                    elevation = 0f
                    try {
                        applyFromOpponentString(avatarData)
                        tag = avatarData
                    } catch (e: Exception) {
                        Log.e("Crazy8", "Failed to render lobby avatar", e)
                        showPlaceholder()
                    }
                }
            },
            update = { view ->
                val lastApplied = view.tag as? String
                if (lastApplied == avatarData) return@AndroidView

                try {
                    view.applyFromOpponentString(avatarData)
                    view.tag = avatarData
                } catch (e: Exception) {
                    Log.e("Crazy8", "Failed to update lobby avatar", e)
                    view.showPlaceholder()
                }
            }
        )
    }
}

@Composable
fun RenderDrawPile(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    shouldPulse: Boolean = false
) {
    val interactionSource = remember { MutableInteractionSource() }

    val pulseOverlayAlpha = remember { Animatable(0f) }

    LaunchedEffect(shouldPulse) {
        if (!shouldPulse) {
            pulseOverlayAlpha.snapTo(0f)
            return@LaunchedEffect
        }

        while (true) {
            pulseOverlayAlpha.animateTo(
                targetValue = 0.34f,
                animationSpec = tween(620, easing = LinearEasing)
            )
            pulseOverlayAlpha.animateTo(
                targetValue = 0.08f,
                animationSpec = tween(620, easing = LinearEasing)
            )
        }
    }

    Box(
        modifier = modifier
            .size(88.dp, 118.dp)
            .then(
                if (onClick != null) {
                    Modifier.clickable(
                        interactionSource = interactionSource,
                        indication = null
                    ) { onClick() }
                } else {
                    Modifier
                }
            )
    ) {
        // Back card (no text)
        Box(
            modifier = Modifier
                .offset(x = (-3).dp, y = (-3).dp)
                .size(80.dp, 110.dp)
        ) {
            RenderCardBack(lightweight = true)
        }

        Box(
            modifier = Modifier
                .size(80.dp, 110.dp),
            contentAlignment = Alignment.Center
        ) {
            RenderCardBack(lightweight = true)

            Text(
                "CRAZY 8",
                color = Color.White.copy(alpha = 0.22f),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
        }
        if (shouldPulse) {
            Box(
                modifier = Modifier
                    .size(80.dp, 110.dp)
                    .background(
                        Color.White.copy(alpha = pulseOverlayAlpha.value),
                        RoundedCornerShape(4.dp)
                    )
                    .border(
                        2.dp,
                        Color.White.copy(alpha = pulseOverlayAlpha.value.coerceAtMost(0.42f)),
                        RoundedCornerShape(4.dp)
                    )
            )
        }
    }
}

private fun lerp(start: Float, stop: Float, fraction: Float): Float {
    return start + (stop - start) * fraction
}

@Composable
fun TurnConeOverlay(
    modifier: Modifier = Modifier,
    from: Offset,
    to: Offset,
    isActive: Boolean,
    lightweight: Boolean = false,
    blurRadius: androidx.compose.ui.unit.Dp = 0.dp
) {
    if (!isActive) return

    val pulse = remember { Animatable(0.18f) }

    LaunchedEffect(isActive) {
        if (!isActive) return@LaunchedEffect

        while (true) {
            pulse.animateTo(
                targetValue = 0.28f,
                animationSpec = tween(350, easing = LinearEasing)
            )
            pulse.animateTo(
                targetValue = 0.16f,
                animationSpec = tween(350, easing = LinearEasing)
            )
        }
    }

    val coneAlpha = if (lightweight) pulse.value else pulse.value.coerceAtMost(0.32f)

    Canvas(modifier = modifier) {
        val dx = to.x - from.x
        val dy = to.y - from.y
        val len = sqrt(dx * dx + dy * dy).coerceAtLeast(1f)
        val ux = dx / len
        val uy = dy / len
        val px = -uy
        val py = ux

        val startHalfWidth = 14.dp.toPx()
        val endHalfWidth = 60.dp.toPx()

        val p1 = Offset(from.x + px * startHalfWidth, from.y + py * startHalfWidth)
        val p2 = Offset(from.x - px * startHalfWidth, from.y - py * startHalfWidth)
        val p3 = Offset(to.x - px * endHalfWidth, to.y - py * endHalfWidth)
        val p4 = Offset(to.x + px * endHalfWidth, to.y + py * endHalfWidth)

        val path = Path().apply {
            moveTo(p1.x, p1.y)
            lineTo(p2.x, p2.y)
            lineTo(p3.x, p3.y)
            lineTo(p4.x, p4.y)
            close()
        }

        drawPath(
            path = path,
            brush = Brush.linearGradient(
                colors = listOf(
                    Color.White.copy(alpha = coneAlpha),
                    Color.Transparent
                ),
                start = from,
                end = to
            ),
            blendMode = BlendMode.Screen
        )
    }
}

@Composable
fun DirectionArrowOverlay(
    modifier: Modifier = Modifier,
    center: Offset,
    target: Offset,
    clockwise: Boolean
) {
    val density = LocalDensity.current

    val dx = target.x - center.x
    val dy = target.y - center.y
    val len = sqrt(dx * dx + dy * dy).coerceAtLeast(1f)

    val ux = dx / len
    val uy = dy / len
    val px = -uy
    val py = ux

    val midT = 0.5f
    val midX = center.x + dx * midT
    val midY = center.y + dy * midT

    val sideOffsetPx = with(density) { 60.dp.toPx() }
    val arrowSize = 26.dp

    val leftCenter = Offset(
        x = midX - px * sideOffsetPx,
        y = midY - py * sideOffsetPx
    )

    val rightCenter = Offset(
        x = midX + px * sideOffsetPx,
        y = midY + py * sideOffsetPx
    )

    val beamAngleDeg = Math.toDegrees(kotlin.math.atan2(dy.toDouble(), dx.toDouble())).toFloat()
    val directionFlip = if (clockwise) 0f else 180f
    val baseRotation = beamAngleDeg + 90f + directionFlip

    val leftRotation = baseRotation - 30f
    val rightRotation = baseRotation + 30f

    Box(modifier = modifier) {
        Image(
            painter = painterResource(id = R.drawable.crazyarrow),
            contentDescription = null,
            modifier = Modifier
                .offset(
                    x = with(density) { leftCenter.x.toDp() - arrowSize / 2 },
                    y = with(density) { leftCenter.y.toDp() - arrowSize / 2 }
                )
                .size(arrowSize)
                .rotate(leftRotation),
            contentScale = ContentScale.Fit
        )

        Image(
            painter = painterResource(id = R.drawable.crazyarrow),
            contentDescription = null,
            modifier = Modifier
                .offset(
                    x = with(density) { rightCenter.x.toDp() - arrowSize / 2 },
                    y = with(density) { rightCenter.y.toDp() - arrowSize / 2 }
                )
                .size(arrowSize)
                .rotate(rightRotation),
            contentScale = ContentScale.Fit
        )
    }
}

private fun normalizedAngle(angle: Float): Float {
    var a = angle
    while (a < 0f) a += (2f * PI.toFloat())
    while (a >= 2f * PI.toFloat()) a -= (2f * PI.toFloat())
    return a
}

private fun shortestAngleDelta(from: Float, to: Float): Float {
    val twoPi = (2f * PI.toFloat())
    var delta = (to - from) % twoPi
    if (delta > PI.toFloat()) delta -= twoPi
    if (delta < -PI.toFloat()) delta += twoPi
    return delta
}

private fun directionalAngleDelta(
    from: Float,
    to: Float,
    clockwise: Boolean
): Float {
    val twoPi = 2f * PI.toFloat()
    var delta = (to - from) % twoPi

    if (clockwise) {
        while (delta <= 0f) {
            delta += twoPi
        }
    } else {
        while (delta >= 0f) {
            delta -= twoPi
        }
    }

    return delta
}

private fun crazyCardSortKey(card: CrazyCard): Triple<Int, Int, Int> {
    val colorBucket = when (card.rank) {
        0 -> 0 // red
        1 -> 1 // blue
        2 -> 2 // yellow
        3 -> 3 // green
        5 -> 4 // wilds
        else -> 5
    }

    val valueBucket = when {
        card.rank != 5 -> card.file
        card.file == 14 -> 999 // +4 at very end
        else -> card.file + 100
    }

    return Triple(colorBucket, valueBucket, card.rank)
}

private fun sortCrazyHandInPlace(hand: SnapshotStateList<CrazyCard>) {
    val sorted = hand.sortedWith(
        compareBy<CrazyCard>(
            { crazyCardSortKey(it).first },
            { crazyCardSortKey(it).second },
            { crazyCardSortKey(it).third }
        )
    )
    hand.clear()
    hand.addAll(sorted)
}

private fun buildCrazyHandInstanceKeys(cards: List<CrazyCard>): List<String> {
    val seen = mutableMapOf<String, Int>()

    return cards.map { card ->
        val enc = card.encode()
        val count = seen[enc] ?: 0
        seen[enc] = count + 1
        "$enc#$count"
    }
}

private fun cardScaleForHand(game: CrazyGame): Float {
    val cardCount = game.hand.size
    val playerCount = game.participants.size.coerceAtLeast(3)

    val playerTightness = when (playerCount) {
        5, 6 -> 0.94f
        4 -> 0.97f
        else -> 1f
    }

    return when {
        cardCount <= 6 -> 1.00f
        cardCount <= 8 -> 0.92f
        cardCount <= 10 -> 0.84f
        cardCount <= 12 -> 0.76f
        else -> 0.68f
    } * playerTightness
}

private fun shouldAutoPlayDrawnCard(
    drawnCard: CrazyCard,
    currentCard: CrazyCard
): Boolean {
    return drawnCard.isCompatibleWith(currentCard)
}

data class CrazyHeadFx(
    val	key: Int,
    val	playerId: Int,
    val	text: String? = null,
    val	skip: Boolean = false
)

data class CrazyReverseFx(
    val	key: Int,
    val	clockwise: Boolean
)

private fun skippedPlayerId(
    participants: List<CrazyParticipant>,
    movedId: Int,
    nextTurnId: Int,
    clockwise: Boolean
): Int? {
    val n = participants.size
    if (n < 3) return null

    val movedIndex = participants.indexOfFirst { it.id == movedId }
    val nextIndex = participants.indexOfFirst { it.id == nextTurnId }
    if (movedIndex == -1 || nextIndex == -1) return null

    val skipIndex = if (clockwise) {
        (movedIndex + 1) % n
    } else {
        (movedIndex - 1 + n) % n
    }

    val expectedNext = if (clockwise) {
        (movedIndex + 2) % n
    } else {
        (movedIndex - 2 + n + n) % n
    }

    return if (nextIndex == expectedNext) participants[skipIndex].id else null
}

private data class CrazySeat(
    val cardCx: Float,
    val cardCy: Float,
    val avatarCx: Float,
    val avatarCy: Float,
    val bubbleFlip: Boolean = false
)

private fun crazyOpponentSeats(count: Int): List<CrazySeat> {
    val top = CrazySeat(0.50f, 0.06f, 0.50f, 0.17f)
    val leftMid = CrazySeat(0.00f, 0.24f, 0.20f, 0.30f)
    val rightMid = CrazySeat(1.00f, 0.24f, 0.80f, 0.30f, true)
    val bottomLeft = CrazySeat(0.00f, 0.60f, 0.20f, 0.63f)
    val bottomRight = CrazySeat(1.00f, 0.60f, 0.80f, 0.63f, true)

    return when (count) {
        2 -> listOf(leftMid, rightMid)
        3 -> listOf(top, leftMid, rightMid)
        4 -> listOf(top, leftMid, rightMid, bottomLeft)
        else -> listOf(top, leftMid, rightMid, bottomLeft, bottomRight)
    }
}

@Composable
fun RenderGame(game: CrazyGame, activity: Crazy8Activity?, messages: SnapshotStateList<CrazyMessage>) {
    val selectedKey = remember { mutableStateOf<String?>(null) }
    val selectedWildcardKey = remember { mutableStateOf<String?>(null) }
    var lastTappedCardKey by remember { mutableStateOf<String?>(null) }
    var lastTappedAtMs by remember { mutableStateOf(0L) }
    val doubleTapWindowMs = 260L
    val me = game.participants.find { it.isMe }
    val label = activity?.label
    val textInput = remember { mutableStateOf("") }
    val imeVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
    val keyboardController = LocalSoftwareKeyboardController.current
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current

    var drawPileCenter by remember { mutableStateOf<Offset?>(null) }
    var discardPileCenter by remember { mutableStateOf<Offset?>(null) }
    var pileGroupCenter by remember { mutableStateOf<Offset?>(null) }
    var boardOriginRoot by remember { mutableStateOf(Offset.Zero) }
    var turnPileGroupCenter by remember { mutableStateOf<Offset?>(null) }
    val handCardCenters = remember { mutableStateMapOf<String, Offset>() }
    val avatarCenters = remember { mutableStateMapOf<Int, Offset>() }
    val turnAvatarCenters = remember { mutableStateMapOf<Int, Offset>() }
    var handAreaSize by remember { mutableStateOf(IntSize.Zero) }

    val perf = buildCrazyPerfProfile(game)
    val handKeys = buildCrazyHandInstanceKeys(game.hand)
    val handSignature = handKeys.joinToString("|")
    val handPlayable = game.hand.map { it.isCompatibleWith(game.card) }
    val selectedWildcardIndex = selectedWildcardKey.value?.let { handKeys.indexOf(it) } ?: -1

    val avatarWidth = 64.dp
    val avatarHeight = 46.dp
    val pileScale = 0.90f

    var flyingCard by remember { mutableStateOf<CrazyCard?>(null) }
    val flyingCardOffset = remember { Animatable(Offset.Zero, Offset.VectorConverter) }
    val flyingCardScaleAnim = remember { Animatable(1f) }
    var hiddenHandKey by remember { mutableStateOf<String?>(null) }
    var interactionLocked by remember { mutableStateOf(false) }
    var drawInFlight by remember { mutableStateOf(false) }
    var drewAndMustWaitThisTurn by remember(game) { mutableStateOf(false) }
    val opponentPileCenters = remember { mutableStateMapOf<Int, Offset>() }
    var flyingBackside by remember { mutableStateOf(false) }
    var previousOpponentCounts by remember(game) {
        mutableStateOf(
            game.participants
                .filter { !it.isMe }
                .associate { it.id to it.cardCount }
        )
    }

    var previousHandSnapshot by remember(game) {
        mutableStateOf(buildCrazyHandInstanceKeys(game.hand))
    }

    val incomingHandKeys = remember(handSignature, previousHandSnapshot) {
        handKeys.filter { it !in previousHandSnapshot }.toSet()
    }

    val handLightweight = true
    val maxVisibleOpponentCards = perf.maxVisibleOpponentCards

    suspend fun animateFlyingCard(
        card: CrazyCard,
        start: Offset,
        end: Offset,
        hideKey: String? = null,
        startScale: Float = 1f,
        endScale: Float = 1f,
        durationMs: Int = 280
    ) {
        hiddenHandKey = hideKey
        flyingCard = card
        flyingBackside = false
        flyingCardOffset.snapTo(start)
        flyingCardScaleAnim.snapTo(startScale)

        coroutineScope {
            launch {
                flyingCardOffset.animateTo(
                    targetValue = end,
                    animationSpec = tween(durationMillis = durationMs, easing = FastOutSlowInEasing)
                )
            }
            launch {
                flyingCardScaleAnim.animateTo(
                    targetValue = endScale,
                    animationSpec = tween(durationMillis = durationMs, easing = FastOutSlowInEasing)
                )
            }
        }

        activity?.performCardSnapHaptic()

        flyingCard = null
        flyingBackside = false
        hiddenHandKey = null
    }

    suspend fun animateOpponentFly(
        card: CrazyCard?,
        start: Offset,
        end: Offset,
        backside: Boolean,
        durationMs: Int = 260
    ) {
        flyingBackside = backside
        flyingCard = card
        flyingCardOffset.snapTo(start)
        flyingCardScaleAnim.snapTo(0.96f)

        coroutineScope {
            launch {
                flyingCardOffset.animateTo(
                    targetValue = end,
                    animationSpec = tween(durationMillis = durationMs, easing = FastOutSlowInEasing)
                )
            }
            launch {
                flyingCardScaleAnim.animateTo(
                    targetValue = 1f,
                    animationSpec = tween(durationMillis = durationMs, easing = FastOutSlowInEasing)
                )
            }
        }

        activity?.performCardSnapHaptic()

        flyingCard = null
        flyingBackside = false
    }

    var chatRead by remember { mutableIntStateOf(0) }
    if (imeVisible) {
        chatRead = messages.size
    }

    val unread = messages.size - chatRead
    val clockwise = game.clockwise
    val animatedBeamAngle = remember { Animatable(0f) }
    var beamAngleInitialized by remember { mutableStateOf(false) }
    var lastHandledForceAroundKey by remember { mutableIntStateOf(activity?.turnConeForceAroundKey ?: 0) }

    val rulesIcon = if (activity != null) {
        rememberAssetBitmap(activity, "global/rules.png")
    } else {
        null
    }

    val settingsIcon = if (activity != null) {
        rememberAssetBitmap(activity, "global/settings.png")
    } else {
        null
    }

    fun avatarFor(participant: CrazyParticipant): String {
        return participant.avatar
    }

    fun centerInBoard(coords: LayoutCoordinates): Offset {
        val rootCenter = centerOf(coords)
        return Offset(
            x = rootCenter.x - boardOriginRoot.x,
            y = rootCenter.y - boardOriginRoot.y
        )
    }

    fun playCardFromHand(index: Int, cardKey: String, card: CrazyCard) {
        if (interactionLocked) return
        if (drewAndMustWaitThisTurn) return
        if (label != null) return
        if (game.turn != me) return
        if (!card.isCompatibleWith(game.card)) return

        if (card.rank == 5) {
            selectedKey.value = null
            selectedWildcardKey.value = cardKey
            return
        }

        val start = handCardCenters[cardKey]
        val end = discardPileCenter

        selectedKey.value = null

        if (start == null || end == null) {
            if (index in game.hand.indices) {
                game.hand.removeAt(index)
                activity?.playCard(card)
            }
            return
        }

        scope.launch {
            interactionLocked = true
            animateFlyingCard(
                card = card,
                start = start,
                end = end,
                hideKey = cardKey,
                startScale = cardScaleForHand(game),
                endScale = cardScaleForHand(game) * 0.96f,
                durationMs = 240
            )
            if (index in game.hand.indices) {
                game.hand.removeAt(index)
                activity?.playCard(card)
            }
            interactionLocked = false
        }
    }

    fun playCurrentlySelectedCard() {
        val key = selectedKey.value ?: return
        lastTappedCardKey = null
        lastTappedAtMs = 0L
        val keys = handKeys
        val index = keys.indexOf(key)
        if (index == -1) {
            selectedKey.value = null
            return
        }

        val card = game.hand.getOrNull(index)
        if (card == null) {
            selectedKey.value = null
            return
        }

        playCardFromHand(index, key, card)
    }

    fun handleCardTap(index: Int, cardKey: String, card: CrazyCard, isPlayable: Boolean) {
        if (interactionLocked) return
        if (drewAndMustWaitThisTurn) return
        if (label != null) return
        if (game.turn != me) return
        if (!isPlayable) return

        val now = SystemClock.uptimeMillis()
        val isDoubleTap =
            lastTappedCardKey == cardKey &&
                    (now - lastTappedAtMs) <= doubleTapWindowMs

        if (isDoubleTap) {
            lastTappedCardKey = null
            lastTappedAtMs = 0L
            selectedKey.value = cardKey
            playCardFromHand(index, cardKey, card)
            return
        }

        selectedWildcardKey.value = null
        selectedKey.value = cardKey
        lastTappedCardKey = cardKey
        lastTappedAtMs = now
    }

    LaunchedEffect(handSignature) {
        val currentSnapshot = handKeys

        if (drawPileCenter == null) {
            drawInFlight = false
            previousHandSnapshot = currentSnapshot
            return@LaunchedEffect
        }

        if (currentSnapshot.size > previousHandSnapshot.size) {
            drawInFlight = false

            val newKeys = currentSnapshot
                .filter { it !in previousHandSnapshot }
                .take(8)

            for ((newIndex, targetKey) in newKeys.withIndex()) {
                var targetCenter: Offset? = null
                repeat(12) {
                    targetCenter = handCardCenters[targetKey]
                    if (targetCenter != null) return@repeat
                    delay(16)
                }

                val resolvedTargetCenter = targetCenter
                val targetIndex = currentSnapshot.indexOf(targetKey)
                val card = game.hand.getOrNull(targetIndex)

                if (card != null && resolvedTargetCenter != null) {
                    if (newIndex > 0) {
                        delay(35)
                    }

                    animateFlyingCard(
                        card = card,
                        start = drawPileCenter!!,
                        end = resolvedTargetCenter,
                        hideKey = targetKey,
                        startScale = 0.88f,
                        endScale = 1f,
                        durationMs = if (newKeys.size <= 2) 180 else 110
                    )

                    val pendingWild = activity?.pendingAutoWildDraw
                    if (
                        pendingWild != null &&
                        pendingWild.rank == card.rank &&
                        pendingWild.file == card.file
                    ) {
                        selectedKey.value = null
                        selectedWildcardKey.value = targetKey
                        activity.pendingAutoWildDraw = null
                        previousHandSnapshot = currentSnapshot
                        return@LaunchedEffect
                    }

                    val pendingAutoPlay = activity?.pendingAutoPlayDraw
                    if (
                        pendingAutoPlay != null &&
                        pendingAutoPlay.rank == card.rank &&
                        pendingAutoPlay.file == card.file
                    ) {
                        val discardCenter = discardPileCenter
                        if (discardCenter != null) {
                            interactionLocked = true

                            animateFlyingCard(
                                card = card,
                                start = resolvedTargetCenter,
                                end = discardCenter,
                                hideKey = targetKey,
                                startScale = cardScaleForHand(game),
                                endScale = cardScaleForHand(game) * 0.96f,
                                durationMs = 220
                            )

                            val liveIndex = game.hand.indexOfFirst {
                                it.rank == card.rank && it.file == card.file
                            }

                            if (liveIndex != -1) {
                                game.hand.removeAt(liveIndex)
                            }

                            activity.playCard(card)
                            activity.pendingAutoPlayDraw = null
                            interactionLocked = false
                            previousHandSnapshot = buildCrazyHandInstanceKeys(game.hand)
                            return@LaunchedEffect
                        }
                    }
                }
            }
        }

        previousHandSnapshot = buildCrazyHandInstanceKeys(game.hand)
    }

    LaunchedEffect(
        game.participants
            .filter { !it.isMe }
            .joinToString("|") { "${it.id}:${it.cardCount}" }
    ) {
        val opponentsNow = game.participants.filter { !it.isMe }

        for (participant in opponentsNow) {
            val oldCount = previousOpponentCounts[participant.id] ?: participant.cardCount
            val newCount = participant.cardCount
            val delta = newCount - oldCount

            if (delta == 0) continue

            var pileCenter: Offset? = null
            var drawCenter: Offset? = null
            var discardCenter: Offset? = null

            repeat(10) {
                pileCenter = opponentPileCenters[participant.id]
                drawCenter = drawPileCenter
                discardCenter = discardPileCenter

                if (pileCenter != null && drawCenter != null && discardCenter != null) {
                    return@repeat
                }

                delay(16)
            }

            val resolvedPileCenter = pileCenter
            val resolvedDrawCenter = drawCenter
            val resolvedDiscardCenter = discardCenter

            if (
                resolvedPileCenter == null ||
                resolvedDrawCenter == null ||
                resolvedDiscardCenter == null
            ) {
                continue
            }

            val animCount = when {
                delta > 0 && activity?.headFx?.playerId == participant.id && !activity.headFx?.text.isNullOrBlank() -> {
                    activity.headFx?.text
                        ?.removePrefix("+")
                        ?.toIntOrNull()
                        ?.coerceIn(1, 8)
                        ?: abs(delta).coerceIn(1, 8)
                }
                abs(delta) <= 2 -> abs(delta)
                else -> 1
            }

            if (delta > 0) {
                repeat(animCount) { index ->
                    if (index > 0) delay(28)

                    animateOpponentFly(
                        card = null,
                        start = resolvedDrawCenter,
                        end = resolvedPileCenter,
                        backside = true,
                        durationMs = if (animCount <= 2) 150 else 85
                    )
                }
            } else {
                repeat(animCount) { index ->
                    if (index > 0) delay(28)

                    animateOpponentFly(
                        card = game.card,
                        start = resolvedPileCenter,
                        end = resolvedDiscardCenter,
                        backside = false,
                        durationMs = if (animCount <= 2) 150 else 85
                    )
                }
            }
        }

        previousOpponentCounts = opponentsNow.associate { it.id to it.cardCount }
    }

    LaunchedEffect(game.turn.id) {
        drewAndMustWaitThisTurn = false

        if (game.turn != me) {
            drawInFlight = false
            selectedKey.value = null
            selectedWildcardKey.value = null
            lastTappedCardKey = null
            lastTappedAtMs = 0L
        }
    }

    val boardSize = remember { mutableStateOf(IntSize.Zero) }

    Box(
        modifier = Modifier.fillMaxSize()
    ) {
        Image(
            painter = painterResource(id = R.drawable.crazybg),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop
        )

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .statusBarsPadding()
                .padding(horizontal = 12.dp, vertical = 8.dp)
                .zIndex(5f)
        ) {
            IconButton(
                onClick = { activity?.openRules() },
                modifier = Modifier.align(Alignment.CenterStart)
            ) {
                if (rulesIcon != null) {
                    Image(
                        bitmap = rulesIcon,
                        contentDescription = "Rules",
                        modifier = Modifier.size(36.dp),
                        contentScale = ContentScale.Fit
                    )
                }
            }

            IconButton(
                onClick = { activity?.openSettings() },
                modifier = Modifier.align(Alignment.CenterEnd)
            ) {
                if (settingsIcon != null) {
                    Image(
                        bitmap = settingsIcon,
                        contentDescription = "Settings",
                        modifier = Modifier.size(36.dp),
                        contentScale = ContentScale.Fit
                    )
                }
            }
        }



        Box(
            modifier = Modifier
                .fillMaxSize()
                .navigationBarsPadding()
                .statusBarsPadding()
                .onGloballyPositioned { coords ->
                    boardOriginRoot = coords.positionInRoot()
                }
                .onSizeChanged { boardSize.value = it }
        ) {
            val boardDensity = LocalDensity.current
            val boardWidthPx = boardSize.value.width.toFloat()
            val boardHeightPx = boardSize.value.height.toFloat()
            val boardWidthDp = with(boardDensity) { boardSize.value.width.toDp() }

            val fallbackBeamCenter = Offset(
                x = boardWidthPx * 0.50f,
                y = boardHeightPx * 0.43f
            )

            val beamCenter = turnPileGroupCenter ?: fallbackBeamCenter

            val oppCardWidth = 80.dp
            val oppCardHeight = 110.dp

            val joinedOrder = game.participants
            val mySeatIndex = joinedOrder.indexOfFirst { it.isMe }

            val opponents = if (mySeatIndex == -1) {
                joinedOrder.filter { !it.isMe }
            } else {
                (1 until joinedOrder.size).map { offset ->
                    joinedOrder[(mySeatIndex + offset) % joinedOrder.size]
                }
            }

            val seats = crazyOpponentSeats(opponents.size)
            val boardHeightDp = with(boardDensity) { boardSize.value.height.toDp() }

            val rawTarget = if (boardWidthPx <= 0f || boardHeightPx <= 0f) {
                null
            } else {
                turnAvatarCenters[game.turn.id]
            }

            LaunchedEffect(rawTarget, boardWidthPx, boardHeightPx, clockwise, activity?.turnConeForceAroundKey) {
                if (rawTarget == null) return@LaunchedEffect

                val targetAngle = normalizedAngle(
                    kotlin.math.atan2(
                        rawTarget.y - beamCenter.y,
                        rawTarget.x - beamCenter.x
                    )
                )

                if (!beamAngleInitialized) {
                    animatedBeamAngle.snapTo(targetAngle)
                    beamAngleInitialized = true
                    lastHandledForceAroundKey = activity?.turnConeForceAroundKey ?: 0
                    return@LaunchedEffect
                }

                val current = animatedBeamAngle.value
                val forceAroundKey = activity?.turnConeForceAroundKey ?: 0
                val forceAround = forceAroundKey != lastHandledForceAroundKey

                val delta = if (forceAround) {
                    lastHandledForceAroundKey = forceAroundKey
                    directionalAngleDelta(current, targetAngle, clockwise)
                } else {
                    shortestAngleDelta(current, targetAngle)
                }

                if (abs(delta) < 0.01f) {
                    animatedBeamAngle.snapTo(targetAngle)
                } else {
                    animatedBeamAngle.animateTo(
                        targetValue = current + delta,
                        animationSpec = tween(
                            durationMillis = if (forceAround) 260 else 150,
                            easing = FastOutSlowInEasing
                        )
                    )
                }
            }

            val beamRadius = if (rawTarget != null) {
                sqrt(
                    (rawTarget.x - beamCenter.x) * (rawTarget.x - beamCenter.x) +
                            (rawTarget.y - beamCenter.y) * (rawTarget.y - beamCenter.y)
                )
            } else {
                0f
            }

            val animatedTarget = if (rawTarget != null && beamRadius > 0f) {
                Offset(
                    x = beamCenter.x + cos(animatedBeamAngle.value) * beamRadius,
                    y = beamCenter.y + sin(animatedBeamAngle.value) * beamRadius
                )
            } else {
                null
            }

            if (
                animatedTarget != null &&
                boardWidthPx > 0f &&
                boardHeightPx > 0f
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .zIndex(1.5f)
                ) {
                    TurnConeOverlay(
                        modifier = Modifier.fillMaxSize(),
                        from = beamCenter,
                        to = animatedTarget,
                        isActive = true,
                        lightweight = true,
                        blurRadius = 0.dp
                    )
                }

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .zIndex(3.5f)
                ) {
                    DirectionArrowOverlay(
                        modifier = Modifier.fillMaxSize(),
                        center = beamCenter,
                        target = animatedTarget,
                        clockwise = clockwise
                    )
                }
            }

            opponents.forEachIndexed { index, participant ->
                val seat = seats[index]
                val cardX = boardWidthDp * seat.cardCx - oppCardWidth / 2
                val cardY = boardHeightDp * seat.cardCy - oppCardHeight / 2
                val avatarX = boardWidthDp * seat.avatarCx - avatarWidth / 2
                val avatarY = boardHeightDp * seat.avatarCy - avatarHeight / 2

                Box(
                    modifier = Modifier
                        .offset(x = cardX, y = cardY)
                        .onGloballyPositioned { coords ->
                            opponentPileCenters.putCenterIfChanged(participant.id, coords)
                        }
                        .zIndex(1f)
                ) {
                    Column(
                        verticalArrangement = Arrangement.spacedBy((-100).dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        (1..min(participant.cardCount, maxVisibleOpponentCards)).forEach {
                            RenderCardBack(lightweight = true)
                        }
                    }
                }

                Box(
                    modifier = Modifier
                        .offset(x = avatarX, y = avatarY)
                        .zIndex(6f)
                ) {
                    val bubbleText = activity?.lobbySpeechBubbles?.get(participant.id)

                    if (!bubbleText.isNullOrBlank()) {
                        LobbyAvatarSpeechBubble(
                            text = bubbleText,
                            flip = seat.bubbleFlip,
                            modifier = Modifier.offset(
                                x = if (seat.bubbleFlip) (-122).dp else 42.dp,
                                y = (-6).dp
                            )
                        )
                    }

                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        RenderLobbyAvatar(
                            avatarData = avatarFor(participant),
                            modifier = Modifier
                                .padding(top = 4.dp, bottom = 4.dp)
                                .size(width = avatarWidth, height = avatarHeight)
                                .onGloballyPositioned { coords ->
                                    avatarCenters.putCenterIfChanged(participant.id, coords)
                                    turnAvatarCenters.putOffsetIfChanged(participant.id, centerInBoard(coords))
                                }
                        )

                        Text(
                            participant.name,
                            modifier = Modifier.padding(bottom = 6.dp),
                            fontWeight = if (participant == game.turn) FontWeight.ExtraBold else FontWeight.Normal,
                            color = Color.White,
                            fontSize = 13.sp
                        )
                    }
                }
            }

            Row(
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(horizontal = 48.dp)
                    .offset(y = (-8).dp)
                    .onGloballyPositioned { coords ->
                        pileGroupCenter = updatedCenter(pileGroupCenter, coords)
                        turnPileGroupCenter = centerInBoard(coords)
                    }
                    .zIndex(2f),
                horizontalArrangement = Arrangement.spacedBy(-8.dp)
            ) {
                Box(
                    modifier = Modifier
                        .graphicsLayer {
                            scaleX = pileScale
                            scaleY = pileScale
                        }
                        .onGloballyPositioned { coords ->
                            drawPileCenter = updatedCenter(drawPileCenter, coords)
                        }
                ) {
                    RenderDrawPile(
                        shouldPulse = game.turn == me &&
                                label == null &&
                                !interactionLocked &&
                                !drawInFlight &&
                                game.hand.none { it.isCompatibleWith(game.card) },
                        onClick = {
                            if (interactionLocked) return@RenderDrawPile
                            if (drawInFlight) return@RenderDrawPile
                            if (game.turn != me) return@RenderDrawPile
                            drawInFlight = true
                            drewAndMustWaitThisTurn = true
                            activity?.drawCard()
                        }
                    )
                }

                Box(
                    modifier = Modifier
                        .graphicsLayer {
                            scaleX = pileScale
                            scaleY = pileScale
                        }
                        .onGloballyPositioned { coords ->
                            discardPileCenter = updatedCenter(discardPileCenter, coords)
                        }
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null
                        ) {
                            playCurrentlySelectedCard()
                        }
                ) {
                    RenderCard(
                        card = game.card,
                        lightweight = true
                    )
                }
            }
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = 8.dp, vertical = 62.dp)
                .navigationBarsPadding()
                .statusBarsPadding()
                .zIndex(4f),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (me != null) {
                Box {
                    val bubbleText = activity?.lobbySpeechBubbles?.get(me.id)

                    if (!bubbleText.isNullOrBlank()) {
                        LobbyAvatarSpeechBubble(
                            text = bubbleText,
                            modifier = Modifier.offset(x = 42.dp, y = (-6).dp)
                        )
                    }

                    RenderLobbyAvatar(
                        avatarData = avatarFor(me),
                        modifier = Modifier
                            .padding(top = 4.dp, bottom = 4.dp)
                            .size(width = avatarWidth, height = avatarHeight)
                            .onGloballyPositioned { coords ->
                                avatarCenters.putCenterIfChanged(me.id, coords)
                                turnAvatarCenters.putOffsetIfChanged(me.id, centerInBoard(coords))
                            }
                    )
                }

                Text(
                    me.name,
                    modifier = Modifier.padding(bottom = 10.dp, top = 2.dp),
                    fontWeight = if (me == game.turn) FontWeight.ExtraBold else FontWeight.Normal,
                    color = Color.White
                )
            }

            if (me != null) {

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 10.dp)
                        .height(132.dp)
                        .onSizeChanged { handAreaSize = it }
                ) {
                    val handDensity = LocalDensity.current
                    val cardCount = game.hand.size
                    val baseCardWidthPx = with(handDensity) { 80.dp.toPx() }
                    val baseCardHeightPx = with(handDensity) { 110.dp.toPx() }
                    val availableWidthPx = handAreaSize.width.toFloat().coerceAtLeast(1f)

                    val tileScale = when {
                        cardCount <= 6 -> 1.00f
                        cardCount <= 10 -> 0.94f
                        cardCount <= 15 -> 0.88f
                        else -> 0.82f
                    }

                    val tileCardWidthPx = baseCardWidthPx * tileScale
                    val tileCardHeightPx = baseCardHeightPx * tileScale
                    val preferredVisiblePx = tileCardWidthPx * 0.50f
                    val minimumVisiblePx = with(handDensity) { 30.dp.toPx() }

                    data class HandLayoutSlot(
                        val index: Int,
                        val xPx: Float,
                        val yPx: Float,
                        val scale: Float,
                        val tileMode: Boolean
                    )

                    fun buildTileLayout(rowCount: Int): List<HandLayoutSlot>? {
                        if (cardCount <= 0) return emptyList()

                        val maxRowCount = rowCount.coerceAtLeast(1)
                        val rowSizes = MutableList(maxRowCount) { cardCount / maxRowCount }
                        repeat(cardCount % maxRowCount) { rowSizes[it] += 1 }

                        val availableHeightPx = handAreaSize.height.toFloat().coerceAtLeast(1f)

                        val preferredRowStepPx = tileCardHeightPx * 0.48f
                        val maxRowStepPx = if (maxRowCount <= 1) {
                            0f
                        } else {
                            ((availableHeightPx - tileCardHeightPx) / (maxRowCount - 1))
                                .coerceAtLeast(10f)
                        }

                        val rowStepPx = if (maxRowCount <= 1) {
                            0f
                        } else {
                            preferredRowStepPx.coerceAtMost(maxRowStepPx)
                        }

                        val slots = mutableListOf<HandLayoutSlot>()
                        var globalIndex = 0

                        for (row in 0 until maxRowCount) {
                            val countInRow = rowSizes[row]
                            if (countInRow <= 0) continue

                            val rawGap = if (countInRow == 1) {
                                0f
                            } else {
                                ((availableWidthPx - tileCardWidthPx) / (countInRow - 1)).coerceAtLeast(0f)
                            }

                            if (countInRow > 1 && rawGap < minimumVisiblePx) {
                                return null
                            }

                            val gap = if (countInRow == 1) {
                                0f
                            } else {
                                rawGap.coerceAtMost(preferredVisiblePx)
                            }

                            val rowWidth = tileCardWidthPx + gap * (countInRow - 1)
                            val startX = ((availableWidthPx - rowWidth) / 2f).coerceAtLeast(0f)
                            val y = row * rowStepPx

                            for (i in 0 until countInRow) {
                                slots.add(
                                    HandLayoutSlot(
                                        index = globalIndex,
                                        xPx = startX + gap * i,
                                        yPx = y,
                                        scale = tileScale,
                                        tileMode = true
                                    )
                                )
                                globalIndex += 1
                            }
                        }

                        return slots
                    }

                    val tileSlots = buildTileLayout(1)
                        ?: buildTileLayout(2)
                        ?: buildTileLayout(3)

                    if (tileSlots != null && tileSlots.isNotEmpty()) {
                        for (slot in tileSlots) {
                            val index = slot.index
                            val card = game.hand[index]
                            val cardKey = handKeys[index]
                            val isPlayable = handPlayable[index]

                            val selectedYOffsetPx = if (selectedKey.value == cardKey) {
                                with(handDensity) { (-14).dp.toPx() }
                            } else {
                                0f
                            }

                            val xDp = with(handDensity) { slot.xPx.toDp() }
                            val yDp = with(handDensity) { (slot.yPx + selectedYOffsetPx).toDp() }

                            Box(
                                modifier = Modifier
                                    .offset(x = xDp, y = yDp)
                                    .graphicsLayer {
                                        scaleX = slot.scale
                                        scaleY = slot.scale
                                        transformOrigin = TransformOrigin(0f, 0f)
                                    }
                                    .onGloballyPositioned { coords ->
                                        handCardCenters.putCenterIfChanged(cardKey, coords)
                                    }
                                    .alpha(
                                        if (hiddenHandKey == cardKey || cardKey in incomingHandKeys) 0f else 1f
                                    )
                                    .zIndex(
                                        when {
                                            selectedKey.value == cardKey -> 1000f
                                            else -> index.toFloat()
                                        }
                                    )
                                    .clickable(
                                        interactionSource = remember { MutableInteractionSource() },
                                        indication = null
                                    ) {
                                        handleCardTap(index, cardKey, card, isPlayable)
                                    }
                            ) {
                                val faceModifier = Modifier.drawWithContent {
                                    drawContent()

                                    if (!isPlayable && game.turn == me) {
                                        drawRoundRect(
                                            color = Color.Black.copy(alpha = 0.42f),
                                            cornerRadius = CornerRadius(4.dp.toPx())
                                        )
                                    }
                                }

                                RenderCard(
                                    card,
                                    modifier = faceModifier,
                                    lightweight = true
                                )
                            }
                        }
                    } else {
                        val cardScale = cardScaleForHand(game)

                        val scaledCardWidthPx = baseCardWidthPx * cardScale
                        val blockedGapPx = scaledCardWidthPx * 0.22f
                        val playableGapPx = scaledCardWidthPx * 0.34f

                        val rawGaps = mutableListOf<Float>()
                        for (i in 0 until (cardCount - 1)) {
                            val currentPlayable = handPlayable[i]
                            val nextPlayable = handPlayable[i + 1]
                            rawGaps.add(if (currentPlayable || nextPlayable) playableGapPx else blockedGapPx)
                        }

                        val rawTotalWidth = if (cardCount <= 0) {
                            0f
                        } else {
                            scaledCardWidthPx + rawGaps.sum()
                        }

                        val compressedGaps: List<Float> =
                            if (rawTotalWidth > availableWidthPx && rawGaps.isNotEmpty()) {
                                val availableForGaps = (availableWidthPx - scaledCardWidthPx).coerceAtLeast(0f)
                                val rawGapTotal = rawGaps.sum().coerceAtLeast(1f)
                                val gapScale = availableForGaps / rawGapTotal
                                rawGaps.map { it * gapScale }
                            } else {
                                rawGaps
                            }

                        val totalWidth = if (cardCount <= 0) {
                            0f
                        } else {
                            scaledCardWidthPx + compressedGaps.sum()
                        }

                        val startX = ((availableWidthPx - totalWidth) / 2f).coerceAtLeast(0f)

                        var runningX = startX

                        for (index in game.hand.indices) {
                            val card = game.hand[index]
                            val cardKey = handKeys[index]
                            val isPlayable = handPlayable[index]

                            val targetOffsetY = when {
                                selectedKey.value == cardKey -> (-16).dp
                                else -> 0.dp
                            }

                            val xDp = with(handDensity) { runningX.toDp() }

                            Box(
                                modifier = Modifier
                                    .offset(x = xDp, y = targetOffsetY)
                                    .graphicsLayer {
                                        scaleX = cardScale
                                        scaleY = cardScale
                                        transformOrigin = TransformOrigin(0f, 0f)
                                    }
                                    .onGloballyPositioned { coords ->
                                        handCardCenters.putCenterIfChanged(cardKey, coords)
                                    }
                                    .alpha(
                                        if (hiddenHandKey == cardKey || cardKey in incomingHandKeys) 0f else 1f
                                    )
                                    .zIndex(
                                        when {
                                            selectedKey.value == cardKey -> 100f
                                            isPlayable -> 50f + index.toFloat()
                                            else -> index.toFloat()
                                        }
                                    )
                                    .clickable(
                                        interactionSource = remember { MutableInteractionSource() },
                                        indication = null
                                    ) {
                                        handleCardTap(index, cardKey, card, isPlayable)
                                    }
                            ) {
                                RenderCard(
                                    card,
                                    modifier = Modifier,
                                    lightweight = true
                                )
                            }

                            if (index < compressedGaps.size) {
                                runningX += compressedGaps[index]
                            }
                        }
                    }
                    if (selectedWildcardIndex in game.hand.indices) {
                        val wildcardKey = selectedWildcardKey.value ?: ""
                        val wildcardBaseCard = game.hand[selectedWildcardIndex]

                        AlertDialog(
                            onDismissRequest = {
                                selectedWildcardKey.value = null
                                selectedKey.value = null
                            },
                            title = {
                                Text(text = "Choose card")
                            },
                            text = {
                                Column(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    for (x in 0..1) {
                                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            for (i in 0..1) {
                                                val newCard = CrazyCard(x * 2 + i, wildcardBaseCard.file)

                                                RenderCard(
                                                    newCard,
                                                    modifier = Modifier.clickable {
                                                        val start = handCardCenters[wildcardKey]
                                                        val end = discardPileCenter

                                                        if (start == null || end == null) {
                                                            if (selectedWildcardIndex in game.hand.indices) {
                                                                game.hand.removeAt(selectedWildcardIndex)
                                                            }
                                                            activity?.playCard(newCard)
                                                            selectedWildcardKey.value = null
                                                            selectedKey.value = null
                                                            return@clickable
                                                        }

                                                        scope.launch {
                                                            interactionLocked = true
                                                            selectedWildcardKey.value = null

                                                            animateFlyingCard(
                                                                card = newCard,
                                                                start = start,
                                                                end = end,
                                                                hideKey = wildcardKey,
                                                                startScale = cardScaleForHand(game),
                                                                endScale = cardScaleForHand(game) * 0.96f,
                                                                durationMs = 240
                                                            )

                                                            if (selectedWildcardIndex in game.hand.indices) {
                                                                game.hand.removeAt(selectedWildcardIndex)
                                                            }
                                                            activity?.playCard(newCard)
                                                            selectedKey.value = null
                                                            interactionLocked = false
                                                        }
                                                    }
                                                )
                                            }
                                        }
                                    }
                                }
                            },
                            confirmButton = {
                                TextButton(onClick = {
                                    selectedWildcardKey.value = null
                                    selectedKey.value = null
                                }) {
                                    Text("Cancel")
                                }
                            },
                        )
                    }
                }
            }
        }

        if (imeVisible) {
            ChatMessagesList(
                messages = messages,
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(0x77000000))
                    .imePadding()
                    .navigationBarsPadding()
                    .statusBarsPadding()
                    .padding(bottom = 60.dp, start = 8.dp, end = 8.dp, top = 8.dp)
                    .clickable(
                        indication = null,
                        interactionSource = remember { MutableInteractionSource() }
                    ) {
                        keyboardController?.hide()
                    }
                    .zIndex(10f)
            )
        }

        BasicTextField(
            value = textInput.value,
            onValueChange = { textInput.value = it },
            textStyle = TextStyle(fontSize = 16.sp, color = Color.White),
            cursorBrush = SolidColor(Color.White),
            keyboardOptions = KeyboardOptions.Default.copy(
                imeAction = ImeAction.Send
            ),
            keyboardActions = KeyboardActions(
                onSend = {
                    activity?.sendMessage(textInput.value)
                    textInput.value = ""
                }
            ),
            modifier = Modifier
                .padding(bottom = 10.dp, top = 30.dp, start = 15.dp, end = 15.dp)
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .statusBarsPadding()
                .imePadding()
                .background(
                    Color(0x55000000),
                    shape = RoundedCornerShape(16.dp)
                )
                .padding(vertical = 10.dp, horizontal = 15.dp)
                .fillMaxWidth()
                .zIndex(11f),
            decorationBox = { innerTextField ->
                if (textInput.value.isEmpty()) {
                    Text(
                        text = if (unread == 0) "Chat" else "Chat ($unread)",
                        style = TextStyle(fontSize = 16.sp, color = Color.White)
                    )
                }
                innerTextField()
            },
        )

        if (label != null) {
            Text(
                label,
                modifier = Modifier
                    .align(Alignment.Center)
                    .navigationBarsPadding()
                    .statusBarsPadding()
                    .background(Color(0x88000000))
                    .padding(10.dp)
                    .zIndex(12f),
                fontSize = 20.sp,
                color = Color.White
            )
        }

        activity?.headFx?.let { fx ->
            avatarCenters[fx.playerId]?.let { center ->
                androidx.compose.runtime.key(fx.key) {
                    if (fx.skip) {
                        SkipHeadEffect(center)
                    } else if (!fx.text.isNullOrBlank()) {
                        PenaltyHeadEffect(center, fx.text)
                    }
                }
            }
        }

        activity?.reverseFx?.let { fx ->
            androidx.compose.runtime.key(fx.key) {
                ReverseCenterEffect(fx.clockwise)
            }
        }

        if (flyingCard != null || flyingBackside) {
            val cardWidthPx = with(density) { 80.dp.toPx() }
            val cardHeightPx = with(density) { 110.dp.toPx() }

            val flyingModifier = Modifier
                .offset {
                    val c = flyingCardOffset.value
                    IntOffset(
                        x = (c.x - cardWidthPx / 2f).roundToInt(),
                        y = (c.y - cardHeightPx / 2f).roundToInt()
                    )
                }
                .graphicsLayer {
                    val s = flyingCardScaleAnim.value
                    scaleX = s
                    scaleY = s
                }
                .zIndex(20f)

            if (flyingBackside) {
                RenderCardBack(
                    modifier = flyingModifier,
                    lightweight = true
                )
            } else {
                RenderCard(
                    card = flyingCard,
                    modifier = flyingModifier,
                    lightweight = true
                )
            }
        }
    }
}

@Composable
fun ChatMessagesList(
    messages: SnapshotStateList<CrazyMessage>,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier,
        reverseLayout = true,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        items(messages) { item ->
            if (item.sender.isMe) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.End
                ) {
                    Text(
                        "Me",
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 10.sp,
                        modifier = Modifier.padding(end = 6.dp, bottom = 2.dp)
                    )
                    Text(
                        item.message,
                        modifier = Modifier
                            .background(Color(0xFF1E88E5), shape = RoundedCornerShape(16.dp))
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                        color = Color.White,
                        fontSize = 16.sp
                    )
                }
            } else {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.Start
                ) {
                    Text(
                        item.sender.name,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 10.sp,
                        modifier = Modifier.padding(start = 6.dp, bottom = 2.dp)
                    )
                    Text(
                        item.message,
                        modifier = Modifier
                            .background(Color.White, shape = RoundedCornerShape(16.dp))
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                        color = Color.Black,
                        fontSize = 16.sp
                    )
                }
            }
        }
    }
}

@Composable
fun WaitingRoomChatPane(
    messages: SnapshotStateList<CrazyMessage>,
    onSend: (String) -> Unit,
    onClose: () -> Unit
) {
    val textInput = remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.scrollToItem(0)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0x66000000))
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) {
                onClose()
            }
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .navigationBarsPadding()
                .statusBarsPadding()
                .imePadding()
                .padding(horizontal = 12.dp, vertical = 12.dp)
        ) {
            Spacer(modifier = Modifier.height(44.dp))

            ChatMessagesList(
                messages = messages,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .clickable(
                        indication = null,
                        interactionSource = remember { MutableInteractionSource() }
                    ) {
                        onClose()
                    }
            )

            Spacer(modifier = Modifier.height(8.dp))

            BasicTextField(
                value = textInput.value,
                onValueChange = { textInput.value = it },
                textStyle = TextStyle(fontSize = 16.sp, color = Color.White),
                cursorBrush = SolidColor(Color.White),
                keyboardOptions = KeyboardOptions.Default.copy(
                    imeAction = ImeAction.Send
                ),
                keyboardActions = KeyboardActions(
                    onSend = {
                        val msg = textInput.value.trim()
                        if (msg.isNotEmpty()) {
                            onSend(msg)
                            textInput.value = ""
                        }
                    }
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0x66000000), shape = RoundedCornerShape(16.dp))
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                decorationBox = { innerTextField ->
                    if (textInput.value.isEmpty()) {
                        Text(
                            text = "Chat",
                            style = TextStyle(
                                fontSize = 16.sp,
                                color = Color.White.copy(alpha = 0.85f)
                            )
                        )
                    }
                    innerTextField()
                }
            )
        }
    }
}

@Composable
fun LobbyAvatarSpeechBubble(
    text: String,
    modifier: Modifier = Modifier,
    flip: Boolean = false
) {
    Box(
        modifier = modifier
            .zIndex(2f)
            .graphicsLayer { scaleX = if (flip) -1f else 1f }
    ) {
        Canvas(
            modifier = Modifier.matchParentSize()
        ) {
            val tailTipX = 0f
            val tailTipY = size.height * 0.72f

            val bubbleLeft = 18.dp.toPx()

            val attachTopX = bubbleLeft + 6.dp.toPx()
            val attachTopY = size.height * 0.60f

            val attachBottomX = bubbleLeft + 6.dp.toPx()
            val attachBottomY = size.height * 0.86f

            val path = Path().apply {
                moveTo(attachTopX, attachTopY)
                lineTo(tailTipX, tailTipY)
                lineTo(attachBottomX, attachBottomY)
                close()
            }
            drawPath(path, color = Color(0xFF1E88E5))
        }

        Box(
            modifier = Modifier
                .padding(start = 16.dp)
                .widthIn(max = 180.dp)
                .background(Color(0xFF1E88E5), shape = RoundedCornerShape(9.dp))
                .padding(horizontal = 12.dp, vertical = 9.dp)
                .graphicsLayer { scaleX = if (flip) -1f else 1f }
        ) {
            Text(
                text = text,
                color = Color.White,
                fontSize = 12.sp,
                maxLines = 2
            )
        }
    }
}

@Composable
fun SkipHeadEffect(center: Offset) {
    val density = LocalDensity.current
    val scale = remember { Animatable(1.2f) }
    val alpha = remember { Animatable(1f) }

    LaunchedEffect(Unit) {
        launch {
            scale.animateTo(
                targetValue = 1f,
                animationSpec = tween(600, easing = FastOutSlowInEasing)
            )
        }
        launch {
            alpha.animateTo(
                targetValue = 0f,
                animationSpec = tween(600)
            )
        }
    }

    Image(
        painter = painterResource(id = R.drawable.skip),
        contentDescription = null,
        modifier = Modifier
            .offset {
                IntOffset(
                    x = (center.x - with(density) { 24.dp.toPx() }).roundToInt(),
                    y = (center.y - with(density) { 20.dp.toPx() }).roundToInt()
                )
            }
            .size(48.dp)
            .graphicsLayer {
                scaleX = scale.value
                scaleY = scale.value
                this.alpha = alpha.value
            }
            .zIndex(30f),
        contentScale = ContentScale.Fit
    )
}

@Composable
fun PenaltyHeadEffect(center: Offset, text: String) {
    val density = LocalDensity.current
    val rise = remember { Animatable(0f) }
    val alpha = remember { Animatable(1f) }

    LaunchedEffect(Unit) {
        launch {
            rise.animateTo(
                targetValue = with(density) { (-34).dp.toPx() },
                animationSpec = tween(760, easing = FastOutSlowInEasing)
            )
        }
        launch {
            alpha.animateTo(
                targetValue = 0f,
                animationSpec = tween(980)
            )
        }
    }

    Text(
        text = text,
        modifier = Modifier
            .offset {
                IntOffset(
                    x = (center.x - with(density) { 20.dp.toPx() }).roundToInt(),
                    y = (center.y - with(density) { 52.dp.toPx() } + rise.value).roundToInt()
                )
            }
            .graphicsLayer {
                this.alpha = alpha.value
            }
            .zIndex(30f),
        color = Color.White,
        fontSize = 30.sp,
        fontWeight = FontWeight.ExtraBold,
        style = TextStyle(
            shadow = Shadow(
                color = Color.Black,
                offset = Offset(2f, 3f),
                blurRadius = 2f
            )
        )
    )
}

@Composable
fun ReverseCenterEffect(clockwise: Boolean) {
    val scale = remember { Animatable(1f) }
    val alpha = remember { Animatable(1f) }
    val rotation = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        launch {
            scale.animateTo(
                targetValue = 2.4f,
                animationSpec = tween(700, easing = FastOutSlowInEasing)
            )
        }
        launch {
            alpha.animateTo(
                targetValue = 0f,
                animationSpec = tween(780)
            )
        }
        launch {
            rotation.animateTo(
                targetValue = if (clockwise) 360f else -360f,
                animationSpec = tween(700, easing = FastOutSlowInEasing)
            )
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .zIndex(30f),
        contentAlignment = Alignment.Center
    ) {
        Image(
            painter = painterResource(id = R.drawable.reverse),
            contentDescription = null,
            modifier = Modifier
                .size(132.dp)
                .graphicsLayer {
                    scaleX = scale.value
                    scaleY = scale.value
                    rotationZ = rotation.value
                    this.alpha = alpha.value
                },
            contentScale = ContentScale.Fit
        )
    }
}

@Composable
fun RenderWaiting(participants: SnapshotStateList<CrazyParticipant>, activity: Crazy8Activity?) {
    val me = participants.find { it.isMe }

    val burgerIcon = if (activity != null) {
        rememberAssetBitmap(activity, "global/burger.png")
    } else {
        null
    }

    val rulesIcon = if (activity != null) {
        rememberAssetBitmap(activity, "global/chat.png")
    } else {
        null
    }

    Box(
        modifier = Modifier.fillMaxSize()
    ) {
        Image(
            painter = painterResource(id = R.drawable.crazybg),
            contentDescription = null,
            modifier = Modifier
                .fillMaxSize()
                .blur(if (activity?.showBurgerMenu == true) 8.dp else 0.dp),
            contentScale = ContentScale.Crop
        )

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxSize()
                .blur(if (activity?.showBurgerMenu == true) 8.dp else 0.dp)
                .navigationBarsPadding()
                .statusBarsPadding()
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp)
            ) {
                IconButton(
                    onClick = {
                        activity?.showLobbyChat = true
                    },
                    modifier = Modifier.align(Alignment.CenterStart)
                ) {
                    if (rulesIcon != null) {
                        Image(
                            bitmap = rulesIcon,
                            contentDescription = "Rules",
                            modifier = Modifier.size(36.dp),
                            contentScale = ContentScale.Fit
                        )
                    }
                }

                IconButton(
                    onClick = {
                        activity?.let {
                            it.showBurgerMenu = !it.showBurgerMenu
                        }
                    },
                    modifier = Modifier.align(Alignment.CenterEnd)
                ) {
                    if (burgerIcon != null) {
                        Image(
                            bitmap = burgerIcon,
                            contentDescription = "Menu",
                            modifier = Modifier.size(36.dp),
                            contentScale = ContentScale.Fit
                        )
                    }
                }
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.Center
            ) {
                for (participant in participants) {
                    ElevatedCard(
                        modifier = Modifier
                            .padding(horizontal = 16.dp, vertical = 5.dp),
                        shape = RoundedCornerShape(32.dp),
                        elevation = CardDefaults.cardElevation(
                            defaultElevation = 6.dp
                        ),
                    ) {
                        Box(
                            modifier = Modifier
                                .padding(horizontal = 4.dp, vertical = 3.dp)
                                .fillMaxWidth()
                        ) {
                            RenderLobbyAvatar(
                                avatarData = participant.avatar,
                                modifier = Modifier
                                    .align(Alignment.CenterStart)
                                    .size(width = 72.dp, height = 52.dp)
                            )

                            val bubbleText = activity?.lobbySpeechBubbles?.get(participant.id)
                            if (!bubbleText.isNullOrBlank()) {
                                LobbyAvatarSpeechBubble(
                                    text = bubbleText,
                                    modifier = Modifier
                                        .align(Alignment.CenterStart)
                                        .offset(x = 42.dp, y = (-6).dp)
                                )
                            }

                            Text(
                                participant.name,
                                modifier = Modifier.align(Alignment.Center),
                                fontWeight = FontWeight.ExtraBold,
                                fontSize = 15.sp
                            )

                            Icon(
                                imageVector = Icons.Rounded.CheckCircle,
                                contentDescription = "Check",
                                modifier = Modifier
                                    .align(Alignment.CenterEnd)
                                    .alpha(if (participant.ready) 1.0f else 0.0f),
                                tint = Color(0xFF06402B)
                            )

                            Text(
                                "—",
                                modifier = Modifier
                                    .align(Alignment.CenterEnd)
                                    .alpha(if (participant.ready) 0.0f else 1.0f)
                                    .padding(horizontal = 5.dp),
                                color = Color.DarkGray,
                                fontWeight = FontWeight.ExtraBold,
                                fontSize = 25.sp
                            )
                        }
                    }
                }
            }

            val playerCountValid = participants.size in 3..6
            val everyoneReady = participants.isNotEmpty() && participants.all { it.ready }

            val statusText = when {
                me?.ready == true && !playerCountValid ->
                    "3-6 players are required to start"
                me?.ready == true && playerCountValid && !everyoneReady ->
                    "We'll start once everyone is READY"
                me?.ready != true ->
                    "Tap \"READY\" to start the match"
                else -> null
            }

            if (statusText != null) {
                Text(
                    statusText,
                    color = Color.White,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp)
                )
            } else {
                Spacer(modifier = Modifier.height(28.dp))
            }

            Button(
                onClick = {
                    me!!.ready = !me.ready
                    activity!!.setReady(me.ready)
                },
                modifier = Modifier
                    .padding(bottom = 16.dp)
                    .shadow(
                        elevation = 10.dp,
                        shape = RoundedCornerShape(6.dp),
                        ambientColor = Color.Black.copy(alpha = 0.24f),
                        spotColor = Color.Black.copy(alpha = 0.24f)
                    ),
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (me?.ready == true) Color(0xFFFF2D2D) else Color(0xFF247E2A),
                    contentColor = Color.White
                )
            ) {
                Text(
                    text = if (me?.ready == true) "CANCEL" else "READY",
                    color = Color.White,
                    fontWeight = FontWeight.ExtraBold
                )
            }
        }
        if (activity?.showLobbyChat == true) {
            WaitingRoomChatPane(
                messages = activity.messages,
                onSend = { msg -> activity.sendMessage(msg) },
                onClose = { activity.showLobbyChat = false }
            )
        }

        if (activity?.showBurgerMenu == true) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clickable(
                        indication = null,
                        interactionSource = remember { MutableInteractionSource() }
                    ) {
                        activity.showBurgerMenu = false
                    }
            ) {
                Column(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = 56.dp, end = 12.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(Color(0xEEFFFFFF))
                        .border(1.dp, Color(0x22000000), RoundedCornerShape(10.dp))
                        .clickable(
                            indication = null,
                            interactionSource = remember { MutableInteractionSource() }
                        ) { }
                        .padding(vertical = 6.dp)
                        .widthIn(min = 120.dp)
                        .wrapContentWidth()
                ) {
                    Text(
                        "Settings",
                        modifier = Modifier
                            .clickable {
                                activity.showBurgerMenu = false
                                activity.openSettings()
                            }
                            .padding(horizontal = 14.dp, vertical = 10.dp),
                        color = Color.Black,
                        fontWeight = FontWeight.SemiBold
                    )

                    Text(
                        "Help",
                        modifier = Modifier
                            .clickable {
                                activity.showBurgerMenu = false
                                activity.openRules()
                            }
                            .padding(horizontal = 14.dp, vertical = 10.dp),
                        color = Color.Black,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        }
    }
}

private fun extractCrazy8DisplayName(data: String): String {
    val legacy = decodeCrazy8PackedAvatarString(data)
    return Regex("""(?:^|`)n,([^`]+)""").find(legacy)?.groupValues?.getOrNull(1) ?: "Player"
}

private fun avatarStringForLobby(raw: String): String {
    val legacy = decodeCrazy8PackedAvatarString(raw)
    return legacyCrazy8ToOpponentString(legacy)
}

private fun legacyCrazy8ToOpponentString(data: String): String {
    val values = mutableMapOf<String, String>()

    for (part in data.split('`')) {
        val idx = part.indexOf(',')
        if (idx == -1) continue
        val key = part.substring(0, idx)
        val value = part.substring(idx + 1)
        values[key] = value
    }

    fun v(key: String, default: String): String {
        return values[key] ?: default
    }

    return "body,${v("b", "4")}" +
            "|eyes,${v("e", "0")}" +
            "|mouth,${v("m", "2")}" +
            "|acc,${v("a", "0")}" +
            "|wins,${v("w", "0")}" +
            "|bg_color,${v("bg", "0.0,0.0,0.0")}" +
            "|body_color,${v("bc", "0.0,0.0,0.0")}" +
            "|glasses,${v("g", "0")}" +
            "|stache,${v("s", "0")}" +
            "|backdrop,${v("d", "0")}" +
            "|hair,${v("h", "3")}" +
            "|clothes,${v("c", "2")}" +
            "|hair_color,${v("hc", "0.0,0.0,0.0")}" +
            "|clothes_color,${v("cc", "0.290639,0.935341,0.083265")}" +
            "|n,${v("n", "")}"
}

private const val CRAZY8_PACKED_ALPHABET =
    "0123456789QWERTYUIOPASDFGHJKLZXCVBNM" +
            "qwertyuiopasdfghjklzxcvbnm" +
            "!@#$%^*()-_=+[{]};.<>/?"

private fun crazy8CharToInt(char: String): Int {
    if (char.isEmpty()) return 0
    val idx = CRAZY8_PACKED_ALPHABET.indexOf(char.take(1))
    return if (idx >= 0) idx else 0
}

private fun crazy8CharToFloat(twoChars: String): Float {
    if (twoChars.length < 2) return 0f

    val n = CRAZY8_PACKED_ALPHABET.length
    val first = CRAZY8_PACKED_ALPHABET.indexOf(twoChars.substring(0, 1)).coerceAtLeast(0)
    val second = CRAZY8_PACKED_ALPHABET.indexOf(twoChars.substring(1, 2)).coerceAtLeast(0)

    val numerator = second + first * n
    val denominator = (n * n) - 1

    return numerator.toFloat() / denominator.toFloat()
}

private fun decodeCrazy8PackedAvatarString(data: String): String {
    if (data.contains("`n,")) return data

    if (data.length < 34) {
        return "b,4`e,0`m,2`a,0`w,0`bg,0.0,0.0,0.0`bc,0.0,0.0,0.0`g,0`s,0`d,0`h,3`c,2`hc,0.0,0.0,0.0`cc,0.290639,0.935341,0.083265`n,$data"
    }

    val token = data.substring(0, 34)
    val name = data.substring(34)

    val b = crazy8CharToInt(token.substring(0, 1))
    val e = crazy8CharToInt(token.substring(1, 2))
    val m = crazy8CharToInt(token.substring(2, 3))
    val a = crazy8CharToInt(token.substring(3, 4))
    val w = crazy8CharToInt(token.substring(4, 5))

    val bgR = crazy8CharToFloat(token.substring(5, 7))
    val bgG = crazy8CharToFloat(token.substring(7, 9))
    val bgB = crazy8CharToFloat(token.substring(9, 11))

    val bcR = crazy8CharToFloat(token.substring(11, 13))
    val bcG = crazy8CharToFloat(token.substring(13, 15))
    val bcB = crazy8CharToFloat(token.substring(15, 17))

    val g = crazy8CharToInt(token.substring(17, 18))
    val s = crazy8CharToInt(token.substring(18, 19))
    val d = crazy8CharToInt(token.substring(19, 20))
    val h = crazy8CharToInt(token.substring(20, 21))
    val c = crazy8CharToInt(token.substring(21, 22))

    val hcR = crazy8CharToFloat(token.substring(22, 24))
    val hcG = crazy8CharToFloat(token.substring(24, 26))
    val hcB = crazy8CharToFloat(token.substring(26, 28))

    val ccR = crazy8CharToFloat(token.substring(28, 30))
    val ccG = crazy8CharToFloat(token.substring(30, 32))
    val ccB = crazy8CharToFloat(token.substring(32, 34))

    return buildString {
        append("b,$b")
        append("`e,$e")
        append("`m,$m")
        append("`a,$a")
        append("`w,$w")
        append("`bg,$bgR,$bgG,$bgB")
        append("`bc,$bcR,$bcG,$bcB")
        append("`g,$g")
        append("`s,$s")
        append("`d,$d")
        append("`h,$h")
        append("`c,$c")
        append("`hc,$hcR,$hcG,$hcB")
        append("`cc,$ccR,$ccG,$ccB")
        append("`n,$name")
    }
}

private fun legacyAvatarStringForCrazy8(playerName: String): String {
    val modern = AvatarView.buildAvatarString()
    val values = mutableMapOf<String, String>()

    for (part in modern.split("|")) {
        val idx = part.indexOf(',')
        if (idx == -1) continue
        val key = part.substring(0, idx)
        val value = part.substring(idx + 1)
        values[key] = value
    }

    fun v(key: String, default: String): String {
        return values[key] ?: default
    }

    fun color3(key: String, default: String): String {
        val raw = values[key] ?: return default
        val parts = raw.split(",")
        if (parts.size < 3) return default
        return "${parts[0]},${parts[1]},${parts[2]}"
    }

    return "b,${v("body", "4")}`" +
            "e,${v("eyes", "0")}`" +
            "m,${v("mouth", "2")}`" +
            "a,${v("acc", "0")}`" +
            "w,${v("wins", "0")}`" +
            "bg,${color3("bg_color", "0.0,0.0,0.0")}`" +
            "bc,${color3("body_color", "0.0,0.0,0.0")}`" +
            "g,${v("glasses", "0")}`" +
            "s,${v("stache", "0")}`" +
            "d,${v("backdrop", "0")}`" +
            "h,${v("hair", "3")}`" +
            "c,${v("clothes", "2")}`" +
            "hc,${color3("hair_color", "0.000000,0.000000,0.000000")}`" +
            "cc,${color3("clothes_color", "0.290639,0.935341,0.083265")}`" +
            "n,$playerName"
}
