package com.openbubbles.openpigeon.settings

import android.content.Context
import android.graphics.*
import android.graphics.BitmapFactory
import android.util.AttributeSet
import android.view.View

class AvatarView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    // ── Region helpers ────────────────────────────────────────────────────────
    private fun p256(col: Int, row: Int) =
        Rect(col * 256, row * 256, (col + 1) * 256, (row + 1) * 256)
    private fun p128(col: Int, row: Int) =
        Rect(col * 128, row * 128, (col + 1) * 128, (row + 1) * 128)

    // ── Sprite regions ────────────────────────────────────────────────────────
    val bgRegions = mapOf(
        "Pattern 1" to p128(0,0), "Pattern 2" to p128(1,0),
        "Pattern 3" to p128(2,0), "Pattern 4" to p128(3,0),
        "Pattern 5" to p128(0,1), "Pattern 6" to p128(1,1),
        "Pattern 7" to p128(2,1), "Pattern 8" to p128(3,1),
        "Pattern 9" to p128(0,2)
    )
    val fshapeRegions = mapOf(
        "Default"  to p256(0,0),
        "fshape1"  to p256(0,0), "fshape2" to p256(1,0),
        "fshape3"  to p256(2,0), "fshape4" to p256(3,0),
        "fshape5"  to p256(4,0), "fshape6" to p256(0,1),
        "fshape7"  to p256(1,1)
    )
    private val torsoRegion = p256(0, 0)
    val hairRegions     = (1..15).associate { i -> "hair$i"     to p256((i-1)%5, (i-1)/5) }
    val eyesRegions     = (1..13).associate { i -> "eyes$i"     to p256((i-1)%5, (i-1)/5) }
    val mouthRegions    = (1..17).associate { i -> "mouth$i"    to p256((i-1)%5, (i-1)/5) }
    val clothingRegions = mapOf(
        "clothing1" to p256(0,0), "clothing2" to p256(1,0), "clothing3" to p256(2,0)
    )
    private val mouthWithFacialHair = setOf("mouth13","mouth14","mouth15","mouth16","mouth17")

    // ── Draw state ────────────────────────────────────────────────────────────
    data class DrawState(
        val bgStyle:            String = "Plain",
        val bgColor:            Int    = Color.parseColor("#4e5d89"),
        val bgBrightness:       Float  = 0f,
        val fshapeStyle:        String = "Default",
        val fshapeColor:        Int    = Color.parseColor("#e0ac69"),
        val fshapeBrightness:   Float  = 0f,
        val hairStyle:          String = "hair1",
        val hairColor:          Int    = Color.parseColor("#2c232b"),
        val hairBrightness:     Float  = 0f,
        val eyesStyle:          String = "eyes1",
        val mouthStyle:         String = "mouth1",
        val clothingStyle:      String = "clothing1",
        val clothingColor:      Int    = Color.parseColor("#a03c3c"),
        val clothingBrightness: Float  = 0f
    )

    companion object {
        fun parseOpponentString(avatarString: String): DrawState {
            if (avatarString.isBlank()) return DrawState()

            val fshapeKeys   = listOf("Default","fshape1","fshape2","fshape3","fshape4",
                                      "fshape5","fshape6","fshape7")
            val hairKeys     = (1..15).map { "hair$it" }
            val eyesKeys     = (1..13).map { "eyes$it" }
            val mouthKeys    = (1..17).map { "mouth$it" }
            val clothingKeys = listOf("clothing1","clothing2","clothing3")
            val backdropKeys = listOf("Plain") + (1..9).map { "Pattern $it" }

            fun parseColor(tokens: List<String>, offset: Int = 1): Int {
                val r = tokens.getOrNull(offset)?.toFloatOrNull() ?: 0f
                val g = tokens.getOrNull(offset+1)?.toFloatOrNull() ?: 0f
                val b = tokens.getOrNull(offset+2)?.toFloatOrNull() ?: 0f
                return Color.rgb((r*255).toInt(), (g*255).toInt(), (b*255).toInt())
            }
            fun <T> List<T>.safeGet(idx: Int) = getOrElse(idx) { first() }

            var bgStyle       = "Plain";        var bgColor       = Color.parseColor("#4e5d89")
            var fshapeStyle   = "Default";      var fshapeColor   = Color.parseColor("#e0ac69")
            var hairStyle     = "hair1";         var hairColor     = Color.parseColor("#2c232b")
            var eyesStyle     = "eyes1";         var mouthStyle    = "mouth1"
            var clothingStyle = "clothing1";     var clothingColor = Color.parseColor("#a03c3c")

            for (part in avatarString.split("|")) {
                val tokens = part.split(",")
                when (tokens.firstOrNull()) {
                    "body", "fshape" -> fshapeStyle  = fshapeKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)
                    "hair"           -> hairStyle     = hairKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)
                    "eyes"           -> eyesStyle     = eyesKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)
                    "mouth"          -> mouthStyle    = mouthKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)
                    "clothes"        -> clothingStyle = clothingKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)
                    "backdrop"       -> bgStyle       = backdropKeys.safeGet(tokens.getOrNull(1)?.toIntOrNull() ?: 0)
                    "bg_color"       -> bgColor       = parseColor(tokens)
                    "body_color"     -> fshapeColor   = parseColor(tokens)
                    "hair_color"     -> hairColor     = parseColor(tokens)
                    "clothes_color"  -> clothingColor = parseColor(tokens)
                }
            }
            return DrawState(
                bgStyle = bgStyle, bgColor = bgColor,
                fshapeStyle = fshapeStyle, fshapeColor = fshapeColor,
                hairStyle = hairStyle, hairColor = hairColor,
                eyesStyle = eyesStyle, mouthStyle = mouthStyle,
                clothingStyle = clothingStyle, clothingColor = clothingColor
            )
        }

        fun buildAvatarString(): String {
            val fshapeKeys   = listOf("Default","fshape1","fshape2","fshape3","fshape4",
                                      "fshape5","fshape6","fshape7")
            val hairKeys     = (1..15).map { "hair$it" }
            val eyesKeys     = (1..13).map { "eyes$it" }
            val mouthKeys    = (1..17).map { "mouth$it" }
            val clothingKeys = listOf("clothing1","clothing2","clothing3")
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

            val bodyIdx     = fshapeKeys.indexOf(AvatarData.fshapeStyle).coerceAtLeast(0)
            val hairIdx     = hairKeys.indexOf(AvatarData.hairStyle).coerceAtLeast(0)
            val eyesIdx     = eyesKeys.indexOf(AvatarData.eyesStyle).coerceAtLeast(0)
            val mouthIdx    = mouthKeys.indexOf(AvatarData.mouthStyle).coerceAtLeast(0)
            val clothesIdx  = clothingKeys.indexOf(AvatarData.clothingStyle).coerceAtLeast(0)
            val backdropIdx = backdropKeys.indexOf(AvatarData.bgStyle).coerceAtLeast(0)

            return listOf(
                "body,$bodyIdx",
                "hair,$hairIdx",
                "eyes,$eyesIdx",
                "mouth,$mouthIdx",
                "clothes,$clothesIdx",
                "backdrop,$backdropIdx",
                "bg_color,${colorStr(adjustedColor(AvatarData.bgColor, AvatarData.bgBrightness))}",
                "body_color,${colorStr(adjustedColor(AvatarData.fshapeColor, AvatarData.fshapeBrightness))}",
                "hair_color,${colorStr(adjustedColor(AvatarData.hairColor, AvatarData.hairBrightness))}",
                "clothes_color,${colorStr(adjustedColor(AvatarData.clothingColor, AvatarData.clothingBrightness))}",
                "acc,0", "glasses,0", "stache,0", "wins,0"
            ).joinToString("|")
        }
    }

    // ── State ─────────────────────────────────────────────────────────────────
    private var state: DrawState? = null   // null = show question mark placeholder

    fun applyFromAvatarData() {
        val s = DrawState(
            bgStyle            = AvatarData.bgStyle,
            bgColor            = AvatarData.bgColor,
            bgBrightness       = AvatarData.bgBrightness,
            fshapeStyle        = AvatarData.fshapeStyle,
            fshapeColor        = AvatarData.fshapeColor,
            fshapeBrightness   = AvatarData.fshapeBrightness,
            hairStyle          = AvatarData.hairStyle,
            hairColor          = AvatarData.hairColor,
            hairBrightness     = AvatarData.hairBrightness,
            eyesStyle          = AvatarData.eyesStyle,
            mouthStyle         = AvatarData.mouthStyle,
            clothingStyle      = AvatarData.clothingStyle,
            clothingColor      = AvatarData.clothingColor,
            clothingBrightness = AvatarData.clothingBrightness
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
                placeholderBitmap = context.assets
                    .open("global/avatar_textures/avatar_pill_empty.png")
                    .use { BitmapFactory.decodeStream(it) }
            } catch (_: Exception) {}
        }
        return placeholderBitmap
    }

    override fun onDraw(canvas: Canvas) {
        val w = width; val h = height
        if (w == 0 || h == 0) return

        val currentState = state

        if (currentState == null) {
            // Draw the question-mark placeholder scaled to fill the view
            val ph = getPlaceholder()
            if (ph != null) {
                canvas.drawBitmap(ph, null, RectF(0f, 0f, w.toFloat(), h.toFloat()), bitmapPaint)
            }
            return
        }

        // Render avatar at actual view size
        if (cachedBitmap == null || cachedBitmap!!.width != w || cachedBitmap!!.height != h) {
            cachedBitmap?.recycle()
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            renderFully(Canvas(bmp), w.toFloat(), h.toFloat(), currentState)
            cachedBitmap = bmp
        }
        canvas.drawBitmap(cachedBitmap!!, 0f, 0f, bitmapPaint)
    }

    // ── Full render ───────────────────────────────────────────────────────────
    private val drawPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val clipPath  = Path()

    private fun renderFully(canvas: Canvas, w: Float, h: Float, s: DrawState) {
        // Pill clip
        clipPath.reset()
        clipPath.addRoundRect(0f, 0f, w, h, w * 0.38f, h * 0.48f, Path.Direction.CW)
        canvas.clipPath(clipPath)

        // Background
        canvas.drawColor(applyBrightness(s.bgColor, s.bgBrightness))
        if (s.bgStyle != "Plain") {
            bgRegions[s.bgStyle]?.let { src ->
                canvas.drawBitmap(AvatarBitmapCache.bmBackground ?: return@let,
                    src, RectF(0f, 0f, w, h), drawPaint)
            }
        }

        val skinFinal  = applyBrightness(s.fshapeColor,   s.fshapeBrightness)
        val hairFinal  = applyBrightness(s.hairColor,     s.hairBrightness)
        val clothFinal = applyBrightness(s.clothingColor, s.clothingBrightness)

        // Sprites sized by height, anchored to bottom
        fun drawCell(bm: Bitmap?, src: Rect?, tint: Int = Color.WHITE, yOffset: Float = 0f) {
			bm  ?: return
			src ?: return
			val scale     = 1.2f
			val bottomPad = -45f * (h / 256f)
			val drawH     = h * scale
			val drawW     = drawH
			val left      = (w - drawW) / 2f
			val top       = h - drawH - bottomPad + yOffset
			drawPaint.colorFilter =
				if (tint == Color.WHITE) null
				else PorterDuffColorFilter(tint, PorterDuff.Mode.MULTIPLY)
			canvas.drawBitmap(bm, src, RectF(left, top, left + drawW, top + drawH), drawPaint)
			drawPaint.colorFilter = null
		}
		
		val hairShift = -8f * (h / 256f)
        drawCell(AvatarBitmapCache.bmHairBack, hairRegions[s.hairStyle], hairFinal, hairShift)
        drawCell(AvatarBitmapCache.bmTorso, torsoRegion, skinFinal)
        drawCell(AvatarBitmapCache.bmClothing, clothingRegions[s.clothingStyle], clothFinal)
        drawCell(AvatarBitmapCache.bmClothingDt, clothingRegions[s.clothingStyle], Color.WHITE)
        drawCell(AvatarBitmapCache.bmFaces, fshapeRegions[s.fshapeStyle] ?: fshapeRegions["Default"], skinFinal)
        drawCell(AvatarBitmapCache.bmEyes, eyesRegions[s.eyesStyle], Color.WHITE)
        val mouthTint = if (s.mouthStyle in mouthWithFacialHair) hairFinal else Color.WHITE
        drawCell(AvatarBitmapCache.bmMouth, mouthRegions[s.mouthStyle], mouthTint)
        drawCell(AvatarBitmapCache.bmHairFront, hairRegions[s.hairStyle], hairFinal, hairShift)
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