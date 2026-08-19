package com.openbubbles.openpigeon.wordgames

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.ImageProvider
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.GameImageChoice
import com.openbubbles.openpigeon.GameNotFound
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderGameChoiceTiles
import com.openbubbles.openpigeon.anagrams.AnagramsGame
import com.openbubbles.openpigeon.wordbites.WordbitesGame
import com.openbubbles.openpigeon.wordhunt.WordHuntGame

class WordGames : Game {
    private val TAG = "WordGames"

    override fun getName(): String {
        return "wordgames"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        RenderGameChoiceTiles(
            title = "Choose Game",
            choices = listOf(
                GameImageChoice(
                    game = AnagramsGame(),
                    label = "Anagrams",
                    image = ImageProvider(R.drawable.anagrams_6l),
                ),
                GameImageChoice(
                    game = WordHuntGame(),
                    label = "Word Hunt",
                    image = ImageProvider(R.drawable.wordhunt),
                ),
                GameImageChoice(
                    game = WordbitesGame(),
                    label = "Word Bites",
                    image = ImageProvider(R.drawable.wordbites),
                ),
            ),
            imageHeight = 74.dp,
        )
    }

    override fun setConfigOption(name: String, value: String) {
    }

    override fun gameClass(): Class<*> {
        return GameNotFound::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.wordgames
    }

    override fun displayName(): String {
        return "Word Games"
    }

    override fun getVersion(): String {
        return "47"
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        return null
    }

    override fun getDefaultReplay(): String {
        return "{}"
    }
}
