package com.example.openbubblesextension.checkers

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import com.bluebubbles.messaging.ITaskCompleteCallback
import com.example.openbubblesextension.GameSession
import com.example.openbubblesextension.MadridExtension
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot


/**
 * Runtime [GodotPlugin] used to enable interaction with the Godot gdscript logic.
 */
class AppPlugin(godot: Godot, private val _activity: CheckersActivity) : GodotPlugin(godot) {
    private var replay = "";
    private var mainLoopStarted = false;

    companion object {
        val SET_REPLAY_SIGNAL = SignalInfo("set_replay", String::class.java)
    }

    override fun getPluginName() = "AppPlugin"

    override fun getPluginSignals() = setOf(SET_REPLAY_SIGNAL)

    override fun onGodotMainLoopStarted() {
        mainLoopStarted = true
        emitSignal(SET_REPLAY_SIGNAL.name, replay)
        super.onGodotMainLoopStarted()
    }

    @UsedByGodot
    fun sendReplay(replay: String) {
        Log.d("openpigeon-checkers", "sendReplay: $replay")
        val gameSessionIPC = _activity.gameSessionIPC!!
        val currentMessage = gameSessionIPC.getCurrentMessage(_activity.sessionId!!)

        val updates = mapOf(
            "player" to if (currentMessage["player"] == "2") "1" else "2",
            "replay" to replay,
            "num" to (currentMessage["num"]?.toInt()!! + 1).toString()
        )

        _activity.gameSessionIPC!!.updateSession(updates, _activity.sessionId!!) {
            Log.i("openpigeon-checkers", "Game session updated")
        }
    }

    /**
     * Used to emit a signal to the gdscript logic to update the game board.
     *
     * @param replay Replay string from GP url
     */
    internal fun setReplay(player: Int, replay: String) {
        this.replay = "player:$player,$replay"
        Log.i("openpigeon-checkers", "Set replay: ${this.replay}")
        if (mainLoopStarted)
            emitSignal(SET_REPLAY_SIGNAL.name, replay)
    }
}