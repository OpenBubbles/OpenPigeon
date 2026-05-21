package com.openbubbles.openpigeon.settings

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.openbubbles.openpigeon.R

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

        val res = context.resources

        fun bmp(id: Int): Bitmap? = try {
            BitmapFactory.decodeResource(res, id)
        } catch (e: Exception) {
            android.util.Log.e("AvatarBitmapCache", "Failed loading drawable resource: $id", e)
            null
        }

        bmFaces      = bmp(R.drawable.avatar_faces)
        bmTorso      = bmp(R.drawable.avatar_torso)
        bmHairBack   = bmp(R.drawable.avatar_hair_back)
        bmHairFront  = bmp(R.drawable.avatar_hair_front)
        bmEyes       = bmp(R.drawable.avatar_eyes)
        bmMouth      = bmp(R.drawable.avatar_mouth)
        bmClothing   = bmp(R.drawable.avatar_clothing_base)
        bmClothingDt = bmp(R.drawable.avatar_clothing_details)
        bmBackground = bmp(R.drawable.background_sheet)

        loaded = listOf(
            bmFaces,
            bmTorso,
            bmHairBack,
            bmHairFront,
            bmEyes,
            bmMouth,
            bmClothing,
            bmClothingDt,
            bmBackground
        ).all { it != null }
    }
}