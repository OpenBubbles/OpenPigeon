package com.openbubbles.openpigeon.knockout

import android.content.Context
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
import kotlin.random.Random

class KnockoutGame : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "knock"
    }

    override fun displayName(): String {
        return "Knockout"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.dots4x4
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            put("mode", "1")
            put("replay", getDefaultReplay())
        }
    }

    override fun getDefaultReplay(): String {
        return "board:" + generateBoardString()
    }

    private fun generateBoardString(): String {
        val pieces = mutableListOf<String>()
        val positionRange = 150.0f // Defines the bounds for random positions, e.g., -150.0 to 150.0

        for (i in 0 until 4) {
            val posX = Random.nextFloat() * 2 * positionRange - positionRange
            val posY = Random.nextFloat() * 2 * positionRange - positionRange
            val player = 1
            val rotation = Random.nextFloat() * 360.0f // Random rotation
            val velX = 0.0f
            val velY = 0.0f
            pieces.add("$posX,$posY,$player,$rotation,$velX,$velY")
        }

        for (i in 0 until 4) {
            val posX = Random.nextFloat() * 2 * positionRange - positionRange
            val posY = Random.nextFloat() * 2 * positionRange - positionRange
            val player = 2
            val rotation = Random.nextFloat() * 360.0f // Random rotation
            val velX = 0.0f
            val velY = 0.0f
            pieces.add("$posX,$posY,$player,$rotation,$velX,$velY")
        }
        println(pieces.joinToString("#"))
        return pieces.joinToString("#")
    }
}
