package com.example.openbubblesextension.checkers

import android.os.Bundle
import android.util.Log
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.GameSession
import com.example.openbubblesextension.IGameSession
import com.example.openbubblesextension.MadridExtension
import com.example.openbubblesextension.R
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin


class CheckersActivity : GodotActivity() {
    private var appPlugin: AppPlugin? = null
    var sessionId: String? = null
    var gameSessionIPC: GameSessionIPC? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContentView(R.layout.activity_checkers)
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main)) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }

        sessionId = intent.getStringExtra("SESSION")!!
        Log.i("openpigeon-checkers", "session: $sessionId")

        GameSessionIPC(applicationContext) { gameSessionIPC ->
            this.gameSessionIPC = gameSessionIPC
            val currentMessage = gameSessionIPC.getCurrentMessage(sessionId!!)
            if (currentMessage.isNotEmpty()) {
                Log.i("openpigeon-checkers", "player: ${currentMessage["player"]!!.toInt()}, replay: ${currentMessage["replay"]!!}")
                setReplay(currentMessage["player"]!!.toInt(), currentMessage["replay"]!!)

                gameSessionIPC.onMessageUpdated(sessionId!!) { new: Map<String, String> ->
                    if(new["player"]!!.toInt() == currentMessage["player"]!!.toInt()) {
                        Log.i(
                            "openpigeon-checkers",
                            "onMessageUpdated -> player: ${new["player"]!!.toInt()}, replay: ${new["replay"]!!}"
                        )
                        setReplay(new["player"]!!.toInt(), new["replay"]!!)
                    }
                }
            }
        }
        }

    private fun getOrCreateAppPlugin() {
        if (appPlugin == null) {
            appPlugin = AppPlugin(godot!!, this)
        }
    }

    private fun setReplay(player: Int, replay: String) {
        getOrCreateAppPlugin()
        appPlugin!!.setReplay(player, replay)
    }

    override fun getHostPlugins(godot: Godot): Set<GodotPlugin> {
        getOrCreateAppPlugin()
        return setOf(appPlugin!!)
    }

    override fun onGodotForceQuit(instance: Godot) {
        runOnUiThread {
//            gameSession?.unlock()
            activity?.finish()
        }
        super.onGodotForceQuit(instance)
    }
}