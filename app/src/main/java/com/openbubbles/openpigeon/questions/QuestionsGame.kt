package com.openbubbles.openpigeon.questions

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.background
import androidx.glance.appwidget.cornerRadius
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity

class QuestionsGame : Game {
    private var secretWord: String = ""

    override fun getVersion() = "0"
    override fun getName() = "questions"
    override fun displayName() = "20 Questions"
    override fun isConfigurable() = true

    @Composable
    override fun Configuration(context: Context?) {
        val current = if (secretWord.isBlank()) "" else secretWord

        val intent = Intent(context, SecretWordActivity::class.java)
            .putExtra("game_name", getName())
            .putExtra("initial", current)

        Column(
            modifier = GlanceModifier
                .padding(16.dp)
                .fillMaxWidth()
                .cornerRadius(16.dp)
                .background(ColorProvider(Color(0xFF2B2B2B)))
                .padding(16.dp)
                .clickable(onClick = actionStartActivity(intent))
        ) {
            Text(
                text = "SECRET WORD",
                style = TextStyle(
                    color = ColorProvider(Color(0xFFEDEDED)),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold
                )
            )
            Text(
                text = if (secretWord.isBlank()) "Think of something" else secretWord,
                style = TextStyle(
                    color = ColorProvider(Color(0xFFF0F0F0))),
                modifier = GlanceModifier.padding(top = 10.dp, bottom = 8.dp)
            )
            Text(
                text = "Your friends will have to guess it in 20 questions or less.",
                style = TextStyle(
                    color = ColorProvider(Color(0xFFBEBEBE)),
                    fontSize = 12.sp
                )
            )
        }
    }

    override fun setConfigOption(name: String, value: String) {
        if (name.equals("answer", true)) secretWord = value
    }

    override fun gameClass(): Class<*> = GodotGameActivity::class.java
    override fun gamePoster(config: Map<String, String>?): Int = R.drawable.questions_preview
    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        if (secretWord.isBlank()) {
            val intent = Intent(context, SecretWordActivity::class.java)
                .putExtra("game_name", getName())
                .putExtra("initial", "")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            return null
        }

        return super.getNewGameData(context)?.apply {
            put("answer", secretWord)
        }
    }

    fun markSecretWordConsumed() {
        secretWord = ""
    }

    override fun getDefaultReplay() = ""
}
