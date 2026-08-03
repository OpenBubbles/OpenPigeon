package com.openbubbles.openpigeon.settings

import android.content.Context
import android.graphics.Color

object AvatarData {
    private val background = SettingScope.Section(
        "avatar_background",
    )

    private val faceShape = SettingScope.Section(
        "avatar_fshape",
    )

    private val hairFront = SettingScope.Section(
        "avatar_hair_front",
    )

    private val hairBack = SettingScope.Section(
        "avatar_hair_back",
    )

    private val hair = SettingScope.Section(
        "avatar_hair",
    )

    private val face = SettingScope.Section(
        "avatar_face",
    )

    private val clothing = SettingScope.Section(
        "avatar_clothing",
    )

    private val accessories = SettingScope.Section(
        "avatar_accessories",
    )

    fun init(
        context: Context,
    ) {
        SettingsData.init(
            context,
        )

        AvatarBitmapCache.load(
            context.applicationContext,
        )
    }

    fun refreshFromGodot(): Boolean {
        return SettingsData.refreshFromGodot()
    }

    var bgStyle: String
        get() = SettingsData.getString(
            background,
            "style",
            "Plain",
        )
        set(value) {
            SettingsData.putString(
                background,
                "style",
                value,
            )
        }

    var bgColor: Int
        get() = SettingsData.getColor(
            background,
            "color",
            Color.parseColor(
                "#4e5d89",
            ),
        )
        set(value) {
            SettingsData.putColor(
                background,
                "color",
                value,
            )
        }

    var bgBrightness: Float
        get() = SettingsData.getFloat(
            background,
            "brightness",
            0f,
        )
        set(value) {
            SettingsData.putFloat(
                background,
                "brightness",
                value,
            )
        }

    var fshapeStyle: String
        get() = SettingsData.getString(
            faceShape,
            "head_style",
            "Default",
        )
        set(value) {
            SettingsData.putString(
                faceShape,
                "head_style",
                value,
            )
        }

    var fshapeColor: Int
        get() = SettingsData.getColor(
            faceShape,
            "color",
            Color.parseColor(
                "#e0ac69",
            ),
        )
        set(value) {
            SettingsData.putColor(
                faceShape,
                "color",
                value,
            )
        }

    var fshapeBrightness: Float
        get() = SettingsData.getFloat(
            faceShape,
            "brightness",
            0f,
        )
        set(value) {
            SettingsData.putFloat(
                faceShape,
                "brightness",
                value,
            )
        }

    var hairStyle: String
        get() = SettingsData.getString(
            hairFront,
            "style",
            "hair1",
        )
        set(value) {
            SettingsData.edit {
                putString(
                    hairFront,
                    "style",
                    value,
                )

                putString(
                    hairBack,
                    "style",
                    value,
                )

                putString(
                    hair,
                    "style",
                    value,
                )
            }
        }

    var hairColor: Int
        get() = SettingsData.getColor(
            hairFront,
            "color",
            Color.parseColor(
                "#2c232b",
            ),
        )
        set(value) {
            SettingsData.edit {
                putColor(
                    hairFront,
                    "color",
                    value,
                )

                putColor(
                    hairBack,
                    "color",
                    value,
                )

                putColor(
                    hair,
                    "color",
                    value,
                )
            }
        }

    var hairBrightness: Float
        get() = SettingsData.getFloat(
            hairFront,
            "brightness",
            0f,
        )
        set(value) {
            SettingsData.edit {
                putFloat(
                    hairFront,
                    "brightness",
                    value,
                )

                putFloat(
                    hairBack,
                    "brightness",
                    value,
                )

                putFloat(
                    hair,
                    "brightness",
                    value,
                )
            }
        }

    var eyesStyle: String
        get() = SettingsData.getString(
            face,
            "eyes",
            "eyes1",
        )
        set(value) {
            SettingsData.putString(
                face,
                "eyes",
                value,
            )
        }

    var mouthStyle: String
        get() = SettingsData.getString(
            face,
            "mouth",
            "mouth1",
        )
        set(value) {
            SettingsData.putString(
                face,
                "mouth",
                value,
            )
        }

    var clothingStyle: String
        get() = SettingsData.getString(
            clothing,
            "style",
            "clothing1",
        )
        set(value) {
            SettingsData.putString(
                clothing,
                "style",
                value,
            )
        }

    var clothingColor: Int
        get() = SettingsData.getColor(
            clothing,
            "color",
            Color.parseColor(
                "#a03c3c",
            ),
        )
        set(value) {
            SettingsData.putColor(
                clothing,
                "color",
                value,
            )
        }

    var clothingBrightness: Float
        get() = SettingsData.getFloat(
            clothing,
            "brightness",
            0f,
        )
        set(value) {
            SettingsData.putFloat(
                clothing,
                "brightness",
                value,
            )
        }

    fun normalizeHeadAccessoryStyle(value: String): String {
        val style = value.trim()
        if (style.isBlank() || style == "None") return "hat_0"
        if (style == "Hat1") return "hat_1"

        val index = if (style.startsWith("hat_")) {
            style.removePrefix("hat_").toIntOrNull()
        } else {
            style.toIntOrNull()
        }

        return "hat_${(index ?: 0).coerceIn(0, 12)}"
    }

    var headAccessoryStyle: String
        get() = normalizeHeadAccessoryStyle(SettingsData.getString(accessories, "head_style", "hat_0"))
        set(value) {
            SettingsData.putString(accessories, "head_style", normalizeHeadAccessoryStyle(value))
        }

    fun normalizeFaceAccessoryStyle(value: String): String {
        val style = value.trim()
        if (style.isBlank() || style == "None" || style == "Mask") return "face_1"
        if (style == "Glasses") return "face_2"

        val index = if (style.startsWith("face_")) {
            style.removePrefix("face_").toIntOrNull()
        } else {
            style.toIntOrNull()
        }

        return "face_${(index ?: 1).coerceIn(1, 14)}"
    }

    var faceAccessoryStyle: String
        get() = normalizeFaceAccessoryStyle(
            SettingsData.getString(accessories, "face_style", "face_1")
        )
        set(value) {
            SettingsData.putString(
                accessories,
                "face_style",
                normalizeFaceAccessoryStyle(value)
            )
        }

    fun writeCfg() {
        SettingsData.flushToGodot()
    }
}