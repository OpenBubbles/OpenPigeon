package com.openbubbles.openpigeon.knockout

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.cos
import kotlin.math.sin
import android.graphics.Path
import android.graphics.Region
import android.os.Build

class KnockoutPiece(
    val traceId: Int,
    val player: Int,
    state: KnockoutPieceState,
    private val p1Bitmap: Bitmap?,
    private val p2Bitmap: Bitmap?,
) {
    val buffer: FloatBuffer = ByteBuffer.allocateDirect(8 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()

    var x: Float = state.x
    var y: Float = state.y
    var rotation: Float = state.rotation
    var shootDir: Float = state.shootDir
    var power: Float = state.power
    var alive: Boolean = true
    var dying: Boolean = false
    private var deathStartMs: Long = 0L
    private var deathX: Float = x
    private var deathY: Float = y
    private var deathRotation: Float = rotation
    private val arrowPath = Path()
    private val arrowClipPath = Path()

    private companion object {
        const val DEATH_DURATION_MS = 460L
        const val DEATH_PHASE_ONE_MS = 160L
    }

    init {
        buffer.put(0, x)
        buffer.put(1, y)
        buffer.put(2, rotation)
        buffer.put(3, 0f)
        buffer.put(4, 0f)
        buffer.put(5, 0f)
        buffer.put(6, player.toFloat())
        buffer.put(7, traceId.toFloat())
    }

    fun syncFromNative() {
        if (dying || !alive) return

        x = buffer.get(0)
        y = buffer.get(1)
        rotation = buffer.get(2)
    }

    fun containsWorldPoint(wx: Float, wy: Float): Boolean {
        val dx = wx - x
        val dy = wy - y
        return dx * dx + dy * dy <= KnockoutConstants.PIECE_TOUCH_RADIUS * KnockoutConstants.PIECE_TOUCH_RADIUS
    }

    fun hasPower(): Boolean = alive && !dying && power > KnockoutConstants.READY_POWER_EPS

    fun setAimFromWorld(wx: Float, wy: Float) {
        val dx = wx - x
        val dy = wy - y
        val len = kotlin.math.hypot(dx, dy)

        shootDir = kotlin.math.atan2(dy, dx)
        power = len.coerceIn(0.0f, KnockoutConstants.MAX_POWER)
    }

    fun startKillAnimation(nowMs: Long) {
        if (dying || !alive) return

        dying = true
        alive = false
        deathStartMs = nowMs
        deathX = x
        deathY = y
        deathRotation = rotation
        power = 0f
        shootDir = 0f
    }

    fun isDeathAnimationDone(nowMs: Long): Boolean {
        return dying && nowMs - deathStartMs >= DEATH_DURATION_MS
    }

    fun finishKillAnimation() {
        dying = false
    }

    private fun deathScale(nowMs: Long): Float {
        if (!dying) return 1f

        val elapsed = (nowMs - deathStartMs).coerceAtLeast(0L)

        return if (elapsed <= DEATH_PHASE_ONE_MS) {
            val t = elapsed.toFloat() / DEATH_PHASE_ONE_MS.toFloat()
            1f + (0.6f - 1f) * t
        } else {
            val t = ((elapsed - DEATH_PHASE_ONE_MS).toFloat() /
                    (DEATH_DURATION_MS - DEATH_PHASE_ONE_MS).toFloat())
                .coerceIn(0f, 1f)

            0.6f * (1f - t)
        }
    }

    fun drawHighlightRing(canvas: Canvas, paint: Paint, pulseScale: Float) {
        if (!alive || dying) return

        val oldStyle = paint.style
        val oldStrokeWidth = paint.strokeWidth
        val oldColor = paint.color
        val oldAlpha = paint.alpha

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 3.0f
        paint.color = 0xff000000.toInt()
        paint.alpha = 240

        val baseRadius = (KnockoutConstants.PIECE_VISUAL_SIZE * 0.5f) + 4.0f
        val radius = baseRadius * pulseScale

        canvas.drawCircle(x, -y, radius, paint)

        paint.style = oldStyle
        paint.strokeWidth = oldStrokeWidth
        paint.color = oldColor
        paint.alpha = oldAlpha
    }

    fun draw(canvas: Canvas, paint: Paint) {
        if (!alive && !dying) return

        val now = System.currentTimeMillis()
        val killScale = deathScale(now)
        if (killScale <= 0.001f) return

        val bitmap = if (player == 1) p1Bitmap else p2Bitmap
        val drawX = if (dying) deathX else x
        val drawY = if (dying) deathY else y
        val drawRotation = if (dying) deathRotation else rotation

        canvas.save()
        canvas.translate(drawX, -drawY)
        canvas.rotate(-Math.toDegrees(drawRotation.toDouble()).toFloat())
        canvas.scale(killScale, killScale)

        if (bitmap != null) {
            val half = KnockoutConstants.PIECE_VISUAL_SIZE / 2f
            canvas.drawBitmap(bitmap, null, RectF(-half, -half, half, half), paint)
        } else {
            paint.style = Paint.Style.FILL
            paint.color = if (player == 1) 0xff222222.toInt() else 0xffdddddd.toInt()
            canvas.drawCircle(0f, 0f, KnockoutConstants.PIECE_RADIUS, paint)
        }

        canvas.restore()
    }

    fun drawArrow(canvas: Canvas, paint: Paint, alpha: Int = 255) {
        if (!alive || dying || power <= 0.001f) return

        val oldStyle = paint.style
        val oldStrokeWidth = paint.strokeWidth
        val oldColor = paint.color
        val oldAlpha = paint.alpha
        val oldCap = paint.strokeCap

        val sx = x
        val sy = -y

        val dirX = cos(shootDir)
        val dirY = -sin(shootDir) // world-up to screen-down

        val ex = sx + dirX * power
        val ey = sy + dirY * power

        val headLen = 14f
        val headHalfW = 9f

        val shaftLen = (power - headLen).coerceAtLeast(0f)
        val shaftEx = sx + dirX * shaftLen
        val shaftEy = sy + dirY * shaftLen

        val perpX = -dirY
        val perpY = dirX

        val baseX = ex - dirX * headLen
        val baseY = ey - dirY * headLen

        paint.color = if (player == 1) {
            0xff000000.toInt()
        } else {
            0xff61779e.toInt()
        }
        paint.alpha = alpha.coerceIn(0, 255)

        canvas.save()

        arrowClipPath.rewind()
        arrowClipPath.addCircle(
            sx,
            sy,
            KnockoutConstants.PIECE_VISUAL_SIZE * 0.5f - 1.5f,
            Path.Direction.CW
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            canvas.clipOutPath(arrowClipPath)
        } else {
            @Suppress("DEPRECATION")
            canvas.clipPath(arrowClipPath, Region.Op.DIFFERENCE)
        }

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 5f
        paint.strokeCap = Paint.Cap.ROUND

        canvas.drawLine(sx, sy, shaftEx, shaftEy, paint)

        arrowPath.rewind()
        arrowPath.moveTo(ex, ey)
        arrowPath.lineTo(baseX + perpX * headHalfW, baseY + perpY * headHalfW)
        arrowPath.lineTo(baseX - perpX * headHalfW, baseY - perpY * headHalfW)
        arrowPath.close()

        paint.style = Paint.Style.FILL
        canvas.drawPath(arrowPath, paint)

        canvas.restore()

        paint.style = oldStyle
        paint.strokeWidth = oldStrokeWidth
        paint.color = oldColor
        paint.alpha = oldAlpha
        paint.strokeCap = oldCap
    }
}
