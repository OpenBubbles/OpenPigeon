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
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
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

class CrazyParticipant(val name: String, val id: Int, val isMe: Boolean, ready: Boolean) {
    var ready by mutableStateOf(ready)
    var cardCount by mutableIntStateOf(0)
}

data class CrazyMessage(val message: String, val sender: CrazyParticipant)

data class CrazyCard(val rank: Int, val file: Int) {
    companion object {
        fun parse(data: String): CrazyCard {
            var parts = data.split(",")
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

    fun getPrefs(): SharedPreferences {
        return getSharedPreferences("crazy_prefs", Context.MODE_PRIVATE)
    }

    @SuppressLint("UseKtx")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        enableEdgeToEdge()

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
                                    joinRoom(currentRoom)
                                }
                            )
                        )
                        Button(onClick = {
                            prefs.edit().putString("name", thisName).apply()
                            name = thisName
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
                    Column(modifier = Modifier.align(Alignment.Center),
                        horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("Failed to connect: $connectedError",
                            fontSize = 20.sp,
                            color = Color.White,
                            modifier = Modifier.padding(10.dp),
                            textAlign = TextAlign.Center)
                        Button(onClick = {
                            connectedError = null
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
                var joinData = mapOf(
                    "id" to userid,
                    // avatar data
                    "name" to "b,4`e,0`m,2`a,0`w,0`bg,0.608878,0.670567,0.842836`bc,0.764706,0.254902,0.152941`g,0`s,0`d,0`h,3`c,2`hc,0.000000,0.000000,0.000000`cc,0.290639,0.935341,0.083265`n,$name",
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
        var parts = data.split("`")
        return CrazyParticipant(parts[0].substring(34), id, id == myId, ready)
    }

    val messages = mutableStateListOf<CrazyMessage>()

    val participants = mutableStateListOf<CrazyParticipant>()
    var game by mutableStateOf<CrazyGame?>(null)
    var label by mutableStateOf<String?>(null)
    var connected by mutableStateOf(false)

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

    var unread = messages.size - chatRead

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
                        for (i in 1..min(participant.cardCount, 10)) {
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
fun RenderWaiting(participants: SnapshotStateList<CrazyParticipant>, activity: Crazy8Activity?) {
    val me = participants.find { it.isMe }
    Column (horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth()
            .navigationBarsPadding()
            .statusBarsPadding()) {
        Column(modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.Center) {
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
                            .padding(8.dp)
                            .fillMaxWidth()
                    ) {
                        Text(participant.name,
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
                        Text("—",
                            modifier = Modifier
                                .align(Alignment.CenterEnd)
                                .alpha(if (participant.ready) 0.0f else 1.0f)
                                .padding(horizontal = 5.dp),
                            color = Color.DarkGray,
                            fontWeight = FontWeight.ExtraBold,
                            fontSize = 25.sp)
                    }
                }
            }
        }
        Text("3-6 players required to start", color = Color.White, modifier = Modifier.padding(8.dp).alpha(if (participants.all { it.ready }) 1.0f else 0.0f))
        Button(onClick = {
            me!!.ready = !me.ready
            activity!!.setReady(me.ready)
        }, modifier = Modifier.padding(bottom = 16.dp)) {
            Text(if (me?.ready == true) "CANCEL" else "READY")
        }
    }
}
