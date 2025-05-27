package com.example.openbubblesextension.wordhunt

import android.content.Context
import androidx.glance.Image
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.layout.Box
import androidx.glance.layout.Row
import androidx.glance.layout.padding
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import com.example.openbubblesextension.RenderConfigOption

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
        val actualContext = context?: LocalContext.current
        val maps = listOf("Map 1", "Map 2", "Map 3", "Map 4")
        val selectedMode = maps[mode - 1]
        val keyboardModeImages = arrayOf(R.drawable.wordhunt_kb_mode1, R.drawable.wordhunt_kb_mode2, R.drawable.wordhunt_kb_mode3, R.drawable.wordhunt_kb_mode4)
        Box(modifier = GlanceModifier.padding(16.dp)) {
            Row(modifier = GlanceModifier.padding(horizontal = 8.dp)) {
                for (image in keyboardModeImages) {
                    Image(ImageProvider(image), "Mode", modifier = GlanceModifier.defaultWeight().padding(horizontal = 8.dp))
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

    override fun gamePoster(): Int {
        return when (mode) {
            1 -> R.drawable.wordhunt
            2 -> R.drawable.wordhunt_2
            3 -> R.drawable.wordhunt_3
            4 -> R.drawable.wordhunt_4
            else -> {R.drawable.empty}
        }
    }

    override fun displayName(): String {
        return "Word Hunt"
    }

    override fun getVersion(): String {
        return "47"
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            put("letters", WordHuntActivity.generateLetterPool(WordHuntActivity.mode(mode)).joinToString(""))
            put("lang", "gp_en2")
            put("avatar2", "body,1|eyes,0|mouth,2|acc,0|wins,65|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,3|stache,0|backdrop,7|hair,0|clothes,3|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021")
            put("mode", "$mode")
        }
    }

    override fun getDefaultReplay(): String {
        TODO("Not yet implemented")
    }
}
