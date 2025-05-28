package com.openbubbles.openpigeon.godot

import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import com.openbubbles.openpigeon.Cryption.Rand48
import org.json.JSONObject
import kotlin.collections.iterator
import kotlin.collections.set


/**
 * Runtime [GodotPlugin] used to enable interaction with the Godot gdscript logic.
 */
class GodotAppPlugin(godot: Godot, private val gameActivity: GodotGameActivity) : GodotPlugin(godot) {
    private var replay = "";
    private var mainLoopStarted = false;
    private var rand48: Map<Int, Rand48> = mapOf(
        1 to Rand48(0L),
        2 to Rand48(0L)
    )

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
    fun getSenderUUID(): String {
        val gameSessionIPC = gameActivity.gameSessionIPC!!
        return gameSessionIPC.getSenderUUID(gameActivity.sessionId)
    }

    @UsedByGodot
    fun updateGameData(updates: String) {
        Log.d("openpigeon-${gameActivity.baseGame.getName()}", "updateGameData: $updates")
        val gameSessionIPC = gameActivity.gameSessionIPC!!
        val currentMessage = gameSessionIPC.getCurrentMessage(gameActivity.sessionId)

        val msgUpdates = mapOf(
            "player" to if (currentMessage["player"] == "2") "1" else "2",
            "num" to (currentMessage["num"]?.toInt()!! + 1).toString(),
            "sender" to gameSessionIPC.getSenderUUID(gameActivity.sessionId)
        ).toMutableMap()

        val parsed = JSONObject(updates)
        for (update in parsed.keys()) {
            msgUpdates[update] = parsed.getString(update)
        }

        gameActivity.gameSessionIPC!!.updateSession(msgUpdates, gameActivity.sessionId) {
            Log.i("openpigeon-${gameActivity.baseGame.getName()}", "Game session updated")
        }
    }

    @UsedByGodot
    fun srand48(player: Int, seed: Int) {
        rand48[player]!!.srand(seed)
    }

    @UsedByGodot
    fun drand48(player: Int): Double {
        return rand48[player]!!.drand()
    }

    /**
     * Used to emit a signal to the gdscript logic to update the game board.
     *
     * @param replay Replay string from GP url
     */
    internal fun setGameData(isYourTurn: Boolean, message: MutableMap<String, String>) {
        replay = JSONObject().apply {
            put("isYourTurn", isYourTurn)
            for (data in message) {
                put(data.key, data.value)
            }
        }.toString()

        Log.i("openpigeon-${gameActivity.baseGame.getName()}", "Set game data: ${this.replay}")
        if (mainLoopStarted)
            emitSignal(SET_GAME_DATA_SIGNAL.name, this.replay)
    }
}