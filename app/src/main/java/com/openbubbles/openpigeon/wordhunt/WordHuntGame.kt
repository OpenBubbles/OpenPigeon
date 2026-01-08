package com.openbubbles.openpigeon.wordhunt

import android.content.Context
import androidx.glance.Image
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.layout.Box
import androidx.glance.layout.Row
import androidx.glance.layout.padding
import com.openbubbles.openpigeon.ConfigureCallback
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption

class WordHuntGame : Game {
    var mode = 1 // Mode 1: 4x4, Mode 2: 5x5 circle shape, Mode 3: 5x5 X shape, Mode 4: 5x5
    override fun getName(): String {
        return "hunt"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        val maps = listOf("Map 1", "Map 2", "Map 3", "Map 4")
        val selectedMode = maps[mode - 1]
        val keyboardModeImages = arrayOf(R.drawable.wordhunt_kb_mode1, R.drawable.wordhunt_kb_mode2, R.drawable.wordhunt_kb_mode3, R.drawable.wordhunt_kb_mode4)
        Box(modifier = GlanceModifier.padding(16.dp)) {
            Row(modifier = GlanceModifier.padding(horizontal = 8.dp)) {
                keyboardModeImages.forEachIndexed { index, image ->
                    Image(
                        ImageProvider(image),
                        "Mode",
                        modifier = GlanceModifier
                            .defaultWeight()
                            .padding(horizontal = 8.dp)
                            .clickable(onClick = actionRunCallback<ConfigureCallback>(
                                actionParametersOf(
                                    ActionParameters.Key<String>("game_name") to getName(),
                                    ActionParameters.Key<String>("configName") to "Map",
                                    ActionParameters.Key<String>("configVal") to maps[index]))
                            )
                    )
                }
            }
            RenderConfigOption(this, "Map", maps, selectedMode)
        }
    }

    override fun setConfigOption(name: String, value: String) {
        mode = value.takeLast(1).toInt()
    }

    override fun gameClass(): Class<*> {
        return WordHuntActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        val mode = config?.get("mode")
        return when (mode) {
            "1" -> R.drawable.wordhunt
            null -> R.drawable.wordhunt
            "2" -> R.drawable.wordhunt_2
            "3" -> R.drawable.wordhunt_3
            "4" -> R.drawable.wordhunt_4
            else -> {R.drawable.empty}
        }
    }

    override fun displayName(): String {
        return "Word Hunt"
    }

    override fun getVersion(): String {
        return "47"
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        return super.getNewGameData(context)?.apply {
            put("letters", WordHuntActivity.generateLetterPool(WordHuntActivity.mode(mode)).joinToString(""))
            put("lang", "gp_en2")
            put("mode", "$mode")
        }
    }

    override fun getDefaultReplay(): String {
        TODO("Not yet implemented")
    }
}
