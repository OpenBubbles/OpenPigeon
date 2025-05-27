package com.example.openbubblesextension

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ExperimentalGlanceApi
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.GridCells
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.LazyVerticalGrid
import androidx.glance.appwidget.lazy.items
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
import com.example.openbubblesextension.MadridExtension.Companion.games
import com.example.openbubblesextension.basketball.BasketballGame
import com.example.openbubblesextension.battleship.BattleshipGame
import com.example.openbubblesextension.checkers.CheckersGame
import com.example.openbubblesextension.connect.ConnectGame
import com.example.openbubblesextension.crazy8.Crazy8Game
import com.example.openbubblesextension.darts.DartsActivity
import com.example.openbubblesextension.darts.DartsGame
import com.example.openbubblesextension.pool.PoolGame
import com.example.openbubblesextension.wordhunt.WordHuntGame
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import kotlin.math.ceil
import kotlin.math.roundToInt


class MadridExtension(val context: Context) : IMadridExtension.Stub() {

    companion object {
        var currentKeyboardHandle: IKeyboardHandle? = null
        var broadcastReceiver: BroadcastReceiver? = null

        val activeSessions: MutableMap<String, GameSession> = mutableMapOf()

        val games: List<Game> = listOf(
            CheckersGame(),
            WordHuntGame(),
            ConnectGame(),
            BasketballGame(),
            BattleshipGame(),
            Crazy8Game(),
            DartsGame(),
            PoolGame(),
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
    }

    private var callback: IViewUpdateCallback? = null

    override fun keyboardClosed() {
        currentKeyboardHandle = null
        callback = null
        configuringGame = null
    }

    var configuringGame: Game? = null

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
        callback?.let {
            val displayMetrics = context.resources.displayMetrics
            val dpWidth = displayMetrics.widthPixels / displayMetrics.density

            val result = runBlocking {
                keyboardRemoteViews.compose(context, DpSize(dpWidth.dp, 300.dp)) {
                    MainKeyboard()
                }
            }

            it.updateView(result.remoteViews)
        }
    }

    @OptIn(ExperimentalGlanceRemoteViewsApi::class)
    val keyboardRemoteViews = GlanceRemoteViews()
    @OptIn(ExperimentalGlanceRemoteViewsApi::class)
    override fun keyboardOpened(callback: IViewUpdateCallback?, handle: IKeyboardHandle?): RemoteViews {
        this.callback = callback

        val displayMetrics = context.resources.displayMetrics
        val dpWidth = displayMetrics.widthPixels / displayMetrics.density

        val result = runBlocking {
            keyboardRemoteViews.compose(context, DpSize(dpWidth.dp, 300.dp)) {
                MainKeyboard()
            }
        }

        currentKeyboardHandle = handle

        return result.remoteViews
    }

    override fun didTapTemplate(message: MadridMessage?, handle: IMessageViewHandle?) {
        // no need to handle, we only have live messages
    }


    @OptIn(ExperimentalGlanceRemoteViewsApi::class)
    override fun getLiveView(
        callback: IViewUpdateCallback?,
        message: MadridMessage?,
        handle: IMessageViewHandle?
    ): RemoteViews {
        val session = getSessionFor(message!!.session, handle!!)
        session.handleNewMessage(message)

        val displayMetrics = context.resources.displayMetrics
        val dpWidth = displayMetrics.widthPixels / displayMetrics.density
        val messageWidth = (dpWidth * 0.60).roundToInt() - 10

        val result = runBlocking {
            keyboardRemoteViews.compose(context, DpSize(messageWidth.dp, 250.dp)) {
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
        val message = game.buildGameMessage(context, game.getNewGameData(context), null)

        MadridExtension.currentKeyboardHandle?.addMessage(message)

        if (game.isConfigurable()) {
            MadridExtensionService.extension?.let {
                it.configuringGame = game
                it.updateKeyboard()
            }
        }
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
            ImageProvider(game.gamePoster()),
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

@Composable
fun RenderKeyboard(extension: MadridExtension?) {
    val itemsPerRow = 5
    Column(modifier = GlanceModifier.fillMaxHeight().padding(1.dp)) {
        Row(horizontalAlignment = Alignment.Horizontal.CenterHorizontally, modifier = GlanceModifier.fillMaxWidth()) {
            Image(ImageProvider(R.drawable.madrid_icon), "OpenPigeon", modifier = GlanceModifier.width(50.dp).padding(8.dp).wrapContentHeight())
            Text("Games", style = TextStyle(fontSize = 24.sp, color = ColorProvider(Color.Gray)), modifier = GlanceModifier.padding(end = 6.dp))
            Text("|", style = TextStyle(fontSize = 30.sp, color = ColorProvider(Color.Gray)))
            Text("Settings", style = TextStyle(fontSize = 15.sp, color = ColorProvider(Color.Gray)), modifier = GlanceModifier.padding(start = 6.dp))
        }
        for (index in 0..<ceil(games.size / itemsPerRow.toDouble()).toInt()) {
            Row(modifier = GlanceModifier.padding(bottom = 3.dp)) {
                for (i in 0..<itemsPerRow) {
                    val game = games.getOrNull(index * itemsPerRow + i)
                    if (game != null) {
                        RenderKeyboardGame(game, extension, modifier = GlanceModifier.defaultWeight())
                    } else {
                        Box(modifier = GlanceModifier.defaultWeight()) {  }
                    }
                }
            }
        }
    }
}

@Composable
fun RenderKeyboardConfig(extension: MadridExtension?, game: Game) {
    Column(modifier = GlanceModifier.fillMaxHeight().padding(1.dp)) {
        Box(contentAlignment = Alignment.CenterStart) {
            Row(horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.Vertical.CenterVertically) {
                Image(ImageProvider(game.gamePoster()), game.getName(), modifier = GlanceModifier.width(50.dp).padding(8.dp).wrapContentHeight())
                Text(game.displayName(), style = TextStyle(fontSize = 24.sp, color = ColorProvider(Color.Gray), fontWeight = FontWeight.Bold),)
            }
            Image(ImageProvider(R.drawable.ios_back), "Back", modifier = GlanceModifier.padding(start = 10.dp)
                .clickable(onClick = actionRunCallback<GoBackCallback>()))
        }
        game.Configuration(extension?.context)
    }
}

private val gameSession = ActionParameters.Key<String>("SESSION")
@OptIn(ExperimentalGlanceApi::class)
@Composable
fun RenderLiveExtension(extension: MadridExtension?, session: GameSession?, message: MadridMessage?) {
    Column(modifier = GlanceModifier.fillMaxHeight().let {
        if (extension != null) {
            it.clickable(onClick =
                actionStartActivity(
                    ComponentName(extension.context, session?.getGame()?.gameClass() ?: DartsActivity::class.java),
                    parameters = actionParametersOf(
                        gameSession to (message?.session ?: "")
                    )
                ))
        } else {
            it
        }
    }, horizontalAlignment = Alignment.Horizontal.CenterHorizontally) {
        Image(ImageProvider(session?.getGame()?.gamePoster() ?: R.drawable.empty),
            session?.getGame()?.getName() ?: "Game",
            modifier = GlanceModifier.defaultWeight(), contentScale = ContentScale.Crop)
        Text((message?.caption ?: "Game Name").uppercase(),
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

        val message = game.buildGameMessage(context, game.getNewGameData(context), null)
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
