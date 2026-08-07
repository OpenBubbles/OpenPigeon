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
import java.util.Calendar

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

            setTextColor(
                com.google.android.material.color.MaterialColors.getColor(
                    this@AboutActivity,
                    com.google.android.material.R.attr.colorOnSurface,
                    0
                )
            )

            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
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
        MaterialAlertDialogBuilder(
            this,
            com.google.android.material.R.style
                .ThemeOverlay_Material3_MaterialAlertDialog
        )
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
            "↻   Reset Stats",
            "♙   Reset Avatar",
            "▶   Reset Tutorial",
            "⚠   Reset Everything",
            "‹   Back"
        )

        MaterialAlertDialogBuilder(
            this,
            com.google.android.material.R.style
                .ThemeOverlay_Material3_MaterialAlertDialog
        )
            .setTitle("Options")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> {
                        showAttributions()
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
                        confirmReset(
                            title = "Reset stats?",
                            message =
                                "This will clear your win counts " +
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

                    4 -> {
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

                    5 -> {
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

                    6 -> {
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

                    7 -> {
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
        MaterialAlertDialogBuilder(
            this,
            com.google.android.material.R.style
                .ThemeOverlay_Material3_MaterialAlertDialog
        )
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
        MaterialAlertDialogBuilder(
            this,
            com.google.android.material.R.style
                .ThemeOverlay_Material3_MaterialAlertDialog
        )
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
                }.onFailure { error ->
                    OpenPigeonLog.e(
                        "Diagnostics",
                        "Unable to create diagnostic report",
                        error
                    )

                    MaterialAlertDialogBuilder(
                        this,
                        com.google.android.material.R.style
                            .ThemeOverlay_Material3_MaterialAlertDialog
                    )
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
        MaterialAlertDialogBuilder(
            this,
            com.google.android.material.R.style
                .ThemeOverlay_Material3_MaterialAlertDialog
        )
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

    private fun resetStats() {
        getSharedPreferences(
            "game_stats",
            MODE_PRIVATE
        ).edit {
            clear()
        }
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