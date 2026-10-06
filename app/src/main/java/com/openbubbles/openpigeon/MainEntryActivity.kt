package com.openbubbles.openpigeon

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.core.net.toUri
import com.google.android.material.dialog.MaterialAlertDialogBuilder

// used for Google Play open
class MainEntryActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val launchIntent = packageManager.getLaunchIntentForPackage("com.openbubbles.messaging")
        if (launchIntent != null) {
            Toast.makeText(this, "Choose OpenPigeon in the photo picker.", Toast.LENGTH_LONG).show()
            // Start main activity
            startActivity(launchIntent)
            finishAndRemoveTask()
        } else {
            MaterialAlertDialogBuilder(
                this,
                com.google.android.material.R.style.ThemeOverlay_Material3_MaterialAlertDialog
            )
                .setTitle("OpenBubbles not installed")
                .setMessage(
                    "OpenPigeon uses iMessage to send messages. Due to Apple's restrictions, " +
                            "OpenPigeon cannot connect to iMessage directly and requires OpenBubbles.\n\n" +
                            "Install and set up OpenBubbles to continue."
                )
                .setNegativeButton("Cancel") { _, _ ->
                    finishAndRemoveTask()
                }
                .setPositiveButton("Set Up OpenBubbles") { _, _ ->
                    val intent = Intent(Intent.ACTION_VIEW)
                    intent.data = "https://openbubbles.app/quickstart.html".toUri()
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    finishAndRemoveTask()
                }
                .setCancelable(false)
                .show()
        }
    }
}