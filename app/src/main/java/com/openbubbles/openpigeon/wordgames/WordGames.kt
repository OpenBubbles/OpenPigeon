package com.openbubbles.openpigeon.wordgames

import android.content.Context
import com.openbubbles.openpigeon.util.OpenPigeonLog
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.layout.Box
import androidx.glance.layout.Row
import androidx.glance.layout.Column
import androidx.glance.layout.padding
import androidx.glance.layout.height
import androidx.glance.layout.Alignment
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.compose.ui.graphics.Color
import com.openbubbles.openpigeon.ChooseGameCallback
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.GameNotFound
import com.openbubbles.openpigeon.R
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
    override fun Configuration(context: Context?) {
        OpenPigeonLog.d(TAG, "Configuration() composable ENTER")

        val choices = listOf(
            GameChoice(
                game = AnagramsGame(),
                label = "Anagrams",
                previewRes = R.drawable.anagrams_6l
            ),
            GameChoice(
                game = WordHuntGame(),
                label = "Word Hunt",
                previewRes = R.drawable.wordhunt
            ),
            GameChoice(
                game = WordbitesGame(),
                label = "Word Bites",
                previewRes = R.drawable.wordbites
            ),
        )

        Box(modifier = GlanceModifier.padding(16.dp)) {
            Row(modifier = GlanceModifier.padding(horizontal = 8.dp)) {
                choices.forEach { choice ->
                    OpenPigeonLog.d(
                        TAG,
                        "Rendering choice: gameName=${choice.game.getName()}, label=${choice.label}"
                    )

                    Box(
                        modifier = GlanceModifier
                            .defaultWeight()
                            .padding(horizontal = 8.dp)
                            .clickable(
                                onClick = actionRunCallback<ChooseGameCallback>(
                                    actionParametersOf(
                                        ActionParameters.Key<String>("game_name") to choice.game.getName()
                                    )
                                )
                            )
                    ) {
                        Column(
                            modifier = GlanceModifier.padding(vertical = 4.dp),
                            horizontalAlignment = Alignment.Horizontal.CenterHorizontally
                        ) {
                            Image(
                                provider = ImageProvider(choice.previewRes),
                                contentDescription = choice.label,
                                modifier = GlanceModifier
                                    .height(100.dp)
                                    .cornerRadius(8.dp)
                            )
                            Text(
                                text = choice.label,
                                style = TextStyle(
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = ColorProvider(Color.White)
                                ),
                                modifier = GlanceModifier.padding(top = 4.dp)
                            )
                        }
                    }
                }
            }
        }

        OpenPigeonLog.d(TAG, "Configuration() composable EXIT")
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

    private data class GameChoice(
        val game: Game,
        val label: String,
        val previewRes: Int,
    )
}
