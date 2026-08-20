package com.openbubbles.openpigeon.settings

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import com.openbubbles.openpigeon.util.OpenPigeonLog
import java.io.File
import java.util.Locale

sealed class SettingScope(
    val section: String,
) {
    object Global :
        SettingScope(
            "global",
        )

    data class Game(
        val gameId: String,
    ) : SettingScope(
        gameId,
    ) {
        init {
            require(
                gameId.isNotBlank() &&
                        '/' !in gameId &&
                        '[' !in gameId &&
                        ']' !in gameId,
            ) {
                "Invalid game setting section: $gameId"
            }
        }
    }

    data class Section(
        val sectionName: String,
    ) : SettingScope(
        sectionName,
    ) {
        init {
            require(
                sectionName.isNotBlank() &&
                        '/' !in sectionName &&
                        '[' !in sectionName &&
                        ']' !in sectionName,
            ) {
                "Invalid setting section: $sectionName"
            }
        }
    }
}


object SettingsData {
    private const val TAG =
        "SettingsData"

    private const val PREFERENCES_NAME =
        "avatar_settings"

    private const val CFG_FILE_NAME =
        "settings.cfg"

    private const val BRIDGE_VERSION =
        1

    private const val META_PREFIX =
        "meta/"

    private const val META_TYPE_PREFIX =
        "meta/type/"

    private const val META_BRIDGE_VERSION =
        "meta/settings_bridge_version"

    private const val META_CFG_MODIFIED =
        "meta/settings_cfg_modified"

    private const val META_CFG_HASH =
        "meta/settings_cfg_hash"

    private val knownColorKeys =
        setOf(
            "avatar_background/color",
            "avatar_fshape/color",
            "avatar_hair_front/color",
            "avatar_hair_back/color",
            "avatar_hair/color",
            "avatar_clothing/color",
        )

    private lateinit var appContext:
            Context

    private enum class ValueType(
        val id: String,
    ) {
        BOOLEAN(
            "boolean",
        ),

        INTEGER(
            "integer",
        ),

        FLOAT(
            "float",
        ),

        STRING(
            "string",
        ),

        COLOR(
            "color",
        ),
    }

    private data class ParsedValue(
        val type: ValueType,
        val value: Any,
    )

    private data class CfgSnapshot(
        val file: File,
        val text: String,
        val modified: Long,
        val hash: Int,
    )

    class Editor internal constructor(
        private val editor:
        SharedPreferences.Editor,
    ) {
        fun putBoolean(
            scope: SettingScope,
            key: String,
            value: Boolean,
        ) {
            put(
                scope = scope,
                key = key,
                value = value,
                type =
                    ValueType.BOOLEAN,
            )
        }

        fun putInt(
            scope: SettingScope,
            key: String,
            value: Int,
        ) {
            put(
                scope = scope,
                key = key,
                value = value,
                type =
                    ValueType.INTEGER,
            )
        }

        fun putFloat(
            scope: SettingScope,
            key: String,
            value: Float,
        ) {
            put(
                scope = scope,
                key = key,
                value = value,
                type =
                    ValueType.FLOAT,
            )
        }

        fun putString(
            scope: SettingScope,
            key: String,
            value: String,
        ) {
            put(
                scope = scope,
                key = key,
                value = value,
                type =
                    ValueType.STRING,
            )
        }

        fun putColor(
            scope: SettingScope,
            key: String,
            value: Int,
        ) {
            put(
                scope = scope,
                key = key,
                value = value,
                type =
                    ValueType.COLOR,
            )
        }

        private fun put(
            scope: SettingScope,
            key: String,
            value: Any,
            type: ValueType,
        ) {
            val fullKey =
                settingPath(
                    scope,
                    key,
                )

            when (value) {
                is Boolean -> {
                    editor.putBoolean(
                        fullKey,
                        value,
                    )
                }

                is Int -> {
                    editor.putInt(
                        fullKey,
                        value,
                    )
                }

                is Float -> {
                    editor.putFloat(
                        fullKey,
                        value,
                    )
                }

                is String -> {
                    editor.putString(
                        fullKey,
                        value,
                    )
                }

                else -> {
                    error(
                        "Unsupported setting type: ${value.javaClass.name}",
                    )
                }
            }

            editor.putString(
                typeMetadataKey(
                    fullKey,
                ),
                type.id,
            )
        }
    }

    @Synchronized
    fun init(
        context: Context,
    ) {
        if (!::appContext.isInitialized) {
            appContext =
                context.applicationContext
        }

        val preferences =
            prefs()

        val firstBridgeRun =
            preferences.getInt(
                META_BRIDGE_VERSION,
                0,
            ) < BRIDGE_VERSION

        if (firstBridgeRun) {
            readCfgSnapshot()
                ?.let {
                    importSnapshot(
                        it,
                    )
                }
        } else {
            refreshFromGodot()
        }

        val migrated =
            migrateLegacySettings()

        if (
            firstBridgeRun ||
            migrated
        ) {
            preferences
                .edit()
                .putInt(
                    META_BRIDGE_VERSION,
                    BRIDGE_VERSION,
                )
                .apply()

            flushToGodot()
        }
    }

    @Synchronized
    fun refreshFromGodot(
        force: Boolean = false,
    ): Boolean {
        ensureInitialized()

        val snapshot =
            readCfgSnapshot()
                ?: return false

        val preferences =
            prefs()

        val lastModified =
            preferences.getLong(
                META_CFG_MODIFIED,
                Long.MIN_VALUE,
            )

        val lastHash =
            preferences.getInt(
                META_CFG_HASH,
                Int.MIN_VALUE,
            )

        if (
            !force &&
            snapshot.modified ==
            lastModified &&
            snapshot.hash ==
            lastHash
        ) {
            return false
        }

        importSnapshot(
            snapshot,
        )

        OpenPigeonLog.d(
            TAG,
            "Imported newer Godot settings " +
                    "modified=${snapshot.modified} " +
                    "hash=${snapshot.hash}",
        )

        return true
    }

    @Synchronized
    fun edit(
        block: Editor.() -> Unit,
    ) {
        ensureInitialized()

        val preferencesEditor =
            prefs().edit()

        Editor(
            preferencesEditor,
        ).block()

        preferencesEditor.apply()

        flushToGodot()
    }

    fun putBoolean(
        scope: SettingScope,
        key: String,
        value: Boolean,
    ) {
        edit {
            putBoolean(
                scope,
                key,
                value,
            )
        }
    }

    @Suppress("unused")
    fun putInt(
        scope: SettingScope,
        key: String,
        value: Int,
    ) {
        edit {
            putInt(
                scope,
                key,
                value,
            )
        }
    }

    fun putFloat(
        scope: SettingScope,
        key: String,
        value: Float,
    ) {
        edit {
            putFloat(
                scope,
                key,
                value,
            )
        }
    }

    fun putString(
        scope: SettingScope,
        key: String,
        value: String,
    ) {
        edit {
            putString(
                scope,
                key,
                value,
            )
        }
    }

    fun putColor(
        scope: SettingScope,
        key: String,
        value: Int,
    ) {
        edit {
            putColor(
                scope,
                key,
                value,
            )
        }
    }

    fun getBoolean(
        scope: SettingScope,
        key: String,
        default: Boolean,
    ): Boolean {
        val value =
            settingValue(
                scope,
                key,
            )

        return when (value) {
            is Boolean -> value
            is Number -> value.toInt() != 0
            is String ->
                value.equals(
                    "true",
                    ignoreCase = true,
                ) ||
                        value == "1"

            else -> default
        }
    }

    @Suppress("unused")
    fun getInt(
        scope: SettingScope,
        key: String,
        default: Int,
    ): Int {
        return when (
            val value =
                settingValue(
                    scope,
                    key,
                )
        ) {
            is Number -> value.toInt()
            is String ->
                value.toIntOrNull()
                    ?: default

            else -> default
        }
    }

    fun getFloat(
        scope: SettingScope,
        key: String,
        default: Float,
    ): Float {
        return when (
            val value =
                settingValue(
                    scope,
                    key,
                )
        ) {
            is Number -> value.toFloat()
            is String ->
                value.toFloatOrNull()
                    ?: default

            else -> default
        }
    }

    fun getString(
        scope: SettingScope,
        key: String,
        default: String,
    ): String {
        return when (
            val value =
                settingValue(
                    scope,
                    key,
                )
        ) {
            is String -> value
            null -> default
            else -> value.toString()
        }
    }

    fun getColor(
        scope: SettingScope,
        key: String,
        default: Int,
    ): Int {
        return when (
            val value =
                settingValue(
                    scope,
                    key,
                )
        ) {
            is Number -> value.toInt()
            else -> default
        }
    }

    @Synchronized
    fun flushToGodot() {
        ensureInitialized()

        try {
            val file =
                cfgFile()

            val sections =
                parseCfgDocument(
                    file
                        .takeIf {
                            it.exists()
                        }
                        ?.readText()
                        .orEmpty(),
                )

            for (
            (fullKey, value) in
            prefs().all
            ) {
                if (
                    fullKey.startsWith(
                        META_PREFIX,
                    ) ||
                    '/' !in fullKey
                ) {
                    continue
                }

                val section =
                    fullKey.substringBefore(
                        '/',
                    )

                val key =
                    fullKey.substringAfter(
                        '/',
                    )

                if (
                    section.isBlank() ||
                    key.isBlank()
                ) {
                    continue
                }

                sections
                    .getOrPut(
                        section,
                    ) {
                        linkedMapOf()
                    }[
                    key
                ] =
                    preferenceValueToCfg(
                        fullKey,
                        value,
                    )
            }

            val output =
                buildCfgText(
                    sections,
                )

            val tempFile =
                File(
                    file.parentFile,
                    "${file.name}.tmp",
                )

            tempFile.writeText(
                output,
            )

            if (!tempFile.renameTo(file)) {
                file.writeText(
                    output,
                )

                tempFile.delete()
            }

            val snapshot =
                readCfgSnapshot()
                    ?: return

            prefs()
                .edit()
                .putInt(
                    META_BRIDGE_VERSION,
                    BRIDGE_VERSION,
                )
                .putLong(
                    META_CFG_MODIFIED,
                    snapshot.modified,
                )
                .putInt(
                    META_CFG_HASH,
                    snapshot.hash,
                )
                .apply()

            OpenPigeonLog.d(
                TAG,
                "Wrote shared settings to ${file.absolutePath}",
            )
        } catch (throwable: Throwable) {
            OpenPigeonLog.e(
                TAG,
                "Failed to write shared settings",
                throwable,
            )
        }
    }

    private fun settingValue(
        scope: SettingScope,
        key: String,
    ): Any? {
        ensureInitialized()

        return prefs().all[
            settingPath(
                scope,
                key,
            )
        ]
    }

    private fun migrateLegacySettings(): Boolean {
        val preferences =
            prefs()

        var changed =
            false

        val editor =
            preferences.edit()

        val globalDarkKey =
            "global/dark_mode"

        if (
            !preferences.contains(
                globalDarkKey,
            )
        ) {
            val legacyDarkKey =
                when {
                    preferences.contains(
                        "pool/dark_mode",
                    ) -> {
                        "pool/dark_mode"
                    }

                    preferences.contains(
                        "shuffle/dark_mode",
                    ) -> {
                        "shuffle/dark_mode"
                    }

                    else -> null
                }

            if (legacyDarkKey != null) {
                editor.putBoolean(
                    globalDarkKey,
                    preferences.getBoolean(
                        legacyDarkKey,
                        false,
                    ),
                )

                editor.putString(
                    typeMetadataKey(
                        globalDarkKey,
                    ),
                    ValueType.BOOLEAN.id,
                )

                changed =
                    true
            }
        }

        val globalMusicKey =
            "global/music_enabled"

        if (
            !preferences.contains(
                globalMusicKey,
            )
        ) {
            val legacyMusicKey =
                when {
                    preferences.contains(
                        "pool/music_enabled",
                    ) -> {
                        "pool/music_enabled"
                    }

                    preferences.contains(
                        "shuffle/music_enabled",
                    ) -> {
                        "shuffle/music_enabled"
                    }

                    else -> null
                }

            if (legacyMusicKey != null) {
                editor.putBoolean(
                    globalMusicKey,
                    preferences.getBoolean(
                        legacyMusicKey,
                        true,
                    ),
                )

                editor.putString(
                    typeMetadataKey(
                        globalMusicKey,
                    ),
                    ValueType.BOOLEAN.id,
                )

                changed =
                    true
            }
        }

        for (
        legacyKey in
        listOf(
            "pool/dark_mode",
            "shuffle/dark_mode",
            "pool/music_enabled",
            "shuffle/music_enabled",
        )
        ) {
            if (
                preferences.contains(
                    legacyKey,
                )
            ) {
                editor.remove(
                    legacyKey,
                )

                editor.remove(
                    typeMetadataKey(
                        legacyKey,
                    ),
                )

                changed =
                    true
            }
        }

        if (changed) {
            editor.apply()
        }

        return changed
    }

    private fun importSnapshot(
        snapshot: CfgSnapshot,
    ) {
        try {
            val editor =
                prefs().edit()

            val sections =
                parseCfgDocument(
                    snapshot.text,
                )

            for (
            (section, values) in
            sections
            ) {
                for (
                (key, rawValue) in
                values
                ) {
                    val parsed =
                        parseCfgValue(
                            rawValue,
                        ) ?: continue

                    val fullKey =
                        "$section/$key"

                    when (
                        val value =
                            parsed.value
                    ) {
                        is Boolean -> {
                            editor.putBoolean(
                                fullKey,
                                value,
                            )
                        }

                        is Int -> {
                            editor.putInt(
                                fullKey,
                                value,
                            )
                        }

                        is Float -> {
                            editor.putFloat(
                                fullKey,
                                value,
                            )
                        }

                        is String -> {
                            editor.putString(
                                fullKey,
                                value,
                            )
                        }
                    }

                    editor.putString(
                        typeMetadataKey(
                            fullKey,
                        ),
                        parsed.type.id,
                    )
                }
            }

            editor
                .putInt(
                    META_BRIDGE_VERSION,
                    BRIDGE_VERSION,
                )
                .putLong(
                    META_CFG_MODIFIED,
                    snapshot.modified,
                )
                .putInt(
                    META_CFG_HASH,
                    snapshot.hash,
                )
                .apply()
        } catch (throwable: Throwable) {
            OpenPigeonLog.e(
                TAG,
                "Failed to import settings.cfg",
                throwable,
            )
        }
    }

    private fun parseCfgDocument(
        text: String,
    ): LinkedHashMap<
            String,
            LinkedHashMap<String, String>
            > {
        val sections =
            linkedMapOf<
                    String,
                    LinkedHashMap<String, String>
                    >()

        var currentSection:
                LinkedHashMap<String, String>? =
            null

        for (
        rawLine in
        text.lineSequence()
        ) {
            val line =
                rawLine.trim()

            when {
                line.isBlank() ||
                        line.startsWith(
                            ';',
                        ) ||
                        line.startsWith(
                            '#',
                        ) -> {
                    continue
                }

                line.startsWith(
                    '[',
                ) &&
                        line.endsWith(
                            ']',
                        ) -> {
                    val sectionName =
                        line
                            .drop(
                                1,
                            )
                            .dropLast(
                                1,
                            )
                            .trim()

                    currentSection =
                        sections.getOrPut(
                            sectionName,
                        ) {
                            linkedMapOf()
                        }
                }

                '=' in line &&
                        currentSection != null -> {
                    val key =
                        line.substringBefore(
                            '=',
                        ).trim()

                    val value =
                        line.substringAfter(
                            '=',
                        ).trim()

                    if (key.isNotBlank()) {
                        currentSection[
                            key
                        ] =
                            value
                    }
                }
            }
        }

        return sections
    }

    private fun buildCfgText(
        sections: LinkedHashMap<
                String,
                LinkedHashMap<String, String>
                >,
    ): String {
        return buildString {
            for (
            (section, values) in
            sections
            ) {
                append(
                    '[',
                )

                append(
                    section,
                )

                appendLine(
                    ']',
                )

                for (
                (key, value) in
                values
                ) {
                    append(
                        key,
                    )

                    append(
                        '=',
                    )

                    appendLine(
                        value,
                    )
                }

                appendLine()
            }
        }
    }

    private fun parseCfgValue(
        rawValue: String,
    ): ParsedValue? {
        val value =
            rawValue.trim()

        if (
            value.equals(
                "true",
                ignoreCase = true,
            )
        ) {
            return ParsedValue(
                ValueType.BOOLEAN,
                true,
            )
        }

        if (
            value.equals(
                "false",
                ignoreCase = true,
            )
        ) {
            return ParsedValue(
                ValueType.BOOLEAN,
                false,
            )
        }

        if (
            value.startsWith(
                '"',
            ) &&
            value.endsWith(
                '"',
            )
        ) {
            return ParsedValue(
                ValueType.STRING,
                unescapeString(
                    value
                        .drop(
                            1,
                        )
                        .dropLast(
                            1,
                        ),
                ),
            )
        }

        if (
            value.startsWith(
                "Color(",
            ) &&
            value.endsWith(
                ')',
            )
        ) {
            val parts =
                value
                    .removePrefix(
                        "Color(",
                    )
                    .removeSuffix(
                        ")",
                    )
                    .split(
                        ',',
                    )
                    .mapNotNull {
                        it
                            .trim()
                            .toFloatOrNull()
                    }

            if (parts.size >= 4) {
                return ParsedValue(
                    ValueType.COLOR,
                    Color.argb(
                        (
                                parts[3] *
                                        255f
                                ).toInt().coerceIn(
                                0,
                                255,
                            ),
                        (
                                parts[0] *
                                        255f
                                ).toInt().coerceIn(
                                0,
                                255,
                            ),
                        (
                                parts[1] *
                                        255f
                                ).toInt().coerceIn(
                                0,
                                255,
                            ),
                        (
                                parts[2] *
                                        255f
                                ).toInt().coerceIn(
                                0,
                                255,
                            ),
                    ),
                )
            }
        }

        if (
            INTEGER_PATTERN.matches(
                value,
            )
        ) {
            value
                .toIntOrNull()
                ?.let {
                    return ParsedValue(
                        ValueType.INTEGER,
                        it,
                    )
                }
        }

        value
            .toFloatOrNull()
            ?.let {
                return ParsedValue(
                    ValueType.FLOAT,
                    it,
                )
            }

        return null
    }

    private fun preferenceValueToCfg(
        fullKey: String,
        value: Any?,
    ): String {
        val type =
            valueTypeFor(
                fullKey,
                value,
            )

        return when (type) {
            ValueType.BOOLEAN -> {
                (
                        value as? Boolean
                        )?.toString()
                    ?: "false"
            }

            ValueType.INTEGER -> {
                (
                        value as? Number
                        )?.toInt()
                    ?.toString()
                    ?: "0"
            }

            ValueType.FLOAT -> {
                (
                        value as? Number
                        )?.toFloat()
                    ?.toString()
                    ?: "0.0"
            }

            ValueType.STRING -> {
                "\"${
                    escapeString(
                        value?.toString()
                            .orEmpty(),
                    )
                }\""
            }

            ValueType.COLOR -> {
                colorToCfg(
                    (
                            value as? Number
                            )?.toInt()
                        ?: Color.WHITE,
                )
            }
        }
    }

    private fun valueTypeFor(
        fullKey: String,
        value: Any?,
    ): ValueType {
        val savedType =
            prefs().getString(
                typeMetadataKey(
                    fullKey,
                ),
                null,
            )

        ValueType.entries
            .firstOrNull {
                it.id ==
                        savedType
            }
            ?.let {
                return it
            }

        if (
            fullKey in
            knownColorKeys
        ) {
            return ValueType.COLOR
        }

        return when (value) {
            is Boolean -> ValueType.BOOLEAN
            is Int -> ValueType.INTEGER
            is Float -> ValueType.FLOAT
            is String -> ValueType.STRING
            else -> ValueType.STRING
        }
    }

    private fun colorToCfg(
        argb: Int,
    ): String {
        return String.format(
            Locale.US,
            "Color(%.6f, %.6f, %.6f, %.6f)",
            Color.red(
                argb,
            ) / 255f,
            Color.green(
                argb,
            ) / 255f,
            Color.blue(
                argb,
            ) / 255f,
            Color.alpha(
                argb,
            ) / 255f,
        )
    }

    private fun readCfgSnapshot():
            CfgSnapshot? {
        val file =
            cfgFile()

        if (!file.exists()) {
            return null
        }

        return try {
            val text =
                file.readText()

            CfgSnapshot(
                file = file,
                text = text,
                modified =
                    file.lastModified(),
                hash =
                    text.hashCode(),
            )
        } catch (throwable: Throwable) {
            OpenPigeonLog.e(
                TAG,
                "Unable to read ${file.absolutePath}",
                throwable,
            )

            null
        }
    }

    private fun cfgFile(): File {
        return File(
            appContext.filesDir,
            CFG_FILE_NAME,
        )
    }

    private fun prefs():
            SharedPreferences {
        ensureInitialized()

        return appContext
            .getSharedPreferences(
                PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            )
    }

    private fun ensureInitialized() {
        check(
            ::appContext.isInitialized,
        ) {
            "SettingsData.init(context) must be called first"
        }
    }

    private fun settingPath(
        scope: SettingScope,
        key: String,
    ): String {
        require(
            key.isNotBlank() &&
                    '/' !in key &&
                    '=' !in key,
        ) {
            "Invalid setting key: $key"
        }

        return "${scope.section}/$key"
    }

    private fun typeMetadataKey(
        fullKey: String,
    ): String {
        return "$META_TYPE_PREFIX$fullKey"
    }

    private fun escapeString(
        value: String,
    ): String {
        return value
            .replace(
                "\\",
                "\\\\",
            )
            .replace(
                "\"",
                "\\\"",
            )
    }

    private fun unescapeString(
        value: String,
    ): String {
        return value
            .replace(
                "\\\"",
                "\"",
            )
            .replace(
                "\\\\",
                "\\",
            )
    }

    private val INTEGER_PATTERN =
        Regex(
            "[-+]?\\d+",
        )
}