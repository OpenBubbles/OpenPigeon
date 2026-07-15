package com.openbubbles.openpigeon

import android.content.Context
import android.graphics.Bitmap

interface DynamicPreviewGame {
    fun gamePreviewBitmap(
        context: Context,
        message: Map<String, String>
    ): Bitmap?

    fun gamePreviewBitmap(
        context: Context,
        message: Map<String, String>,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap? {
        return gamePreviewBitmap(context, message)
    }
}