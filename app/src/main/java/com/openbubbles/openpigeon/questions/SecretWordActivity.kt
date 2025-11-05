package com.openbubbles.openpigeon.questions

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.openbubbles.openpigeon.MadridExtension
import com.openbubbles.openpigeon.MadridExtensionService

@Composable
private fun QuestionsDarkScheme() = darkColorScheme(
    surface = androidx.compose.ui.graphics.Color(0xFF2B2B2B),
    onSurface = androidx.compose.ui.graphics.Color(0xFFEDEDED),
    onSurfaceVariant = androidx.compose.ui.graphics.Color(0xFFBEBEBE),
)

class SecretWordActivity : ComponentActivity() {

    private val ui = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Transparent, dimmed “dialog”
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        @Suppress("DEPRECATION")
        window.addFlags(WindowManager.LayoutParams.FLAG_BLUR_BEHIND)
        window.attributes = window.attributes.apply { dimAmount = 0.6f }

        val gameName = intent.getStringExtra("game_name") ?: "questions"
        val initial  = intent.getStringExtra("initial") ?: ""

        setContent {
            MaterialTheme(colorScheme = QuestionsDarkScheme()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Surface(shape = RoundedCornerShape(16.dp), tonalElevation = 8.dp) {
                        CardContent(
                            initial = initial,
                            onCancel = { finish() },
                            onSave = { value ->
                                // 1) Persist the value on the game instance
                                MadridExtension.findByName(gameName)
                                    ?.setConfigOption("answer", value)

                                // 2) Tell keyboard to show this game's config and repaint
                                MadridExtensionService.extension?.let { ext ->
                                    MadridExtension.findByName(gameName)?.let { game ->
                                        ext.configuringGame = game
                                    }
                                    ext.updateKeyboard()
                                }

                                // 3) Hand focus back to host WITHOUT immediately finishing.
                                //    Make this window non-focusable/invisible so the host regains focus
                                //    (IME stays alive), then finish after a short delay.
                                window.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)
                                window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                                window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
                                // Nudge another couple of repaints to survive OEM transition timing.
                                MadridExtensionService.extension?.updateKeyboard()
                                ui.postDelayed({ MadridExtensionService.extension?.updateKeyboard() }, 120)
                                ui.postDelayed({ MadridExtensionService.extension?.updateKeyboard() }, 250)

                                // 4) Finally finish once the host should be back on top.
                                ui.postDelayed({ finish() }, 300)
                            }
                        )
                    }
                }
            }
        }
    }

    // IMPORTANT: do NOT auto-finish on pause; that collapses the keyboard on some OEMs.
    // override fun onPause() { super.onPause(); finish() }  // <-- leave this out
}

@Composable
private fun CardContent(
    initial: String,
    onCancel: () -> Unit,
    onSave: (String) -> Unit
) {
    var text by remember { mutableStateOf(initial.ifBlank { "" }) }

    Column(
        modifier = Modifier.padding(20.dp).widthIn(min = 260.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("SECRET WORD", style = MaterialTheme.typography.titleSmall)
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            singleLine = true,
            placeholder = { Text("Think of something") },
            modifier = Modifier.fillMaxWidth()
        )
        Text(
            "Your friends will have to guess it in 20 questions or less.",
            style = MaterialTheme.typography.bodySmall
        )
        Button(
            onClick = { onSave(text.trim()) },
            modifier = Modifier.fillMaxWidth(),
            enabled = text.isNotBlank()
        ) { Text("Save") }
        TextButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) {
            Text("Cancel")
        }
    }
}
