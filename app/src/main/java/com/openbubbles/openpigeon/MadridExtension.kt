package com.openbubbles.openpigeon

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.RemoteViews
import android.widget.Toast
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import androidx.glance.ExperimentalGlanceApi
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.layout.wrapContentHeight
import androidx.glance.preview.ExperimentalGlancePreviewApi
import androidx.glance.preview.Preview
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.bluebubbles.messaging.IKeyboardHandle
import com.bluebubbles.messaging.IMadridExtension
import com.bluebubbles.messaging.IMessageViewHandle
import com.bluebubbles.messaging.IViewUpdateCallback
import com.bluebubbles.messaging.MadridMessage
import com.openbubbles.openpigeon.MadridExtension.Companion.games
import com.openbubbles.openpigeon.anagrams.AnagramsGame
import com.openbubbles.openpigeon.archery.ArcheryGame
import com.openbubbles.openpigeon.basketball.BasketballGame
import com.openbubbles.openpigeon.battleship.BattleshipGame
import com.openbubbles.openpigeon.checkers.CheckersGame
import com.openbubbles.openpigeon.chess.ChessGame
import com.openbubbles.openpigeon.connect.ConnectGame
import com.openbubbles.openpigeon.crazy8.Crazy8Game
import com.openbubbles.openpigeon.darts.DartsGame
import com.openbubbles.openpigeon.dots.DotsGame
import com.openbubbles.openpigeon.fill.FillerGame
import com.openbubbles.openpigeon.gomoku.GomokuGame
import com.openbubbles.openpigeon.mancala.MancalaGame
import com.openbubbles.openpigeon.paintball.PaintGame
import com.openbubbles.openpigeon.pong.PongGame
import com.openbubbles.openpigeon.pool.PoolGame
import com.openbubbles.openpigeon.questions.QuestionsGame
import com.openbubbles.openpigeon.reversi.ReversiGame
import com.openbubbles.openpigeon.wordbites.WordbitesGame
import com.openbubbles.openpigeon.wordgames.WordGames
import com.openbubbles.openpigeon.wordhunt.WordHuntGame
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import kotlin.math.ceil
import kotlin.math.min
import kotlin.math.roundToInt


class MadridExtension(val context: Context) : IMadridExtension.Stub() {

    companion object {
        var currentKeyboardHandle: IKeyboardHandle? = null
        var broadcastReceiver: BroadcastReceiver? = null

        val activeSessions: MutableMap<String, GameSession> = mutableMapOf()

        val games: List<Game> = listOf(
            PoolGame(),
            BattleshipGame(),
            BasketballGame(),
            ArcheryGame(),
            WordGames(),
            DartsGame(),
            PongGame(),
            Crazy8Game(),
            ConnectGame(),
            PaintGame(),
            FillerGame(),
            CheckersGame(),
            ChessGame(),
            MancalaGame(),
            DotsGame(),
            GomokuGame(),
            ReversiGame(),
            QuestionsGame(),
            WordHuntGame(), //Marked Hidden as inside Word Games Wrapper
            AnagramsGame(), //Marked Hidden as inside Word Games Wrapper
            WordbitesGame() //Marked Hidden as inside Word Games Wrapper
        )

        fun getSessionFor(id: String, handle: IMessageViewHandle): GameSession {
            if (activeSessions.containsKey(id)) {
                activeSessions[id]!!.updateHandle(handle)
            } else {
                activeSessions[id] = GameSession(handle)
            }
            return activeSessions[id]!!
        }

        fun whichGame(game: JSONObject): Game? {
            return findByName(game.getString("game"))
        }

        fun findByName(name: String): Game? {
            return games.find { it.getName() == name }
        }

        var currentUserCount: Int = 2
    }

    private var callback: IViewUpdateCallback? = null

    override fun keyboardClosed() {
        currentKeyboardHandle = null
        callback = null
        configuringGame = null
    }

    var configuringGame: Game? = null
    var currentPage: Int = 0

    @Composable
    fun MainKeyboard() {
        if (configuringGame != null) {
            RenderKeyboardConfig(this@MadridExtension, configuringGame!!)
        } else {
            RenderKeyboard(this@MadridExtension)
        }
    }

    @OptIn(ExperimentalGlanceRemoteViewsApi::class)
    fun updateKeyboard() {
        val cb = callback ?: return

        val displayMetrics = context.resources.displayMetrics
        val dpWidth = displayMetrics.widthPixels / displayMetrics.density

        val result = runBlocking {
            keyboardRemoteViews.compose(context, DpSize(dpWidth.dp, 300.dp)) {
                MainKeyboard()
            }
        }

        val mainHandler = Handler(Looper.getMainLooper())

        mainHandler.post {
            try {
                cb.updateView(result.remoteViews)
            } catch (t: Throwable) {
                Log.e("MadridExtension", "updateKeyboard updateView failed", t)
            }
        }

        mainHandler.postDelayed({
            try {
                cb.updateView(result.remoteViews)
            } catch (t: Throwable) {
                Log.e("MadridExtension", "updateKeyboard second updateView failed", t)
            }
        }, 50)
    }
    @OptIn(ExperimentalGlanceRemoteViewsApi::class)
    val keyboardRemoteViews = GlanceRemoteViews()
    @OptIn(ExperimentalGlanceRemoteViewsApi::class)
    override fun keyboardOpened(callback: IViewUpdateCallback?, handle: IKeyboardHandle?, userCount: Int): RemoteViews {
        this.callback = callback

        val displayMetrics = context.resources.displayMetrics
        val dpWidth = displayMetrics.widthPixels / displayMetrics.density

        currentUserCount = userCount

        val result = runBlocking {
            keyboardRemoteViews.compose(context, DpSize(dpWidth.dp, 300.dp)) {
                MainKeyboard()
            }
        }

        currentKeyboardHandle = handle

        return result.remoteViews
    }

    override fun didTapTemplate(message: MadridMessage?, handle: IMessageViewHandle?, userCount: Int) {
        if (message == null || handle == null) return
        val session = getSessionFor(message.session, handle)
        session.handleNewMessage(message)
        val game = session.getGame()

        Log.i("Session", message.session.toString())
        if (game != null ) {
            val intent = Intent(context, game.gameClass())
                .apply {
                    putExtra("SESSION", message.session)
                    putExtra("GAME", session.getGame()?.getName())
                    putExtra("DISPLAY_GAME", session.currentMessage["game_name"])
                    data = "data://${System.currentTimeMillis()}".toUri()
                }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } else {
            Log.e("Game","null")
            return
        }
    }


    @OptIn(ExperimentalGlanceRemoteViewsApi::class)
    override fun getLiveView(
        callback: IViewUpdateCallback?,
        message: MadridMessage?,
        handle: IMessageViewHandle?,
        userCount: Int
    ): RemoteViews {
        val session = getSessionFor(message!!.session, handle!!)
        session.handleNewMessage(message)

        val displayMetrics = context.resources.displayMetrics
        val dpWidth = displayMetrics.widthPixels / displayMetrics.density
        val messageWidth = (dpWidth * 0.60).roundToInt() - 10

        val result = runBlocking {
            session.liveRemoteViews.compose(context, DpSize(messageWidth.dp, 250.dp)) {
                RenderLiveExtension(this@MadridExtension, session, message)
            }
        }

        return result.remoteViews
    }

    override fun messageUpdated(message: MadridMessage?) {
        if (message == null) return
        activeSessions[message.session]?.handleNewMessage(message)
        Log.i("update", "message")
    }

}


class ChooseGameCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters
    ) {
        val game = parameters[gameName]?.let { MadridExtension.findByName(it) } ?: return

        if (game.isConfigurable()) {
            MadridExtensionService.extension?.let {
                it.configuringGame = game
                it.updateKeyboard()
            }
        }

        if (MadridExtension.currentUserCount < game.minPlayerRequirement()) {
            Handler(Looper.getMainLooper()).post {
                Toast.makeText(context, "Minimum ${game.minPlayerRequirement()} players required for this game!", Toast.LENGTH_LONG).show()
            }
            return
        }

        val message = game.buildGameMessage(context, game.getNewGameData(context) ?: return, null)

        MadridExtension.currentKeyboardHandle?.addMessage(message)
    }
}

class GoBackCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters
    ) {
        MadridExtensionService.extension?.let {
            it.configuringGame = null
            it.updateKeyboard()
        }
    }
}

private val gameName = ActionParameters.Key<String>("game_name")

@Composable
fun RenderKeyboardGame(game: Game, extension: MadridExtension?, modifier: GlanceModifier = GlanceModifier) {
    Column(modifier = modifier.wrapContentHeight().padding(1.dp), horizontalAlignment = Alignment.Horizontal.CenterHorizontally) {
        Image(
            ImageProvider(game.gamePoster(null)),
            contentDescription = game.displayName(),
            modifier = GlanceModifier.wrapContentHeight().clickable(
                onClick = actionRunCallback<ChooseGameCallback>(actionParametersOf(
                    gameName to game.getName()
                ))
            ).height(80.dp).cornerRadius(5.dp),
            contentScale = ContentScale.Crop,
        )
        Text(game.displayName().uppercase(),
            style = TextStyle(
                color = ColorProvider(Color.Gray),
                textAlign = TextAlign.Center,
                fontWeight = FontWeight.Bold,
                fontSize = 11.sp
            )
        )
    }
}

private val page = ActionParameters.Key<Int>("page")
class ChangePageCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters
    ) {
        MadridExtensionService.extension?.let {
            it.currentPage = parameters[page]!!
            it.updateKeyboard()
        }
    }
}

@Composable
fun RenderKeyboard(extension: MadridExtension?) {
    val itemsPerRow = 5
    val rowsPerPage = 2
    val p = extension?.currentPage ?: 0
    val itemsPerPage = itemsPerRow * rowsPerPage
    val hiddenGameNames = setOf("hunt", "anagrams", "wordbites")
    val visibleGames = games.filter { it.getName() !in hiddenGameNames }
    val totalPages = ceil(visibleGames.size / itemsPerPage.toDouble()).toInt()

    val pageGames = visibleGames.slice(
        min(itemsPerPage * p, visibleGames.size)..<min(itemsPerPage * (p + 1), visibleGames.size)
    )
    Column(modifier = GlanceModifier.fillMaxHeight().padding(1.dp)) {
        Row(horizontalAlignment = Alignment.Horizontal.CenterHorizontally, verticalAlignment = Alignment.CenterVertically, modifier = GlanceModifier.fillMaxWidth()) {
            val arrowSlotWidth = 43.dp
            if (p > 0) {
                Image(
                    ImageProvider(R.drawable.baseline_arrow_back_ios_24),
                    "Back",
                    modifier = GlanceModifier
                        .padding(horizontal = 10.dp, vertical = 5.dp)
                        .clickable(
                            actionRunCallback<ChangePageCallback>(
                                actionParametersOf(page to (p - 1))
                            )
                        )
                )
            } else {
                Spacer(modifier = GlanceModifier.width(arrowSlotWidth))
            }
            Spacer(modifier = GlanceModifier.defaultWeight())
            Image(ImageProvider(R.drawable.madrid_icon), "OpenPigeon", modifier = GlanceModifier.width(50.dp).padding(8.dp).wrapContentHeight())
            Text("Games", style = TextStyle(fontSize = 24.sp, color = ColorProvider(Color.Gray)), modifier = GlanceModifier.padding(end = 6.dp))
            Text("|", style = TextStyle(fontSize = 30.sp, color = ColorProvider(Color.Gray)))
            Text("About", style = TextStyle(fontSize = 15.sp, color = ColorProvider(Color.Gray)), modifier = GlanceModifier.padding(start = 6.dp)
                .clickable(onClick = androidx.glance.action.actionStartActivity<AboutActivity>()))
            Spacer(modifier = GlanceModifier.defaultWeight())
            if (p < (totalPages - 1)) {
                Image(
                    ImageProvider(R.drawable.baseline_arrow_forward_ios_24),
                    "Forward",
                    modifier = GlanceModifier
                        .padding(horizontal = 10.dp, vertical = 5.dp)
                        .clickable(
                            actionRunCallback<ChangePageCallback>(
                                actionParametersOf(page to (p + 1))
                            )
                        )
                )
            } else {
                Spacer(modifier = GlanceModifier.width(arrowSlotWidth))
            }
        }
        for (index in 0..<ceil(pageGames.size / itemsPerRow.toDouble()).toInt()) {
            Row(modifier = GlanceModifier.padding(bottom = 3.dp)) {
                for (i in 0..<itemsPerRow) {
                    val game = pageGames.getOrNull(index * itemsPerRow + i)
                    if (game != null) {
                        RenderKeyboardGame(game, extension, modifier = GlanceModifier.defaultWeight())
                    } else {
                        Box(modifier = GlanceModifier.defaultWeight()) {  }
                    }
                }
            }
        }
        Spacer(modifier = GlanceModifier.defaultWeight())
    }
}

@Composable
fun RenderKeyboardConfig(extension: MadridExtension?, game: Game) {
    Column(modifier = GlanceModifier.fillMaxHeight().padding(1.dp)) {
        Box(contentAlignment = Alignment.CenterStart) {
            Row(horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.Vertical.CenterVertically) {
                Image(ImageProvider(game.gamePoster(null)), game.getName(), modifier = GlanceModifier.width(50.dp).padding(8.dp).wrapContentHeight())
                Text(game.displayName(), style = TextStyle(fontSize = 24.sp, color = ColorProvider(Color.Gray), fontWeight = FontWeight.Bold),)
            }
            Image(ImageProvider(R.drawable.ios_back), "Back", modifier = GlanceModifier.padding(start = 10.dp)
                .clickable(onClick = actionRunCallback<GoBackCallback>()))
        }
        game.Configuration(extension?.context)
    }
}

@OptIn(ExperimentalGlanceApi::class)
@Composable
fun RenderLiveExtension(extension: MadridExtension?, session: GameSession?, message: MadridMessage?) {
    Column(modifier = GlanceModifier.fillMaxHeight().let {
        if (extension != null) {
            val intent = Intent(extension.context, if (session?.getGame()?.isSupported(session.currentMessage) == true) session.getGame()!!.gameClass() else GameNotFound::class.java).apply {
                putExtra("SESSION", message?.session ?: "")
                putExtra("GAME", session?.getGame()?.getName())
                putExtra("DISPLAY_GAME", session?.currentMessage?.get("game_name"))
                data = "data://${System.currentTimeMillis()}".toUri()
            }
            it.clickable(onClick =
                actionStartActivity(intent)
            )
        } else {
            it
        }
    }, horizontalAlignment = Alignment.Horizontal.CenterHorizontally) {
        Box(modifier = GlanceModifier.defaultWeight()) {
            Image(ImageProvider(session?.getGame()?.gamePoster(session.currentMessage) ?: R.drawable.empty),
                session?.getGame()?.getName() ?: "Game", contentScale = ContentScale.Crop)
            val winMode = session?.getGame()?.getWinStateImage(extension!!.context, session.currentMessage)
            if (winMode != null) {
                Image(ImageProvider(winMode), message?.caption ?: "Game Over", contentScale = ContentScale.Crop,
                    modifier = GlanceModifier.fillMaxSize().padding(32.dp))
            }
        }
        Text((session?.getGame()?.getDisplaySubtitle(extension!!.context, session.currentMessage) ?: message?.caption ?: "Game Name").uppercase(),
            style = TextStyle(fontSize = 16.sp, color = ColorProvider(Color.Gray),
                textAlign = TextAlign.Center, fontWeight = FontWeight.Bold),
            modifier = GlanceModifier.padding(vertical = 10.dp))
    }
}

@OptIn(ExperimentalGlancePreviewApi::class)
@Preview(widthDp = 200, heightDp = 250)
@Composable
fun RenderLiveExtensionPreview() {
    Box(modifier = GlanceModifier.background(Color.Black)) {
        RenderLiveExtension(null, null, null)
    }
}

@OptIn(ExperimentalGlancePreviewApi::class)
@Preview(widthDp = 400, heightDp = 300)
@Composable
fun RenderKeyboardConfigPreview() {
    Box(modifier = GlanceModifier.background(Color.Black)) {
        RenderKeyboardConfig(null, PoolGame())
    }
}

@OptIn(ExperimentalGlancePreviewApi::class)
@Preview(widthDp = 400, heightDp = 300)
@Composable
fun RenderKeyboardPreview() {
    Box(modifier = GlanceModifier.background(Color.Black)) {
        RenderKeyboard(null)
    }
}

private val configName = ActionParameters.Key<String>("configName")
private val configVal = ActionParameters.Key<String>("configVal")
class ConfigureCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters
    ) {
        val game = parameters[gameName]?.let { MadridExtension.findByName(it) } ?: return

        game.setConfigOption(parameters[configName]!!, parameters[configVal]!!)

        val message = game.buildGameMessage(context, game.getNewGameData(context) ?: return, null)
        MadridExtension.currentKeyboardHandle?.addMessage(message)

        if (game.isConfigurable()) {
            MadridExtensionService.extension?.updateKeyboard()
        }
    }
}

@Composable
fun RenderConfigOption(game: Game, name: String, options: List<String>, selected: String) {
    Column(modifier = GlanceModifier.padding(8.dp)) {
        Text(name.uppercase(), style = TextStyle(color = ColorProvider(Color.Gray),
            fontWeight = FontWeight.Bold, fontSize = 11.sp))
        Spacer(modifier = GlanceModifier.height(2.dp).background(Color.Gray).fillMaxWidth())
        Row(verticalAlignment = Alignment.Vertical.CenterVertically, modifier = GlanceModifier.fillMaxWidth()) {
            for (option in options) {
                Text(option, style = TextStyle(fontWeight =
                    if (selected == option) FontWeight.Bold else FontWeight.Normal, color = ColorProvider(Color.Gray),
                    fontSize = 18.sp, textAlign = TextAlign.Center
                ), modifier = GlanceModifier.padding(horizontal = 8.dp, vertical = 4.dp).clickable(onClick = actionRunCallback<ConfigureCallback>(actionParametersOf(
                    gameName to game.getName(),
                    configName to name,
                    configVal to option,
                ))).defaultWeight())
                if (options.last() != option) {
                    Spacer(modifier = GlanceModifier.width(1.dp).background(Color.Gray).height(15.dp))
                }
            }
        }
    }
}

@OptIn(ExperimentalGlancePreviewApi::class)
@Preview(widthDp = 400, heightDp = 300)
@Composable
fun RenderConfigOptionPreview() {
    Box(modifier = GlanceModifier.background(Color.Black).fillMaxSize()) {
        RenderConfigOption(BasketballGame(), "Game Mode", listOf("8 Ball", "8 Ball+"), "8 Ball")
    }
}
