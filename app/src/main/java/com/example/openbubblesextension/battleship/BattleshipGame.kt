package com.example.openbubblesextension.battleship

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.layout.Box
import androidx.glance.layout.padding
import com.example.openbubblesextension.Game
import com.example.openbubblesextension.R
import com.example.openbubblesextension.RenderConfigOption
import com.example.openbubblesextension.godot.GodotGameActivity

class BattleshipActivity : GodotGameActivity() {
    override var baseGame: Game = BattleshipGame()
    override var activityLayout: Int = R.layout.activity_checkers
}

class BattleshipGame : Game {
    override fun getVersion(): String {
        return "19"
    }

    override fun getName(): String {
        return "sea"
    }

    override fun displayName(): String {
        return "Sea Battle"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    var battleshipSize = "8x8"

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(this, "Game Mode", listOf("10x10", "9x9", "8x8"), battleshipSize)
        }
    }

    override fun setConfigOption(name: String, value: String) {
        battleshipSize = value
    }

    override fun gameClass(): Class<*> {
        return BattleshipActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.battleship
    }

    override fun getNewGameData(context: Context): MutableMap<String, String> {
        return super.getNewGameData(context).apply {
            put("size", when(battleshipSize) {
                "8x8" -> "8"
                "9x9" -> "9"
                "10x10" -> "10"
                else -> "8"
            })
            put("mode", "1,3,3,0")
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}