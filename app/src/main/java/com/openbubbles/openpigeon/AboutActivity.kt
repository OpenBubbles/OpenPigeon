package com.openbubbles.openpigeon

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.net.toUri
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import java.util.Calendar

class AboutActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val currentYear = Calendar.getInstance().get(Calendar.YEAR)
        MaterialAlertDialogBuilder(this, com.google.android.material.R.style.ThemeOverlay_Material3_MaterialAlertDialog)
            .setTitle("OpenPigeon")
            .setMessage("""
                Copyright (c) $currentYear OpenPigeon Contributors
                
                OpenPigeon is fully open-source, and we're looking for game developers to contribute their favorite games. If you're interested, find out more on GitHub.

                Thank you to our contributors!
                8 Ball - Copper + ty8447
                20 Questions - ty8447
                Anagrams - ty8447
                Archery - jakecrowley + ty8447
                Basketball - jakecrowley + ty8447
                Checkers - jakecrowley + ty8447
                Chess - chasedredmon + ty8447
                Crazy 8 - Copper + ty8447
                Cup Pong - jakecrowley + ty8447
                Darts - jakecrowley + ty8447
                Dots & Boxes - ty8447
                Filler - ty8447
                Four in a Row - jakecrowley + ty8447
                Gomoku - ty8447
                Mancala - ty8447
                Paintball - ty8447
                Reversi - ty8447
                Sea Battle - Copper + ty8447
                Tanks - ty8447
                Wordbites - ty8447
                Word Hunt - npulse4 + ty8447

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
            .setNeutralButton("Attributions") { dialog, which ->
                val inputStream = assets.open("attributions.html")
                val bytes = inputStream.readBytes().decodeToString()
                val url = "data:text/html;charset=utf8,$bytes"

                startActivity(
                    Intent.makeMainSelectorActivity(
                        Intent.ACTION_MAIN, Intent.CATEGORY_APP_BROWSER
                    )
                        .setData(url.toUri())
                )
            }
            .setCancelable(false)
            .show()
    }
}