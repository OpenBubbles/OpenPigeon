package com.openbubbles.openpigeon.godot

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.MadridExtension
import com.openbubbles.openpigeon.R
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin

class GodotGameActivity : GodotActivity() {
    lateinit var baseGame: Game

    lateinit var sessionId: String
    var appPlugin: GodotAppPlugin? = null
    var gameSessionIPC: GameSessionIPC? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContentView(R.layout.activity_godot)
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.surfaceView)) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }
        initGameSession(intent)
    }

    override fun onNewIntent(newIntent: Intent) {
        super.onNewIntent(newIntent)
        baseGame = MadridExtension.findByName(newIntent.getStringExtra("GAME")!!)!!
        getOrCreateAppPlugin().switchGame(baseGame.getName())
        initGameSession(newIntent)
    }

//    override fun getCommandLine(): MutableList<String> {
//        return mutableListOf<String>("--remote-debug", "tcp://192.168.0.81:6008")
//    }

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

    override fun onDestroy() {
        gameSessionIPC!!.setSuppressNotifications(sessionId, false)
        gameSessionIPC!!.unlockMsgHandle(sessionId)
        super.onDestroy()
    }

    private fun initGameSession(intent: Intent) {
        sessionId = intent.getStringExtra("SESSION")!!
        baseGame = MadridExtension.findByName(intent.getStringExtra("GAME")!!)!!

        Log.i("openpigeon-${baseGame.getName()}", "GodotGameActivity opened with session: $sessionId")
        GameSessionIPC(applicationContext) { gameSessionIPC ->
            this.gameSessionIPC = gameSessionIPC
            val currentMessage = gameSessionIPC.getCurrentMessage(sessionId)
            if (currentMessage.isNotEmpty()) {
                gameSessionIPC.lockMsgHandle(sessionId)
                gameSessionIPC.setSuppressNotifications(sessionId, true)
                Log.i("openpigeon-${baseGame.getName()}", "player: ${currentMessage["player"]!!.toInt()}, replay: ${currentMessage["replay"]}")
                sendGameData(isYourTurn(currentMessage), currentMessage.toMutableMap())

                gameSessionIPC.onMessageUpdated(sessionId) { new: Map<String, String> ->
                    if(isYourTurn(new)) {
                        Log.i(
                            "openpigeon-${baseGame.getName()}",
                            "onMessageUpdated -> isYourTurn: ${isYourTurn(new)}, message: $new"
                        )
                        sendGameData(isYourTurn(new), new.toMutableMap())
                    }
                }
            } else {
                Log.e("openpigeon-${baseGame.getName()}", "$sessionId does not exist!")
                activity?.finish()
            }
        }
    }

    private fun getOrCreateAppPlugin(): GodotAppPlugin {
        if (appPlugin == null) {
            appPlugin = GodotAppPlugin(godot!!, this)
        }
        return appPlugin!!
    }

    private fun isYourTurn(message: Map<String, String>): Boolean {
        return message["sender"]!! != gameSessionIPC!!.getSenderUUID(sessionId)
    }

    private fun sendGameData(isYourTurn: Boolean, message: MutableMap<String, String>) {
        if (message["replay"].isNullOrEmpty()) {
            message["replay"] = baseGame.getDefaultReplay()
        }
        getOrCreateAppPlugin().setGameData(isYourTurn, gameSessionIPC!!.getSenderUUID(sessionId), message)
    }

    override fun getHostPlugins(godot: Godot): Set<GodotPlugin> {
        return setOf(getOrCreateAppPlugin())
    }

    override fun onGodotForceQuit(instance: Godot) {
        runOnUiThread {
            activity?.finish()
        }
        super.onGodotForceQuit(instance)
    }

}