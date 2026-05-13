package com.openbubbles.openpigeon.anagrams

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.layout.Box
import androidx.glance.layout.padding
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView

class AnagramsGame : Game {
    var mode = "6 Letters" // "6 Letters" or "7 Letters"

    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "anagrams"
    }

    override fun displayName(): String {
        return "Anagrams"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Game Mode", listOf("6 Letters", "7 Letters"), mode)
        }
    }

    override fun setConfigOption(name: String, value: String) {
        when (name.lowercase()) {
            "game mode" -> mode = value
            else -> {
                println("Warning: unknown config option ‘$name’")
            }
        }
        println("Config option '$name' set to '$value'")
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        val mode = config?.get("mode")
        return when (mode) {
            "6 Letters" -> R.drawable.anagrams_6l
            "7 Letters" -> R.drawable.anagrams_7l
            else -> {R.drawable.anagrams_6l}
        }
    }

    /**
     * Generate a 6- or 7-letter *word* and shuffle its letters.
     * Uses the same dictionary as Godot: gp_wg_en2.txt
     */
    private fun generateStartingLetters(
        context: Context,
        letterCount: Int
    ): String {
        require(letterCount == 6 || letterCount == 7)

        val candidates = mutableListOf<String>()

        // Load from res/raw instead of assets
        context.resources.openRawResource(R.raw.gp_en2).bufferedReader().useLines { lines ->
            lines.forEach { line ->
                val w = line.trim().uppercase()
                if (w.length == letterCount) {
                    candidates.add(w)
                }
            }
        }

        if (candidates.isEmpty()) {
            // Emergency fallback
            val fallback = CharArray(letterCount) { ('A'..'Z').random() }
            return String(fallback)
        }

        val baseWord = candidates.random()
        val chars = baseWord.toCharArray().toMutableList()

        var shuffled = baseWord
        repeat(10) {
            chars.shuffle()
            shuffled = chars.joinToString("")
            if (shuffled != baseWord) return@repeat
        }

        return shuffled
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)
        return super.getNewGameData(context)?.apply {
            put("lang", "en")
            put("mode", mode)

            // Decide 6 vs 7 letters based on the selected mode string
            val letterCount = if (mode.contains("7")) 7 else 6

            // Generate starting letters from a real word
            val letters = generateStartingLetters(context, letterCount)
            put("letters", letters)
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}