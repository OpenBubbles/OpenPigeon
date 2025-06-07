package com.openbubbles.openpigeon

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.net.toUri
import com.google.android.material.dialog.MaterialAlertDialogBuilder

class GameNotFound : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        var name = intent.getStringExtra("DISPLAY_GAME")
        val isGameSupported = intent.getStringExtra("GAME")
        if (isGameSupported != null) {
            name = "this $name mode"
        }

        val warn = if (isGameSupported != null) "This is a missing feature in OpenPigeon. GamePigeon is an unaffiliated app, and is not responsible for providing this paid game mode. Do not ask for a refund.\n\n" else ""
        MaterialAlertDialogBuilder(this, com.google.android.material.R.style.ThemeOverlay_Material3_MaterialAlertDialog)
            .setTitle("Sorry, we don't support $name!")
            .setMessage("${warn}But we could! OpenPigeon is fully open-source, and we're looking for game developers to contribute their favorite games. If you're interested, find out more on GitHub.")
            .setPositiveButton("Done") { dialog, which ->
                finishAndRemoveTask()
            }
            .setNegativeButton("GitHub") { dialog, which ->
                val intent = Intent(Intent.ACTION_VIEW)
                intent.data = "https://github.com/OpenBubbles/OpenPigeon".toUri()
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
                finishAndRemoveTask()
            }
            .setCancelable(false)
            .show()
    }

}