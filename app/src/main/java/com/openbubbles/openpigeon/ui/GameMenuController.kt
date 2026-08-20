package com.openbubbles.openpigeon.ui

import android.app.Activity
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.SettingScope
import com.openbubbles.openpigeon.settings.SettingsSheet
import com.openbubbles.openpigeon.util.LoopingWavPlayer
import com.openbubbles.openpigeon.util.OpenPigeonLog

enum class GameMenuPlacement(
    val gravity: Int,
    val isTop: Boolean,
    val isEnd: Boolean,
) {
    TOP_END(
        Gravity.TOP or Gravity.END,
        true,
        true,
    ),

    BOTTOM_START(
        Gravity.BOTTOM or Gravity.START,
        false,
        false,
    ),

    BOTTOM_END(
        Gravity.BOTTOM or Gravity.END,
        false,
        true,
    ),
}


class GameMenuController(
    private val activity: Activity,
    private val rootFrame: FrameLayout,
    private val gameId: String,
    rulesTitle: String,
    rulesSections: List<RulesPopup.Section>,
    musicAssetPath: String? = null,
    private val placement: GameMenuPlacement = GameMenuPlacement.BOTTOM_START,
    existingButton: ImageButton? = null,
    showDarkMode: Boolean = true,
    showMusic: Boolean = true,
    fallbackDarkOverlayAlpha: Float = 0f,
    private val onDarkModeChanged: (Boolean) -> Unit = {},
    private val onMusicChanged: (Boolean) -> Unit = {},
    onSettingsClosed: (() -> Unit)? = null,
) {
    val sheet = SettingsSheet(
        activity,
        rootFrame,
    )

    private var currentRulesTitle = rulesTitle

    private var currentRulesSections = rulesSections

    private var currentMusicAssetPath = musicAssetPath

    private var musicPlayer = createMusicPlayer(
        musicAssetPath,
    )

    private var activityResumed = false

    private val ownsButton = existingButton == null

    private lateinit var menuButton: ImageButton

    private lateinit var menuOverlay: FrameLayout

    private lateinit var menuPanel: LinearLayout

    private var menuOpen = false
    private var musicEnabled = false
    private var musicUnavailable = false

    private val darkOverlay = fallbackDarkOverlayAlpha.takeIf {
            it > 0f
        }?.let { overlayAlpha ->
            View(
                activity,
            ).apply {
                setBackgroundColor(
                    Color.BLACK,
                )

                alpha = 0f
                isClickable = false
                isFocusable = false

                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO

                tag = overlayAlpha.coerceIn(
                    0f,
                    1f,
                )
            }.also { overlay ->
                rootFrame.addView(
                    overlay,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    ),
                )
            }
        }

    init {
        AvatarData.init(
            activity.applicationContext,
        )

        sheet.onClosed = onSettingsClosed

        if (showDarkMode) {
            sheet.addBooleanSetting(
                label = "Dark Mode",
                scope = SettingScope.Global,
                key = "dark_mode",
                default = false,
            ) { enabled ->
                darkOverlay?.alpha = if (enabled) {
                    darkOverlay.tag as Float
                } else {
                    0f
                }

                onDarkModeChanged(
                    enabled,
                )
            }
        }

        if (
            showMusic &&
            currentMusicAssetPath != null
        ) {
            sheet.addBooleanSetting(
                label = "Music",
                scope = SettingScope.Global,
                key = "music_enabled",
                default = true,
            ) { enabled ->
                musicEnabled =
                    enabled

                onMusicChanged(
                    enabled,
                )

                val player =
                    musicPlayer

                if (!enabled) {
                    musicUnavailable =
                        false

                    player?.stop()
                } else if (
                    !musicUnavailable &&
                    player != null &&
                    !player.start()
                ) {
                    musicUnavailable =
                        true

                    OpenPigeonLog.e(
                        "GameMenu",
                        "Unable to start music for game=$gameId",
                    )
                }
            }
        }

        buildMenu(
            existingButton,
        )
    }

    fun updateRules(
        title: String,
        sections: List<RulesPopup.Section>,
    ) {
        currentRulesTitle = title

        currentRulesSections = sections
    }


    fun updateMusicAssetPath(
        assetPath: String?,
    ) {
        if (currentMusicAssetPath == assetPath) {
            return
        }

        musicPlayer?.stop()

        currentMusicAssetPath = assetPath

        musicPlayer = createMusicPlayer(
            assetPath,
        )

        musicUnavailable = false

        if (activityResumed && musicEnabled) {
            val player = musicPlayer ?: return

            if (!player.start()) {
                musicUnavailable = true

                OpenPigeonLog.e(
                    "GameMenu",
                    "Unable to start updated music for game=$gameId asset=$assetPath",
                )
            }
        }
    }


    fun bringToFront() {
        if (::menuOverlay.isInitialized && menuOpen) {
            menuOverlay.bringToFront()
            menuPanel.bringToFront()
        }

        if (::menuButton.isInitialized) {
            menuButton.bringToFront()
        }
    }

    fun addMenuAction(
        label: String,
        closeMenuOnClick: Boolean = true,
        action: () -> Unit,
    ): TextView {
        val row =
            menuRow(
                label = label,
            ) {
                if (closeMenuOnClick) {
                    setMenuVisible(
                        false,
                    )
                }

                action()
            }

        menuPanel.addView(
            row,
        )

        return row
    }


    fun closeMenu() {
        setMenuVisible(
            false,
        )
    }

    private fun createMusicPlayer(
        assetPath: String?,
    ): LoopingWavPlayer? {
        return assetPath?.let { path ->
            LoopingWavPlayer(
                context = activity,
                assetPath = path,
            )
        }
    }

    fun openSettings() {
        setMenuVisible(
            false,
        )

        sheet.open()
    }

    fun openRules() {
        setMenuVisible(
            false,
        )

        RulesPopup.show(
            context = activity,
            rootView = rootFrame,
            title = currentRulesTitle,
            sections = currentRulesSections,
        )
    }

    fun refresh() {
        sheet.refreshFromStorage()
    }

    fun onResume() {
        activityResumed = true
        refresh()

        if (musicEnabled && !musicUnavailable) {
            if (!musicPlayer?.resume().orFalse()) {
                musicUnavailable = true
            }
        }
    }

    fun onPause() {
        activityResumed = false
        setMenuVisible(
            false,
        )

        musicPlayer?.pause()
    }

    fun destroy() {
        activityResumed = false
        musicPlayer?.stop()
        sheet.onClosed = null
        sheet.detach()

        darkOverlay?.let { overlay ->
            (overlay.parent as? ViewGroup)?.removeView(
                    overlay,
                )
        }

        if (::menuOverlay.isInitialized) {
            (menuOverlay.parent as? ViewGroup)?.removeView(
                    menuOverlay,
                )
        }

        if (ownsButton && ::menuButton.isInitialized) {
            (menuButton.parent as? ViewGroup)?.removeView(
                    menuButton,
                )
        }
    }

    private fun Boolean?.orFalse(): Boolean {
        return this == true
    }

    private fun buildMenu(
        existingButton: ImageButton?,
    ) {
        menuOverlay = FrameLayout(
            activity,
        ).apply {
            visibility = View.GONE

            alpha = 1f
            isClickable = true

            setBackgroundColor(
                Color.argb(
                    34,
                    0,
                    0,
                    0,
                ),
            )

            setOnClickListener {
                setMenuVisible(
                    false,
                )
            }
        }

        menuPanel = LinearLayout(
            activity,
        ).apply {
            orientation = LinearLayout.VERTICAL

            isClickable = true
            elevation = dp(12f)

            background = GradientDrawable().apply {
                cornerRadius = dp(
                    10f,
                )

                setColor(
                    Color.argb(
                        242,
                        255,
                        255,
                        255,
                    ),
                )

                setStroke(
                    dp(
                        1f,
                    ).toInt(),
                    Color.argb(
                        35,
                        0,
                        0,
                        0,
                    ),
                )
            }

            setPadding(
                0,
                dp(6f).toInt(),
                0,
                dp(6f).toInt(),
            )

            setOnClickListener {}
        }

        menuPanel.addView(
            menuRow(
                "Settings",
                ::openSettings,
            ),
        )

        menuPanel.addView(
            menuRow(
                "Help",
                ::openRules,
            ),
        )

        menuOverlay.addView(
            menuPanel,
            panelLayoutParams(),
        )

        rootFrame.addView(
            menuOverlay,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        menuButton = existingButton ?: ImageButton(
            activity,
        ).also { button ->
            rootFrame.addView(
                button,
                buttonLayoutParams(),
            )
        }

        configureButton(
            menuButton,
        )
    }

    private fun configureButton(
        button: ImageButton,
    ) {
        button.visibility = View.VISIBLE

        button.alpha = 0.86f
        button.background = null

        button.scaleType = ImageView.ScaleType.FIT_CENTER

        button.setPadding(
            dp(5f).toInt(),
            dp(5f).toInt(),
            dp(5f).toInt(),
            dp(5f).toInt(),
        )

        runCatching {
            activity.assets.open(
                    "global/burger.png",
                ).use {
                    BitmapFactory.decodeStream(
                        it,
                    )
                }
        }.onSuccess {
            button.setImageBitmap(
                it,
            )
        }.onFailure {
            OpenPigeonLog.e(
                "GameMenu",
                "Missing global/burger.png",
                it,
            )
        }

        button.setOnClickListener {
            setMenuVisible(
                !menuOpen,
            )
        }

        button.bringToFront()
    }

    private fun setMenuVisible(
        visible: Boolean,
    ) {
        if (!::menuOverlay.isInitialized || !::menuPanel.isInitialized) {
            return
        }

        menuOpen = visible

        menuOverlay.animate().cancel()
        menuPanel.animate().cancel()

        if (!visible) {
            menuOverlay.visibility = View.GONE

            menuOverlay.alpha = 1f
            menuPanel.alpha = 1f
            menuPanel.scaleX = 1f
            menuPanel.scaleY = 1f
            return
        }

        menuOverlay.alpha = 0f

        menuOverlay.visibility = View.VISIBLE

        menuPanel.alpha = 0f
        menuPanel.scaleX = 0.92f
        menuPanel.scaleY = 0.92f

        menuOverlay.bringToFront()
        menuPanel.bringToFront()
        menuButton.bringToFront()

        menuOverlay.animate().alpha(
                1f,
            ).setDuration(
                100L,
            ).start()

        menuPanel.animate().alpha(
                1f,
            ).scaleX(
                1f,
            ).scaleY(
                1f,
            ).setDuration(
                130L,
            ).start()
    }

    private fun menuRow(
        label: String,
        action: () -> Unit,
    ): TextView {
        return TextView(
            activity,
        ).apply {
            text = label

            textSize = 16f
            gravity = Gravity.CENTER_VERTICAL

            setTextColor(
                Color.rgb(
                    15,
                    15,
                    15,
                ),
            )

            typeface = android.graphics.Typeface.DEFAULT_BOLD

            setPadding(
                dp(14f).toInt(),
                0,
                dp(14f).toInt(),
                0,
            )

            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(44f).toInt(),
            )

            setOnClickListener {
                action()
            }
        }
    }

    private fun buttonLayoutParams(): FrameLayout.LayoutParams {
        return FrameLayout.LayoutParams(
            dp(48f).toInt(),
            dp(48f).toInt(),
            placement.gravity,
        ).apply {
            val sideMargin = dp(
                8f,
            ).toInt()

            if (placement.isEnd) {
                rightMargin = sideMargin
            } else {
                leftMargin = sideMargin
            }

            if (placement.isTop) {
                topMargin = dp(
                    36f,
                ).toInt()
            } else {
                bottomMargin = dp(
                    16f,
                ).toInt()
            }
        }
    }

    private fun panelLayoutParams(): FrameLayout.LayoutParams {
        return FrameLayout.LayoutParams(
            dp(132f).toInt(),
            FrameLayout.LayoutParams.WRAP_CONTENT,
            placement.gravity,
        ).apply {
            val sideMargin = dp(
                10f,
            ).toInt()

            if (placement.isEnd) {
                rightMargin = sideMargin
            } else {
                leftMargin = sideMargin
            }

            if (placement.isTop) {
                topMargin = dp(
                    92f,
                ).toInt()
            } else {
                bottomMargin = dp(
                    72f,
                ).toInt()
            }
        }
    }

    private fun dp(
        value: Float,
    ): Float {
        return value * activity.resources.displayMetrics.density
    }
}