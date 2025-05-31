package com.openbubbles.openpigeon

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.core.net.toUri
import com.google.android.material.dialog.MaterialAlertDialogBuilder

class AboutActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MaterialAlertDialogBuilder(this, com.google.android.material.R.style.ThemeOverlay_Material3_MaterialAlertDialog)
            .setTitle("OpenPigeon")
            .setMessage("""
                Copyright (c) 2025 OpenPigeon Contributors
                
                OpenPigeon is fully open-source, and we're looking for game developers to contribute their favorite games. If you're interested, find out more on GitHub.

                Thank you to our contributors!
                Checkers - jakecrowley
                Word Hunt - npulse4
                Four in a Row - jakecrowley
                Basketball - jakecrowley
                Sea Battle - Copper
                Crazy 8 - Copper
                Darts - jakecrowley
                8 Ball - Copper
                Cup Pong - jakecrowley
                Archery - jakecrowley

                Are you a developer? Add your favorite game on GitHub!
            """.trimIndent())
            .setPositiveButton("Done") { dialog, which ->
                finishAndRemoveTask()
            }
            .setNegativeButton("GitHub") { dialog, which ->
                val intent = Intent(Intent.ACTION_VIEW)
                intent.data = "https://github.com/OpenBubbles/OpenPigeon".toUri()
                startActivity(intent)
                finishAndRemoveTask()
            }
            .setCancelable(false)
            .show()
    }
}