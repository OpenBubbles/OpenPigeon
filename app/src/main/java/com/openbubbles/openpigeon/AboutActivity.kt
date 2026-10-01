package com.openbubbles.openpigeon

import android.app.Activity
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.edit
import androidx.core.content.pm.PackageInfoCompat
import androidx.core.net.toUri
import androidx.core.text.HtmlCompat
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.openbubbles.openpigeon.util.OpenPigeonLog
import android.text.format.DateUtils
import android.widget.ScrollView
import com.openbubbles.openpigeon.settings.AvatarView
import com.openbubbles.openpigeon.settings.GameStats
import java.util.Calendar
import android.content.DialogInterface
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import com.google.android.material.R as MaterialR
import com.google.android.material.color.MaterialColors

class AboutActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val currentYear = Calendar.getInstance().get(Calendar.YEAR)

        val packageInfo = packageManager.getPackageInfo(
            packageName,
            0
        )

        val versionName = packageInfo.versionName ?: "Unknown"
        val versionCode = PackageInfoCompat.getLongVersionCode(
            packageInfo
        )

        val versionText =
            "Version $versionName ($versionCode)"

        showAboutDialog(
            currentYear,
            versionText
        )
    }

    private fun dp(value: Int): Int {
        return (
                value *
                        resources.displayMetrics.density
                ).toInt()
    }

    private fun dialog() = MaterialAlertDialogBuilder(this, MaterialR.style.ThemeOverlay_Material3_MaterialAlertDialog)

    private fun buildTitleView(): LinearLayout {
        val icon = ImageView(this).apply {
            setImageResource(
                R.drawable.madrid_icon_small
            )

            layoutParams = LinearLayout.LayoutParams(
                dp(40),
                dp(40)
            )

            adjustViewBounds = true
        }

        val title = TextView(this).apply {
            setText(R.string.app_name)

            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD

            setTextColor(color(MaterialR.attr.colorOnSurface))

            layoutParams = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                marginStart = dp(14)
            }
        }

        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL

            setPadding(
                dp(24),
                dp(22),
                dp(24),
                dp(8)
            )

            addView(icon)
            addView(title)
        }
    }

    private fun showAboutDialog(
        currentYear: Int,
        versionText: String
    ) {
        dialog()
            .setCustomTitle(
                buildTitleView()
            )
            .setMessage(
                buildAboutMessage(
                    currentYear,
                    versionText
                )
            )
            .setNeutralButton(
                "Done"
            ) { _, _ ->
                finishAndRemoveTask()
            }
            .setNegativeButton(
                "Options"
            ) { _, _ ->
                showMoreOptions(
                    currentYear,
                    versionText
                )
            }
            .setPositiveButton(
                "GitHub"
            ) { _, _ ->
                val intent = Intent(
                    Intent.ACTION_VIEW
                ).apply {
                    data =
                        "https://github.com/OpenBubbles/OpenPigeon"
                            .toUri()
                }

                startActivity(intent)
                finishAndRemoveTask()
            }

            .setOnCancelListener {
                finishAndRemoveTask()
            }

            .show()
    }

    private fun showMoreOptions(
        currentYear: Int,
        versionText: String
    ) {
        val options = arrayOf(
            "ⓘ   Attributions",
            "⚖   License",
            "✉   Send Diagnostic Report",
            "▦   Stats",
            "↻   Reset Stats",
            "♙   Reset Avatar",
            "▶   Reset Tutorial",
            "⚠   Reset Everything",
            "‹   Back"
        )

        dialog()
            .setTitle("Options")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> {
                        showAttributions()
                        showMoreOptions(currentYear, versionText)
                    }

                    1 -> {
                        showLicenseInfo(
                            currentYear,
                            versionText
                        )
                    }

                    2 -> {
                        confirmDiagnosticReport(
                            currentYear,
                            versionText
                        )
                    }

                    3 -> {
                        showStats(
                            currentYear,
                            versionText
                        )
                    }

                    4 -> {
                        confirmReset(
                            title = "Reset stats?",
                            message =
                                "This will clear your win counts and records " +
                                        "for all games. This cannot " +
                                        "be undone.",
                            currentYear = currentYear,
                            versionText = versionText
                        ) {
                            resetStats()

                            showAboutDialog(
                                currentYear,
                                versionText
                            )
                        }
                    }

                    5 -> {
                        confirmReset(
                            title = "Reset avatar?",
                            message =
                                "This will reset your avatar to " +
                                        "defaults. This cannot be undone.",
                            currentYear = currentYear,
                            versionText = versionText
                        ) {
                            resetAvatar()

                            showAboutDialog(
                                currentYear,
                                versionText
                            )
                        }
                    }

                    6 -> {
                        confirmReset(
                            title = "Reset tutorial?",
                            message =
                                "The welcome tutorial will appear " +
                                        "again next time you open the " +
                                        "game picker.",
                            currentYear = currentYear,
                            versionText = versionText
                        ) {
                            resetTutorial()

                            showAboutDialog(
                                currentYear,
                                versionText
                            )
                        }
                    }

                    7 -> {
                        confirmReset(
                            title = "Reset everything?",
                            message =
                                "This will clear your stats, avatar, " +
                                        "and tutorial state. This cannot " +
                                        "be undone.",
                            currentYear = currentYear,
                            versionText = versionText
                        ) {
                            resetStats()
                            resetAvatar()
                            resetTutorial()

                            showAboutDialog(
                                currentYear,
                                versionText
                            )
                        }
                    }

                    8 -> {
                        showAboutDialog(
                            currentYear,
                            versionText
                        )
                    }
                }
            }
            .setCancelable(true)
            .setOnCancelListener {
                showAboutDialog(
                    currentYear,
                    versionText
                )
            }
            .show()
    }

    private fun showLicenseInfo(
        currentYear: Int,
        versionText: String
    ) {
        dialog()
            .setTitle("OpenPigeon License")
            .setMessage(
                """
            OpenPigeon is source-available.

            The source code may be viewed, studied, modified, and contributed to under the terms of the OpenPigeon Source License.

            Commercial redistribution, repackaging, white-label distribution, embedding OpenPigeon games into another product, or publishing modified versions requires separate permission.

            Applications may integrate with the separately installed OpenPigeon app through its documented integration interfaces.

            Copyright © 2023-$currentYear OpenPigeon Contributors.
            """.trimIndent()
            )
            .setPositiveButton(
                "View Full License"
            ) { _, _ ->
                val intent = Intent(
                    Intent.ACTION_VIEW
                ).apply {
                    data =
                        "https://github.com/OpenBubbles/OpenPigeon/blob/HEAD/LICENSE"
                            .toUri()
                }

                startActivity(intent)
                showLicenseInfo(currentYear, versionText)
            }
            .setNegativeButton(
                "Back"
            ) { _, _ ->
                showMoreOptions(
                    currentYear,
                    versionText
                )
            }
            .setOnCancelListener {
                showMoreOptions(
                    currentYear,
                    versionText
                )
            }
            .show()
    }

    private fun confirmDiagnosticReport(
        currentYear: Int,
        versionText: String
    ) {
        dialog()
            .setTitle(
                "Send diagnostic report?"
            )
            .setMessage(
                """
                OpenPigeon will create a sanitized ZIP containing recent warnings, errors, safe diagnostic events, and basic app and device information.

                Player and session identifiers are replaced with consistent labels such as p1uid, p2uid, uid1, and session1. This allows related events to be followed without including the original identifiers.

                Emails, URLs, IP addresses, authentication data, avatar data, contact names, and user-message fields are removed.

                Your email app will open with the report addressed to support@colerabe.com. You can review or cancel the email before sending it.
                """.trimIndent()
            )
            .setPositiveButton(
                "Create report"
            ) { _, _ ->
                runCatching {
                    OpenPigeonLog.shareReport(
                        this
                    )
                }.onSuccess {
                    showAboutDialog(currentYear, versionText)
                }.onFailure { error ->
                    OpenPigeonLog.e(
                        "Diagnostics",
                        "Unable to create diagnostic report",
                        error
                    )

                    dialog()
                        .setTitle(
                            "Report could not be created"
                        )
                        .setMessage(
                            "OpenPigeon could not prepare the " +
                                    "diagnostic report. Please try again."
                        )
                        .setPositiveButton(
                            "OK"
                        ) { _, _ ->
                            showAboutDialog(
                                currentYear,
                                versionText
                            )
                        }

                        .setOnCancelListener {
                            showAboutDialog(
                                currentYear,
                                versionText
                            )
                        }

                        .show()
                }
            }
            .setNegativeButton(
                "Cancel"
            ) { _, _ ->
                showAboutDialog(
                    currentYear,
                    versionText
                )
            }
            .setOnCancelListener {
                showAboutDialog(
                    currentYear,
                    versionText
                )
            }
            .show()
    }

    private fun confirmReset(
        title: String,
        message: String,
        currentYear: Int,
        versionText: String,
        onConfirm: () -> Unit
    ) {
        dialog()
            .setTitle(
                title
            )
            .setMessage(
                message
            )
            .setPositiveButton(
                "Reset"
            ) { _, _ ->
                onConfirm()
            }
            .setNegativeButton(
                "Cancel"
            ) { _, _ ->
                showAboutDialog(
                    currentYear,
                    versionText
                )
            }
            .setOnCancelListener {
                showAboutDialog(
                    currentYear,
                    versionText
                )
            }
            .show()
    }

    private fun showAttributions() {
        val inputStream = assets.open(
            "attributions.html"
        )

        val bytes = inputStream
            .readBytes()
            .decodeToString()

        val url =
            "data:text/html;charset=utf8,$bytes"

        startActivity(
            Intent.makeMainSelectorActivity(
                Intent.ACTION_MAIN,
                Intent.CATEGORY_APP_BROWSER
            ).setData(
                url.toUri()
            )
        )
    }

    private fun color(attr: Int) = MaterialColors.getColor(this, attr, 0)

    private fun pct(w: Int, l: Int) = if (w + l == 0) "—" else "${w * 100 / (w + l)}%"

    private fun recordText(w: Int, l: Int, d: Int) = if (d > 0) "$w–$l–$d" else "$w–$l"

    private fun ago(seconds: Long) = DateUtils.getRelativeTimeSpanString(seconds * 1000).toString()

    private fun gameLabel(game: String) = MadridExtension.findByName(game)?.displayName() ?: game

    private fun statText(value: CharSequence, size: Float, color: Int, bold: Boolean = false) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(color)
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    private fun statSection(title: String) =
        statText(title.uppercase(), 12f, color(MaterialR.attr.colorPrimary), bold = true).apply {
            letterSpacing = 0.08f
            setPadding(dp(2), dp(20), 0, dp(2))
        }

    private fun statRow(vararg children: View) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        children.forEach { addView(it) }
    }

    private fun statCard(vararg children: View) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(14), dp(12), dp(14), dp(12))
        background = GradientDrawable().apply {
            cornerRadius = dp(14).toFloat()
            setColor((color(MaterialR.attr.colorSurfaceVariant) and 0x00FFFFFF) or (0x99 shl 24))
        }
        layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = dp(10) }
        children.forEach { addView(it) }
    }

    private fun recordBar(w: Int, l: Int, d: Int) = LinearLayout(this).apply {
        layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, dp(6)).apply { topMargin = dp(10) }
        background = GradientDrawable().apply {
            cornerRadius = dp(3).toFloat()
            setColor((color(MaterialR.attr.colorOutline) and 0x00FFFFFF) or (0x40 shl 24))
        }
        clipToOutline = true
        for ((n, c) in listOf(w to MaterialR.attr.colorPrimary, d to MaterialR.attr.colorOutline, l to MaterialR.attr.colorError)) {
            if (n > 0) addView(View(this@AboutActivity).apply {
                setBackgroundColor(color(c))
                layoutParams = LinearLayout.LayoutParams(0, MATCH_PARENT, n.toFloat())
            })
        }
    }

    private fun rivalCard(opponent: String, w: Int, l: Int, d: Int, detail: String, footer: String?, onTap: () -> Unit): LinearLayout {
        val named = GameStats.opponentName(opponent)
        return statCard(
            statRow(
                AvatarView(this).apply {
                    GameStats.opponentAvatar(opponent)?.let { applyFromOpponentString(it) } ?: showPlaceholder()
                    layoutParams = LinearLayout.LayoutParams(dp(32), dp(46)).apply { marginEnd = dp(12) }
                },
                LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
                    addView(statText(named ?: "Unnamed opponent", 15f, color(MaterialR.attr.colorOnSurface), bold = true))
                    addView(statText(if (named == null) "$detail  ·  Tap to name" else detail, 12f, color(MaterialR.attr.colorOnSurfaceVariant)))
                },
                LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.END
                    addView(statText(recordText(w, l, d), 17f, color(MaterialR.attr.colorOnSurface), bold = true))
                    addView(statText(pct(w, l), 12f, color(MaterialR.attr.colorOnSurfaceVariant)))
                },
            ),
            recordBar(w, l, d),
        ).apply {
            if (footer != null) addView(statText(footer, 12f, color(MaterialR.attr.colorOnSurfaceVariant)).apply { setPadding(0, dp(8), 0, 0) })
            setOnClickListener { onTap() }
        }
    }

    private fun statDialog(title: String, content: LinearLayout, onBack: () -> Unit) =
        dialog()
            .setTitle(title)
            .setView(ScrollView(this).apply { addView(content) })
            .setPositiveButton("Back") { _, _ -> onBack() }
            .setOnCancelListener { onBack() }
            .show()

    private fun renameRival(opponent: String, done: () -> Unit) {
        val input = android.widget.EditText(this).apply {
            setText(GameStats.opponentName(opponent).orEmpty())
            hint = "Name"
            setSingleLine()
        }
        MaterialAlertDialogBuilder(this, MaterialR.style.ThemeOverlay_Material3_MaterialAlertDialog)
            .setTitle("Name this opponent")
            .setMessage("Only shown on this device.")
            .setView(LinearLayout(this).apply { setPadding(dp(24), 0, dp(24), 0); addView(input, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)) })
            .setPositiveButton("Save") { _, _ -> GameStats.setOpponentName(opponent, input.text.toString()); done() }
            .setNegativeButton("Cancel") { _, _ -> done() }
            .setOnCancelListener { done() }
            .show()
    }

    private fun showStats(
        currentYear: Int,
        versionText: String
    ) {
        GameStats.init(this)
        val onSurface = color(MaterialR.attr.colorOnSurface)
        val muted = color(MaterialR.attr.colorOnSurfaceVariant)
        val records = GameStats.allRecords()
        val allWins = GameStats.allWins()
        val w = records.sumOf { it.wins }
        val l = records.sumOf { it.losses }
        var dialog: DialogInterface? = null
        val reopen = { showStats(currentYear, versionText) }

        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(4), dp(18), dp(12))
        }

        list.addView(statRow(*listOf(
            "${allWins.values.sum()}" to "Wins",
            pct(w, l) to "Win rate",
            "${records.distinctBy { it.opponent }.size}" to "Opponents",
            "${records.maxOfOrNull { it.bestStreak } ?: 0}" to "Best streak",
        ).map { (value, name) ->
            statCard(
                statText(value, 20f, onSurface, bold = true).apply { gravity = Gravity.CENTER },
                statText(name, 11f, muted).apply { gravity = Gravity.CENTER },
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(dp(4), dp(10), dp(4), dp(10))
                layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).apply { marginStart = dp(3); marginEnd = dp(3) }
            }
        }.toTypedArray()))

        if (records.isEmpty()) {
            list.addView(statText("Finish a game against someone to start tracking records, streaks and opponents.", 14f, muted).apply { setPadding(dp(2), dp(18), dp(2), 0) })
        }

        val rivals = records.groupBy { it.opponent }.entries.sortedByDescending { (_, rs) -> rs.sumOf { it.wins + it.losses + it.draws } }
        if (rivals.isNotEmpty()) list.addView(statSection("Opponents"))

        for ((opponent, rs) in rivals) {
            list.addView(rivalCard(
                opponent, rs.sumOf { it.wins }, rs.sumOf { it.losses }, rs.sumOf { it.draws },
                ago(rs.maxOf { it.lastPlayed }),
                rs.sortedByDescending { it.wins + it.losses + it.draws }.joinToString("   ") { "${gameLabel(it.game)} ${recordText(it.wins, it.losses, it.draws)}" },
            ) {
                dialog?.dismiss()
                renameRival(opponent, reopen)
            })
        }

        val games = (records.map { it.game } + allWins.keys).distinct()
            .sortedByDescending { g -> records.filter { it.game == g }.maxOfOrNull { it.lastPlayed } ?: 0L }
        if (games.isNotEmpty()) list.addView(statSection("By game"))

        for (game in games) {
            val rs = records.filter { it.game == game }
            val gw = rs.sumOf { it.wins }
            val gl = rs.sumOf { it.losses }
            val gd = rs.sumOf { it.draws }
            val best = rs.maxOfOrNull { it.bestStreak } ?: 0
            list.addView(statCard(
                statRow(
                    statText(gameLabel(game), 15f, onSurface, bold = true).apply { layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f) },
                    statText("${allWins[game] ?: 0} wins", 13f, onSurface, bold = true),
                ),
                statText(
                    if (rs.isEmpty()) "Records start with your next finished game"
                    else "${recordText(gw, gl, gd)}  ·  ${pct(gw, gl)} win rate  ·  ${rs.size} ${if (rs.size == 1) "opponent" else "opponents"}" + if (best >= 2) "  ·  best streak $best" else "",
                    12f, muted
                ).apply { setPadding(0, dp(4), 0, 0) },
                recordBar(gw, gl, gd),
            ).apply {
                if (rs.isNotEmpty()) setOnClickListener {
                    dialog?.dismiss()
                    showGameStats(game, reopen)
                }
            })
        }

        dialog = statDialog("Stats", list) { showMoreOptions(currentYear, versionText) }
    }

    private fun showGameStats(game: String, onBack: () -> Unit) {
        var dialog: DialogInterface? = null
        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(4), dp(18), dp(12))
        }

        for (r in GameStats.allRecords().filter { it.game == game }.sortedByDescending { it.lastPlayed }) {
            val streak = when {
                r.streak >= 2 -> "Won last ${r.streak}"
                r.streak <= -2 -> "Lost last ${-r.streak}"
                else -> null
            }
            list.addView(rivalCard(
                r.opponent, r.wins, r.losses, r.draws,
                listOfNotNull(ago(r.lastPlayed), streak).joinToString("  ·  "),
                if (r.bestStreak >= 2) "Best streak: ${r.bestStreak} wins" else null,
            ) {
                dialog?.dismiss()
                renameRival(r.opponent) { showGameStats(game, onBack) }
            })
        }

        dialog = statDialog(gameLabel(game), list, onBack)
    }

    private fun resetStats() {
        GameStats.init(this)
        GameStats.clearAll()
    }

    private fun resetAvatar() {
        getSharedPreferences(
            "avatar_settings",
            MODE_PRIVATE
        ).edit {
            clear()
        }

        // Also delete the Godot settings.cfg so it gets
        // regenerated from defaults next time.
        val cfgFile = java.io.File(
            filesDir,
            "settings.cfg"
        )

        if (cfgFile.exists()) {
            cfgFile.delete()
        }
    }

    private fun resetTutorial() {
        getSharedPreferences(
            "openpigeon",
            MODE_PRIVATE
        ).edit {
            putBoolean(
                "tutorial_seen",
                false
            )
        }
    }
}

private const val RULE =
    "<font color=\"#40808080\">" +
            "————————————————————" +
            "</font>"

private const val ACCENT = "#7C4DFF"

private fun buildAboutMessage(
    currentYear: Int,
    versionText: String
): CharSequence {

    fun contributor(
        handle: String,
        credit: String
    ): String {
        return (
                "<p>" +
                        "<b>" +
                        "<font color=\"$ACCENT\">" +
                        handle +
                        "</font>" +
                        "</b>" +
                        "<br>" +
                        "<small>" +
                        credit +
                        "</small>" +
                        "</p>"
                )
    }

    val html = """
        <p><small>$versionText<br>
        Copyright © 2023-$currentYear OpenPigeon Contributors</small></p>

        <p>OpenPigeon is source-available, and we're looking for game developers
        to contribute their favorite games.</p>

        <p align="center">$RULE</p>

        <p><b>Thank you to our contributors</b></p>

        ${contributor(
        "ty8447",
        "Game development and maintenance"
    )}

        ${contributor(
        "jakecrowley",
        "Archery, Basketball, Checkers, Cup Pong, Darts, Four in a Row"
    )}

        ${contributor(
        "Copper",
        "8 Ball, Crazy 8, Sea Battle"
    )}

        ${contributor(
        "chasedredmon",
        "Chess"
    )}

        ${contributor(
        "npulse4",
        "Word Hunt"
    )}

        <p align="center">$RULE</p>

        <p><small>Are you a developer? Add your favorite game on GitHub.</small></p>
    """.trimIndent()

    return HtmlCompat.fromHtml(
        html,
        HtmlCompat.FROM_HTML_MODE_COMPACT
    )
}