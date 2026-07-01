package com.openbubbles.openpigeon.golf

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.openbubbles.openpigeon.ConfigureCallback
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.random.Random
import androidx.compose.ui.unit.sp

class GolfGame : Game {
    companion object {
        private const val TAG = "GolfNative"
        private const val CONFIG_GAME_MODE = "Game Mode"
        private const val MODE_3_HOLES = "3 Holes"
        private const val MODE_5_HOLES = "5 Holes"

        private val forcedNewGameSeedForTesting: Int? = 1849131108
    }

    var holes: Int = 3

    override fun getVersion(): String = "41"
    override fun getName(): String = "golf"
    override fun displayName(): String = "Mini Golf"
    override fun isConfigurable(): Boolean = true

    override fun gameClass(): Class<*> {
        OpenPigeonLog.i(TAG, "GolfGame.gameClass requested")
        return GolfActivity::class.java
    }

    @Composable
    override fun Configuration(context: Context?) {
        context?.let { OpenPigeonLog.installContext(it) }

        val options = listOf(
            3 to MODE_3_HOLES,
            5 to MODE_5_HOLES
        )

        val golfPoleImageProvider = try {
            context?.assets
                ?.open("golf/golf_pole_Normal@3x.png")
                ?.use { stream ->
                    BitmapFactory.decodeStream(stream)
                }
                ?.let { bitmap -> ImageProvider(bitmap) }
                ?: ImageProvider(R.drawable.golf)
        } catch (e: Exception) {
            OpenPigeonLog.w(TAG, "Failed to load golf pole image from assets", e)
            ImageProvider(R.drawable.golf)
        }

        OpenPigeonLog.i(
            TAG,
            "GolfGame.Configuration holes=$holes contextNull=${context == null}"
        )

        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "GAME MODE",
                style = TextStyle(
                    color = ColorProvider(Color.White),
                    fontWeight = FontWeight.Medium
                )
            )

            Spacer(modifier = GlanceModifier.height(10.dp))

            Row(modifier = GlanceModifier.fillMaxWidth()) {
                options.forEach { (holeCount, label) ->
                    val isSelected = holes == holeCount

                    Box(
                        modifier = GlanceModifier
                            .defaultWeight()
                            .padding(horizontal = 8.dp)
                            .clickable(
                                onClick = actionRunCallback<ConfigureCallback>(
                                    actionParametersOf(
                                        ActionParameters.Key<String>("game_name") to getName(),
                                        ActionParameters.Key<String>("configName") to CONFIG_GAME_MODE,
                                        ActionParameters.Key<String>("configVal") to label
                                    )
                                )
                            )
                    ) {
                        Column(
                            modifier = GlanceModifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.Horizontal.CenterHorizontally
                        ) {
                            Text(
                                text = label,
                                style = TextStyle(
                                    color = ColorProvider(
                                        if (isSelected) {
                                            Color.White
                                        } else {
                                            Color(0xFFB8B8B8)
                                        }
                                    ),
                                    fontSize = 17.sp,
                                    fontWeight = if (isSelected) {
                                        FontWeight.Bold
                                    } else {
                                        FontWeight.Medium
                                    }
                                )
                            )

                            Spacer(modifier = GlanceModifier.height(8.dp))

                            Image(
                                provider = golfPoleImageProvider,
                                contentDescription = label,
                                modifier = GlanceModifier.size(38.dp)
                            )
                        }
                    }
                }
            }
        }
    }

    override fun setConfigOption(name: String, value: String) {
        OpenPigeonLog.i(TAG, "GolfGame.setConfigOption name=$name value=$value previousHoles=$holes")

        if (name == CONFIG_GAME_MODE || name == "Holes") {
            holes = when (value) {
                MODE_5_HOLES, "5" -> 5
                MODE_3_HOLES, "3" -> 3
                else -> value.filter { it.isDigit() }.toIntOrNull()?.coerceIn(3, 5) ?: 3
            }
        }

        OpenPigeonLog.i(TAG, "GolfGame.setConfigOption result holes=$holes")
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        OpenPigeonLog.i(TAG, "GolfGame.gamePoster configKeys=${config?.keys?.sorted().orEmpty()}")
        return R.drawable.golf
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        OpenPigeonLog.installContext(context)
        OpenPigeonLog.i(TAG, "GolfGame.getNewGameData enter holes=$holes")

        return super.getNewGameData(context)?.apply {
            val holeText = when (holes) {
                5 -> "5"
                else -> "3"
            }

            put("game", "golf")
            put("game_name", "Mini Golf")
            put("caption", "Let's play Mini Golf!")
            put("subcaption", "$holeText Holes")
            put("version", "41")
            put("v3", "3")
            put("mode", holeText)

            val seedForNewGame = forcedNewGameSeedForTesting ?: Random.nextInt()

            put("seed", seedForNewGame.toString())
            put("num", "1")
            put("player", "2")

            remove("replay")
            remove("replay2")

            get("id")?.trim()?.takeIf { it.isNotBlank() }?.let { put("id", it) }

            OpenPigeonLog.i(
                TAG,
                "GolfGame.getNewGameData output keys=${keys.sorted()} " +
                        "version=${get("version")} v3=${get("v3")} " +
                        "player=${get("player")} player2Blank=${get("player2").isNullOrBlank()} " +
                        "mode=${get("mode")} seed=${get("seed")} num=${get("num")} " +
                        "id='${get("id").orEmpty()}'"
            )
        }
    }

    override fun getDefaultReplay(): String {
        OpenPigeonLog.i(TAG, "GolfGame.getDefaultReplay")
        return ""
    }
}