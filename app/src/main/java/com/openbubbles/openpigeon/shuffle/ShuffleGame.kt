package com.openbubbles.openpigeon.shuffle

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.layout.Box
import androidx.glance.layout.padding
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import kotlin.random.Random

class ShuffleGame : Game {
    override fun getVersion(): String {
        return "0"
    }

    override fun getName(): String {
        return "shuffle"
    }

    override fun displayName(): String {
        return "Shuffleboard"
    }

    override fun isConfigurable(): Boolean {
        return true
    }

    private var boardMode = "1"

    @Composable
    override fun Configuration(
        context: Context?,
    ) {
        Box(modifier = GlanceModifier.padding(16.dp)) {
            RenderConfigOption(
                this,
                "Board",
                listOf("1", "2", "3"),
                boardMode
            )
        }
    }

    override fun setConfigOption(name: String, value: String) {
        when (name.lowercase()) {
            "board" -> boardMode = value
        }
    }

    override fun gameClass(): Class<*> {
        return ShuffleActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.shuffle
    }

    override fun getNewGameData(
        context: Context,
    ): MutableMap<String, String>? {
        AvatarData.init(context)

        val selectedMode =
            boardMode
                .toIntOrNull()
                ?.coerceIn(1, 3)
                ?: 1

        return super.getNewGameData(context)?.apply {
            put(
                "mode",
                selectedMode.toString(),
            )

            put(
                "map",
                generateMapForMode(selectedMode),
            )

            put("num", "1")
            remove("replay")

            put(
                "avatar2",
                AvatarView.buildAvatarString(),
            )
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }

    private fun generateMapForMode(mode: Int): String {
        return when (mode) {
            1 -> generateRandomMap(MODE_1_SCORE_POOL, 12)
            2 -> generateRandomMap(MODE_2_SCORE_POOL, 16)
            3 -> generateRandomMap(MODE_3_SCORE_POOL, 21)
            else -> generateRandomMap(MODE_1_SCORE_POOL, 12)
        }
    }

    private fun generateRandomMap(
        scorePool: List<Int>,
        count: Int
    ): String {
        return List(count) {
            scorePool[Random.nextInt(scorePool.size)]
        }.joinToString(",")
    }

    private companion object {
        private val MODE_1_SCORE_POOL = listOf(
            2, 3, 4, 5, 6, 7, 8, 10
        )

        private val MODE_2_SCORE_POOL = listOf(
            2, 3, 4, 5, 6, 7, 8, 10
        )

        private val MODE_3_SCORE_POOL = listOf(
            2, 3, 4, 5, 6, 7, 8, 10
        )

        private const val DEFAULT_REPLAY =
            "board:0,0#" +
                    "0.000000,-215.000000,1,0.000000,0.000000,0.000000#" +
                    "0.000000,215.000000,2,0.000000,0.000000,0.000000#"
    }
}