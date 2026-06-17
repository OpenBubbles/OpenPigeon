package com.openbubbles.openpigeon.godot

import com.openbubbles.openpigeon.util.OpenPigeonLog
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
        val SWITCH_GAME_SIGNAL = SignalInfo("switch_game", String::class.java)
    }

    init {
        installLogContext()
    }

    private fun installLogContext() {
        OpenPigeonLog.installContext(gameActivity.applicationContext)
    }

    override fun getPluginName() = "AppPlugin"

    override fun getPluginSignals() = setOf(SET_GAME_DATA_SIGNAL, SWITCH_GAME_SIGNAL)

    @UsedByGodot
    fun godotLog(level: String, tag: String, message: String) {
        installLogContext()
        OpenPigeonLog.godotLog(level, tag, message)
    }

    @UsedByGodot
    fun godotEvent(tag: String, message: String) {
        installLogContext()
        OpenPigeonLog.godotEvent(tag, message)
    }

    @UsedByGodot
    fun godotD(tag: String, message: String) {
        installLogContext()
        OpenPigeonLog.godotD(tag, message)
    }

    @UsedByGodot
    fun godotI(tag: String, message: String) {
        installLogContext()
        OpenPigeonLog.godotI(tag, message)
    }

    @UsedByGodot
    fun godotW(tag: String, message: String) {
        installLogContext()
        OpenPigeonLog.godotW(tag, message)
    }

    @UsedByGodot
    fun godotE(tag: String, message: String) {
        installLogContext()
        OpenPigeonLog.godotE(tag, message)
    }

    @UsedByGodot
    fun log(level: String, tag: String, message: String) {
        godotLog(level, tag, message)
    }

    @UsedByGodot
    fun event(tag: String, message: String) {
        godotEvent(tag, message)
    }

    @UsedByGodot
    fun d(tag: String, message: String) {
        godotD(tag, message)
    }

    @UsedByGodot
    fun i(tag: String, message: String) {
        godotI(tag, message)
    }

    @UsedByGodot
    fun w(tag: String, message: String) {
        godotW(tag, message)
    }

    @UsedByGodot
    fun e(tag: String, message: String) {
        godotE(tag, message)
    }

    override fun onGodotMainLoopStarted() {
        super.onGodotMainLoopStarted()
        mainLoopStarted = true
    }

    @UsedByGodot
    fun switchGame(game: String) {
        emitSignal("switch_game", game)
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
        OpenPigeonLog.d("openpigeon-${gameActivity.baseGame.getName()}", "updateGameData: $updates")
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
            OpenPigeonLog.i("openpigeon-${gameActivity.baseGame.getName()}", "Game session updated")
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
    internal fun setGameData(isYourTurn: Boolean, myPlayerId: String, message: MutableMap<String, String>) {
        replay = JSONObject().apply {
            put("isYourTurn", isYourTurn)
            put("myPlayerId", myPlayerId)
            for (data in message) {
                put(data.key, data.value)
            }
        }.toString()

        OpenPigeonLog.i("openpigeon-${gameActivity.baseGame.getName()}", "Set game data: ${this.replay}")
        if (mainLoopStarted)
            emitSignal(SET_GAME_DATA_SIGNAL.name, this.replay)
    }
}