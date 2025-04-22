package com.example.openbubblesextension.checkers

import android.os.Bundle
import android.util.Log
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.example.openbubblesextension.GameSession
import com.example.openbubblesextension.MadridExtension
import com.example.openbubblesextension.R
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin


class CheckersActivity : GodotActivity() {
    private var appPlugin: AppPlugin? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContentView(R.layout.activity_checkers)
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main)) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }

        val sessionId: String = intent.getStringExtra("SESSION")!!
        val currentMessage = MadridExtension.activeSessions[sessionId]!!.currentMessage
        setReplay(currentMessage["player"]!!.toInt(), currentMessage["replay"]!!)
    }

    private fun getOrCreateAppPlugin() {
        if (appPlugin == null) {
            appPlugin = AppPlugin(godot!!, intent, this)
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
            activity!!.finish()
        }
        super.onGodotForceQuit(instance)
    }
}