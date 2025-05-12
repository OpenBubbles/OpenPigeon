package com.example.openbubblesextension.godot

import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import com.example.openbubblesextension.Cryption.Rand48
import kotlin.collections.iterator
import kotlin.collections.set


/**
 * Runtime [GodotPlugin] used to enable interaction with the Godot gdscript logic.
 */
class GodotAppPlugin(godot: Godot, private val gameActivity: GodotGameActivity) : GodotPlugin(godot) {
    private var replay = "";
    private var mainLoopStarted = false;
    private var rand48: Rand48 = Rand48(0L)

    companion object {
        val SET_GAME_DATA_SIGNAL = SignalInfo("set_game_data", String::class.java)
    }

    override fun getPluginName() = "AppPlugin"

    override fun getPluginSignals() = setOf(SET_GAME_DATA_SIGNAL)

    override fun onGodotMainLoopStarted() {
        super.onGodotMainLoopStarted()
        mainLoopStarted = true
    }

    @UsedByGodot
    fun onReady() {
        emitSignal(SET_GAME_DATA_SIGNAL.name, this.replay)
    }

    @UsedByGodot
    fun getGameName(): String {
        return gameActivity.baseGame.getName()
    }

    @UsedByGodot
    fun sendReplay(replay: String) {
        Log.d("openpigeon-${gameActivity.baseGame.getName()}", "sendReplay: $replay")
        val gameSessionIPC = gameActivity.gameSessionIPC!!
        val currentMessage = gameSessionIPC.getCurrentMessage(gameActivity.sessionId)

        val updates = mapOf(
            "player" to if (currentMessage["player"] == "2") "1" else "2",
            "replay" to replay,
            "num" to (currentMessage["num"]?.toInt()!! + 1).toString(),
            "sender" to gameSessionIPC.getSenderUUID(gameActivity.sessionId)
        )

        gameActivity.gameSessionIPC!!.updateSession(updates, gameActivity.sessionId) {
            Log.i("openpigeon-${gameActivity.baseGame.getName()}", "Game session updated")
        }
    }

    @UsedByGodot
    fun srand48(seed: Int) {
        rand48.srand(seed)
    }

    @UsedByGodot
    fun drand48(): Double {
        return rand48.drand()
    }

    /**
     * Used to emit a signal to the gdscript logic to update the game board.
     *
     * @param replay Replay string from GP url
     */
    internal fun setGameData(isYourTurn: Boolean, message: MutableMap<String, String>) {
        var turn = if (isYourTurn) 1 else 0
        this.replay = "isYourTurn:$turn;"
        for (data in message) {
            this.replay += "${data.key}:${data.value};"
        }
        this.replay = replay.dropLast(1)
        Log.i("openpigeon-${gameActivity.baseGame.getName()}", "Set game data: ${this.replay}")
        if (mainLoopStarted)
            emitSignal(SET_GAME_DATA_SIGNAL.name, this.replay)
    }
}