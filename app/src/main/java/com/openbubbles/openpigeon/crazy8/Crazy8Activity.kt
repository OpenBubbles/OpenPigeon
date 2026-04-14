package com.openbubbles.openpigeon.crazy8

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.draw.drawWithContent
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
import com.openbubbles.openpigeon.godot.GameSessionIPC
import com.playerio.Callback
import com.playerio.Client
import com.playerio.Connection
import com.playerio.DisconnectListener
import com.playerio.Message
import com.playerio.MessageListener
import com.playerio.PlayerIO
import com.playerio.PlayerIOError
import kotlin.concurrent.thread
import kotlin.math.min
import androidx.core.graphics.drawable.toDrawable
import com.google.android.vending.licensing.util.Base64
import java.util.Timer
import java.util.TimerTask
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

class CrazyParticipant(
    val name: String,
    val id: Int,
    val isMe: Boolean,
    ready: Boolean,
    val avatar: String = "",
) {
    var ready by mutableStateOf(ready)
    var cardCount by mutableIntStateOf(0)
}

data class CrazyMessage(val message: String, val sender: CrazyParticipant)

data class CrazyCard(val rank: Int, val file: Int) {
    companion object {
        fun parse(data: String): CrazyCard {
            val parts = data.split(",")
            return CrazyCard(parts[0].toInt(), parts[1].toInt())
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

class CrazyGame(val participants: List<CrazyParticipant>, turn: CrazyParticipant, card: CrazyCard, val hand: SnapshotStateList<CrazyCard>) {
    var turn by mutableStateOf(turn)
    var card by mutableStateOf(card)
}


class Crazy8Activity : ComponentActivity() {
    var gameSessionIPC: GameSessionIPC? = null
    lateinit var sessionId: String
    var baseGame = Crazy8Game()
    var currentConnection: Connection? = null
    var name by mutableStateOf<String?>(null)

    lateinit var settingsSheet: SettingsSheet
    private var settingsConfigured = false
    private var settingsNameEdit: android.widget.EditText? = null
    private var settingsAvatarView: AvatarView? = null

    fun getPrefs(): SharedPreferences {
        return getSharedPreferences("crazy_prefs", Context.MODE_PRIVATE)
    }

    private fun refreshSettingsSheetValues() {
        settingsNameEdit?.let { edit ->
            val current = name ?: getPrefs().getString("name", "") ?: ""
            if (edit.text?.toString() != current) {
                edit.setText(current)
                edit.setSelection(edit.text?.length ?: 0)
            }
        }

        settingsAvatarView?.apply {
            try {
                applyFromAvatarData()
            } catch (e: Exception) {
                Log.e("Crazy8", "Failed to refresh settings avatar", e)
            }
        }
    }

    private fun setupSettingsSheet() {
        if (settingsConfigured) return
        settingsConfigured = true

        val container = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            layoutParams = android.widget.LinearLayout.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setPadding(0, 8, 0, 8)
        }

        val avatar = AvatarView(this).apply {
            layoutParams = android.widget.LinearLayout.LayoutParams(150, 110).also {
                it.marginEnd = 24
            }
            setBackgroundColor(android.graphics.Color.WHITE)
            alpha = 1f

            try {
                applyFromAvatarData()
            } catch (e: Exception) {
                Log.e("Crazy8", "Failed to apply avatar preview", e)
            }
        }

        val edit = androidx.appcompat.widget.AppCompatEditText(this).apply {
            layoutParams = android.widget.LinearLayout.LayoutParams(
                0,
                android.view.ViewGroup.LayoutParams.WRAP_CONTENT,
                1f
            )
            hint = "Player name"
            setSingleLine(true)
            setText(name ?: getPrefs().getString("name", "") ?: "")
        }

        edit.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}

            override fun afterTextChanged(s: android.text.Editable?) {
                val newName = s?.toString()?.trim().orEmpty()
                getPrefs().edit().putString("name", newName).apply()
                name = newName
            }
        })

        container.addView(avatar)
        container.addView(edit)

        settingsAvatarView = avatar
        settingsNameEdit = edit

        settingsSheet.addGameControl("Player", container)
    }

    fun openSettings() {
        if (::settingsSheet.isInitialized) {
            refreshSettingsSheetValues()
            settingsSheet.open()
        }
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
        setupSettingsSheet()

        Timer().schedule(object: TimerTask() {
            override fun run() {
                thread {
                    currentConnection?.send("p")
                }
            }
        }, 0, 120000)

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
            
            Log.i("name", prefs.getString("name", "")!!)
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
                    // avatar data
                    "name" to legacyAvatarStringForCrazy8(name ?: "Player"),
                    "version" to "52"
                )
                p0!!.multiplayer.createJoinRoom(room, "Chat", true, mapOf(), joinData, object : Callback<Connection>() {
                    override fun onSuccess(connection: Connection?) {
                        setupConnection(connection!!)
                    }

                    override fun onError(p0: PlayerIOError?) {
                        Log.e("PlayerIO", "Error joining $p0")
                        connectedError = p0.toString()
                    }
                })
            }

            override fun onError(p0: PlayerIOError?) {
                Log.e("PlayerIO", "Error $p0")
                connectedError = p0.toString()
            }
        })
        Log.i("Godot room", room)
    }

    fun sendMessage(message: String) {
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        // Vitalii Zlotskii is very good at cryptography, as showed off here...
        // this encryption is very effective
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(ByteArray(32) { 0x00 }, "AES"), IvParameterSpec(
            ByteArray(16) { 0x00 }))
        val encrypted = cipher.doFinal(message.encodeToByteArray())
        thread {
            currentConnection!!.send("emsg", encrypted)
        }
    }

    fun setReady(ready: Boolean) {
        thread {
            currentConnection!!.send(if (ready) "ready" else "notready")
        }
    }

    fun playCard(card: CrazyCard) {
        thread {
            currentConnection!!.send("move", card.encode(), "", 0)
        }
    }

    fun drawCard() {
        thread {
            currentConnection!!.send("move", "-1,-1", "", 0)
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
    fun setupConnection(connection: Connection) {
        currentConnection = connection
        connection.send("p")
        connection.addMessageListener("*", object : MessageListener() {
            override fun onMessage(message: Message?) {
                Log.i("PlayerIO", "message $message")
                //Handle message...
                when (message!!.type) {
                    "join_list", "game_list" -> {
                        connected = true
                        myId = message.getInt(1)
                        participants.clear()
                        participants.addAll(message.getString(0).split("|").map {
                            val parts = it.split("&")
                            parseParticipant(parts[0].toInt(), parts[1], parts[2] == "1")
                        })
                        if (message.type == "game_list") {
                            val participantIds = message.getString(2).split(",").map { it.toInt() }.toList()
                            val gameParticipants = participants.filter { participantIds.contains(it.id) }
                            val turn = gameParticipants.find { it.id == message.getInt(4) }!!
                            val cardState = message.getString(3).split("|")
                            val currentCard = CrazyCard.parse(cardState[0])
                            for (cardCount in cardState[1].split("&")) {
                                val parts = cardCount.split(":")
                                val participant = gameParticipants.find { it.id == parts[0].toInt() } ?: continue
                                participant.cardCount = parts[1].toInt()
                            }
                            val myCards = if (cardState.size > 2) cardState[2].split("&").map { CrazyCard.parse(it) }.toMutableStateList() else mutableStateListOf()
                            game = CrazyGame(gameParticipants, turn, currentCard, myCards)
                        }
                    }
                    "join" -> {
                        participants.add(parseParticipant(message.getInt(0), message.getString(1), false))
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
                        val participantIds = message.getString(0).split(",").map { it.toInt() }.toList()
                        val gameParticipants = participants.filter { participantIds.contains(it.id) }
                        val turn = gameParticipants.find { it.id == message.getInt(2) }!!
                        val cardState = message.getString(1).split("|")
                        val currentCard = CrazyCard.parse(cardState[0])
                        for (cardCount in cardState[1].split("&")) {
                            val parts = cardCount.split(":")
                            val participant = gameParticipants.find { it.id == parts[0].toInt() } ?: continue
                            participant.cardCount = parts[1].toInt()
                        }
                        val myCards = cardState[2].split("&").map { CrazyCard.parse(it) }.toMutableStateList()
                        game = CrazyGame(gameParticipants, turn, currentCard, myCards)
                    }
                    "move" -> {
                        game?.let { game ->
                            val moved = game.participants.find { it.id == message.getInt(0) }!!
                            game.turn = game.participants.find { it.id == message.getInt(2) }!!
                            val move = message.getString(1).split("|")
                            if (move[0] != "-1,-1") {
                                game.card = CrazyCard.parse(move[0])
                                moved.cardCount -= 1
                                if (moved.cardCount == 0) {
                                    label = "${if (moved.isMe) "You" else moved.name} won!"
                                    Handler(Looper.getMainLooper()).postDelayed({
                                        for (participant in participants) {
                                            participant.ready = false
                                        }
                                        this@Crazy8Activity.game = null
                                    }, 6000)
                                }
                            }
                            if (move.size == 1) {
                                // handled
                            } else if (move[1] == "d") {
                                moved.cardCount += move.size - 2 // card, d
                                if (moved.isMe) {
                                    game.hand.addAll(move.slice(2..<move.size).map { CrazyCard.parse(it) })
                                    val card = CrazyCard.parse(move[2])
                                    if (card.rank != 5 && card.isCompatibleWith(game.card)) {
                                        game.hand.remove(card)
                                        playCard(card)
                                    }
                                }
                            } else if (move[1] == "c") {
                                val added = game.participants.find { it.id == move[2].toInt() }!!
                                added.cardCount += move.size - 3 // card, c, id
                                if (added.isMe) {
                                    game.hand.addAll(move.slice(3..<move.size).map { CrazyCard.parse(it) })
                                }
                            }
                        }
                    }
                    "emsg" -> {
                        val sender = participants.find { it.id == message.getInt(0) }
                        if (sender == null) return

                        val bytes = message.getByteArray(1)
                        Log.i("bytes", Base64.encode(bytes))
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

                        Log.i("Got message", decrypted)
                    }
                    else -> { }
                }
            }
        })
        connection.addDisconnectListener(object : DisconnectListener() {
            override fun onDisconnect() {
                //Disconnected from room...
                Log.i("PlayerIO", "disconnected")
                connected = false
                currentConnection = null
            }
        })
    }

    override fun onDestroy() {
        super.onDestroy()
        currentConnection?.disconnect()
    }

    override fun onResume() {
        if (gameSessionIPC != null) {
            gameSessionIPC?.setSuppressNotifications(sessionId, true)
        } else {
            Log.w("openpigeon-${baseGame.getName()}", "onResume called before gameSessionIPC was initialized!")
        }
        super.onResume()
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
    )
    participants[1].cardCount = 7
    participants[2]. cardCount = 7
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
fun RenderCard(card: CrazyCard?, modifier: Modifier = Modifier) {
    val colors = when (card?.rank ?: -1) {
        0 -> listOf(
            Color(0xFFff5f64),
            Color(0xFFe11218),
        )
        1 -> listOf(
            Color(0xFF6DB0DF),
            Color(0xFF007FFF),
        )
        2 -> listOf(
            Color(0xFFe6c600),
            Color(0xFFccac00),
        )
        3 -> listOf(
            Color(0xFF4ec160),
            Color(0xFF1b8e2d),
        )
        5 -> listOf(
            Color(0xFFFF0000),
            Color(0xFFff9a00),
            Color(0xFFd0de21),
            Color(0xFF4fdc4a),
            Color(0xFF3fdad8),
            Color(0xFF2fc9e2),
            Color(0xFF1c7fee),
            Color(0xFF5f15f2),
            Color(0xFFba0cf8),
            Color(0xFFfb07d9),
        )
        else -> listOf(
            Color(0xFF666666),
            Color(0xFF444444),
        )
    }
    Box(
        modifier = modifier.size(80.dp, 110.dp)
            .background(
                brush = Brush.verticalGradient(colors),
                shape = RoundedCornerShape(4.dp),
            )
            .border(width = 4.dp, color = Color.White, shape = RoundedCornerShape(4.dp))
    ) {
        if (card != null)
        Text(
            card.displayName(),
            modifier = Modifier.align(Alignment.Center),
            color = Color.White,
            style = TextStyle(
                fontSize = 35.sp,
                fontWeight = FontWeight.ExtraBold,
                shadow = Shadow(
                    color = Color.Black, offset = Offset(3.0f, 5.0f), blurRadius = 1f
                )
            )
        )
        if (card != null)
        Text(
            card.extraName(),
            modifier = Modifier.align(Alignment.TopStart)
                .padding(horizontal = 8.dp, vertical = 3.dp),
            color = Color.White,
            style = TextStyle(
                fontSize = 25.sp,
                fontWeight = FontWeight.ExtraBold,
                shadow = Shadow(
                    color = Color.Black, offset = Offset(2.0f, 3.0f), blurRadius = 1f
                )
            )
        )
        if (card != null)
        Text(
            card.extraName(),
            modifier = Modifier.align(Alignment.BottomEnd)
                .padding(horizontal = 8.dp, vertical = 3.dp),
            color = Color.White,
            style = TextStyle(
                fontSize = 25.sp,
                fontWeight = FontWeight.ExtraBold,
                shadow = Shadow(
                    color = Color.Black, offset = Offset(2.0f, 3.0f), blurRadius = 1f
                )
            )
        )
    }
}

@Composable
fun RenderParticipant(game: CrazyGame, participant: CrazyParticipant) {
    Box(
        modifier = Modifier
            .size(8.dp)
            .clip(CircleShape)
            .background(if (participant == game.turn) Color.White else Color.Transparent)
    )
    Text(
        participant.name,
        modifier = Modifier.padding(bottom = 10.dp, top = 5.dp),
        fontWeight = if (participant == game.turn) FontWeight.ExtraBold else FontWeight.Normal,
        color = Color.White
    )
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
    androidx.compose.runtime.key(avatarData) {
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
                    AvatarData.init(context)
                    AvatarView(context).apply {
                        setBackgroundColor(android.graphics.Color.WHITE)
                        setLayerType(android.view.View.LAYER_TYPE_SOFTWARE, null)
                        alpha = 1f
                        elevation = 0f
                        try {
                            applyFromOpponentString(avatarData)
                        } catch (e: Exception) {
                            Log.e("Crazy8", "Failed to render lobby avatar", e)
                            showPlaceholder()
                        }
                    }
                },
                update = { view ->
                    view.setBackgroundColor(android.graphics.Color.WHITE)
                    view.setLayerType(android.view.View.LAYER_TYPE_SOFTWARE, null)
                    view.alpha = 1f
                    view.elevation = 0f
                    try {
                        view.applyFromOpponentString(avatarData)
                    } catch (e: Exception) {
                        Log.e("Crazy8", "Failed to update lobby avatar", e)
                        view.showPlaceholder()
                    }
                }
            )
        }
    }
}

@Composable
fun RenderGame(game: CrazyGame, activity: Crazy8Activity?, messages: SnapshotStateList<CrazyMessage>) {
    val scrollState = rememberScrollState()
    val participantScrollState = rememberScrollState()
    val selected = remember { mutableStateOf<CrazyCard?>(null) }
    val selectedWildcard = remember { mutableStateOf<CrazyCard?>(null) }
    val me = game.participants.find { it.isMe }
    val label = activity?.label
    val textInput = remember { mutableStateOf("") }
    val imeVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
    val keyboardController = LocalSoftwareKeyboardController.current

    var chatRead by remember { mutableIntStateOf(0) }
    if (imeVisible) {
        chatRead = messages.size
    }

    val unread = messages.size - chatRead

    Log.i("visible", imeVisible.toString())
    Box(
        modifier = Modifier.fillMaxSize()
    ) {
        Row(
            modifier = Modifier.align(Alignment.TopCenter)
                .horizontalScroll(participantScrollState)
                .fillMaxWidth()
                .navigationBarsPadding()
                .statusBarsPadding(),
            horizontalArrangement = Arrangement.Center,
        ) {
            val meIdx = game.participants.indexOf(me)
            val list = if (meIdx != -1) {
                val participants = arrayListOf<CrazyParticipant>()
                // exclude me
                participants.addAll(game.participants.slice(meIdx + 1..<game.participants.size))
                participants.addAll(game.participants.slice(0..<meIdx))
                participants
            } else {
                game.participants
            }
            for (participant in list) {
                Column(
                    modifier = Modifier.padding(10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    RenderParticipant(game, participant)
                    Column(
                        verticalArrangement = Arrangement.spacedBy((-100).dp)
                    ) {
                        (1..min(participant.cardCount, 10)).forEach { _ ->
                            RenderCard(null)
                        }
                    }
                }
            }
        }
        Row(
            modifier = Modifier.align(Alignment.Center)
                .navigationBarsPadding()
                .statusBarsPadding(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            RenderCard(null, modifier = Modifier.clickable {
                if (game.turn != me) return@clickable
                activity!!.drawCard()
            })
            RenderCard(
                game.card,
            )
        }
        Column(
            modifier = Modifier.align(Alignment.BottomCenter)
                .padding(horizontal = 30.dp, vertical = 80.dp)
                .navigationBarsPadding()
                .statusBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (me != null)
            RenderParticipant(game, me)
            if (me != null)
            Row(
                modifier = Modifier.horizontalScroll(scrollState)
                    .fillMaxWidth()
                    .padding(top = 10.dp),
                horizontalArrangement = Arrangement.spacedBy((-25).dp, alignment = Alignment.CenterHorizontally)
            ) {
                for (card in game.hand) {
                    val offsetY by animateDpAsState(
                        targetValue = if (selected.value == card) (-20).dp else 0.dp,
                        animationSpec = tween(
                            durationMillis = 300,
                            easing = FastOutSlowInEasing
                        ),
                        label = "offsetAnimation"
                    )
                    if (selectedWildcard.value == card) {
                        AlertDialog(
                            onDismissRequest = { selectedWildcard.value = null },
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
                                        Row(
                                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                                        ) {
                                            for (i in 0..1) {
                                                val newCard = CrazyCard(x * 2 + i, card.file)
                                                RenderCard(newCard, modifier = Modifier.clickable {
                                                    game.hand.remove(card)
                                                    activity!!.playCard(newCard)
                                                    selectedWildcard.value = null
                                                })
                                            }
                                        }
                                    }
                                }
                            },
                            confirmButton = {
                                TextButton(onClick = { selectedWildcard.value = null }) {
                                    Text("Cancel")
                                }
                            },
                        )
                    }
                    RenderCard(card, modifier = Modifier.clickable {
                        if (label != null) return@clickable
                        if (game.turn != me) return@clickable
                        if (!card.isCompatibleWith(game.card)) return@clickable
                        if (selected.value != card) {
                            selected.value = card
                            return@clickable
                        }
                        selected.value = null
                        if (card.rank == 5) {
                            selectedWildcard.value = card
                            return@clickable
                        }
                        game.hand.remove(card)
                        activity!!.playCard(card)
                    }.drawWithContent {
                        drawContent() // draw the original content
                        drawRoundRect(
                            color = if (!card.isCompatibleWith(game.card) && game.turn == me) Color.Black.copy(alpha = 0.3f) else Color.Transparent,
                            cornerRadius = CornerRadius(4.dp.toPx())
                        )
                    }.offset(y = offsetY))
                }
            }
        }
        
        if (imeVisible)
        LazyColumn(
            modifier = Modifier.fillMaxSize()
                .background(Color(0x77000000))
                .imePadding()
                .navigationBarsPadding()
                .statusBarsPadding()
                .padding(bottom = 60.dp)
                .clickable(
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() }
                ) {
                    keyboardController?.hide()
                },
            reverseLayout = true
        ) {
            items(messages) { item ->
                if (item.sender.isMe) {
                    Text(
                        item.message,
                        modifier = Modifier
                            .fillMaxWidth()
                            .wrapContentWidth(Alignment.End)
                            .padding(8.dp)
                            .background(Color(0xFF007FFF), shape = RoundedCornerShape(16.dp))
                            .padding(8.dp),
                        color = Color.White,
                        fontSize = 16.sp,
                    )
                } else {
                    Column(modifier = Modifier.padding(8.dp)) {
                        Text(item.sender.name,
                            color = Color.LightGray,
                            fontWeight = FontWeight.ExtraBold,
                            fontSize = 10.sp,
                            modifier = Modifier.padding(bottom = 4.dp)
                        )
                        Text(
                            item.message,
                            modifier = Modifier
                                .background(Color.White, shape = RoundedCornerShape(16.dp))
                                .padding(8.dp),
                            color = Color.Black,
                            fontSize = 16.sp,
                        )
                    }
                }
            }
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
                    activity!!.sendMessage(textInput.value)
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
                .fillMaxWidth(),
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
        if (label != null)
        Text(label,
            modifier = Modifier.align(Alignment.Center)
                .navigationBarsPadding()
                .statusBarsPadding()
                .background(Color(0x88000000))
                .padding(10.dp),
            fontSize = 20.sp,
            color = Color.White
        )
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

            LazyColumn(
                state = listState,
                reverseLayout = true,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .clickable(
                        indication = null,
                        interactionSource = remember { MutableInteractionSource() }
                    ) {
                        onClose()
                    },
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
fun LobbyAvatarSpeechBubble(text: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.zIndex(2f)
    ) {
        Canvas(
            modifier = Modifier
                .matchParentSize()
        ) {
            val tailTipX = 0f
            val tailTipY = size.height * 0.72f

            val bubbleLeft = 18.dp.toPx()

            val attachTopX = bubbleLeft + 6.dp.toPx()
            val attachTopY = size.height * 0.60f

            val attachBottomX = bubbleLeft + 6.dp.toPx()
            val attachBottomY = size.height * 0.86f

            val path = androidx.compose.ui.graphics.Path().apply {
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
