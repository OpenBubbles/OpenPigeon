package com.openbubbles.openpigeon.settings

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.*
import android.graphics.BitmapFactory
import android.util.AttributeSet
import android.view.View
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import kotlin.math.roundToInt
import androidx.core.graphics.toColorInt
import androidx.core.graphics.createBitmap
import androidx.core.graphics.withClip

class AvatarView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    // ── Region helpers ────────────────────────────────────────────────────────
    private fun p256(col: Int, row: Int) =
        Rect(col * 256, row * 256, (col + 1) * 256, (row + 1) * 256)

    private fun p128(col: Int, row: Int) =
        Rect(col * 128, row * 128, (col + 1) * 128, (row + 1) * 128)

    private fun p384(col: Int, row: Int) =
        Rect(col * 384, row * 384, (col + 1) * 384, (row + 1) * 384)

    // ── Sprite regions ────────────────────────────────────────────────────────
    val bgRegions = mapOf(
        "Pattern 1" to p128(0, 0),
        "Pattern 2" to p128(1, 0),
        "Pattern 3" to p128(2, 0),
        "Pattern 4" to p128(3, 0),
        "Pattern 5" to p128(0, 1),
        "Pattern 6" to p128(1, 1),
        "Pattern 7" to p128(2, 1),
        "Pattern 8" to p128(3, 1),
        "Pattern 9" to p128(0, 2)
    )
    val fshapeRegions = mapOf(
        "Default" to p256(0, 0),
        "fshape1" to p256(0, 0),
        "fshape2" to p256(1, 0),
        "fshape3" to p256(2, 0),
        "fshape4" to p256(3, 0),
        "fshape5" to p256(4, 0),
        "fshape6" to p256(0, 1),
        "fshape7" to p256(1, 1)
    )
    private val torsoRegion = p256(0, 0)
    val hairRegions = (1..15).associate { i -> "hair$i" to p256((i - 1) % 5, (i - 1) / 5) }
    val eyesRegions = (1..13).associate { i -> "eyes$i" to p256((i - 1) % 5, (i - 1) / 5) }
    val mouthRegions = (1..17).associate { i -> "mouth$i" to p256((i - 1) % 5, (i - 1) / 5) }
    val clothingRegions = mapOf(
        "clothing1" to p256(0, 0), "clothing2" to p256(1, 0), "clothing3" to p256(2, 0)
    )

    val headAccessoryRegions =
        (0..12).associate { index -> "hat_$index" to p384(index % 5, index / 5) }

    val faceAccessoryRegions =
        (1..14).associate { index -> "face_$index" to p256((index - 1) % 5, (index - 1) / 5) }

    private val mouthWithFacialHair = setOf("mouth13", "mouth14", "mouth15", "mouth16", "mouth17")

    // ── Draw state ────────────────────────────────────────────────────────────
    data class DrawState(
        val bgStyle: String = "Plain",
        @SuppressLint("UseKtx") val bgColor: Int = "#4e5d89".toColorInt(),
        val bgBrightness: Float = 0f,
        val fshapeStyle: String = "Default",
        val fshapeColor: Int = "#e0ac69".toColorInt(),
        val fshapeBrightness: Float = 0f,
        val hairStyle: String = "hair1",
        val hairColor: Int = "#2c232b".toColorInt(),
        val hairBrightness: Float = 0f,
        val eyesStyle: String = "eyes1",
        val mouthStyle: String = "mouth1",
        val clothingStyle: String = "clothing1",
        val clothingColor: Int = "#a03c3c".toColorInt(),
        val clothingBrightness: Float = 0f,
        val headAccessoryStyle: String = "hat_0",
        val faceAccessoryStyle: String = "face_1"
    )

    companion object {
        private const val LOGICAL_WIDTH = 96f
        private const val LOGICAL_HEIGHT = 140f
        private const val PILL_HEIGHT = 70f
        private const val BODY_HEIGHT = 90f
        private const val BODY_SCALE = 1.1f
        private const val BODY_BOTTOM_PAD = -12f

        fun configureTallAnchor(anchor: FrameLayout) {
            anchor.clipChildren = false
            anchor.clipToPadding = false

            (anchor.parent as? ViewGroup)?.apply {
                clipChildren = false
                clipToPadding = false
            }

            anchor.post {
                val avatar = (0 until anchor.childCount).map { anchor.getChildAt(it) }
                    .filterIsInstance<AvatarView>().firstOrNull() ?: return@post

                if (anchor.width <= 0) return@post

                val targetHeight = (anchor.width * LOGICAL_HEIGHT / LOGICAL_WIDTH).roundToInt()
                avatar.layoutParams = FrameLayout.LayoutParams(
                    anchor.width, targetHeight, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                )
                avatar.invalidate()
            }
        }

        fun parseOpponentString(avatarString: String): DrawState {
            if (avatarString.isBlank()) return DrawState()

            val fshapeKeys = listOf(
                "Default",
                "fshape1",
                "fshape2",
                "fshape3",
                "fshape4",
                "fshape5",
                "fshape6",
                "fshape7"
            )
            val hairKeys = (1..15).map { "hair$it" }
            val eyesKeys = (1..13).map { "eyes$it" }
            val mouthKeys = (1..17).map { "mouth$it" }
            val clothingKeys = listOf("clothing1", "clothing2", "clothing3")
            val backdropKeys = listOf("Plain") + (1..9).map { "Pattern $it" }

            fun parseColor(tokens: List<String>, offset: Int = 1): Int {
                val r = tokens.getOrNull(offset)?.toFloatOrNull() ?: 0f
                val g = tokens.getOrNull(offset + 1)?.toFloatOrNull() ?: 0f
                val b = tokens.getOrNull(offset + 2)?.toFloatOrNull() ?: 0f
                return Color.rgb((r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt())
            }

            fun <T> List<T>.safeGet(idx: Int) = getOrElse(idx) { first() }

            var bgStyle = "Plain"
            var bgColor = "#4e5d89".toColorInt()
            var fshapeStyle = "Default"
            var fshapeColor = "#e0ac69".toColorInt()
            var hairStyle = "hair1"
            var hairColor = "#2c232b".toColorInt()
            var eyesStyle = "eyes1"
            var mouthStyle = "mouth1"
            var clothingStyle = "clothing1"
            var clothingColor = "#a03c3c".toColorInt()
            var headAccessoryStyle = "hat_0"
            var faceAccessoryStyle = "face_1"

            for (part in avatarString.split("|")) {
                val tokens = part.split(",")

                when (tokens.firstOrNull()) {
                    "body", "fshape" -> fshapeStyle =
                        fshapeKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)

                    "hair" -> hairStyle =
                        hairKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)

                    "eyes" -> eyesStyle =
                        eyesKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)

                    "mouth" -> mouthStyle =
                        mouthKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)

                    "clothes" -> clothingStyle =
                        clothingKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)

                    "backdrop" -> bgStyle =
                        backdropKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)

                    "acc", "head_acc", "head_accessory" -> headAccessoryStyle =
                        AvatarData.normalizeHeadAccessoryStyle(tokens.getOrNull(1).orEmpty())

                    "glasses" -> {
                        val index = (tokens.getOrNull(1)?.toIntOrNull() ?: 0).coerceIn(0, 13)
                        faceAccessoryStyle = "face_${index + 1}"
                    }

                    "bg_color" -> bgColor = parseColor(tokens)
                    "body_color" -> fshapeColor = parseColor(tokens)
                    "hair_color" -> hairColor = parseColor(tokens)
                    "clothes_color" -> clothingColor = parseColor(tokens)
                }
            }

            return DrawState(
                bgStyle = bgStyle,
                bgColor = bgColor,
                fshapeStyle = fshapeStyle,
                fshapeColor = fshapeColor,
                hairStyle = hairStyle,
                hairColor = hairColor,
                eyesStyle = eyesStyle,
                mouthStyle = mouthStyle,
                clothingStyle = clothingStyle,
                clothingColor = clothingColor,
                headAccessoryStyle = headAccessoryStyle,
                faceAccessoryStyle = faceAccessoryStyle
            )
        }

        fun buildAvatarString(): String {
            val fshapeKeys = listOf(
                "Default",
                "fshape1",
                "fshape2",
                "fshape3",
                "fshape4",
                "fshape5",
                "fshape6",
                "fshape7"
            )
            val hairKeys = (1..15).map { "hair$it" }
            val eyesKeys = (1..13).map { "eyes$it" }
            val mouthKeys = (1..17).map { "mouth$it" }
            val clothingKeys = listOf("clothing1", "clothing2", "clothing3")
            val backdropKeys = listOf("Plain") + (1..9).map { "Pattern $it" }

            fun colorStr(argb: Int): String {
                val r = Color.red(argb) / 255f
                val g = Color.green(argb) / 255f
                val b = Color.blue(argb) / 255f
                return "%.6f,%.6f,%.6f".format(r, g, b)
            }

            fun adjustedColor(base: Int, brightness: Float): Int {
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

            val bodyIdx = fshapeKeys.indexOf(AvatarData.fshapeStyle).coerceAtLeast(0)
            val hairIdx = hairKeys.indexOf(AvatarData.hairStyle).coerceAtLeast(0)
            val eyesIdx = eyesKeys.indexOf(AvatarData.eyesStyle).coerceAtLeast(0)
            val mouthIdx = mouthKeys.indexOf(AvatarData.mouthStyle).coerceAtLeast(0)
            val clothesIdx = clothingKeys.indexOf(AvatarData.clothingStyle).coerceAtLeast(0)
            val backdropIdx = backdropKeys.indexOf(AvatarData.bgStyle).coerceAtLeast(0)
            val headAccessoryIdx =
                AvatarData.headAccessoryStyle.removePrefix("hat_").toIntOrNull()?.coerceIn(0, 12)
                    ?: 0
            val faceAccessoryIdx =
                AvatarData.faceAccessoryStyle.removePrefix("face_").toIntOrNull()
                    ?.minus(1)
                    ?.coerceIn(0, 13)
                    ?: 0

            return listOf(
                "body,$bodyIdx",
                "hair,$hairIdx",
                "eyes,$eyesIdx",
                "mouth,$mouthIdx",
                "clothes,$clothesIdx",
                "backdrop,$backdropIdx",
                "bg_color,${colorStr(adjustedColor(AvatarData.bgColor, AvatarData.bgBrightness))}",
                "body_color,${
                    colorStr(
                        adjustedColor(
                            AvatarData.fshapeColor, AvatarData.fshapeBrightness
                        )
                    )
                }",
                "hair_color,${
                    colorStr(
                        adjustedColor(
                            AvatarData.hairColor, AvatarData.hairBrightness
                        )
                    )
                }",
                "clothes_color,${
                    colorStr(
                        adjustedColor(
                            AvatarData.clothingColor, AvatarData.clothingBrightness
                        )
                    )
                }",
                "acc,$headAccessoryIdx",
                "glasses,$faceAccessoryIdx",
                "stache,0",
                "wins,0"
            ).joinToString("|")
        }
    }

    // ── State ─────────────────────────────────────────────────────────────────
    private var state: DrawState? = null   // null = show question mark placeholder

    fun applyFromAvatarData() {
        val s = DrawState(
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

        if (s == state && cachedBitmap != null) return

        state = s
        cachedBitmap = null
        invalidate()
    }

    fun applyFromOpponentString(avatarString: String) {
        applyPreview(parseOpponentString(avatarString))
    }

    // Show the question-mark placeholder. call when opponent is unknown.
    fun showPlaceholder() {
        if (state == null && cachedBitmap != null) return  // already showing placeholder
        state = null
        cachedBitmap = null
        invalidate()
    }

    fun applyPreview(s: DrawState) {
        if (s == state && cachedBitmap != null) return
        state = s
        cachedBitmap = null
        invalidate()
    }

    // ── Render cache ──────────────────────────────────────────────────────────
    private var cachedBitmap: Bitmap? = null
    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)

    // Placeholder bitmap - loaded once lazily
    private var placeholderBitmap: Bitmap? = null
    private fun getPlaceholder(): Bitmap? {
        if (placeholderBitmap == null) {
            try {
                placeholderBitmap =
                    context.assets.open("global/avatar_textures/avatar_pill_empty.png")
                        .use { BitmapFactory.decodeStream(it) }
            } catch (_: Exception) {
            }
        }
        return placeholderBitmap
    }

    override fun onDraw(canvas: Canvas) {
        val w = width
        val h = height
        if (w == 0 || h == 0) return

        val currentState = state

        if (currentState == null) {
            val unit = minOf(w / LOGICAL_WIDTH, h / LOGICAL_HEIGHT)
            val contentWidth = LOGICAL_WIDTH * unit
            val contentHeight = LOGICAL_HEIGHT * unit
            val contentLeft = (w - contentWidth) / 2f
            val contentTop = h - contentHeight
            val pillTop = contentTop + (LOGICAL_HEIGHT - PILL_HEIGHT) * unit
            val ph = getPlaceholder()

            if (ph != null) {
                canvas.drawBitmap(ph, null, RectF(contentLeft, pillTop, contentLeft + contentWidth, contentTop + contentHeight), bitmapPaint)
            }

            return
        }

        // Render avatar at actual view size
        if (cachedBitmap == null || cachedBitmap!!.width != w || cachedBitmap!!.height != h) {
            cachedBitmap?.recycle()
            val bmp = createBitmap(w, h)
            renderFully(Canvas(bmp), w.toFloat(), h.toFloat(), currentState)
            cachedBitmap = bmp
        }
        canvas.drawBitmap(cachedBitmap!!, 0f, 0f, bitmapPaint)
    }

    // ── Full render ───────────────────────────────────────────────────────────
    private val drawPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val clipPath = Path()

    private fun renderFully(canvas: Canvas, w: Float, h: Float, s: DrawState) {
        val unit = minOf(w / LOGICAL_WIDTH, h / LOGICAL_HEIGHT)
        val contentWidth = LOGICAL_WIDTH * unit
        val contentHeight = LOGICAL_HEIGHT * unit
        val contentLeft = (w - contentWidth) / 2f
        val contentTop = h - contentHeight
        val centerX = contentLeft + contentWidth / 2f
        val pillRect = RectF(contentLeft, contentTop + (LOGICAL_HEIGHT - PILL_HEIGHT) * unit, contentLeft + contentWidth, contentTop + contentHeight)

        clipPath.reset()
        clipPath.addRoundRect(pillRect, pillRect.width() * 0.38f, pillRect.height() * 0.48f, Path.Direction.CW)

        canvas.withClip(clipPath) {
            drawColor(applyBrightness(s.bgColor, s.bgBrightness))

            if (s.bgStyle != "Plain") {
                bgRegions[s.bgStyle]?.let { src ->
                    AvatarBitmapCache.bmBackground?.let { drawBitmap(it, src, pillRect, drawPaint) }
                }
            }

        }

        val skinFinal = applyBrightness(s.fshapeColor, s.fshapeBrightness)
        val hairFinal = applyBrightness(s.hairColor, s.hairBrightness)
        val clothFinal = applyBrightness(s.clothingColor, s.clothingBrightness)
        val bodyAreaTop = contentTop + (LOGICAL_HEIGHT - BODY_HEIGHT) * unit
        val drawSize = BODY_HEIGHT * unit * BODY_SCALE
        val baseY = bodyAreaTop + BODY_HEIGHT * unit - drawSize / 2f - BODY_BOTTOM_PAD * unit

        fun drawCell(bitmap: Bitmap?, source: Rect?, tint: Int = Color.WHITE, yOffset: Float = 0f) {
            bitmap ?: return
            source ?: return

            val left = centerX - drawSize / 2f
            val top = baseY - drawSize / 2f + yOffset
            drawPaint.colorFilter = if (tint == Color.WHITE) null else PorterDuffColorFilter(tint, PorterDuff.Mode.MULTIPLY)
            canvas.drawBitmap(bitmap, source, RectF(left, top, left + drawSize, top + drawSize), drawPaint)
            drawPaint.colorFilter = null
        }

        val hairShift = -8f * (BODY_HEIGHT * unit / 256f)
        drawCell(AvatarBitmapCache.bmHairBack, hairRegions[s.hairStyle], hairFinal, hairShift)
        drawCell(AvatarBitmapCache.bmTorso, torsoRegion, skinFinal)
        drawCell(AvatarBitmapCache.bmClothing, clothingRegions[s.clothingStyle], clothFinal)
        drawCell(AvatarBitmapCache.bmClothingDt, clothingRegions[s.clothingStyle])
        drawCell(AvatarBitmapCache.bmFaces, fshapeRegions[s.fshapeStyle] ?: fshapeRegions["Default"], skinFinal)
        drawCell(AvatarBitmapCache.bmEyes, eyesRegions[s.eyesStyle])
        drawCell(AvatarBitmapCache.bmMouth, mouthRegions[s.mouthStyle], if (s.mouthStyle in mouthWithFacialHair) hairFinal else Color.WHITE)
        drawCell(AvatarBitmapCache.bmHairFront, hairRegions[s.hairStyle], hairFinal, hairShift)

        val headAccessoryStyle = AvatarData.normalizeHeadAccessoryStyle(s.headAccessoryStyle)

        if (headAccessoryStyle != "hat_0") {
            val source = headAccessoryRegions[headAccessoryStyle]
            val bitmap = AvatarBitmapCache.bmHeadAccessories

            if (source != null && bitmap != null) {
                val accessorySize = drawSize * 1.5f
                val accessoryCenterY = baseY - drawSize * 0.25f
                val left = centerX - accessorySize / 2f
                val top = accessoryCenterY - accessorySize / 2f
                drawPaint.colorFilter = null
                canvas.drawBitmap(bitmap, source, RectF(left, top, left + accessorySize, top + accessorySize), drawPaint)
            }
        }

        val faceAccessoryStyle = AvatarData.normalizeFaceAccessoryStyle(s.faceAccessoryStyle)
        drawCell(
            AvatarBitmapCache.bmFaceAccessories,
            faceAccessoryRegions[faceAccessoryStyle]
        )
    }

    // ── Brightness math ───────────────────────────────────────────────────────
    fun applyBrightness(color: Int, brightness: Float): Int {
        if (brightness == 0f) return color
        val hsv = FloatArray(3)
        Color.colorToHSV(color, hsv)
        if (brightness < 0f) {
            val t = brightness + 1f
            hsv[2] = hsv[2] * t + 0.3f * (1f - t)
        } else {
            hsv[1] = hsv[1] * (1f - brightness)
            hsv[2] = hsv[2] + (1f - hsv[2]) * brightness
        }
        return Color.HSVToColor(hsv)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        cachedBitmap?.recycle()
        cachedBitmap = null
    }
}