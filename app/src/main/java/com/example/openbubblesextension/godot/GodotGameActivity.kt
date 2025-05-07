package com.example.openbubblesextension.godot

import android.os.Bundle
import android.util.Log
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.GameSession
import com.example.openbubblesextension.R
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin

abstract class GodotGameActivity : GodotActivity() {
    abstract var baseGame: Game
    abstract var activityLayout: Int

    lateinit var sessionId: String
    var appPlugin: GodotAppPlugin? = null
    var gameSessionIPC: GameSessionIPC? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContentView(activityLayout)
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main)) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }

        sessionId = intent.getStringExtra("SESSION")!!

        Log.i("openpigeon-${baseGame.getName()}", "GodotGameActivity opened with session: $sessionId")
        GameSessionIPC(applicationContext) { gameSessionIPC ->
            this.gameSessionIPC = gameSessionIPC
            val currentMessage = gameSessionIPC.getCurrentMessage(sessionId)
            if (currentMessage.isNotEmpty()) {
                gameSessionIPC.lockMsgHandle(sessionId)
                gameSessionIPC.setSuppressNotifications(sessionId, true)
                Log.i("openpigeon-${baseGame.getName()}", "CRINGE!!! ${currentMessage}")
                Log.i("openpigeon-${baseGame.getName()}", "player: ${currentMessage["player"]!!.toInt()}, replay: ${currentMessage["replay"]}")
                setReplay(isYourTurn(currentMessage), currentMessage["player"]!!.toInt(), currentMessage["replay"])

                gameSessionIPC.onMessageUpdated(sessionId) { new: Map<String, String> ->
                    if(new["player"]!!.toInt() == currentMessage["player"]!!.toInt()) {
                        Log.i(
                            "openpigeon-${baseGame.getName()}",
                            "onMessageUpdated -> isYourTurn: ${isYourTurn(new)}, player: ${new["player"]!!.toInt()}, replay: ${new["replay"]}"
                        )
                        setReplay(isYourTurn(new), new["player"]!!.toInt(), new["replay"])
                    }
                }
            } else {
                Log.e("openpigeon-${baseGame.getName()}", "$sessionId does not exist!")
                activity?.finish()
            }
        }
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

    override fun onDestroy() {
        gameSessionIPC!!.setSuppressNotifications(sessionId, false)
        gameSessionIPC!!.unlockMsgHandle(sessionId)
        super.onDestroy()
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

    private fun setReplay(isYourTurn: Boolean, player: Int, replay: String?) {
        if (replay.isNullOrEmpty()) {
            getOrCreateAppPlugin().setReplay(isYourTurn, player, baseGame.getDefaultReplay())
        } else {
            getOrCreateAppPlugin().setReplay(isYourTurn, player, replay)
        }
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