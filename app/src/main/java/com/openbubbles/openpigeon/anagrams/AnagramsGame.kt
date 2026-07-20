package com.openbubbles.openpigeon.anagrams

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.layout.padding
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.height
import com.openbubbles.openpigeon.wordgames.WordGameLanguage
import com.openbubbles.openpigeon.wordgames.WordGameLanguages

class AnagramsGame : Game {
    var mode = "6 Letters" // "6 Letters" or "7 Letters"
    var language: String
        get() =
            WordGameLanguages.selectedOptionLabel

        set(value) {
            WordGameLanguages.select(value)
        }

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
        Column(
            modifier = GlanceModifier.padding(16.dp),
        ) {
            RenderConfigOption(
                this@AnagramsGame,
                "Game Mode",
                listOf("6 Letters", "7 Letters"),
                mode,
            )

            Spacer(
                modifier = GlanceModifier.height(12.dp),
            )

            RenderConfigOption(
                this@AnagramsGame,
                "Language",
                WordGameLanguages.configurationOptions,
                language,
            )
        }
    }

    override fun setConfigOption(
        name: String,
        value: String,
    ) {
        when (name.lowercase()) {
            "game mode" -> {
                mode = value
            }

            "language" -> {
                language = WordGameLanguages
                    .fromSelection(value)
                    .optionLabel
            }

            else -> {
                println("Warning: unknown config option '$name'")
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

    private fun generateStartingLetters(
        context: Context,
        letterCount: Int,
        selectedLanguage: WordGameLanguage,
    ): String {
        require(letterCount == 6 || letterCount == 7)

        val candidates = WordGameLanguages
            .loadDictionary(context, selectedLanguage)
            .filter { word ->
                word.length == letterCount
            }

        if (candidates.isEmpty()) {
            return WordGameLanguages.randomLetters(
                language = selectedLanguage,
                count = letterCount,
            )
        }

        val baseWord = candidates.random()
        var shuffled = baseWord

        repeat(10) {
            shuffled = baseWord
                .toList()
                .shuffled()
                .joinToString("")

            if (shuffled != baseWord) {
                return shuffled
            }
        }

        return shuffled
    }

    override fun getNewGameData(
        context: Context,
    ): MutableMap<String, String>? {
        AvatarData.init(context)

        val selectedLanguage =
            WordGameLanguages.fromSelection(language)

        val letterCount =
            if (mode.contains("7")) 7 else 6

        val letters = generateStartingLetters(
            context = context,
            letterCount = letterCount,
            selectedLanguage = selectedLanguage,
        )

        return super.getNewGameData(context)?.apply {
            WordGameLanguages.applyToGameData(
                gameData = this,
                language = selectedLanguage,
            )

            put("mode", mode)
            put("letters", letters)
            put(
                "avatar2",
                AvatarView.buildAvatarString(),
            )
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}