package com.openbubbles.openpigeon

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.core.net.toUri
import com.google.android.material.dialog.MaterialAlertDialogBuilder

// used for google play open
class MainEntryActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val launchIntent = packageManager.getLaunchIntentForPackage("com.openbubbles.messaging")
        if (launchIntent != null) {
            Toast.makeText(this, "Add OpenPigeon like you would a photo.", Toast.LENGTH_LONG).show()
            // Start main activity
            startActivity(launchIntent)
            finishAndRemoveTask()
        } else {
            MaterialAlertDialogBuilder(this, com.google.android.material.R.style.ThemeOverlay_Material3_MaterialAlertDialog)
                .setTitle("OpenBubbles not installed")
                .setMessage("To use iMessage, OpenPigeon requires OpenBubbles. Learn how to get started at openbubbles.app")
                .setNegativeButton("Cancel") { dialog, which ->
                    finishAndRemoveTask()
                }
                .setPositiveButton("Open") { dialog, which ->
                    val intent = Intent(Intent.ACTION_VIEW)
                    intent.data = "https://openbubbles.app".toUri()
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    finishAndRemoveTask()
                }
                .setCancelable(false)
                .show()
        }
    }
}