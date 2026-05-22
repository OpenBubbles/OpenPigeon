package com.openbubbles.openpigeon.settings

import android.app.Activity
import android.os.Bundle
import android.os.Build
import android.widget.FrameLayout

class AvatarSettingsActivity : Activity() {
    private lateinit var root: FrameLayout
    private lateinit var sheet: SettingsSheet

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        AvatarData.init(applicationContext)

        root = FrameLayout(this)
        setContentView(root)

        sheet = SettingsSheet(this, root)
        sheet.onClosed = {
            AvatarView.buildAvatarString()
            AvatarData.init(applicationContext)

            finishWithoutAnimation()
        }

        root.post {
            sheet.open()
        }
    }

    private fun finishWithoutAnimation() {
        finish()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }

    override fun onPause() {
        AvatarView.buildAvatarString()
        super.onPause()
    }
}