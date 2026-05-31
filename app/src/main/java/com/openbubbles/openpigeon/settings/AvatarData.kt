package com.openbubbles.openpigeon.settings

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import com.openbubbles.openpigeon.util.OpenPigeonLog
import androidx.core.content.edit
import java.io.File

object AvatarData {

    private const val TAG              = "AvatarData"
    private const val PREFS_NAME       = "avatar_settings"
    private const val PREF_LAST_WRITE  = "meta/last_android_write_ms"

    // Godot 4 writes user:// directly to filesDir with no subfolder.
    // Confirmed from device log: /data/data/com.openbubbles.openpigeon/files/settings.cfg
    private const val GODOT_CFG_SUBPATH = "settings.cfg"

    private lateinit var appContext: Context

    // ── Init ──────────────────────────────────────────────────────────────────
    fun init(context: Context) {
        appContext = context.applicationContext
        AvatarBitmapCache.load(appContext)
        syncFromCfgIfNewer()
    }

    // ── Bidirectional sync ────────────────────────────────────────────────────
    private fun syncFromCfgIfNewer() {
        val file = File(appContext.filesDir, GODOT_CFG_SUBPATH)
        if (!file.exists()) {
            OpenPigeonLog.d(TAG, "No cfg at ${file.absolutePath} — skipping import")
            return
        }

        val cfgModified     = file.lastModified()
        val lastAndroidWrite = prefs().getLong(PREF_LAST_WRITE, 0L)

        OpenPigeonLog.d(TAG, "cfg lastModified=$cfgModified  lastAndroidWrite=$lastAndroidWrite")

        if (cfgModified > lastAndroidWrite) {
            OpenPigeonLog.d(TAG, "Godot wrote more recently — importing cfg into prefs")
            importFromCfg(file)
        } else {
            OpenPigeonLog.d(TAG, "Android wrote more recently (or same) — keeping prefs, re-writing cfg")
            // Re-write so Godot always has the freshest Android values
            writeCfg()
        }
    }

    // ── Cfg → SharedPreferences ───────────────────────────────────────────────
    private fun importFromCfg(file: File) {
        try {
            val editor = prefs().edit()
            var currentSection = ""

            file.forEachLine { raw ->
                val line = raw.trim()
                when {
                    line.startsWith("[") && line.endsWith("]") -> {
                        currentSection = line.drop(1).dropLast(1)
                    }
                    line.contains("=") && currentSection.isNotEmpty() -> {
                        val key      = line.substringBefore("=").trim()
                        val value    = line.substringAfter("=").trim()
                        val prefsKey = "$currentSection/$key"
                        when {
                            // String: "hair1"
                            value.startsWith("\"") && value.endsWith("\"") -> {
                                editor.putString(prefsKey, value.removeSurrounding("\""))
                            }
                            // Color: Color(r, g, b, a)
                            value.startsWith("Color(") -> {
                                val parts = value
                                    .removePrefix("Color(").removeSuffix(")")
                                    .split(",").map { it.trim().toFloatOrNull() ?: 0f }
                                if (parts.size >= 4) {
                                    editor.putInt(prefsKey, Color.argb(
                                        (parts[3] * 255).toInt(),
                                        (parts[0] * 255).toInt(),
                                        (parts[1] * 255).toInt(),
                                        (parts[2] * 255).toInt()
                                    ))
                                }
                            }
                            // Float
                            value.toFloatOrNull() != null -> {
                                editor.putFloat(prefsKey, value.toFloat())
                            }
                            value == "true"  -> editor.putBoolean(prefsKey, true)
                            value == "false" -> editor.putBoolean(prefsKey, false)
                        }
                    }
                }
            }
            // Stamp the write time as "now" so we don't re-import next time
            editor.putLong(PREF_LAST_WRITE, System.currentTimeMillis())
            editor.apply()
            OpenPigeonLog.d(TAG, "Import from cfg complete")
        } catch (e: Exception) {
            OpenPigeonLog.e(TAG, "Failed to import cfg", e)
        }
    }

    // ── SharedPreferences helpers ─────────────────────────────────────────────
    private fun prefs(): SharedPreferences =
        appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun getString(section: String, key: String, default: String): String =
        prefs().getString("$section/$key", default) ?: default

    private fun putString(section: String, key: String, value: String) {
        prefs().edit { putString("$section/$key", value) }
        writeCfg()
    }

    private fun getFloat(section: String, key: String, default: Float): Float =
        prefs().getFloat("$section/$key", default)

    private fun putFloat(section: String, key: String, value: Float) {
        prefs().edit { putFloat("$section/$key", value) }
        writeCfg()
    }

    private fun getColor(section: String, key: String, default: Int): Int =
        prefs().getInt("$section/$key", default)

    private fun putColor(section: String, key: String, value: Int) {
        prefs().edit { putInt("$section/$key", value) }
        writeCfg()
    }

    // ── Avatar properties ─────────────────────────────────────────────────────

    var bgStyle: String
        get() = getString("avatar_background", "style", "Plain")
        set(v) = putString("avatar_background", "style", v)

    var bgColor: Int
        get() = getColor("avatar_background", "color", Color.parseColor("#4e5d89"))
        set(v) = putColor("avatar_background", "color", v)

    var bgBrightness: Float
        get() = getFloat("avatar_background", "brightness", 0f)
        set(v) = putFloat("avatar_background", "brightness", v)

    var fshapeStyle: String
        get() = getString("avatar_fshape", "head_style", "Default")
        set(v) = putString("avatar_fshape", "head_style", v)

    var fshapeColor: Int
        get() = getColor("avatar_fshape", "color", Color.parseColor("#e0ac69"))
        set(v) = putColor("avatar_fshape", "color", v)

    var fshapeBrightness: Float
        get() = getFloat("avatar_fshape", "brightness", 0f)
        set(v) = putFloat("avatar_fshape", "brightness", v)

    var hairStyle: String
        get() = getString("avatar_hair_front", "style", "hair1")
        set(v) {
            prefs().edit {
                putString("avatar_hair_front/style", v)
                putString("avatar_hair_back/style", v)
                putString("avatar_hair/style", v)
            }
            writeCfg()
        }

    var hairColor: Int
        get() = getColor("avatar_hair_front", "color", Color.parseColor("#2c232b"))
        set(v) {
            prefs().edit {
                putInt("avatar_hair_front/color", v)
                putInt("avatar_hair_back/color", v)
                putInt("avatar_hair/color", v)
            }
            writeCfg()
        }

    var hairBrightness: Float
        get() = getFloat("avatar_hair_front", "brightness", 0f)
        set(v) {
            prefs().edit {
                putFloat("avatar_hair_front/brightness", v)
                putFloat("avatar_hair_back/brightness", v)
                putFloat("avatar_hair/brightness", v)
            }
            writeCfg()
        }

    var eyesStyle: String
        get() = getString("avatar_face", "eyes", "eyes1")
        set(v) = putString("avatar_face", "eyes", v)

    var mouthStyle: String
        get() = getString("avatar_face", "mouth", "mouth1")
        set(v) = putString("avatar_face", "mouth", v)

    var clothingStyle: String
        get() = getString("avatar_clothing", "style", "clothing1")
        set(v) = putString("avatar_clothing", "style", v)

    var clothingColor: Int
        get() = getColor("avatar_clothing", "color", Color.parseColor("#a03c3c"))
        set(v) = putColor("avatar_clothing", "color", v)

    var clothingBrightness: Float
        get() = getFloat("avatar_clothing", "brightness", 0f)
        set(v) = putFloat("avatar_clothing", "brightness", v)

    // ── SharedPreferences → Godot cfg ─────────────────────────────────────────
    private fun colorToCfg(argb: Int): String {
        val r = Color.red(argb)   / 255f
        val g = Color.green(argb) / 255f
        val b = Color.blue(argb)  / 255f
        val a = Color.alpha(argb) / 255f
        return "Color(%.6f, %.6f, %.6f, %.6f)".format(r, g, b, a)
    }

    fun writeCfg() {
        try {
            val file = File(appContext.filesDir, GODOT_CFG_SUBPATH)
            file.parentFile?.mkdirs()

            val sb = StringBuilder()
            fun section(name: String, vararg pairs: Pair<String, String>) {
                sb.appendLine("[$name]")
                for ((k, v) in pairs) sb.appendLine("$k=$v")
                sb.appendLine()
            }

            section("avatar_background",
                "style"      to "\"$bgStyle\"",
                "color"      to colorToCfg(bgColor),
                "brightness" to bgBrightness.toString()
            )
            section("avatar_fshape",
                "head_style" to "\"$fshapeStyle\"",
                "color"      to colorToCfg(fshapeColor),
                "brightness" to fshapeBrightness.toString()
            )
            for (sec in listOf("avatar_hair_front", "avatar_hair_back", "avatar_hair")) {
                section(sec,
                    "style"      to "\"$hairStyle\"",
                    "color"      to colorToCfg(hairColor),
                    "brightness" to hairBrightness.toString()
                )
            }
            section("avatar_face",
                "eyes"  to "\"$eyesStyle\"",
                "mouth" to "\"$mouthStyle\""
            )
            section("avatar_clothing",
                "style"      to "\"$clothingStyle\"",
                "color"      to colorToCfg(clothingColor),
                "brightness" to clothingBrightness.toString()
            )

            file.writeText(sb.toString())

            // Stamp the write time so syncFromCfgIfNewer() knows Android wrote this
            prefs().edit { putLong(PREF_LAST_WRITE, System.currentTimeMillis()) }

            OpenPigeonLog.d(TAG, "Wrote cfg to ${file.absolutePath}")
        } catch (e: Exception) {
            OpenPigeonLog.e(TAG, "Failed to write cfg", e)
        }
    }
}
