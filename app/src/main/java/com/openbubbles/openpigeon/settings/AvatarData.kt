package com.openbubbles.openpigeon.settings

import android.content.Context
import android.graphics.Color

object AvatarData {
    private val background =
        SettingScope.Section(
            "avatar_background",
        )

    private val faceShape =
        SettingScope.Section(
            "avatar_fshape",
        )

    private val hairFront =
        SettingScope.Section(
            "avatar_hair_front",
        )

    private val hairBack =
        SettingScope.Section(
            "avatar_hair_back",
        )

    private val hair =
        SettingScope.Section(
            "avatar_hair",
        )

    private val face =
        SettingScope.Section(
            "avatar_face",
        )

    private val clothing =
        SettingScope.Section(
            "avatar_clothing",
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
        get() =
            SettingsData.getString(
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
        get() =
            SettingsData.getColor(
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
        get() =
            SettingsData.getFloat(
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
        get() =
            SettingsData.getString(
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
        get() =
            SettingsData.getColor(
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
        get() =
            SettingsData.getFloat(
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
        get() =
            SettingsData.getString(
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
        get() =
            SettingsData.getColor(
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
        get() =
            SettingsData.getFloat(
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
        get() =
            SettingsData.getString(
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
        get() =
            SettingsData.getString(
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
        get() =
            SettingsData.getString(
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
        get() =
            SettingsData.getColor(
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
        get() =
            SettingsData.getFloat(
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

    fun writeCfg() {
        SettingsData.flushToGodot()
    }
}