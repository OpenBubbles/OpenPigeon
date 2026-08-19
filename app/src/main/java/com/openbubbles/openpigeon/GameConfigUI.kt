@file:Suppress("RestrictedApi")

package com.openbubbles.openpigeon

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import android.os.Parcel
import com.bluebubbles.messaging.MadridMessage
import com.openbubbles.openpigeon.util.OpenPigeonLog
import java.util.Locale

internal val gameName = ActionParameters.Key<String>("game_name")
internal val configName = ActionParameters.Key<String>("configName")
internal val configVal = ActionParameters.Key<String>("configVal")

internal fun logGameDataSize(
    source: String,
    game: Game,
    data: Map<String, String>,
) {
    val fieldSizes = data.entries
        .map { entry ->
            entry.key to entry.value.toByteArray(Charsets.UTF_8).size
        }
        .sortedByDescending { it.second }

    val totalBytes = fieldSizes.sumOf { it.second }

    val largestFields = fieldSizes
        .take(10)
        .joinToString(", ") { "${it.first}=${it.second}B" }

    OpenPigeonLog.i(
        "MadridSize",
        "$source game=${game.getName()} " +
                "dataFields=${data.size} " +
                "dataUtf8Bytes=$totalBytes " +
                "largest=[$largestFields]"
    )
}

internal fun logMadridMessageSize(
    source: String,
    game: Game,
    message: MadridMessage,
) {
    val parcel = Parcel.obtain()

    try {
        message.writeToParcel(parcel, 0)

        val bytes = parcel.dataSize()
        val kib = bytes / 1024f

        OpenPigeonLog.i(
            "MadridSize",
            "$source game=${game.getName()} " +
                    "parcelBytes=$bytes " +
                    "parcelKiB=${String.format(Locale.US, "%.1f", kib)}"
        )
    } catch (t: Throwable) {
        OpenPigeonLog.e(
            "MadridSize",
            "$source game=${game.getName()} unable to measure MadridMessage",
            t
        )
    } finally {
        parcel.recycle()
    }
}

private val CONFIG_SECTION_BACKGROUND = Color(0xFF151517)
private val CONFIG_OPTION_BACKGROUND = Color(0xFF202023)
private val CONFIG_OPTION_SELECTED_BACKGROUND = Color(0xFF3A3A3C)

private val CONFIG_TITLE_COLOR = Color(0xFF9A9A9E)
private val CONFIG_OPTION_COLOR = Color(0xFFB8B8BC)
private val CONFIG_OPTION_SELECTED_COLOR = Color.White

data class ConfigImageOption(
    val label: String,
    val image: ImageProvider,
    val value: String = label,
)

data class GameImageChoice(
    val game: Game,
    val image: ImageProvider,
    val label: String = game.displayName(),
)

class ConfigureCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val game = parameters[gameName]
            ?.let { MadridExtension.findByName(it) }
            ?: return

        val name = parameters[configName] ?: return
        val value = parameters[configVal] ?: return

        OpenPigeonLog.i(
            "MadridSize",
            "CONFIG_CLICK game=${game.getName()} option=$name value=$value"
        )

        game.setConfigOption(name, value)

        val gameData = game.getNewGameData(context) ?: return

        logGameDataSize(
            source = "CONFIG_DATA",
            game = game,
            data = gameData,
        )

        val message = game.buildGameMessage(
            context,
            gameData,
            null,
        )

        logMadridMessageSize(
            source = "CONFIG_MESSAGE",
            game = game,
            message = message,
        )

        MadridExtension.currentKeyboardHandle?.addMessage(message)

        if (game.isConfigurable()) {
            MadridExtensionService.extension?.updateKeyboard()
        }
    }
}

@Composable
fun RenderConfigOption(
    game: Game,
    name: String,
    options: List<String>,
    selected: String,
) {
    if (options.isEmpty()) return

    val columns = configColumnCount(options.size)
    val rows = options.chunked(columns)

    Column(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 5.dp),
    ) {
        RenderConfigSectionTitle(name)

        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(CONFIG_SECTION_BACKGROUND)
                .cornerRadius(9.dp)
                .padding(3.dp),
        ) {
            rows.forEachIndexed { rowIndex, rowOptions ->
                RenderConfigOptionRow(
                    game = game,
                    name = name,
                    options = rowOptions,
                    selected = selected,
                    totalOptionCount = options.size,
                )

                if (rowIndex < rows.lastIndex) {
                    Spacer(modifier = GlanceModifier.height(3.dp))
                }
            }
        }
    }
}

@Composable
private fun RenderConfigOptionRow(
    game: Game,
    name: String,
    options: List<String>,
    selected: String,
    totalOptionCount: Int,
) {
    val fontSize = if (totalOptionCount >= 5) 14.sp else 16.sp

    Row(
        modifier = GlanceModifier.fillMaxWidth(),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        options.forEach { option ->
            val isSelected = option == selected

            Box(
                modifier = GlanceModifier
                    .defaultWeight()
                    .padding(horizontal = 2.dp, vertical = 1.dp)
                    .background(
                        if (isSelected) {
                            CONFIG_OPTION_SELECTED_BACKGROUND
                        } else {
                            CONFIG_OPTION_BACKGROUND
                        }
                    )
                    .cornerRadius(7.dp)
                    .clickable(
                        onClick = actionRunCallback<ConfigureCallback>(
                            actionParametersOf(
                                gameName to game.getName(),
                                configName to name,
                                configVal to option,
                            )
                        )
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = option,
                    style = TextStyle(
                        color = ColorProvider(
                            if (isSelected) {
                                CONFIG_OPTION_SELECTED_COLOR
                            } else {
                                CONFIG_OPTION_COLOR
                            }
                        ),
                        fontSize = fontSize,
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                        textAlign = TextAlign.Center,
                    ),
                    modifier = GlanceModifier.padding(horizontal = 4.dp, vertical = 8.dp),
                )
            }
        }
    }
}

@Composable
fun RenderConfigImageOption(
    game: Game,
    name: String,
    options: List<ConfigImageOption>,
    selected: String,
    settingName: String = name,
    imageHeight: Dp = 68.dp,
    contentScale: ContentScale = ContentScale.Fit,
    showLabels: Boolean = true,
) {
    if (options.isEmpty()) return

    val columns = if (options.size <= 4) options.size.coerceAtLeast(1) else 3
    val rows = options.chunked(columns)

    Column(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 5.dp),
    ) {
        RenderConfigSectionTitle(name)

        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(CONFIG_SECTION_BACKGROUND)
                .cornerRadius(9.dp)
                .padding(3.dp),
        ) {
            rows.forEachIndexed { rowIndex, rowOptions ->
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                ) {
                    rowOptions.forEach { option ->
                        val isSelected = option.value == selected

                        Column(
                            modifier = GlanceModifier
                                .defaultWeight()
                                .padding(2.dp)
                                .background(
                                    if (isSelected) {
                                        CONFIG_OPTION_SELECTED_BACKGROUND
                                    } else {
                                        CONFIG_OPTION_BACKGROUND
                                    }
                                )
                                .cornerRadius(7.dp)
                                .clickable(
                                    onClick = actionRunCallback<ConfigureCallback>(
                                        actionParametersOf(
                                            gameName to game.getName(),
                                            configName to settingName,
                                            configVal to option.value,
                                        )
                                    )
                                )
                                .padding(4.dp),
                            horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
                        ) {
                            Image(
                                provider = option.image,
                                contentDescription = option.label,
                                modifier = GlanceModifier
                                    .fillMaxWidth()
                                    .height(imageHeight)
                                    .cornerRadius(5.dp),
                                contentScale = contentScale,
                            )

                            if (showLabels) {
                                Spacer(modifier = GlanceModifier.height(3.dp))

                                Text(
                                    text = option.label,
                                    style = TextStyle(
                                        color = ColorProvider(
                                            if (isSelected) {
                                                CONFIG_OPTION_SELECTED_COLOR
                                            } else {
                                                CONFIG_OPTION_COLOR
                                            }
                                        ),
                                        fontSize = 11.sp,
                                        fontWeight = if (isSelected) {
                                            FontWeight.Bold
                                        } else {
                                            FontWeight.Medium
                                        },
                                        textAlign = TextAlign.Center,
                                    ),
                                )
                            }
                        }
                    }
                }

                if (rowIndex < rows.lastIndex) {
                    Spacer(modifier = GlanceModifier.height(3.dp))
                }
            }
        }
    }
}

@Composable
fun RenderGameChoiceTiles(
    choices: List<GameImageChoice>,
    title: String? = null,
    imageHeight: Dp = 76.dp,
    contentScale: ContentScale = ContentScale.Fit,
) {
    if (choices.isEmpty()) return

    val columns = if (choices.size <= 4) choices.size.coerceAtLeast(1) else 3
    val rows = choices.chunked(columns)

    Column(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 5.dp),
    ) {
        if (!title.isNullOrBlank()) {
            RenderConfigSectionTitle(title)
        }

        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(CONFIG_SECTION_BACKGROUND)
                .cornerRadius(9.dp)
                .padding(3.dp),
        ) {
            rows.forEachIndexed { rowIndex, rowChoices ->
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                ) {
                    rowChoices.forEach { choice ->
                        Column(
                            modifier = GlanceModifier
                                .defaultWeight()
                                .padding(2.dp)
                                .background(CONFIG_OPTION_BACKGROUND)
                                .cornerRadius(7.dp)
                                .clickable(
                                    onClick = actionRunCallback<ChooseGameCallback>(
                                        actionParametersOf(
                                            gameName to choice.game.getName(),
                                        )
                                    )
                                )
                                .padding(4.dp),
                            horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
                        ) {
                            Image(
                                provider = choice.image,
                                contentDescription = choice.label,
                                modifier = GlanceModifier
                                    .fillMaxWidth()
                                    .height(imageHeight)
                                    .cornerRadius(5.dp),
                                contentScale = contentScale,
                            )

                            Spacer(modifier = GlanceModifier.height(3.dp))

                            Text(
                                text = choice.label,
                                style = TextStyle(
                                    color = ColorProvider(CONFIG_OPTION_SELECTED_COLOR),
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    textAlign = TextAlign.Center,
                                ),
                            )
                        }
                    }
                }

                if (rowIndex < rows.lastIndex) {
                    Spacer(modifier = GlanceModifier.height(3.dp))
                }
            }
        }
    }
}

@Composable
private fun RenderConfigSectionTitle(
    name: String,
) {
    Text(
        text = name.uppercase(),
        style = TextStyle(
            color = ColorProvider(CONFIG_TITLE_COLOR),
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
        ),
    )

    Spacer(modifier = GlanceModifier.height(4.dp))
}

private fun configColumnCount(
    optionCount: Int,
): Int {
    return when {
        optionCount <= 0 -> 1
        optionCount <= 4 -> optionCount
        else -> 3
    }
}