package com.openbubbles.openpigeon.settings

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import kotlin.math.cos
import kotlin.math.sin
import androidx.core.view.isVisible
import androidx.core.graphics.withTranslation

class AvatarWinBurstView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(
    context,
    attrs,
) {
    private val rayPaint =
        Paint(
            Paint.ANTI_ALIAS_FLAG,
        ).apply {
            style =
                Paint.Style.FILL

            isDither =
                true
        }

    private val cutoutPaint =
        Paint(
            Paint.ANTI_ALIAS_FLAG,
        ).apply {
            style =
                Paint.Style.FILL

            color =
                Color.BLACK

            xfermode =
                PorterDuffXfermode(
                    PorterDuff.Mode.DST_OUT,
                )
        }

    private val rayPath =
        Path()

    private var rayColor =
        Color.rgb(
            255,
            214,
            0,
        )

    private var rayCount =
        18

    private var spinDegrees =
        0f

    private var spinAnimator:
            ValueAnimator? =
        null

    init {
        visibility =
            GONE

        alpha =
            0f

        isClickable =
            false

        isFocusable =
            false

        importantForAccessibility =
            IMPORTANT_FOR_ACCESSIBILITY_NO

        setLayerType(
            LAYER_TYPE_SOFTWARE,
            null,
        )
    }

    fun setRayColor(
        color: Int,
    ) {
        rayColor =
            color

        invalidate()
    }

    fun setRayCount(
        count: Int,
    ) {
        rayCount =
            count.coerceIn(
                4,
                64,
            )

        invalidate()
    }

    fun play() {
        if (
            isVisible &&
            spinAnimator?.isRunning == true &&
            alpha >= 0.999f
        ) {
            return
        }

        visibility =
            VISIBLE

        animate().cancel()

        animate()
            .alpha(
                1f,
            )
            .setDuration(
                FADE_DURATION_MS,
            )
            .start()

        startSpinAnimation()
    }

    fun stop(
        immediate: Boolean = true,
    ) {
        animate().cancel()

        if (immediate) {
            alpha =
                0f

            visibility =
                GONE

            stopSpinAnimation()

            return
        }

        animate()
            .alpha(
                0f,
            )
            .setDuration(
                FADE_DURATION_MS,
            )
            .withEndAction {
                visibility =
                    GONE

                stopSpinAnimation()
            }
            .start()
    }

    private fun startSpinAnimation() {
        if (spinAnimator?.isRunning == true) {
            return
        }

        spinAnimator =
            ValueAnimator.ofFloat(
                0f,
                360f,
            ).apply {
                duration =
                    ROTATION_DURATION_MS

                repeatCount =
                    ValueAnimator.INFINITE

                repeatMode =
                    ValueAnimator.RESTART

                interpolator =
                    LinearInterpolator()

                addUpdateListener { animator ->
                    spinDegrees =
                        animator.animatedValue as Float

                    invalidate()
                }

                start()
            }
    }

    private fun stopSpinAnimation() {
        spinAnimator?.cancel()

        spinAnimator =
            null
    }

    override fun onDraw(
        canvas: Canvas,
    ) {
        super.onDraw(
            canvas,
        )

        if (
            width <= 0 ||
            height <= 0
        ) {
            return
        }

        val viewWidth =
            width.toFloat()

        val viewHeight =
            height.toFloat()

        val centerX =
            viewWidth /
                    2f

        val centerY =
            viewHeight /
                    2f

        val layer =
            canvas.saveLayer(
                0f,
                0f,
                viewWidth,
                viewHeight,
                null,
            )

        canvas.withTranslation(
            centerX,
            centerY,
        ) {

            canvas.scale(
                viewWidth /
                        2f,
                viewHeight /
                        2f,
            )

            canvas.rotate(
                spinDegrees,
            )

            rayPaint.shader =
                RadialGradient(
                    0f,
                    0f,
                    1f,
                    intArrayOf(
                        colorWithAlpha(
                            rayColor,
                            0,
                        ),
                        colorWithAlpha(
                            rayColor,
                            235,
                        ),
                        colorWithAlpha(
                            rayColor,
                            145,
                        ),
                        colorWithAlpha(
                            rayColor,
                            0,
                        ),
                    ),
                    floatArrayOf(
                        0f,
                        0.22f,
                        0.68f,
                        1f,
                    ),
                    Shader.TileMode.CLAMP,
                )

            drawRaySet(
                canvas = canvas,
                halfRayAngleFactor = 0.36f,
                paintAlpha = 100,
            )

            drawRaySet(
                canvas = canvas,
                halfRayAngleFactor = 0.19f,
                paintAlpha = 225,
            )

            rayPaint.shader =
                null

            rayPaint.alpha =
                255

        }

        val pillWidth =
            viewWidth *
                    0.35f

        val pillHeight =
            viewHeight *
                    0.15f

        val pillRect =
            RectF(
                centerX -
                        pillWidth /
                        2f,
                centerY -
                        pillHeight /
                        2f,
                centerX +
                        pillWidth /
                        2f,
                centerY +
                        pillHeight /
                        2f,
            )

        canvas.drawRoundRect(
            pillRect,
            pillHeight /
                    2f,
            pillHeight /
                    2f,
            cutoutPaint,
        )

        canvas.restoreToCount(
            layer,
        )
    }

    private fun drawRaySet(
        canvas: Canvas,
        halfRayAngleFactor: Float,
        paintAlpha: Int,
    ) {
        val count =
            rayCount.coerceAtLeast(
                1,
            )

        val sectorDegrees =
            360f /
                    count.toFloat()

        val halfRayDegrees =
            sectorDegrees *
                    halfRayAngleFactor

        rayPaint.alpha =
            paintAlpha.coerceIn(
                0,
                255,
            )

        for (index in 0 until count) {
            val centerDegrees =
                index.toFloat() *
                        sectorDegrees

            buildRayPath(
                startDegrees =
                    centerDegrees -
                            halfRayDegrees,
                endDegrees =
                    centerDegrees +
                            halfRayDegrees,
            )

            canvas.drawPath(
                rayPath,
                rayPaint,
            )
        }
    }

    private fun buildRayPath(
        startDegrees: Float,
        endDegrees: Float,
    ) {
        val startRadians =
            Math.toRadians(
                startDegrees.toDouble(),
            )

        val endRadians =
            Math.toRadians(
                endDegrees.toDouble(),
            )

        val startCos =
            cos(
                startRadians,
            ).toFloat()

        val startSin =
            sin(
                startRadians,
            ).toFloat()

        val endCos =
            cos(
                endRadians,
            ).toFloat()

        val endSin =
            sin(
                endRadians,
            ).toFloat()

        rayPath.reset()

        rayPath.moveTo(
            startCos *
                    INNER_RAY_RADIUS,
            startSin *
                    INNER_RAY_RADIUS,
        )

        rayPath.lineTo(
            startCos,
            startSin,
        )

        rayPath.lineTo(
            endCos,
            endSin,
        )

        rayPath.lineTo(
            endCos *
                    INNER_RAY_RADIUS,
            endSin *
                    INNER_RAY_RADIUS,
        )

        rayPath.close()
    }

    private fun colorWithAlpha(
        color: Int,
        alpha: Int,
    ): Int {
        return Color.argb(
            alpha.coerceIn(
                0,
                255,
            ),
            Color.red(
                color,
            ),
            Color.green(
                color,
            ),
            Color.blue(
                color,
            ),
        )
    }

    override fun onDetachedFromWindow() {
        animate().cancel()

        stopSpinAnimation()

        super.onDetachedFromWindow()
    }

    private companion object {
        private const val ROTATION_DURATION_MS =
            20_000L

        private const val FADE_DURATION_MS =
            250L

        private const val INNER_RAY_RADIUS =
            0.04f
    }
}