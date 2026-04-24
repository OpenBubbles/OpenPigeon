package com.openbubbles.openpigeon.settings

import android.app.Activity
import android.os.Bundle
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

            finish()
            overridePendingTransition(0, 0)
        }

        root.post {
            sheet.open()
        }
    }

    override fun onPause() {
        AvatarView.buildAvatarString()
        super.onPause()
    }
}