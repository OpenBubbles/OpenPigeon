package com.example.openbubblesextension.checkers

import android.app.Activity
import android.content.Intent
import android.util.Log
import com.bluebubbles.messaging.ITaskCompleteCallback
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot


/**
 * Runtime [GodotPlugin] used to enable interaction with the Godot gdscript logic.
 */
class AppPlugin(godot: Godot, val intent: Intent, val _activity: Activity) : GodotPlugin(godot) {

    private var replay = "";

    companion object {
        val SET_REPLAY_SIGNAL = SignalInfo("set_replay", String::class.java)
    }

    override fun getPluginName() = "AppPlugin"

    override fun getPluginSignals() = setOf(SET_REPLAY_SIGNAL)

    override fun onGodotMainLoopStarted() {
        Log.i("gamepigeon", "IM READY IM READY");
        emitSignal(SET_REPLAY_SIGNAL.name, replay)
        super.onGodotMainLoopStarted()
    }

    @UsedByGodot
    fun sendReplay(replay: String) {
        Log.d("gamepigeon", "sendReplay: $replay")

        runOnUiThread {
            val gameData = MadridExtension.currentGameData
            val message = MadridExtension.currentMessage
            val handle = MadridExtension.currentMessageHandle
            if (gameData == null || handle == null || message == null) {
                Log.e("gamepigeon", "Data required does not exist!")
                _activity.finish()
            } else {
                gameData.setReplay(replay)
                val newUrl = gameData.nextTurnUrl()

                Log.d("gamepigeon", "New GP Data URL: $newUrl")

                message.url = newUrl

                handle.updateMessage(message, object : ITaskCompleteCallback.Stub() {
                    override fun complete() {
                        Log.i("gamepigeon", "Sent updated game message.")
                        handle.unlock()
                        _activity.finish()
                    }
                })
            }
        }
    }

    /**
     * Used to emit a signal to the gdscript logic to update the game board.
     *
     * @param replay Replay string from GP url
     */
    internal fun setReplay(player: Int, replay: String) {
        this.replay = "player:$player,$replay"
        Log.i("gamepigeon", "Set replay: ${this.replay}")
    }
}