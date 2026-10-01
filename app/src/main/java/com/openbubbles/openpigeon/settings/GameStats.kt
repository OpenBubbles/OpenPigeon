package com.openbubbles.openpigeon.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

object GameStats {
    private const val PREFS_NAME = "game_stats"

    private lateinit var appContext: Context

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    private fun prefs(): SharedPreferences =
        appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getWins(gameName: String): Int =
        prefs().getInt("wins/$gameName", 0)

    fun incrementWins(gameName: String) {
        val current = getWins(gameName)
        prefs().edit { putInt("wins/$gameName", current + 1) }
    }


    private const val VS_PREFS_NAME = "game_stats_vs"

    data class Record(val game: String, val opponent: String, val wins: Int, val losses: Int, val draws: Int, val lastPlayed: Long, val streak: Int = 0, val bestStreak: Int = 0)

    private fun vsPrefs(): SharedPreferences =
        appContext.getSharedPreferences(VS_PREFS_NAME, Context.MODE_PRIVATE)

    private fun parseRecord(key: String, value: String?): Record? {
        val parts = key.split("|", limit = 2)
        if (parts.size != 2 || value == null) return null
        val n = value.split(",").map { it.toLongOrNull() ?: 0L }
        return Record(parts[0], parts[1], n.getOrElse(0) { 0 }.toInt(), n.getOrElse(1) { 0 }.toInt(), n.getOrElse(2) { 0 }.toInt(), n.getOrElse(3) { 0 }, n.getOrElse(4) { 0 }.toInt(), n.getOrElse(5) { 0 }.toInt())
    }

    fun getRecord(gameName: String, opponent: String): Record =
        parseRecord("$gameName|$opponent", vsPrefs().getString("$gameName|$opponent", "0,0,0,0"))!!

    // result: 1 = win, -1 = loss, 0 = draw
    fun recordResult(gameName: String, opponent: String, result: Int, opponentAvatar: String?) {
        val r = getRecord(gameName, opponent)
        val streak = when (result) { 1 -> maxOf(r.streak, 0) + 1; -1 -> minOf(r.streak, 0) - 1; else -> 0 }
        vsPrefs().edit {
            putString("$gameName|$opponent", listOf(r.wins + if (result == 1) 1 else 0, r.losses + if (result == -1) 1 else 0, r.draws + if (result == 0) 1 else 0, System.currentTimeMillis() / 1000, streak, maxOf(r.bestStreak, streak)).joinToString(","))
            if (!opponentAvatar.isNullOrBlank()) putString("avatar|$opponent", opponentAvatar)
        }
    }

    fun allRecords(): List<Record> =
        vsPrefs().all.mapNotNull { (k, v) -> if (k.startsWith("avatar|") || k.startsWith("name|")) null else parseRecord(k, v as? String) }

    fun allWins(): Map<String, Int> =
        prefs().all.filterKeys { it.startsWith("wins/") }.mapKeys { it.key.removePrefix("wins/") }.mapValues { it.value as? Int ?: 0 }

    fun opponentAvatar(opponent: String): String? = vsPrefs().getString("avatar|$opponent", null)

    fun opponentName(opponent: String): String? = vsPrefs().getString("name|$opponent", null)

    fun setOpponentName(opponent: String, name: String) =
        vsPrefs().edit { if (name.isBlank()) remove("name|$opponent") else putString("name|$opponent", name.trim().take(24)) }

    fun clearAll() {
        prefs().edit { clear() }
        vsPrefs().edit { clear() }
    }
}