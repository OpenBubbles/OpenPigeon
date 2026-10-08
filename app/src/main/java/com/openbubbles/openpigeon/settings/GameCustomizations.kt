package com.openbubbles.openpigeon.settings

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.core.graphics.toColorInt
import com.openbubbles.openpigeon.pool.availableCueStyles
import com.openbubbles.openpigeon.pool.rotatedCueBitmap
import com.openbubbles.openpigeon.settings.SettingsSheet.PickerItem
import com.openbubbles.openpigeon.settings.SettingsSheet.PickerPreview

// Mirrors PAINT_STYLES in paintball_game.gd (last entry = Random).
private val PAINT_STYLES = listOf(
    "FFD400 FFEC66 E0A600", "D62828 FFFFFF 1E5BD6", "2ECC40 7EE38A 11702A", "C0271F 141414 8C1610",
    "1E5BD6 4FC3F7 0B2F7A", "FF5FA2 FFE066 FFFFFF", "FF2D2D FF9F1C 2ECC40 1E5BD6", "FF4FB8 B6FF2E FF8FD0",
    "FFDF20 FF8C1A FF3B1F", "8E44AD C94FD6 FF6FD8", "FFD6E0 CDEAC0 BFD8FF FFF1B6", "111111 3A3A3A 000000",
    "FF7518 1A1A1A 7B2FF7", "FFD400 1E5BD6 4FC3F7", "FF0000 FFFF00 00FF00 00FFFF 0000FF FF00FF",
)

// id|label|stone colors — mirrors MANCALA_THEME_NAMES / _get_palette_for_theme in mancala.gd.
private val MANCALA_THEMES = listOf(
    "Default|Default|FFFCF2 414851 176CAB", "Retro|Retro|E80038 FFB900 2FA5A0",
    "Penguin|Penguin|00E603 00C6CF 0083E3 E90008 C303C1", "Sakura Ink|Sakura|F7BFCF 2A2E34 4F65A3",
    "Emerald Brass|Emerald|2FAF74 1D8F5A 66C79E 8C6B32", "Desert Dusk|Desert|E8A66A 3A2C27 2FA5A0",
    "Cotton Candy|Cotton|AEB6C2 F59FC5 82BFF2", "Green & White|Green|188C4D FFFFFF",
    "Red & White|Red|D92D32 FFFFFF", "Black & White|B&W|111111 FFFFFF", "Pink & White|Pink|F15A9D FFFFFF",
    "All White|White|FFFFFF F2F2F2 E1E1E1", "Gamer|Gamer|E53935 28C840 2585F5 FFD52A",
    "Ocean|Ocean|0077B6 00B4D8 48CAE4 90E0C5", "Vintage|Vintage|C92D32 009681 7B4AA2",
)

private fun bands(hex: String) = PickerPreview.Custom { ctx ->
    LinearLayout(ctx).apply {
        clipToOutline = true
        background = GradientDrawable().apply { cornerRadius = 12f * ctx.resources.displayMetrics.density }
        hex.split(' ').forEach { addView(View(ctx).apply { setBackgroundColor("#$it".toColorInt()) }, LinearLayout.LayoutParams(0, -1, 1f)) }
    }
}

// (style, file) pairs for baked previews shipped as raw assets, e.g. darts/previews/dart03.png -> (3, "dart03.png").
private fun assetStyles(ctx: Context, dir: String, prefix: String): List<Pair<Int, String>> {
    val re = Regex("$prefix(\\d+)\\.png")
    return runCatching { ctx.assets.list(dir) }.getOrNull().orEmpty()
        .mapNotNull { f -> re.matchEntire(f)?.let { it.groupValues[1].toInt() to f } }.sortedBy { it.first }
}

/** Adds every game's customization picker to the sheet's custom tab (one scrolling page). */
fun SettingsSheet.addGameCustomizations(ctx: Context) {
    ensureCustomTab()
    onCustomTabFirstOpened = { buildGameCustomizations(ctx) }
}

private fun SettingsSheet.buildGameCustomizations(ctx: Context) {
    // Godot reads these as ints; the sheet stores strings, so re-store typed (Godot's own pickers write ints too).
    fun pick(title: String, sub: String, scope: SettingScope, key: String, items: List<PickerItem>, default: String, asInt: Boolean = true) {
        if (items.isNotEmpty()) addPickerSetting(title, sub, scope, key, items, default) { id -> if (asInt) id.toIntOrNull()?.let { SettingsData.putInt(scope, key, it) } }
    }
    fun assets(dir: String, prefix: String, label: String, offset: Int) =
        assetStyles(ctx, dir, prefix).map { (s, f) -> PickerItem("$s", "$label ${s + offset}", PickerPreview.Asset("$dir/$f")) }

    availableCueStyles(ctx).takeIf { it.isNotEmpty() }?.let { cues ->
        addListPickerSetting("Pool · Cue", "Stick design", SettingScope.Game("pool"), "cue_style",
            cues.map { s -> PickerItem("$s", "Cue $s", PickerPreview.Custom { c -> ImageView(c).apply { setImageBitmap(rotatedCueBitmap(c, s)); scaleType = ImageView.ScaleType.FIT_CENTER } }) },
            "1", rowHeightDp = 88f) {}
    }
    pick("Darts · Dart", "Flight design", SettingScope.Game("darts"), "dart_style", assets("darts/previews", "dart", "Dart", 1), "0")
    pick("Paintball · Paint", "Color you splatter on your opponent", SettingScope.Game("paintball"), "paint_style",
        PAINT_STYLES.mapIndexed { i, hex -> PickerItem("$i", if (i == PAINT_STYLES.lastIndex) "Random" else "Paint ${i + 1}", bands(hex)) }, "0")
    pick("Cup Pong · Cups", "Choose your cup style", SettingScope.Section("beer"), "cup_style", assets("pong/previews", "cup", "Cup", 0), "1")
    pick("Cup Pong · Balls", "Choose your ball style", SettingScope.Section("beer"), "ball_style", assets("pong/previews", "ball", "Ball", 0), "1")
    pick("Mancala · Theme", "Board and stone colors", SettingScope.Game("mancala"), "theme",
        MANCALA_THEMES.map { it.split('|').let { (id, label, hex) -> PickerItem(id, label, bands(hex)) } }, "Default", asInt = false)
}