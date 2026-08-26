package com.openbubbles.openpigeon.settings

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.*
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.*
import android.view.animation.DecelerateInterpolator
import android.widget.*
import androidx.core.view.isVisible
import androidx.appcompat.widget.SwitchCompat
import androidx.core.graphics.toColorInt
import com.openbubbles.openpigeon.R
import java.util.WeakHashMap
import kotlin.math.min

private class SettingsMaxHeightScrollView(context: Context) : ScrollView(context) {
    var maxHeightPx: Int = Int.MAX_VALUE

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val cappedHeight = if (maxHeightPx == Int.MAX_VALUE) heightMeasureSpec else View.MeasureSpec.makeMeasureSpec(maxHeightPx, View.MeasureSpec.AT_MOST)
        super.onMeasure(widthMeasureSpec, cappedHeight)
    }
}

class SettingsSheet(
    private val context: Context, private val rootFrame: FrameLayout

) {

    companion object {
        private const val Z_SETTINGS_DIM = 50000f
        private const val Z_SETTINGS_CARD = 50001f
    }

    // ── dp helpers ────────────────────────────────────────────────────────────
    private fun dp(v: Float) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics
    ).toInt()

    private fun dpf(v: Float) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics
    )

    // ── Colors ───────────────────────────────────────────────────────────────
    private val COL_CARD = "#1e1e2e".toColorInt()
    private val COL_HANDLE = "#555566".toColorInt()
    private val COL_LABEL = "#aaaacc".toColorInt()
    private val COL_TAB_SEL = "#a78bfa".toColorInt()
    private val COL_TAB_UNSEL = "#666688".toColorInt()
    private val COL_SEL_BORDER = "#a78bfa".toColorInt()
    private val COL_DIVIDER = "#333355".toColorInt()

    // ── Views ─────────────────────────────────────────────────────────────────
    private val dimView: View
    private val card: LinearLayout
    private val contentScroll: SettingsMaxHeightScrollView
    private val content: LinearLayout

    private lateinit var mainPreview: AvatarView
    private lateinit var headerRow: LinearLayout
    private lateinit var headerNameContainer: LinearLayout
    private lateinit var headerNameEdit: EditText

    private var headerNameEnabled = false
    private var suppressHeaderNameCallback = false
    private var onHeaderNameChanged: ((String) -> Unit)? = null
    private lateinit var tabBar: LinearLayout
    private lateinit var pickerScroll: HorizontalScrollView
    private lateinit var pickerRow: LinearLayout
    private lateinit var colorRowContainer: LinearLayout
    private lateinit var colorRow: LinearLayout
    private lateinit var brightnessContainer: FrameLayout
    private lateinit var controlsSection: LinearLayout
    private lateinit var controlsContainer: LinearLayout
    private lateinit var miscRowsContainer: LinearLayout

    // In-game avatars
    private var gameAvatarView: AvatarView? = null
    private var oppAvatarView: AvatarView? = null
    private var gameAvatarRefreshEnabled = true

    private val extraRows = mutableListOf<View>()

    private data class BooleanSettingBinding(
        val scope: SettingScope,
        val key: String,
        val default: Boolean,
        val switch: SwitchCompat,
        val onChanged: (Boolean) -> Unit,
        var suppressCallback: Boolean = false,
    )

    private val booleanSettingBindings = mutableListOf<BooleanSettingBinding>()

    private var isOpen = false

    var onClosed: (() -> Unit)? = null
    private var hasNotifiedClosed = false

    private enum class Tab { BACKGROUND, BODY, HAIR, FACE, CLOTHING, HATS, MISC }

    private var currentTab = Tab.HAIR
    private val tabViews = mutableMapOf<Tab, ImageView>()
    private var miscTabAdded = false
    private var settingsDarkMode = true
    private val baseTextColors = WeakHashMap<TextView, Int>()
    private val baseSurfaceColors = WeakHashMap<View, Int>()
    private val paletteSkipSurface = WeakHashMap<View, Boolean>()

    // Slider state
    private var currentSliderBaseColor: Int = Color.GRAY
    private var brightnessProgress: Int = 100

    // Shader cache - only rebuilt on color change
    private var cachedTrackShader: Shader? = null
    private var cachedTrackColor: Int = -1
    private var cachedTrackWidth: Float = 0f

    private var gradientTrackView: View? = null
    private var gradientThumbDrawable: GradientDrawable? = null
    private var gradientThumbView: View? = null

    // Thumb diameter in px - set once in buildGradientSlider, used in positionThumb
    private var thumbDiameterPx: Int = 0

    sealed class PickerPreview {
        data class Asset(val path: String) : PickerPreview()
        data class DrawableResource(val resourceId: Int) : PickerPreview()
        data class Custom(val createView: (Context) -> View) : PickerPreview()
    }

    data class PickerItem(val id: String, val label: String = "", val preview: PickerPreview)

    private data class StringSettingBinding(
        val scope: SettingScope,
        val key: String,
        val default: String,
        val applyValue: (String) -> Unit,
        val onChanged: (String) -> Unit,
    )

    private val stringSettingBindings = mutableListOf<StringSettingBinding>()

    fun addGameControl(label: String, controlView: View) {
        addGameControl(label, "", controlView)
    }

    fun addGameControl(label: String, subtitle: String, controlView: View) {
        if (!::controlsSection.isInitialized) return
        controlsSection.isVisible = true
        content.setPadding(0, 0, 0, 0)
        controlsContainer.addView(buildGameControlCard(label, subtitle, controlView))
        updateResponsiveLayout()
    }

    fun addGameControl(label: String, subtitle: String, controlView: View, inCustomTab: Boolean) {
        if (!inCustomTab) {
            addGameControl(label, subtitle, controlView)
            return
        }
        if (!::miscRowsContainer.isInitialized) return
        miscRowsContainer.addView(buildGameControlCard(label, subtitle, controlView))
        ensureCustomTab()
        updateResponsiveLayout()
    }

    fun ensureCustomTab() = ensureMiscTab()

    fun addBooleanSetting(
        label: String,
        scope: SettingScope,
        key: String,
        default: Boolean,
        onChanged: (Boolean) -> Unit,
    ): SwitchCompat = addBooleanSetting(label, "", scope, key, default, onChanged = onChanged)

    fun addBooleanSetting(
        label: String,
        subtitle: String,
        scope: SettingScope,
        key: String,
        default: Boolean,
        inCustomTab: Boolean = false,
        onChanged: (Boolean) -> Unit,
    ): SwitchCompat {
        SettingsData.init(context)
        val control = SwitchCompat(context)
        val states = arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf())
        control.thumbTintList = ColorStateList(states, intArrayOf(Color.WHITE, Color.WHITE))
        control.trackTintList = ColorStateList(states, intArrayOf(COL_TAB_SEL, "#444455".toColorInt()))
        val binding = BooleanSettingBinding(scope, key, default, control, onChanged)
        control.setOnCheckedChangeListener { _, checked ->
            if (binding.suppressCallback) return@setOnCheckedChangeListener
            SettingsData.putBoolean(binding.scope, binding.key, checked)
            binding.onChanged(checked)
        }
        booleanSettingBindings += binding
        addGameControl(label, subtitle, control, inCustomTab)
        refreshBooleanSetting(binding)
        return control
    }

    fun addOptionSetting(
        label: String,
        subtitle: String,
        scope: SettingScope,
        key: String,
        items: List<Pair<String, String>>,
        default: String,
        inCustomTab: Boolean = false,
        onChanged: (String) -> Unit,
    ): Spinner {
        SettingsData.init(context)
        val spinner = Spinner(context)
        val labels = items.map { it.second }
        val adapter = ArrayAdapter(context, android.R.layout.simple_spinner_item, labels).apply { setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
        spinner.adapter = adapter
        spinner.background = GradientDrawable().apply { setColor("#2a2a3a".toColorInt()); cornerRadius = dpf(10f); setStroke(dp(1f), COL_DIVIDER) }
        spinner.setPadding(dp(10f), 0, dp(10f), 0)
        spinner.minimumWidth = dp(130f)
        var suppress = true
        spinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent: AdapterView<*>?) {}
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (suppress || position !in items.indices) return
                val selected = items[position].first
                SettingsData.putString(scope, key, selected)
                onChanged(selected)
            }
        }
        val binding = StringSettingBinding(scope, key, default, { value ->
            val index = items.indexOfFirst { it.first == value }.let { if (it >= 0) it else items.indexOfFirst { it.first == default }.coerceAtLeast(0) }
            suppress = true
            if (items.isNotEmpty()) spinner.setSelection(index, false)
            suppress = false
        }, onChanged)
        stringSettingBindings += binding
        addGameControl(label, subtitle, spinner, inCustomTab)
        refreshStringSetting(binding)
        return spinner
    }

    fun addPickerSetting(
        title: String,
        subtitle: String,
        scope: SettingScope,
        key: String,
        items: List<PickerItem>,
        default: String,
        onChanged: (String) -> Unit,
    ): View {
        SettingsData.init(context)

        val section = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).also {
                it.bottomMargin = dp(12f)
            }
        }

        section.addView(TextView(context).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 14f
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        })

        if (subtitle.isNotBlank()) {
            section.addView(TextView(context).apply {
                text = subtitle
                setTextColor(COL_LABEL)
                textSize = 11f
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).also {
                    it.topMargin = dp(2f)
                }
            })
        }

        val scroll = HorizontalScrollView(context).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(108f)).also {
                it.topMargin = dp(6f)
            }
        }

        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(2f), dp(2f), dp(2f))
        }

        scroll.addView(row)
        section.addView(scroll)

        val cells = linkedMapOf<String, View>()

        fun applySelection(value: String) {
            cells.forEach { (id, cell) ->
                cell.background = pickerBorder(id == value)
            }
        }

        for (item in items) {
            val cell = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(dp(90f), dp(100f)).also {
                    it.rightMargin = dp(8f)
                }
                setPadding(dp(5f), dp(5f), dp(5f), dp(4f))
            }

            paletteSkipSurface[cell] = true

            val previewHost = FrameLayout(context).apply {
                layoutParams = LinearLayout.LayoutParams(dp(74f), dp(74f))
                clipChildren = false
                clipToPadding = false
            }

            previewHost.addView(createPickerPreview(item.preview))
            cell.addView(previewHost)

            if (item.label.isNotBlank()) {
                cell.addView(TextView(context).apply {
                    text = item.label
                    setTextColor(Color.WHITE)
                    textSize = 10f
                    gravity = Gravity.CENTER
                    maxLines = 1
                    layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).also {
                        it.topMargin = dp(2f)
                    }
                })
            }

            cell.setOnClickListener {
                SettingsData.putString(scope, key, item.id)
                applySelection(item.id)
                onChanged(item.id)
            }

            cells[item.id] = cell
            row.addView(cell)
        }

        val binding = StringSettingBinding(scope, key, default, ::applySelection, onChanged)
        stringSettingBindings += binding

        miscRowsContainer.addView(section)
        ensureMiscTab()
        refreshStringSetting(binding)
        updateResponsiveLayout()
        return section
    }

    fun refreshGameControls(refreshFromGodot: Boolean = true) {
        if (refreshFromGodot) SettingsData.refreshFromGodot()
        booleanSettingBindings.forEach(::refreshBooleanSetting)
        stringSettingBindings.forEach(::refreshStringSetting)
    }

    fun refreshFromStorage() {
        SettingsData.refreshFromGodot()
        refreshGameControls(refreshFromGodot = false)
        refreshHeaderAvatar()
    }

    private fun refreshBooleanSetting(binding: BooleanSettingBinding) {
        val enabled = SettingsData.getBoolean(binding.scope, binding.key, binding.default)
        binding.suppressCallback = true
        if (binding.switch.isChecked != enabled) binding.switch.isChecked = enabled
        binding.suppressCallback = false
        binding.onChanged(enabled)
    }

    private fun refreshStringSetting(binding: StringSettingBinding) {
        val value = SettingsData.getString(binding.scope, binding.key, binding.default)
        binding.applyValue(value)
        binding.onChanged(value)
    }

    private fun buildGameCard(): LinearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).also { it.bottomMargin = dp(8f) }
        background = GradientDrawable().apply { setColor("#1a1a24".toColorInt()); cornerRadius = dpf(16f); setStroke(dp(1f), "#47475f".toColorInt()) }
        setPadding(dp(12f), dp(10f), dp(12f), dp(10f))
    }

    private fun buildGameCopy(title: String, subtitle: String): LinearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_VERTICAL
        addView(TextView(context).apply { text = title; setTextColor(Color.WHITE); textSize = 16f })
        if (subtitle.isNotBlank()) addView(TextView(context).apply { text = subtitle; setTextColor(COL_LABEL); textSize = 12f; setPadding(0, dp(2f), 0, 0) })
    }

    private fun buildGameControlCard(title: String, subtitle: String, controlView: View): View {
        val card = buildGameCard()
        val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val copy = buildGameCopy(title, subtitle).apply { layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f) }
        row.addView(copy)
        if (controlView.parent is ViewGroup) (controlView.parent as ViewGroup).removeView(controlView)
        controlView.layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).also { it.leftMargin = dp(12f) }
        row.addView(controlView)
        card.addView(row)
        return card
    }

    private fun paletteInvert(color: Int, saturationScale: Float): Int {
        val hsv = FloatArray(3)
        Color.colorToHSV(color, hsv)
        if (hsv[1] >= 0.35f) return color
        hsv[1] *= saturationScale
        hsv[2] = 1f - hsv[2] * 0.8f
        return Color.HSVToColor(Color.alpha(color), hsv)
    }

    private fun paletteSurface(color: Int) = if (settingsDarkMode) color else paletteInvert(color, 0.4f)

    private fun paletteText(color: Int) = if (settingsDarkMode) color else paletteInvert(color, 1f)

    private fun tabTint(selected: Boolean) = if (selected) COL_TAB_SEL else paletteText(COL_TAB_UNSEL)

    fun setDarkMode(enabled: Boolean) {
        if (settingsDarkMode == enabled) return
        settingsDarkMode = enabled
        applyPalette()
        updateResponsiveLayout()
    }

    private fun applyPalette() {
        applyPaletteTo(card)
        tabViews.forEach { (tab, view) -> view.imageTintList = ColorStateList.valueOf(tabTint(tab == currentTab)) }
    }

    private fun applyPaletteTo(view: View) {
        if (view is AvatarView) return

        if (view is TextView) {
            val base = baseTextColors.getOrPut(view) { view.currentTextColor }
            view.setTextColor(paletteText(base))
        }

        if (paletteSkipSurface[view] != true) {
            val bg = view.background
            if (bg is ColorDrawable) {
                val base = baseSurfaceColors.getOrPut(view) { bg.color }
                view.setBackgroundColor(paletteSurface(base))
            } else if (bg is GradientDrawable) {
                bg.color?.defaultColor?.let { current ->
                    val base = baseSurfaceColors.getOrPut(view) { current }
                    bg.setColor(paletteSurface(base))
                }
            }
        }

        if (view is ViewGroup) for (i in 0 until view.childCount) applyPaletteTo(view.getChildAt(i))
    }

    private fun pickerBorder(selected: Boolean) = GradientDrawable().apply {
        setColor(paletteSurface(if (selected) "#2a2640".toColorInt() else "#20202c".toColorInt()))
        cornerRadius = dpf(12f)
        setStroke(dp(if (selected) 2f else 1f), if (selected) COL_SEL_BORDER else "#3b3b50".toColorInt())
    }

    private fun createPickerPreview(preview: PickerPreview): View {
        val view = when (preview) {
            is PickerPreview.Asset -> ImageView(context).apply {
                scaleType = ImageView.ScaleType.FIT_CENTER
                try { context.assets.open(preview.path).use { setImageBitmap(BitmapFactory.decodeStream(it)) } } catch (_: Exception) { setImageDrawable(null) }
            }
            is PickerPreview.DrawableResource -> ImageView(context).apply { scaleType = ImageView.ScaleType.FIT_CENTER; setImageResource(preview.resourceId) }
            is PickerPreview.Custom -> preview.createView(context)
        }
        if (view.parent is ViewGroup) (view.parent as ViewGroup).removeView(view)
        view.layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT, Gravity.CENTER)
        return view
    }

    private fun tabLabel(tab: Tab): String = when (tab) {
        Tab.CLOTHING -> "Clothes"
        Tab.HATS -> "Acc"
        Tab.MISC -> "Misc"
        else -> tab.name.lowercase().replaceFirstChar { it.uppercase() }
    }

    private fun tabIcon(tab: Tab): Int = when (tab) {
        Tab.BACKGROUND -> R.drawable.backgroundtab
        Tab.BODY -> R.drawable.bodytab
        Tab.HAIR -> R.drawable.hairtab
        Tab.FACE -> R.drawable.eyemouthtab
        Tab.CLOTHING -> R.drawable.clothingtab
        Tab.HATS -> R.drawable.hatglassestab
        Tab.MISC -> R.drawable.customtab
    }

    private fun createTabView(tab: Tab): ImageView = ImageView(context).apply {
        setImageResource(tabIcon(tab))
        scaleType = ImageView.ScaleType.FIT_CENTER
        imageTintList = ColorStateList.valueOf(tabTint(tab == currentTab))
        contentDescription = tabLabel(tab)
        layoutParams = LinearLayout.LayoutParams(0, dp(40f), 1f)
        setPadding(dp(7f), dp(7f), dp(7f), dp(7f))
        setOnClickListener { selectTab(tab) }
    }

    private fun ensureMiscTab() {
        if (miscTabAdded || !::tabBar.isInitialized) return
        val view = createTabView(Tab.MISC)
        tabViews[Tab.MISC] = view
        tabBar.addView(view)
        miscTabAdded = true
    }

    fun attachGameAvatar(gameRoot: FrameLayout) {
        gameAvatarView?.let {
            if (it.parent != null) {
                (it.parent as ViewGroup).removeView(it)
            }
        }

        val av = AvatarView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
            )
            applyFromAvatarData()
        }

        gameRoot.clipChildren = false
        gameRoot.clipToPadding = false
        gameRoot.addView(av)
        gameAvatarView = av

        AvatarView.configureTallAnchor(gameRoot)
    }

    fun attachOpponentAvatar(gameRoot: FrameLayout) {
        oppAvatarView?.let {
            if (it.parent != null) {
                (it.parent as ViewGroup).removeView(it)
            }
        }

        val av = AvatarView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
            )
            showPlaceholder()
        }

        gameRoot.clipChildren = false
        gameRoot.clipToPadding = false
        gameRoot.addView(av)
        oppAvatarView = av

        AvatarView.configureTallAnchor(gameRoot)
    }

    fun applyOpponentAvatarString(avatarString: String) {
        oppAvatarView?.applyFromOpponentString(avatarString)
    }

    fun setGameAvatarRefreshTarget(
        avatarView: AvatarView?,
    ) {
        gameAvatarView = avatarView
    }

    fun setGameAvatarRefreshEnabled(enabled: Boolean) {
        gameAvatarRefreshEnabled = enabled

        if (enabled) {
            refreshGameAvatar()
        }
    }

    fun refreshGameAvatar() {
        if (!gameAvatarRefreshEnabled) return

        gameAvatarView?.applyFromAvatarData()
    }

    fun configureHeaderNameField(
        enabled: Boolean,
        value: String = "",
        hint: String = "Player name",
        onChanged: ((String) -> Unit)? = null
    ) {
        headerNameEnabled = enabled
        onHeaderNameChanged = onChanged

        if (!::headerNameContainer.isInitialized || !::headerNameEdit.isInitialized) return

        headerNameContainer.isVisible = enabled
        if (enabled) {
            headerNameEdit.hint = hint
            setHeaderNameValue(value)
        }
    }

    fun setHeaderNameValue(value: String) {
        if (!::headerNameEdit.isInitialized) return

        val current = headerNameEdit.text?.toString().orEmpty()
        if (current == value) return

        suppressHeaderNameCallback = true
        headerNameEdit.setText(value)
        headerNameEdit.setSelection(headerNameEdit.text?.length ?: 0)
        suppressHeaderNameCallback = false
    }

    fun refreshHeaderAvatar() {
        if (::mainPreview.isInitialized) {
            mainPreview.applyFromAvatarData()
        }
        refreshGameAvatar()
    }

    // ── Construction ──────────────────────────────────────────────────────────
    init {
        dimView = View(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
            )

            setBackgroundColor(Color.argb(160, 0, 0, 0))
            alpha = 0f
            isVisible = false

            setSheetLayer(this, Z_SETTINGS_DIM)

            setOnClickListener { close() }
        }
        card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL)
            setSheetLayer(this, Z_SETTINGS_CARD)
            clipToOutline = true
            outlineProvider = ViewOutlineProvider.BACKGROUND
            isClickable = true
            isFocusable = true
            setOnClickListener { }
        }
        contentScroll = SettingsMaxHeightScrollView(context).apply {
            isFillViewport = false
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT)
        }
        contentScroll.addView(content)
        card.addView(contentScroll)
        buildCardContent()
        setupDragToDismiss()
        rootFrame.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> if (isOpen) updateResponsiveLayout() }
    }

    // ── Card content ──────────────────────────────────────────────────────────
    private fun buildCardContent() {
        // Handle
        content.addView(View(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp(40f), dp(4f)).also {
                it.gravity = Gravity.CENTER_HORIZONTAL
                it.topMargin = dp(12f); it.bottomMargin = dp(8f)
            }
            background = GradientDrawable().apply { setColor(COL_HANDLE); cornerRadius = dpf(2f) }
        })

        // Header row: centered avatar preview, optional name field on the right
        headerRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL or Gravity.CENTER_HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).also {
                it.leftMargin = dp(16f)
                it.rightMargin = dp(16f)
                it.bottomMargin = dp(12f)
            }
        }

        mainPreview = AvatarView(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp(110f), dp(160f))
        }

        headerNameContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).also {
                it.leftMargin = dp(12f)
            }
            isVisible = false
        }

        headerNameEdit = EditText(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                dp(180f), LinearLayout.LayoutParams.WRAP_CONTENT
            )
            hint = "Player name"
            isSingleLine = true
            setTextColor(Color.WHITE)
            setHintTextColor(COL_LABEL)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            background = GradientDrawable().apply {
                setColor("#2a2a3a".toColorInt())
                cornerRadius = dpf(10f)
                setStroke(dp(1f), COL_DIVIDER)
            }
            setPadding(dp(12f), dp(10f), dp(12f), dp(10f))

            addTextChangedListener(object : android.text.TextWatcher {
                override fun beforeTextChanged(
                    s: CharSequence?,
                    start: Int,
                    count: Int,
                    after: Int
                ) {
                }

                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(s: android.text.Editable?) {
                    if (!headerNameEnabled) return
                    if (suppressHeaderNameCallback) return
                    onHeaderNameChanged?.invoke(s?.toString().orEmpty())
                }
            })
        }

        headerNameContainer.addView(headerNameEdit)
        headerRow.addView(mainPreview)
        headerRow.addView(headerNameContainer)
        content.addView(headerRow)

        // Tab bar
        tabBar = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            )
            setPadding(dp(8f), 0, dp(8f), 0)
        }
        listOf(Tab.BACKGROUND, Tab.BODY, Tab.HAIR, Tab.FACE, Tab.CLOTHING, Tab.HATS).forEach { tab ->
            val tv = createTabView(tab)
            tabViews[tab] = tv
            tabBar.addView(tv)
        }
        content.addView(tabBar)

        // Divider
        content.addView(View(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(1f)
            ).also { it.leftMargin = dp(12f); it.rightMargin = dp(12f) }
            setBackgroundColor(COL_DIVIDER)
        })

        miscRowsContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).also {
                it.leftMargin = dp(12f)
                it.rightMargin = dp(12f)
                it.topMargin = dp(10f)
                it.bottomMargin = dp(4f)
            }
            isVisible = false
        }
        content.addView(miscRowsContainer)

        // Primary picker scroll
        pickerScroll = HorizontalScrollView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(96f),
            ).also {
                it.topMargin = dp(10f)
                it.bottomMargin = dp(4f)
            }
            isHorizontalScrollBarEnabled = false
        }
        pickerRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(12f), dp(4f), dp(12f), dp(4f))
        }
        pickerScroll.addView(pickerRow)
        content.addView(pickerScroll)

        // Color swatches - centered
        colorRowContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).also { it.topMargin = dp(6f) }
            gravity = Gravity.CENTER_HORIZONTAL
        }
        colorRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
            )
            setPadding(0, dp(4f), 0, dp(4f))
        }
        colorRowContainer.addView(colorRow)
        content.addView(colorRowContainer)

        // Gradient brightness slider
        brightnessContainer = buildGradientSlider()
        content.addView(brightnessContainer)

        // Game controls section
        controlsSection = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).also {
                it.leftMargin = dp(16f); it.rightMargin = dp(16f)
                it.topMargin = dp(4f); it.bottomMargin = dp(16f)
            }
            isVisible = false
        }
        controlsSection.addView(View(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(1f)
            ).also { it.bottomMargin = dp(10f) }
            setBackgroundColor(COL_DIVIDER)
        })
        controlsSection.addView(TextView(context).apply {
            text = "Global Settings"; setTextColor(Color.WHITE); textSize = 15f
            gravity = Gravity.CENTER_HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).also { it.bottomMargin = dp(8f) }
        })
        controlsContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        controlsSection.addView(controlsContainer)
        content.addView(controlsSection)
    }

    private fun buildGradientSlider(): FrameLayout {
        val thumbD = dp(22f)
        val trackH = dp(10f)
        val totalH = thumbD + dp(4f)
        val outerPad = dp(28f)    // outer margin from card edge
        val halfThumb = thumbD / 2

        thumbDiameterPx = thumbD

        // The container has extra horizontal padding equal to half the thumb diameter.
        // This means the track sits inset by halfThumb on each side, and the thumb
        // can slide fully to the ends without being clipped by the container edge.
        val container = FrameLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, totalH
            ).also {
                it.leftMargin = outerPad; it.rightMargin = outerPad
                it.topMargin = dp(8f); it.bottomMargin = dp(30f)
            }
            // Allow the thumb to draw outside the track bounds (into the padding)
            clipChildren = false
            clipToPadding = false
            // Horizontal padding reserves space for the thumb at each end
            setPadding(halfThumb, 0, halfThumb, 0)
            isVisible = false
        }

        // Track fills the container's padded width
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        val track = object : View(context) {
            override fun onDraw(c: Canvas) {
                val w = width.toFloat()
                if (cachedTrackColor != currentSliderBaseColor || cachedTrackShader == null || cachedTrackWidth != w) {
                    cachedTrackColor = currentSliderBaseColor
                    cachedTrackWidth = w
                    cachedTrackShader = buildTrackShader(currentSliderBaseColor, w)
                }
                trackPaint.shader = cachedTrackShader
                val r = height / 2f
                c.drawRoundRect(0f, 0f, w, height.toFloat(), r, r, trackPaint)
            }
        }.apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, trackH
            ).also { it.gravity = Gravity.CENTER_VERTICAL }
        }

        // Thumb
        val thumbDrawable = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.WHITE)
            setStroke(dp(2f), COL_SEL_BORDER)
        }
        val thumb = View(context).apply {
            layoutParams = FrameLayout.LayoutParams(thumbD, thumbD).also {
                it.gravity = Gravity.CENTER_VERTICAL or Gravity.START
            }
            background = thumbDrawable
            elevation = dpf(4f)
        }

        gradientTrackView = track
        gradientThumbView = thumb
        gradientThumbDrawable = thumbDrawable

        container.addView(track)
        container.addView(thumb)

        // Touch - x is relative to the padded track area
        container.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                    // Subtract padding so x=0 means start of track
                    val trackX = (event.x - halfThumb).coerceIn(0f, (v.width - thumbD).toFloat())
                    val trackW = (v.width - thumbD).toFloat()
                    val fraction = if (trackW > 0f) trackX / trackW else 0f
                    val progress = (fraction * 200f).toInt().coerceIn(0, 200)
                    brightnessProgress = progress
                    positionThumb(progress)

                    val brightness = (progress - 100) / 100f
                    applyBrightnessForCurrentTab(brightness)
                    thumbDrawable.setColor(computeAdjustedColor(currentSliderBaseColor, brightness))
                    refreshMainPreview()
                    true
                }

                MotionEvent.ACTION_UP -> {
                    refreshPickerTints()
                    true
                }

                else -> false
            }
        }

        container.post { positionThumb(brightnessProgress) }
        return container
    }

    private fun positionThumb(progress: Int) {
        val thumb = gradientThumbView ?: return
        val container = brightnessContainer
        if (container.width == 0) return

        val trackW =
            (container.width - thumbDiameterPx - container.paddingLeft - container.paddingRight).toFloat()
        val fraction = progress / 200f
        // translationX: 0 = track start (left padding), trackW = track end
        thumb.translationX = fraction * trackW
    }

    private fun buildTrackShader(baseColor: Int, width: Float): Shader {
        val hsv = FloatArray(3)
        Color.colorToHSV(baseColor, hsv)
        val dark =
            Color.HSVToColor(floatArrayOf(hsv[0], hsv[1], (hsv[2] * 0.3f).coerceAtLeast(0.05f)))
        val light = Color.HSVToColor(floatArrayOf(hsv[0], 0f, 1f))
        return LinearGradient(
            0f, 0f, width, 0f, intArrayOf(dark, baseColor, light), null, Shader.TileMode.CLAMP
        )
    }

    private fun computeAdjustedColor(base: Int, brightness: Float): Int {
        if (brightness == 0f) return base
        val hsv = FloatArray(3)
        Color.colorToHSV(base, hsv)
        if (brightness < 0f) {
            val t = brightness + 1f
            hsv[2] = hsv[2] * t + 0.3f * (1f - t)
        } else {
            hsv[1] = hsv[1] * (1f - brightness)
            hsv[2] = hsv[2] + (1f - hsv[2]) * brightness
        }
        return Color.HSVToColor(hsv)
    }

    private fun showBrightnessSlider(baseColor: Int, current: Float) {
        currentSliderBaseColor = baseColor
        brightnessProgress = ((current + 1f) * 100f).toInt().coerceIn(0, 200)
        cachedTrackShader = null
        cachedTrackColor = -1
        cachedTrackWidth = 0f
        gradientTrackView?.invalidate()
        val brightness = (brightnessProgress - 100) / 100f
        gradientThumbDrawable?.setColor(computeAdjustedColor(baseColor, brightness))
        brightnessContainer.isVisible = true
        brightnessContainer.post { positionThumb(brightnessProgress) }
    }

    private fun hideBrightnessSlider() {
        brightnessContainer.isVisible = false
    }

    private fun applyBrightnessForCurrentTab(v: Float) {
        when (currentTab) {
            Tab.BACKGROUND -> AvatarData.bgBrightness = v
            Tab.BODY -> AvatarData.fshapeBrightness = v
            Tab.HAIR -> AvatarData.hairBrightness = v
            Tab.CLOTHING -> AvatarData.clothingBrightness = v
            else -> {}
        }
    }

    // ── Extra row management ──────────────────────────────────────────────────
    private fun removeExtraRows() {
        extraRows.forEach { if (it.parent === content) content.removeView(it) }
        extraRows.clear()
    }

    private fun addExtraRow(view: View) {
        val insertAt = content.indexOfChild(pickerScroll) + 1 + extraRows.size
        content.addView(view, insertAt)
        extraRows.add(view)
    }

    // ── Tab selection ─────────────────────────────────────────────────────────
    private fun selectTab(tab: Tab) {
        removeExtraRows()
        currentTab = tab
        tabViews.forEach { (t, tv) ->
            tv.imageTintList = ColorStateList.valueOf(tabTint(t == tab))
        }
        miscRowsContainer.isVisible = tab == Tab.MISC
        pickerScroll.isVisible = tab != Tab.MISC
        buildPickerFor(tab)
    }

    // ── Picker builder ────────────────────────────────────────────────────────
    private fun buildPickerFor(tab: Tab) {
        pickerRow.removeAllViews()
        colorRow.removeAllViews()
        hideBrightnessSlider()
        colorRowContainer.isVisible = false
        miscRowsContainer.isVisible = tab == Tab.MISC
        pickerScroll.isVisible = tab != Tab.MISC
        applyPalette()

        when (tab) {
            Tab.BACKGROUND -> {
                buildStylePicker(
                    pickerRow,
                    listOf("Plain") + (1..9).map { "Pattern $it" },
                    AvatarData.bgStyle
                ) { AvatarData.bgStyle = it; refreshMainPreview() }
                buildColorSwatches(bgColors(), AvatarData.bgColor) { c ->
                    AvatarData.bgColor = c; onColorSwatchPicked(c)
                    refreshMainPreview(); rebuildCurrentPicker()
                }
                showBrightnessSlider(AvatarData.bgColor, AvatarData.bgBrightness)
            }

            Tab.BODY -> {
                buildStylePicker(
                    pickerRow,
                    listOf("Default") + (1..7).map { "fshape$it" },
                    AvatarData.fshapeStyle
                ) { AvatarData.fshapeStyle = it; refreshMainPreview() }
                buildColorSwatches(skinTones(), AvatarData.fshapeColor) { c ->
                    AvatarData.fshapeColor = c; onColorSwatchPicked(c)
                    refreshMainPreview(); rebuildCurrentPicker()
                }
                showBrightnessSlider(AvatarData.fshapeColor, AvatarData.fshapeBrightness)
            }

            Tab.HAIR -> {
                buildStylePicker(
                    pickerRow,
                    (1..15).map { "hair$it" },
                    AvatarData.hairStyle
                ) { AvatarData.hairStyle = it; refreshMainPreview() }
                buildColorSwatches(hairColors(), AvatarData.hairColor) { c ->
                    AvatarData.hairColor = c; onColorSwatchPicked(c)
                    refreshMainPreview(); rebuildCurrentPicker()
                }
                showBrightnessSlider(AvatarData.hairColor, AvatarData.hairBrightness)
            }

            Tab.FACE -> {
                buildStylePicker(
                    pickerRow,
                    (1..13).map { "eyes$it" },
                    AvatarData.eyesStyle
                ) { AvatarData.eyesStyle = it; refreshMainPreview() }
                val mouthScroll = HorizontalScrollView(context).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT, dp(96f)
                    ).also { it.topMargin = dp(4f); it.bottomMargin = dp(4f) }
                    isHorizontalScrollBarEnabled = false
                }
                val mouthRow = LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(dp(12f), dp(4f), dp(12f), dp(4f))
                }
                mouthScroll.addView(mouthRow)
                buildStylePicker(
                    mouthRow,
                    (1..17).map { "mouth$it" },
                    AvatarData.mouthStyle
                ) { AvatarData.mouthStyle = it; refreshMainPreview() }
                addExtraRow(mouthScroll)
            }

            Tab.CLOTHING -> {
                buildStylePicker(
                    pickerRow,
                    (1..3).map { "clothing$it" },
                    AvatarData.clothingStyle
                ) { AvatarData.clothingStyle = it; refreshMainPreview() }
                buildColorSwatches(clothingColors(), AvatarData.clothingColor) { c ->
                    AvatarData.clothingColor = c; onColorSwatchPicked(c)
                    refreshMainPreview(); rebuildCurrentPicker()
                }
                showBrightnessSlider(AvatarData.clothingColor, AvatarData.clothingBrightness)
            }

            Tab.HATS -> {
                buildStylePicker(
                    pickerRow,
                    (0..12).map { "hat_$it" },
                    AvatarData.headAccessoryStyle
                ) { style ->
                    AvatarData.headAccessoryStyle = style
                    refreshMainPreview()
                }

                val faceAccessoryScroll = HorizontalScrollView(context).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        dp(96f)
                    ).also {
                        it.topMargin = dp(4f)
                        it.bottomMargin = dp(4f)
                    }
                    isHorizontalScrollBarEnabled = false
                }

                val faceAccessoryRow = LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(dp(12f), dp(4f), dp(12f), dp(4f))
                }

                faceAccessoryScroll.addView(faceAccessoryRow)

                buildStylePicker(
                    faceAccessoryRow,
                    (1..14).map { "face_$it" },
                    AvatarData.faceAccessoryStyle
                ) { style ->
                    AvatarData.faceAccessoryStyle = style
                    refreshMainPreview()
                }

                addExtraRow(faceAccessoryScroll)
            }

            Tab.MISC -> {
                miscRowsContainer.isVisible = true
                pickerScroll.isVisible = false
            }
        }

        content.setPadding(0, 0, 0, if (controlsSection.isVisible) 0 else dp(20f))
    }

    private fun onColorSwatchPicked(color: Int) {
        currentSliderBaseColor = color
        cachedTrackShader = null; cachedTrackColor = -1; cachedTrackWidth = 0f
        gradientTrackView?.invalidate()
        val brightness = (brightnessProgress - 100) / 100f
        gradientThumbDrawable?.setColor(computeAdjustedColor(color, brightness))
    }

    private fun rebuildCurrentPicker() {
        removeExtraRows()
        buildPickerFor(currentTab)
    }

    // ── Style picker ──────────────────────────────────────────────────────────
    private fun buildStylePicker(
        row: LinearLayout, styles: List<String>, selected: String, onPick: (String) -> Unit
    ) {
        row.removeAllViews()
        styles.forEach { style ->
            val thumb = AvatarView(context).apply {
                layoutParams = LinearLayout.LayoutParams(dp(60f), dp(88f)).also {
                    it.rightMargin = dp(6f)
                }
                background = pillBorder(style == selected)
                applyPreview(previewStateFor(currentDrawState(), style))
                setOnClickListener {
                    onPick(style)
                    highlightSelected(row, this)
                    applyFromAvatarData()
                    refreshGameAvatar()
                }
            }
            row.addView(thumb)
        }
    }

    private fun pillBorder(selected: Boolean) = GradientDrawable().apply {
        setColor(Color.TRANSPARENT)
        cornerRadius = dpf(8f)
        if (selected) setStroke(dp(2f), COL_SEL_BORDER)
    }

    private fun highlightSelected(row: LinearLayout, selected: View) {
        for (i in 0 until row.childCount) {
            row.getChildAt(i).background = pillBorder(row.getChildAt(i) === selected)
        }
    }

    private fun refreshPickerTints() {
        for (i in 0 until pickerRow.childCount) {
            val thumb = pickerRow.getChildAt(i) as? AvatarView ?: continue
            val style = styleForIndex(currentTab, i)
            thumb.applyPreview(previewStateFor(currentDrawState(), style))
        }
    }

    private fun styleForIndex(tab: Tab, i: Int): String = when (tab) {
        Tab.BACKGROUND -> if (i == 0) "Plain" else "Pattern $i"
        Tab.BODY -> if (i == 0) "Default" else "fshape$i"
        Tab.HAIR -> "hair${i + 1}"
        Tab.FACE -> "eyes${i + 1}"
        Tab.CLOTHING -> "clothing${i + 1}"
        Tab.HATS -> "hat_$i"
        Tab.MISC -> ""
    }

    // ── Preview state ─────────────────────────────────────────────────────────
    private fun previewStateFor(base: AvatarView.DrawState, style: String) = when {
        style == "Plain" || style.startsWith("Pattern") -> base.copy(bgStyle = style)
        style == "Default" || style.startsWith("fshape") -> base.copy(fshapeStyle = style)
        style.startsWith("hair") -> base.copy(hairStyle = style)
        style.startsWith("eyes") -> base.copy(eyesStyle = style)
        style.startsWith("mouth") -> base.copy(mouthStyle = style)
        style.startsWith("clothing") -> base.copy(clothingStyle = style)
        style.startsWith("hat_") -> base.copy(headAccessoryStyle = style)
        style.startsWith("face_") -> base.copy(faceAccessoryStyle = style)
        else -> base
    }

    private fun currentDrawState() = AvatarView.DrawState(
        bgStyle = AvatarData.bgStyle,
        bgColor = AvatarData.bgColor,
        bgBrightness = AvatarData.bgBrightness,
        fshapeStyle = AvatarData.fshapeStyle,
        fshapeColor = AvatarData.fshapeColor,
        fshapeBrightness = AvatarData.fshapeBrightness,
        hairStyle = AvatarData.hairStyle,
        hairColor = AvatarData.hairColor,
        hairBrightness = AvatarData.hairBrightness,
        eyesStyle = AvatarData.eyesStyle,
        mouthStyle = AvatarData.mouthStyle,
        clothingStyle = AvatarData.clothingStyle,
        clothingColor = AvatarData.clothingColor,
        clothingBrightness = AvatarData.clothingBrightness,
        headAccessoryStyle = AvatarData.headAccessoryStyle,
        faceAccessoryStyle = AvatarData.faceAccessoryStyle
    )

    private fun refreshMainPreview() {
        mainPreview.applyFromAvatarData()
        refreshGameAvatar()
    }

    // ── Colour swatches ───────────────────────────────────────────────────────
    private fun buildColorSwatches(colors: List<Int>, current: Int, onPick: (Int) -> Unit) {
        colorRow.removeAllViews()
        colorRowContainer.isVisible = true
        colors.forEach { color ->
            colorRow.addView(View(context).apply {
                val size = dp(28f)
                layoutParams =
                    LinearLayout.LayoutParams(size, size).also { it.rightMargin = dp(6f) }
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL; setColor(color)
                    if (color == current) setStroke(dp(2f), COL_SEL_BORDER)
                }
                setOnClickListener {
                    onPick(color)
                    for (i in 0 until colorRow.childCount) {
                        val sv = colorRow.getChildAt(i)
                        (sv.background as? GradientDrawable)?.setStroke(
                            if (sv === this) dp(2f) else 0, COL_SEL_BORDER
                        )
                    }
                }
            })
        }
    }

    private fun updateResponsiveLayout() {
        val width = rootFrame.width
        val height = rootFrame.height
        if (width <= 0 || height <= 0) return
        val landscape = width > height
        val targetWidth = if (landscape) min((width * 0.92f).toInt(), dp(1100f)) else FrameLayout.LayoutParams.MATCH_PARENT
        val maxHeight = (height * if (landscape) 0.92f else 0.94f).toInt()
        contentScroll.maxHeightPx = maxHeight
        contentScroll.requestLayout()
        card.layoutParams = FrameLayout.LayoutParams(targetWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).also { it.bottomMargin = if (landscape) dp(10f) else 0 }
        paletteSkipSurface[card] = true
        card.background = GradientDrawable().apply {
            setColor(paletteSurface(COL_CARD))
            val r = dpf(22f)
            cornerRadii = if (landscape) floatArrayOf(r, r, r, r, r, r, r, r) else floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
        }
        card.requestLayout()
        applyPalette()
    }

    // ── Drag-to-dismiss ───────────────────────────────────────────────────────
    private fun setupDragToDismiss() {
        var dragStartY = 0f
        var dragging = false
        card.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    dragStartY = event.rawY; dragging = false; false
                }

                MotionEvent.ACTION_MOVE -> {
                    val delta = event.rawY - dragStartY
                    if (!dragging && delta > dp(10f)) dragging = true
                    if (dragging) {
                        card.translationY = (delta - dp(10f)).coerceAtLeast(0f)
                        dimView.alpha = (1f - card.translationY / card.height).coerceIn(0f, 1f)
                    }
                    false
                }

                MotionEvent.ACTION_UP -> {
                    if (dragging && card.translationY > card.height * 0.28f) close()
                    else {
                        card.animate().translationY(0f).setDuration(150).start()
                        dimView.animate().alpha(1f).setDuration(150).start()
                    }
                    false
                }

                else -> false
            }
        }
    }

    private fun setSheetLayer(view: View, layer: Float) {
        view.elevation = layer
        view.translationZ = 0f
        view.z = layer
    }

    private fun promoteSheet() {
        if (dimView.parent === rootFrame) {
            setSheetLayer(dimView, Z_SETTINGS_DIM)
            rootFrame.bringChildToFront(dimView)
            dimView.bringToFront()
        }

        if (card.parent === rootFrame) {
            setSheetLayer(card, Z_SETTINGS_CARD)
            rootFrame.bringChildToFront(card)
            card.bringToFront()
        }

        rootFrame.invalidate()
        dimView.invalidate()
        card.invalidate()
    }

    // ── Open / Close ──────────────────────────────────────────────────────────
    fun open() {
        if (isOpen) return
        refreshFromStorage()

        isOpen = true
        hasNotifiedClosed = false

        rootFrame.addView(dimView)
        rootFrame.addView(card)
        updateResponsiveLayout()

        dimView.isVisible = true

        promoteSheet()

        card.post {
            promoteSheet()
            updateResponsiveLayout()

            card.translationY = card.height.toFloat()
            refreshMainPreview()
            selectTab(Tab.HAIR)

            val slideUp = ObjectAnimator.ofFloat(
                card, "translationY", card.height.toFloat(), 0f
            ).apply {
                duration = 320
                interpolator = DecelerateInterpolator(1.8f)
            }

            val fadeIn = ObjectAnimator.ofFloat(
                dimView, "alpha", 0f, 1f
            ).apply {
                duration = 220
            }

            AnimatorSet().apply {
                playTogether(slideUp, fadeIn)
                start()
            }

            rootFrame.post { promoteSheet() }
            rootFrame.postDelayed({ if (isOpen) promoteSheet() }, 50L)
            rootFrame.postDelayed({ if (isOpen) promoteSheet() }, 150L)
        }
    }

    fun close() {
        if (!isOpen) return

        promoteSheet()

        if (::headerNameEdit.isInitialized) {
            headerNameEdit.clearFocus()
        }

        val slideDown = ObjectAnimator.ofFloat(card, "translationY", 0f, card.height.toFloat())
            .apply { duration = 260; interpolator = DecelerateInterpolator(1.4f) }
        val fadeOut =
            ObjectAnimator.ofFloat(dimView, "alpha", dimView.alpha, 0f).apply { duration = 220 }
        AnimatorSet().apply {
            playTogether(slideDown, fadeOut)
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    detach()
                }
            })
            start()
        }
    }

    fun detach() {
        isOpen = false
        removeExtraRows()
        if (dimView.parent != null) rootFrame.removeView(dimView)
        if (card.parent != null) rootFrame.removeView(card)

        if (!hasNotifiedClosed) {
            hasNotifiedClosed = true
            onClosed?.invoke()
        }
    }

    // ── Palettes ──────────────────────────────────────────────────────────────
    private fun bgColors() = listOf(
        "#7c7c7c",
        "#e7639f",
        "#9e45c0",
        "#5798f6",
        "#32d5c8",
        "#7cb33e",
        "#b1da1a",
        "#f6d61a",
        "#ee7c09",
        "#f11f06",
        "#d3292c"
    ).map { it.toColorInt() }

    private fun skinTones() = listOf(
        "#ffbd9a",
        "#ffb070",
        "#804734",
        "#5f442f",
        "#cccccc",
        "#da73a2",
        "#6394f1",
        "#82b941",
        "#f8cf55",
        "#f6820c",
        "#c34126"
    ).map { it.toColorInt() }

    private fun hairColors() = listOf(
        "#f8cf55",
        "#e1872f",
        "#d24325",
        "#6d411d",
        "#572c1f",
        "#000000",
        "#e1e1e1",
        "#ee67a4",
        "#a348c7",
        "#699bff",
        "#82b941"
    ).map { it.toColorInt() }

    private fun clothingColors() = listOf(
        "#7c7c7c",
        "#e7639f",
        "#9e45c0",
        "#5798f6",
        "#32d5c8",
        "#7cb33e",
        "#b1da1a",
        "#f6d61a",
        "#ee7c09",
        "#f11f06",
        "#d3292c"
    ).map { it.toColorInt() }
}