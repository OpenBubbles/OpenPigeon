package com.openbubbles.openpigeon.pool

import android.animation.ValueAnimator
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import com.openbubbles.openpigeon.util.OpenPigeonLog
import android.view.SurfaceHolder
import android.view.Surface
import androidx.core.animation.doOnEnd
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan
import kotlin.math.min
import android.util.TypedValue
import kotlin.math.max
import android.os.Handler
import android.os.Looper
import androidx.core.graphics.withMatrix
import androidx.core.graphics.withSave
import android.graphics.ColorMatrixColorFilter
import com.openbubbles.openpigeon.R
import androidx.core.graphics.withTranslation
import androidx.core.graphics.createBitmap

class PoolRenderer(val holder: SurfaceHolder, val activity: PoolActivity) : Thread(), SurfaceHolder.Callback {
    var running = true

    private fun decodeTableBitmap(resId: Int, name: String): Bitmap {
        return BitmapFactory.decodeResource(
            activity.resources,
            resId,
            BitmapFactory.Options().apply {
                inScaled = false
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
        ) ?: error("Unable to decode pool table bitmap: $name")
    }

    private val poolFill: Bitmap = decodeTableBitmap(R.drawable.pool_fill, "pool_fill")
    private val poolLine: Bitmap = decodeTableBitmap(R.drawable.pool_line, "pool_line")
    private val poolPlus: Bitmap = decodeTableBitmap(R.drawable.pool_plus, "pool_plus")
    private val poolBorderFelt: Bitmap = decodeTableBitmap(R.drawable.pool_border_felt, "pool_border_felt")
    private val poolBorder: Bitmap = decodeTableBitmap(R.drawable.pool_border, "pool_border")

    private val tablePaint = Paint(
        Paint.ANTI_ALIAS_FLAG or
                Paint.FILTER_BITMAP_FLAG or
                Paint.DITHER_FLAG
    )

    private val pocketPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
    }

    private val callPocketPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x55FFFFFF
    }

    private val cuePaint = Paint(
        Paint.ANTI_ALIAS_FLAG or
                Paint.FILTER_BITMAP_FLAG or
                Paint.DITHER_FLAG
    )

    private val cueDrawRect = RectF()

    @Volatile
    var cue: Bitmap = BitmapFactory.decodeResource(
        activity.resources,
        cueDrawableId(activity, activity.cueStyle)
    )
        private set

    @Volatile
    private var cueHalfHeight = cueHalfHeightFor(cue)

    fun applyCueStyle(style: Int) {
        val next = BitmapFactory.decodeResource(
            activity.resources,
            cueDrawableId(activity, style)
        )

        cueHalfHeight = cueHalfHeightFor(next)
        cue = next
    }

    private fun cueHalfHeightFor(bitmap: Bitmap): Float {
        if (bitmap.height <= 0) {
            return 5f
        }

        return CUE_DRAW_LENGTH * bitmap.width.toFloat() / bitmap.height.toFloat() / 2f
    }

    init {
        holder.addCallback(this)
    }

    private val targetFps: Int = 60
    private val frameTime: Long = (1000 / targetFps).toLong()

    var cueRot = 0.0f
    var cueDraw = 0.0f
    var cueAlpha = 1.0f
    var cuePos = floatArrayOf(0f, 0f)
    var scratchRingPhase = 0f
    var nineBallTargetRingPhase = 0f


    @Volatile var tableScreenBounds: RectF = RectF()

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var frameReadySignaled = true
    @Volatile private var onFrameReadyCallback: (() -> Unit)? = null

    fun notifyWhenFrameReady(callback: () -> Unit) {
        if (frameReadySignaled) {
            mainHandler.post(callback)
            return
        }
        onFrameReadyCallback = callback
    }

    fun resetFrameReadySignal() {
        frameReadySignaled = false
        onFrameReadyCallback = null
    }

    private fun signalFrameReady() {
        if (frameReadySignaled) return
        frameReadySignaled = true
        val cb = onFrameReadyCallback
        onFrameReadyCallback = null
        if (cb != null) {
            mainHandler.post(cb)
        }
    }

    companion object {
        private const val WORLD_WIDTH = 784.743f
        private const val WORLD_HEIGHT = 441.189f

        private const val TABLE_CACHE_WIDTH = 1200
        private const val TABLE_CACHE_HEIGHT = 677

        private const val TABLE_CACHE_SHADOW_PADDING_X_PX = 120
        private const val TABLE_CACHE_SHADOW_PADDING_Y_PX = 90

        private const val TABLE_CACHE_BITMAP_WIDTH =
            TABLE_CACHE_WIDTH + TABLE_CACHE_SHADOW_PADDING_X_PX * 2

        private const val TABLE_CACHE_BITMAP_HEIGHT =
            TABLE_CACHE_HEIGHT + TABLE_CACHE_SHADOW_PADDING_Y_PX * 2

        private const val COLOR_RED = 0xFFcf0019.toInt()
        private const val COLOR_BLUE = 0xFF1065e6.toInt()
        private const val COLOR_PURPLE = 0xFFba82ff.toInt()

        private const val FELT_TINT_LUMA_SCALE = 1.32f
        private const val FELT_TINT_BRIGHTNESS_LIFT = 34f
        private const val TABLE_ASSET_CONTENT_SCALE_HORIZONTAL = 1.09f
        private const val TABLE_ASSET_CONTENT_SCALE_VERTICAL = 1.16f

        private const val TABLE_ASSET_CONTENT_OFFSET_X_PX = 0f
        private const val TABLE_ASSET_CONTENT_OFFSET_Y_PX = 0f
    }

    private val tableBitmapRect = RectF(-0.057f, -0.189f, WORLD_WIDTH, WORLD_HEIGHT)

    private val tableBitmapWithShadowRect = RectF(
        tableBitmapRect.left -
                tableBitmapRect.width() * TABLE_CACHE_SHADOW_PADDING_X_PX / TABLE_CACHE_WIDTH,
        tableBitmapRect.top -
                tableBitmapRect.height() * TABLE_CACHE_SHADOW_PADDING_Y_PX / TABLE_CACHE_HEIGHT,
        tableBitmapRect.right +
                tableBitmapRect.width() * TABLE_CACHE_SHADOW_PADDING_X_PX / TABLE_CACHE_WIDTH,
        tableBitmapRect.bottom +
                tableBitmapRect.height() * TABLE_CACHE_SHADOW_PADDING_Y_PX / TABLE_CACHE_HEIGHT
    )

    private data class TableCacheKey(
        val tintColor: Int,
        val drawBreakLine: Boolean,
        val drawPlus: Boolean
    )

    private var cachedTableKey: TableCacheKey? = null
    private var cachedBaseTableBitmap: Bitmap? = null
    private var cachedTopTableBitmap: Bitmap? = null

    private val portraitAssetDrawRect = run {
        val scaledWidth = TABLE_CACHE_HEIGHT * TABLE_ASSET_CONTENT_SCALE_VERTICAL
        val scaledHeight = TABLE_CACHE_WIDTH * TABLE_ASSET_CONTENT_SCALE_HORIZONTAL

        RectF(
            (TABLE_CACHE_HEIGHT - scaledWidth) * 0.5f + TABLE_ASSET_CONTENT_OFFSET_X_PX,
            (TABLE_CACHE_WIDTH - scaledHeight) * 0.5f + TABLE_ASSET_CONTENT_OFFSET_Y_PX,
            (TABLE_CACHE_HEIGHT + scaledWidth) * 0.5f + TABLE_ASSET_CONTENT_OFFSET_X_PX,
            (TABLE_CACHE_WIDTH + scaledHeight) * 0.5f + TABLE_ASSET_CONTENT_OFFSET_Y_PX
        )
    }

    private data class PoolWallSegment(
        val ax: Float,
        val ay: Float,
        val bx: Float,
        val by: Float
    )

    @Suppress("FloatingPointLiteralPrecision")
    private val iosAimWallSegments = listOf(
        PoolWallSegment(370.000000f, 50.000000f, 75.000000f, 50.000000f),
        PoolWallSegment(414.000000f, 50.000000f, 709.000000f, 50.000000f),
        PoolWallSegment(75.000000f, 50.000000f, 63.130043f, 33.903290f),
        PoolWallSegment(63.130043f, 33.903290f, 54.456924f, 19.282175f),
        PoolWallSegment(54.456924f, 19.282175f, 27.072823f, 9.736966f),
        PoolWallSegment(50.000000f, 75.000000f, 33.903290f, 63.130043f),
        PoolWallSegment(33.903290f, 63.130043f, 19.282175f, 54.456924f),
        PoolWallSegment(19.282175f, 54.456924f, 9.736966f, 27.072823f),
        PoolWallSegment(27.072823f, 9.736966f, 9.736966f, 27.072823f),
        PoolWallSegment(709.000000f, 50.000000f, 720.869934f, 33.903290f),
        PoolWallSegment(720.869934f, 33.903290f, 729.543030f, 19.282177f),
        PoolWallSegment(729.543030f, 19.282177f, 756.927124f, 9.736967f),
        PoolWallSegment(734.000000f, 75.000000f, 750.096680f, 63.130039f),
        PoolWallSegment(750.096680f, 63.130039f, 764.717773f, 54.456917f),
        PoolWallSegment(764.717773f, 54.456917f, 774.263000f, 27.072817f),
        PoolWallSegment(756.927124f, 9.736967f, 774.263000f, 27.072817f),
        PoolWallSegment(709.000000f, 390.000000f, 720.869934f, 406.096710f),
        PoolWallSegment(720.869934f, 406.096710f, 729.543030f, 420.717834f),
        PoolWallSegment(729.543030f, 420.717834f, 756.927124f, 430.263031f),
        PoolWallSegment(734.000000f, 365.000000f, 750.096680f, 376.869965f),
        PoolWallSegment(750.096680f, 376.869965f, 764.717773f, 385.543091f),
        PoolWallSegment(764.717773f, 385.543091f, 774.263000f, 412.927185f),
        PoolWallSegment(756.927124f, 430.263031f, 774.263000f, 412.927185f),
        PoolWallSegment(75.000000f, 390.000000f, 63.130043f, 406.096710f),
        PoolWallSegment(63.130043f, 406.096710f, 54.456924f, 420.717834f),
        PoolWallSegment(54.456924f, 420.717834f, 27.072823f, 430.263031f),
        PoolWallSegment(50.000000f, 365.000000f, 33.903290f, 376.869965f),
        PoolWallSegment(33.903290f, 376.869965f, 19.282175f, 385.543091f),
        PoolWallSegment(19.282175f, 385.543091f, 9.736966f, 412.927185f),
        PoolWallSegment(27.072823f, 430.263031f, 9.736966f, 412.927185f),
        PoolWallSegment(370.000000f, 50.000000f, 376.160095f, 34.155334f),
        PoolWallSegment(376.160095f, 34.155334f, 370.340881f, 17.121933f),
        PoolWallSegment(370.340881f, 17.121933f, 392.000000f, 0.000000f),
        PoolWallSegment(414.000000f, 50.000000f, 408.504089f, 33.912899f),
        PoolWallSegment(408.504089f, 33.912899f, 415.026520f, 17.136196f),
        PoolWallSegment(415.026520f, 17.136196f, 392.000000f, 0.000000f),
        PoolWallSegment(370.000000f, 390.000000f, 376.160095f, 405.844666f),
        PoolWallSegment(376.160095f, 405.844666f, 370.340881f, 422.878052f),
        PoolWallSegment(370.340881f, 422.878052f, 392.000000f, 440.000000f),
        PoolWallSegment(414.000000f, 390.000000f, 408.504089f, 406.087097f),
        PoolWallSegment(408.504089f, 406.087097f, 415.026520f, 422.863800f),
        PoolWallSegment(415.026520f, 422.863800f, 392.000000f, 440.000000f),
        PoolWallSegment(75.000000f, 390.000000f, 370.000000f, 390.000000f),
        PoolWallSegment(414.000000f, 390.000000f, 709.000000f, 390.000000f),
        PoolWallSegment(50.000000f, 75.000000f, 50.000000f, 365.000000f),
        PoolWallSegment(734.000000f, 75.000000f, 734.000000f, 365.000000f)
    )

    // 1.0f = maximum fitted size. Smaller values leave room for UI around the table.
    var tableVisualScale = 1f
    var rotatedTableVisualScale = 0.88f

    // Positive moves the table downward/rightward on screen, negative upward/leftward.
    var tableOffsetYPx = 0f
    var rotatedTableOffsetXPx = 0f
    var rotatedTableOffsetYPx = 0f

    private fun sideUiInsetPx(): Float {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            50f,
            activity.resources.displayMetrics
        )
    }

    val transform: Matrix
        get() = Matrix().apply {
            val surfaceWidth = holder.surfaceFrame.width().toFloat()
            val surfaceHeight = holder.surfaceFrame.height().toFloat()

            @Suppress("DEPRECATION")
            val screenRotationDegrees = when (activity.windowManager.defaultDisplay.rotation) {
                Surface.ROTATION_90 -> 90f
                Surface.ROTATION_180 -> 180f
                Surface.ROTATION_270 -> 270f
                else -> 0f
            }

            val tableRotation = -90f - screenRotationDegrees

            val fitBounds = RectF(0f, 0f, WORLD_WIDTH, WORLD_HEIGHT)
            val fitMatrix = Matrix().apply {
                postScale(1f, -1f)
                postRotate(tableRotation)
            }
            fitMatrix.mapRect(fitBounds)

            val sideInset = sideUiInsetPx()
            val availableWidth = max(1f, surfaceWidth - sideInset * 2f)

            val fitScale = min(
                availableWidth / fitBounds.width(),
                surfaceHeight / fitBounds.height()
            )

            val isRotated = screenRotationDegrees != 0f
            val scale = fitScale * if (isRotated) rotatedTableVisualScale else tableVisualScale
            val visualWidth = fitBounds.width() * scale
            val visualHeight = fitBounds.height() * scale

            val offsetX = if (isRotated) rotatedTableOffsetXPx else 0f
            val offsetY = if (isRotated) rotatedTableOffsetYPx else tableOffsetYPx

            val left = sideInset + (availableWidth - visualWidth) * 0.5f + offsetX
            val top = (surfaceHeight - visualHeight) * 0.5f + offsetY

            postScale(scale, -scale)
            postRotate(tableRotation)

            val drawBounds = RectF(0f, 0f, WORLD_WIDTH, WORLD_HEIGHT)
            mapRect(drawBounds)

            postTranslate(left - drawBounds.left, top - drawBounds.top)

            val finalBounds = RectF(0f, 0f, WORLD_WIDTH, WORLD_HEIGHT)
            mapRect(finalBounds)
            tableScreenBounds = finalBounds
        }

    fun angleDifference(a: Double, b: Double): Double {
        var diff = (a - b + PI) % (2 * PI)
        if (diff < 0) diff += 2 * PI
        return diff - PI
    }

    private fun hasRemainingClaimedBalls(): Boolean {
        val stripes = activity.iAmStripes ?: return true
        return activity.poolBalls.any {
            !it.sunk && it.number != 0 && ((stripes && it.isStripe) || (!stripes && it.isSolid))
        }
    }

    private fun rayEndAtTableEdge(startX: Float, startY: Float, dirX: Float, dirY: Float): Pair<Float, Float> {
        var bestT = Float.POSITIVE_INFINITY
        var bestX = startX
        var bestY = startY

        fun cross(ax: Float, ay: Float, bx: Float, by: Float): Float {
            return ax * by - ay * bx
        }

        for (seg in iosAimWallSegments) {
            val sx = seg.bx - seg.ax
            val sy = seg.by - seg.ay
            val denom = cross(dirX, dirY, sx, sy)

            if (abs(denom) < 0.0001f)
                continue

            val qx = seg.ax - startX
            val qy = seg.ay - startY

            val t = cross(qx, qy, sx, sy) / denom
            val u = cross(qx, qy, dirX, dirY) / denom

            if (t > 0.001f && u >= -0.001f && u <= 1.001f && t < bestT) {
                bestT = t
                bestX = startX + dirX * t
                bestY = startY + dirY * t
            }
        }

        if (!bestT.isFinite()) {
            return Pair(startX, startY)
        }

        return Pair(bestX, bestY)
    }
    private fun drawAimAssist(canvas: Canvas) {
        if (activity.mode != PoolActivity.PoolMode.Aiming) return
        val cueBall = activity.cueBall ?: return
        val paint = Paint().apply {
            color = Color.WHITE
            strokeWidth = 2.5f
            style = Paint.Style.STROKE
            isAntiAlias = true
        }

        var closestBall: PoolActivity.PoolBall? = null
        var closestDistance = Float.MAX_VALUE
        var hitPointX = 0f
        var hitPointY = 0f

        for (ball in activity.poolBalls) {
            if (ball.number == 0 || ball.sunk) continue

            val otherBallX = ball.x - cueBall.x
            val otherBallY = ball.y - cueBall.y

            val slope = tan(cueRot)
            val a = slope * slope + 1
            val b = 2 * (-slope * otherBallY - otherBallX)
            val c = otherBallY * otherBallY + otherBallX * otherBallX - 400
            val discriminant = b * b - 4 * a * c
            if (discriminant <= 0) continue

            val pointsRight = cos(cueRot) > 0
            val direction = if (pointsRight) -1 else 1
            val xCoord = (-b + sqrt(discriminant) * direction) / 2 / a

            if (pointsRight && xCoord < 0) continue
            if (!pointsRight && xCoord > 0) continue

            if (abs(xCoord) < closestDistance) {
                closestDistance = abs(xCoord)
                closestBall = ball
                hitPointY = slope * xCoord + cueBall.y
                hitPointX = xCoord + cueBall.x
            }
        }

        if (closestBall == null) {
            val dirX = cos(cueRot)
            val dirY = sin(cueRot)
            val edge = rayEndAtTableEdge(cueBall.x, cueBall.y, dirX, dirY)

            val markerRadius = 9f
            val markerX = edge.first - dirX * markerRadius
            val markerY = edge.second - dirY * markerRadius
            val lineEndX = markerX - dirX * markerRadius
            val lineEndY = markerY - dirY * markerRadius

            canvas.drawLine(
                cueBall.x + dirX * 10f,
                cueBall.y + dirY * 10f,
                lineEndX,
                lineEndY,
                paint
            )

            canvas.drawCircle(markerX, markerY, markerRadius, paint)
            return
        }

        canvas.drawCircle(hitPointX, hitPointY, 9f, paint)
        canvas.drawLine(
            hitPointX - cos(cueRot) * 10f,
            hitPointY - sin(cueRot) * 10f,
            cueBall.x + cos(cueRot) * 10f,
            cueBall.y + sin(cueRot) * 10f,
            paint
        )

        val stripes = activity.iAmStripes
        val ball = closestBall

        if (activity.isNineBall) {
            val target = activity.lowestNineBallNumber()

            if (target != null && ball.number != target) {
                canvas.drawLine(
                    hitPointX - 10f,
                    hitPointY - 10f,
                    hitPointX + 10f,
                    hitPointY + 10f,
                    paint
                )
                canvas.drawLine(
                    hitPointX + 10f,
                    hitPointY - 10f,
                    hitPointX - 10f,
                    hitPointY + 10f,
                    paint
                )
                return
            }
        } else if (stripes == null) {
            // Open table: allow trajectories for solids and stripes, but not the 8-ball.
            if (ball.number == 8) {
                canvas.drawLine(
                    hitPointX - 10f,
                    hitPointY - 10f,
                    hitPointX + 10f,
                    hitPointY + 10f,
                    paint
                )
                canvas.drawLine(
                    hitPointX + 10f,
                    hitPointY - 10f,
                    hitPointX - 10f,
                    hitPointY + 10f,
                    paint
                )
                return
            }
        } else {
            val hasMoreBalls = hasRemainingClaimedBalls()
            val isWrongBall =
                (stripes && !ball.isStripe && !(ball.number == 8 && !hasMoreBalls)) ||
                        (!stripes && !ball.isSolid && !(ball.number == 8 && !hasMoreBalls))

            if (isWrongBall) {
                canvas.drawLine(
                    hitPointX - 10f,
                    hitPointY - 10f,
                    hitPointX + 10f,
                    hitPointY + 10f,
                    paint
                )
                canvas.drawLine(
                    hitPointX + 10f,
                    hitPointY - 10f,
                    hitPointX - 10f,
                    hitPointY + 10f,
                    paint
                )
                return
            }
        }

        if (activity.isHard) {
            return
        }

        val interBallX = ball.x - hitPointX
        val interBallY = ball.y - hitPointY
        val interBallAngle = atan2(interBallY, interBallX)

        val directness = (angleDifference(
            interBallAngle.toDouble(),
            cueRot.toDouble()
        ) / (PI / 2)).toFloat()

        canvas.drawLine(
            ball.x,
            ball.y,
            ball.x + cos(interBallAngle) * 70f * (1 - abs(directness)),
            ball.y + sin(interBallAngle) * 70f * (1 - abs(directness)),
            paint
        )

        var tangentAngle = interBallAngle
        if (directness < 0) {
            tangentAngle += PI.toFloat() / 2
        } else {
            tangentAngle -= PI.toFloat() / 2
        }

        canvas.drawLine(
            hitPointX + cos(tangentAngle) * 10f,
            hitPointY + sin(tangentAngle) * 10f,
            hitPointX + cos(tangentAngle) * 10f + cos(tangentAngle) * 70f * abs(directness),
            hitPointY + sin(tangentAngle) * 10f + sin(tangentAngle) * 70f * abs(directness),
            paint
        )
    }

    private fun feltTintColor(): Int? {
        return when {
            activity.isNineBall && activity.isHard -> COLOR_PURPLE
            activity.isNineBall -> COLOR_BLUE
            activity.isHard -> COLOR_RED
            else -> null
        }
    }

    private fun feltPaintForTint(tint: Int?): Paint? {
        return tint?.let { color ->
            Paint(
                Paint.ANTI_ALIAS_FLAG or
                        Paint.FILTER_BITMAP_FLAG or
                        Paint.DITHER_FLAG
            ).apply {
                colorFilter = ColorMatrixColorFilter(colorizeMatrix(color))
            }
        }
    }

    private fun colorizeMatrix(color: Int): FloatArray {
        val targetR = Color.red(color) / 255f
        val targetG = Color.green(color) / 255f
        val targetB = Color.blue(color) / 255f

        val lumR = 0.2126f
        val lumG = 0.7152f
        val lumB = 0.0722f

        val scale = FELT_TINT_LUMA_SCALE
        val lift = FELT_TINT_BRIGHTNESS_LIFT

        return floatArrayOf(
            lumR * targetR * scale, lumG * targetR * scale, lumB * targetR * scale, 0f, lift,
            lumR * targetG * scale, lumG * targetG * scale, lumB * targetG * scale, 0f, lift,
            lumR * targetB * scale, lumG * targetB * scale, lumB * targetB * scale, 0f, lift,
            0f, 0f, 0f, 1f, 0f
        )
    }

    private fun shouldDrawBreakLine(): Boolean {
        return !activity.isHard && !activity.isEightBallPlus
    }

    private fun shouldDrawPlus(): Boolean {
        return activity.isEightBallPlus
    }

    private fun currentTableCacheKey(): TableCacheKey {
        val tint = feltTintColor()

        return TableCacheKey(
            tintColor = tint ?: 0,
            drawBreakLine = shouldDrawBreakLine(),
            drawPlus = shouldDrawPlus()
        )
    }

    private fun drawPortraitAssetIntoHorizontalCache(
        canvas: Canvas,
        bitmap: Bitmap,
        paint: Paint?
    ) {
        canvas.withTranslation(
            TABLE_CACHE_WIDTH.toFloat() + TABLE_CACHE_SHADOW_PADDING_X_PX,
            TABLE_CACHE_SHADOW_PADDING_Y_PX.toFloat()
        ) {
            rotate(90f)

            drawBitmap(
                bitmap,
                null,
                portraitAssetDrawRect,
                paint
            )
        }
    }

    private fun buildBaseTableBitmap(tint: Int?, drawBreakLine: Boolean, drawPlus: Boolean): Bitmap {
        val output = createBitmap(TABLE_CACHE_BITMAP_WIDTH, TABLE_CACHE_BITMAP_HEIGHT)

        val canvas = Canvas(output)
        val feltPaint = feltPaintForTint(tint)

        drawPortraitAssetIntoHorizontalCache(canvas, poolFill, feltPaint)

        if (drawBreakLine) {
            drawPortraitAssetIntoHorizontalCache(canvas, poolLine, tablePaint)
        }

        if (drawPlus) {
            drawPortraitAssetIntoHorizontalCache(canvas, poolPlus, tablePaint)
        }

        return output
    }

    private fun buildTopTableBitmap(tint: Int?): Bitmap {
        val output = createBitmap(TABLE_CACHE_BITMAP_WIDTH, TABLE_CACHE_BITMAP_HEIGHT)

        val canvas = Canvas(output)
        val feltPaint = feltPaintForTint(tint)

        drawPortraitAssetIntoHorizontalCache(canvas, poolBorderFelt, feltPaint)
        drawPortraitAssetIntoHorizontalCache(canvas, poolBorder, tablePaint)

        return output
    }

    private fun ensureTableBitmaps() {
        val key = currentTableCacheKey()
        if (cachedTableKey == key && cachedBaseTableBitmap != null && cachedTopTableBitmap != null) {
            return
        }

        val tint = feltTintColor()

        cachedTableKey = key
        cachedBaseTableBitmap = buildBaseTableBitmap(
            tint = tint,
            drawBreakLine = key.drawBreakLine,
            drawPlus = key.drawPlus
        )
        cachedTopTableBitmap = buildTopTableBitmap(tint)

        OpenPigeonLog.i(
            "PoolAssets",
            "rebuilt_table_cache tint=${tint?.let { String.format("#%08X", it) } ?: "green"} " +
                    "line=${key.drawBreakLine} plus=${key.drawPlus} " +
                    "contentScaleH=$TABLE_ASSET_CONTENT_SCALE_HORIZONTAL " +
                    "contentScaleV=$TABLE_ASSET_CONTENT_SCALE_VERTICAL " +
                    "shadowPad=${TABLE_CACHE_SHADOW_PADDING_X_PX}x${TABLE_CACHE_SHADOW_PADDING_Y_PX} " +
                    "cache=${TABLE_CACHE_BITMAP_WIDTH}x${TABLE_CACHE_BITMAP_HEIGHT}"
        )
    }

    private fun drawTableBase(canvas: Canvas) {
        ensureTableBitmaps()

        cachedBaseTableBitmap?.let { bitmap ->
            canvas.drawBitmap(bitmap, null, tableBitmapWithShadowRect, tablePaint)
        }
    }

    private fun drawTableTop(canvas: Canvas) {
        ensureTableBitmaps()

        cachedTopTableBitmap?.let { bitmap ->
            canvas.drawBitmap(bitmap, null, tableBitmapWithShadowRect, tablePaint)
        }
    }

    external fun update(table: Long): Boolean

    private fun getBackgroundColor(): Int {
        return if (activity.isPoolDarkModeEnabled()) {
            0xFF2E2B2E.toInt()
        } else {
            0xFFC8C5C8.toInt()
        }
    }

    private fun drawFrame(canvas: Canvas) {
        synchronized(activity) {
            canvas.drawColor(getBackgroundColor())

            if (activity.poolActivityClosing || activity.table == 0L) {
                return@synchronized
            }

            canvas.withMatrix(transform) {
                val frameStartNs = System.nanoTime()

                val updateStartNs = System.nanoTime()
                val nativeMoving = update(activity.table)
                val updateMs = (System.nanoTime() - updateStartNs) / 1_000_000.0

                activity.traceVisualRoll(
                    reason = "renderer_after_native_update",
                    nativeMoving = nativeMoving
                )

                if (activity.mode == PoolActivity.PoolMode.Playing) {
                    if (!nativeMoving) {
                        activity.handleFinishPlay()
                    } else {
                        activity.handleNativeStillMoving()
                    }
                }

                drawPockets(this)

                for (ball in activity.poolBalls) {
                    if (!ball.inPocket) continue
                    ball.draw(this)
                }

                drawTableBase(this)
                drawAimAssist(this)

                for (ball in activity.poolBalls) {
                    if (ball.sunk || ball.inPocket) continue
                    ball.drawShadow(this)
                }

                drawNineBallTargetRing(this)

                for (ball in activity.poolBalls) {
                    if (ball.sunk || ball.inPocket) continue
                    ball.draw(this)
                }

                activity.traceVisualRoll(
                    reason = "renderer_after_ball_draw",
                    nativeMoving = nativeMoving
                )

                drawScratchRing(this)

                drawTableTop(this)

                if (activity.call8Ball) {
                    for (hole in activity.holes) {
                        drawCircle(
                            hole[0].toFloat(),
                            hole[1].toFloat(),
                            20f,
                            callPocketPaint
                        )
                    }
                }

                if (
                    activity.mode == PoolActivity.PoolMode.Aiming ||
                    activity.mode == PoolActivity.PoolMode.ReplayAiming ||
                    activity.mode == PoolActivity.PoolMode.Playing
                ) {
                    val translation = if (activity.mode != PoolActivity.PoolMode.Playing) {
                        val cueBall = activity.cueBall ?: return@withMatrix
                        floatArrayOf(cueBall.x, cueBall.y)
                    } else {
                        cuePos
                    }

                    translate(translation[0], translation[1])
                    rotate(Math.toDegrees(cueRot.toDouble()).toFloat())

                    cuePaint.alpha = (cueAlpha * 255).roundToInt().coerceIn(0, 255)

                    withSave {
                        translate(-CUE_TIP_OFFSET - cueDraw, 0f)
                        rotate(90f)

                        cueDrawRect.set(
                            -cueHalfHeight,
                            0f,
                            cueHalfHeight,
                            CUE_DRAW_LENGTH
                        )

                        drawBitmap(
                            cue,
                            null,
                            cueDrawRect,
                            cuePaint
                        )
                    }
                }
                val frameMs = (System.nanoTime() - frameStartNs) / 1_000_000.0

                if (activity.mode == PoolActivity.PoolMode.Playing && frameMs > 20.0) {
                    OpenPigeonLog.w(
                        "PoolFramePerf",
                        "slow_frame frameMs=${String.format("%.2f", frameMs)} " +
                                "nativeUpdateMs=${String.format("%.2f", updateMs)} " +
                                "balls=${activity.poolBalls.size} replaying=${activity.replaying}"
                    )
                }
            }
        }
    }

    private fun drawPockets(canvas: Canvas) {
        val pocketRadius = 28f

        for (hole in activity.holes) {
            canvas.drawCircle(
                hole[0].toFloat(),
                hole[1].toFloat(),
                pocketRadius,
                pocketPaint
            )
        }
    }

    private fun drawScratchRing(canvas: Canvas) {
        if (!(activity.mode == PoolActivity.PoolMode.Aiming && activity.scratch)) return
        val cueBall = activity.cueBall ?: return

        scratchRingPhase += 0.05f
        if (scratchRingPhase > (PI * 2).toFloat()) {
            scratchRingPhase -= (PI * 2).toFloat()
        }

        val baseRadius = 15f
        val pulse = ((sin(scratchRingPhase.toDouble()).toFloat() + 1f) * 0.5f) * 3f
        val radius = baseRadius + pulse

        canvas.drawCircle(
            cueBall.x,
            cueBall.y,
            radius,
            Paint().apply {
                color = Color.WHITE
                strokeWidth = 2.5f
                style = Paint.Style.STROKE
                isAntiAlias = true
                alpha = 180
            }
        )
    }

    private fun drawNineBallTargetRing(canvas: Canvas) {
        if (!(activity.isNineBall && activity.mode == PoolActivity.PoolMode.Aiming)) return

        val target = activity.lowestNineBallNumber() ?: return
        val ball = activity.poolBalls.find { it.number == target && !it.sunk } ?: return

        nineBallTargetRingPhase += 0.015f
        if (nineBallTargetRingPhase > 1f) {
            nineBallTargetRingPhase -= 1f
        }

        val phase = nineBallTargetRingPhase
        val radius = 10f + (1f - phase) * 10f
        val alpha = ((1f - phase) * 210f).roundToInt().coerceIn(0, 210)

        canvas.drawCircle(
            ball.x,
            ball.y,
            radius,
            Paint().apply {
                color = Color.WHITE
                strokeWidth = 2.5f
                style = Paint.Style.STROKE
                isAntiAlias = true
                this.alpha = alpha
            }
        )
    }

    var cueAnimator: ValueAnimator? = null

    fun setCueVisible(visible: Boolean) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post {
                setCueVisible(visible)
            }
            return
        }

        cueAnimator?.cancel()
        cueAnimator = null

        cueAnimator = ValueAnimator.ofFloat(cueAlpha, if (visible) 1f else 0f).apply {
            duration = 200L

            addUpdateListener { animation ->
                cueAlpha = animation.animatedValue as Float
            }

            doOnEnd {
                cueAnimator = null
                cueAlpha = if (visible) 1f else 0f
            }

            start()
        }
    }

    var hasSurface = false
    override fun run() {
        var startTime: Long
        var timeMillis: Long
        var waitTime: Long
        var frame = 0L

        while (running) {
            startTime = System.nanoTime()

            if (hasSurface) {
                val canvas = holder.lockHardwareCanvas()
                if (canvas != null) {
                    drawFrame(canvas)
                    holder.unlockCanvasAndPost(canvas)

                    frame += 1
                    signalFrameReady()
                }
            }

            timeMillis = (System.nanoTime() - startTime) / 1000000

            waitTime = frameTime - timeMillis

            if (waitTime > 0) {
                try {
                    sleep(waitTime)
                } catch (_: InterruptedException) {
                }
            }
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        OpenPigeonLog.d("Surface", "Created")
        hasSurface = true
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        OpenPigeonLog.d("Surface", "Changed width: $width, Height: $height")
        transform
        activity.syncCueRailsToTable()
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        OpenPigeonLog.d("Surface", "Destroyed")
        hasSurface = false
    }
}