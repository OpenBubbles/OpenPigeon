package com.openbubbles.openpigeon.settings

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory

object AvatarBitmapCache {

    var loaded = false
        private set

    var bmFaces:      Bitmap? = null
    var bmTorso:      Bitmap? = null
    var bmHairBack:   Bitmap? = null
    var bmHairFront:  Bitmap? = null
    var bmEyes:       Bitmap? = null
    var bmMouth:      Bitmap? = null
    var bmClothing:   Bitmap? = null
    var bmClothingDt: Bitmap? = null
    var bmBackground: Bitmap? = null

    fun load(context: Context) {
        if (loaded) return
        loaded = true

        val assets = context.applicationContext.assets
        val base   = "global/avatar_textures"

        fun bmp(path: String): Bitmap? = try {
            assets.open(path).use { BitmapFactory.decodeStream(it) }
        } catch (e: Exception) { e.printStackTrace(); null }

        bmFaces      = bmp("$base/body/avatar_faces.png")
        bmTorso      = bmp("$base/body/avatar_torso.png")
        bmHairBack   = bmp("$base/hair/avatar_hair_back.png")
        bmHairFront  = bmp("$base/hair/avatar_hair_front.png")
        bmEyes       = bmp("$base/face/avatar_eyes.png")
        bmMouth      = bmp("$base/face/avatar_mouth.png")
        bmClothing   = bmp("$base/clothing/avatar_clothing_base.png")
        bmClothingDt = bmp("$base/clothing/avatar_clothing_details.png")
        bmBackground = bmp("$base/backgrounds/background_sheet.png")
    }
}
