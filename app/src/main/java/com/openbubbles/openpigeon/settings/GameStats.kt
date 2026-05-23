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
}