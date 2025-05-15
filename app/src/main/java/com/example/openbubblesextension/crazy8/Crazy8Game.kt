package com.example.openbubblesextension.crazy8

import android.content.Context
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import com.example.openbubblesextension.Cryption
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import com.example.openbubblesextension.godot.GameSessionIPC
import com.example.openbubblesextension.godot.GodotGameActivity
import com.google.android.vending.licensing.util.Base64
import java.util.UUID
import kotlin.random.Random

class Crazy8Game : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "crazy"
    }

    override fun displayName(): String {
        return "CRAZY 8"
    }

    override fun buttonId(): Int {
        return R.id.btn_crazy8
    }

    override fun gameClass(): Class<*> {
        return Crazy8Activity::class.java
    }

    override fun gamePoster(): Int {
        return R.drawable.crazy8thumb
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        var data = super.getNewGameData(context).apply {
            val id = UUID.randomUUID().toString()
            val randBytes = ByteArray(6)
            Random.nextBytes(randBytes)
            var annendum = android.util.Base64.encodeToString(randBytes, android.util.Base64.DEFAULT)
            put("room", "$id${annendum}")
        }
        Log.i("what", data.toString())
        return data
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}