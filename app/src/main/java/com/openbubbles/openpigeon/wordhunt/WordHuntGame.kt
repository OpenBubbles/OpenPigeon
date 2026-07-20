package com.openbubbles.openpigeon.wordhunt

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.height
import androidx.glance.layout.padding
import com.openbubbles.openpigeon.ConfigureCallback
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.wordgames.WordGameLanguages
import androidx.glance.layout.fillMaxWidth

class WordHuntGame : Game {

    var mode = 1

    var language: String
        get() =
            WordGameLanguages.selectedOptionLabel

        set(value) {
            WordGameLanguages.select(value)
        }

    override fun getName(): String {
        return "hunt"
    }

    override fun displayName(): String {
        return "Word Hunt"
    }

    override fun getVersion(): String {
        return "48"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        val maps = listOf(
            "Map 1",
            "Map 2",
            "Map 3",
            "Map 4",
        )

        val keyboardModeImages = arrayOf(
            R.drawable.wordhunt_kb_mode1,
            R.drawable.wordhunt_kb_mode2,
            R.drawable.wordhunt_kb_mode3,
            R.drawable.wordhunt_kb_mode4,
        )

        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .padding(
                    horizontal = 12.dp,
                    vertical = 6.dp,
                ),
        ) {
            /*
             * The images are the map selector. Do not render another
             * RenderConfigOption for Map underneath them.
             */
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
            ) {
                keyboardModeImages.forEachIndexed { index, image ->
                    Image(
                        provider = ImageProvider(image),
                        contentDescription = maps[index],
                        modifier = GlanceModifier
                            .defaultWeight()
                            .height(70.dp)
                            .padding(horizontal = 4.dp)
                            .clickable(
                                onClick = actionRunCallback<
                                        ConfigureCallback
                                        >(
                                    actionParametersOf(
                                        ActionParameters.Key<String>(
                                            "game_name",
                                        ) to getName(),
                                        ActionParameters.Key<String>(
                                            "configName",
                                        ) to "Map",
                                        ActionParameters.Key<String>(
                                            "configVal",
                                        ) to maps[index],
                                    ),
                                ),
                            ),
                    )
                }
            }

            Spacer(
                modifier = GlanceModifier.height(4.dp),
            )

            RenderConfigOption(
                game = this@WordHuntGame,
                name = "Language",
                options = WordGameLanguages.configurationOptions,
                selected = language,
            )
        }
    }

    override fun setConfigOption(
        name: String,
        value: String,
    ) {
        when (name.lowercase()) {
            "map" -> {
                mode = value
                    .takeLast(1)
                    .toIntOrNull()
                    ?.coerceIn(1, 4)
                    ?: 1
            }

            "language" -> {
                language = WordGameLanguages
                    .fromSelection(value)
                    .optionLabel
            }

            else -> {
                println(
                    "Warning: unknown Word Hunt config option '$name'",
                )
            }
        }

        println(
            "Word Hunt config '$name' set to '$value'",
        )
    }

    override fun gameClass(): Class<*> {
        return WordHuntActivity::class.java
    }

    override fun gamePoster(
        config: Map<String, String>?,
    ): Int {
        return when (config?.get("mode")) {
            "1", null -> R.drawable.wordhunt
            "2" -> R.drawable.wordhunt_2
            "3" -> R.drawable.wordhunt_3
            "4" -> R.drawable.wordhunt_4
            else -> R.drawable.empty
        }
    }

    override fun getNewGameData(
        context: Context,
    ): MutableMap<String, String>? {
        val selectedLanguage =
            WordGameLanguages.fromSelection(language)

        val selectedMode =
            WordHuntActivity.mode(mode)

        val letters =
            WordHuntActivity.generateLetterPool(
                context = context,
                mode = selectedMode,
                language = selectedLanguage,
            ).joinToString("")

        return super.getNewGameData(context)?.apply {
            WordGameLanguages.applyToGameData(
                gameData = this,
                language = selectedLanguage,
            )

            put("letters", letters)
            put("mode", mode.toString())
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}