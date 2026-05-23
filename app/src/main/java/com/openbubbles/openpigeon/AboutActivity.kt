package com.openbubbles.openpigeon

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import java.util.Calendar

class AboutActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val currentYear = Calendar.getInstance().get(Calendar.YEAR)
        val versionText = "Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

        showAboutDialog(currentYear, versionText)
    }

    private fun showAboutDialog(currentYear: Int, versionText: String) {
        MaterialAlertDialogBuilder(this, com.google.android.material.R.style.ThemeOverlay_Material3_MaterialAlertDialog)
            .setTitle("OpenPigeon")
            .setMessage(buildAboutMessage(currentYear, versionText))
            .setPositiveButton("Done") { _, _ ->
                finishAndRemoveTask()
            }
            .setNegativeButton("More…") { _, _ ->
                showMoreOptions(currentYear, versionText)
            }
            .setNeutralButton("GitHub") { _, _ ->
                val intent = Intent(Intent.ACTION_VIEW)
                intent.data = "https://github.com/OpenBubbles/OpenPigeon".toUri()
                startActivity(intent)
                finishAndRemoveTask()
            }
            .setCancelable(false)
            .show()
    }

    private fun showMoreOptions(currentYear: Int, versionText: String) {
        val options = arrayOf("Attributions", "Reset Stats", "Reset Avatar", "Reset Tutorial", "Reset Everything", "Back")
        MaterialAlertDialogBuilder(this, com.google.android.material.R.style.ThemeOverlay_Material3_MaterialAlertDialog)
            .setTitle("More options")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> showAttributions()
                    1 -> confirmReset("Reset stats?", "This will clear your win counts for all games. This cannot be undone.", currentYear, versionText) {
                        resetStats(); showAboutDialog(currentYear, versionText)
                    }
                    2 -> confirmReset("Reset avatar?", "This will reset your avatar to defaults. This cannot be undone.", currentYear, versionText) {
                        resetAvatar(); showAboutDialog(currentYear, versionText)
                    }
                    3 -> confirmReset("Reset tutorial?", "The welcome tutorial will appear again next time you open the game picker.", currentYear, versionText) {
                        resetTutorial(); showAboutDialog(currentYear, versionText)
                    }
                    4 -> confirmReset("Reset everything?", "This will clear your stats, avatar, and tutorial state. This cannot be undone.", currentYear, versionText) {
                        resetStats(); resetAvatar(); resetTutorial()
                        showAboutDialog(currentYear, versionText)
                    }
                    5 -> showAboutDialog(currentYear, versionText)
                }
            }
            .setCancelable(true)
            .setOnCancelListener { showAboutDialog(currentYear, versionText) }
            .show()
    }

    private fun confirmReset(
        title: String,
        message: String,
        currentYear: Int,
        versionText: String,
        onConfirm: () -> Unit
    ) {
        MaterialAlertDialogBuilder(this, com.google.android.material.R.style.ThemeOverlay_Material3_MaterialAlertDialog)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton("Reset") { _, _ -> onConfirm() }
            .setNegativeButton("Cancel") { _, _ -> showAboutDialog(currentYear, versionText) }
            .setOnCancelListener { showAboutDialog(currentYear, versionText) }
            .show()
    }

    private fun showAttributions() {
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

    private fun resetStats() {
        getSharedPreferences("game_stats", MODE_PRIVATE).edit().clear().apply()
    }

    private fun resetAvatar() {
        getSharedPreferences("avatar_settings", MODE_PRIVATE).edit().clear().apply()
        // Also delete the Godot settings.cfg so it gets regenerated from defaults next time
        val cfgFile = java.io.File(filesDir, "settings.cfg")
        if (cfgFile.exists()) cfgFile.delete()
    }

    private fun resetTutorial() {
        getSharedPreferences("openpigeon", MODE_PRIVATE).edit()
            .putBoolean("tutorial_seen", false)
            .apply()
    }
}

private fun buildAboutMessage(currentYear: Int, versionText: String): String {
    return """
		$versionText

		Copyright © $currentYear OpenPigeon Contributors
		
		OpenPigeon is fully open-source, and we're looking for game developers to contribute to their favorite games. If you're interested, find out more on GitHub.

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
	""".trimIndent()
}

@Composable
private fun AboutPreviewContent(
    currentYear: Int = 2026,
    versionText: String = "Version 1.4.0 (26052301)"
) {
    MaterialTheme {
        Surface(
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(
                modifier = Modifier
                    .padding(24.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    text = "OpenPigeon",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )

                Text(
                    text = buildAboutMessage(currentYear, versionText),
                    modifier = Modifier.padding(top = 16.dp),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

@Preview(
    name = "About Screen",
    showBackground = true,
    widthDp = 360,
    heightDp = 720
)
@Composable
private fun AboutActivityPreview() {
    AboutPreviewContent()
}