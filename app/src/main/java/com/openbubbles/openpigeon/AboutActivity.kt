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

        MaterialAlertDialogBuilder(this, com.google.android.material.R.style.ThemeOverlay_Material3_MaterialAlertDialog)
            .setTitle("OpenPigeon")
            .setMessage(buildAboutMessage(currentYear, versionText))
            .setPositiveButton("Done") { _, _ ->
                finishAndRemoveTask()
            }
            .setNegativeButton("GitHub") { _, _ ->
                val intent = Intent(Intent.ACTION_VIEW)
                intent.data = "https://github.com/OpenBubbles/OpenPigeon".toUri()
                startActivity(intent)
                finishAndRemoveTask()
            }
            .setNeutralButton("Attributions") { _, _ ->
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