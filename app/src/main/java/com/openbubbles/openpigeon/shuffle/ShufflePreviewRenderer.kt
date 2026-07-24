package com.openbubbles.openpigeon.shuffle

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import androidx.annotation.DrawableRes
import com.openbubbles.openpigeon.R
import kotlin.math.abs
import kotlin.math.min

data class ShufflePreviewPuck(
    val x: Float,
    val y: Float,
    val player: Int,
    val rotation: Float = 0f,
)

data class ShufflePreviewBoard(
    val pucks: List<ShufflePreviewPuck>,
)

object ShufflePreviewRenderer {

    private const val DEFAULT_OUT_WIDTH = 320
    private const val DEFAULT_OUT_HEIGHT = 480

    private const val PUCKS_PER_PLAYER = 4

    private const val PLAYABLE_HALF_WIDTH = 178f
    private const val PLAYABLE_HALF_HEIGHT = 193f

    private const val PUCK_RADIUS_WORLD = 15f
    private const val PUCK_DIAMETER_WORLD = PUCK_RADIUS_WORLD * 2f

    private const val READY_AREA_Y = 205f

    private const val BOARD_WORLD_WIDTH = 380f
    private const val BOARD_WORLD_HEIGHT = 410f
    private const val BOARD_INSET_WORLD = 12f

    private const val BOARD_MAX_WIDTH_RATIO = 0.72f
    private const val BOARD_MAX_HEIGHT_RATIO = 0.96f

    private const val INDICATOR_SIZE_RATIO = 0.90f
    private const val INDICATOR_SPACING_RATIO = 1.18f
    private const val INDICATOR_BOARD_GAP_RATIO = 0.32f

    private val boardBitmapCache = mutableMapOf<Int, Bitmap>()
    private val puckBitmapCache = mutableMapOf<Int, Bitmap?>()
    private var bumperBitmapCache: Bitmap? = null
    private var bumperBitmapLoaded = false

    fun render(
        context: Context,
        board: ShufflePreviewBoard,
        mapMode: Int,
        mapScores: List<Int>,
        gameFinished: Boolean = false,
    ): Bitmap {
        return render(
            context = context,
            board = board,
            mapMode = mapMode,
            mapScores = mapScores,
            targetWidthPx = DEFAULT_OUT_WIDTH,
            targetHeightPx = DEFAULT_OUT_HEIGHT,
            gameFinished = gameFinished,
        )
    }

    fun render(
        context: Context,
        board: ShufflePreviewBoard,
        mapMode: Int,
        mapScores: List<Int>,
        targetWidthPx: Int,
        targetHeightPx: Int,
        gameFinished: Boolean = false,
    ): Bitmap {
        val outputWidth = targetWidthPx.coerceAtLeast(1)
        val outputHeight = targetHeightPx.coerceAtLeast(1)

        val output = Bitmap.createBitmap(
            outputWidth,
            outputHeight,
            Bitmap.Config.ARGB_8888,
        )

        val canvas = Canvas(output)

        val boardRect = calculateBoardRect(
            outputWidth = outputWidth,
            outputHeight = outputHeight,
        )

        val imagePaint = Paint(
            Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG,
        )

        drawBoardShadow(
            canvas = canvas,
            boardRect = boardRect,
        )

        val hasValidGeneratedMap = mapScores.size == expectedMapCountForMode(mapMode)

        if (hasValidGeneratedMap) {
            drawGeneratedShuffleBoard(
                canvas = canvas,
                boardRect = boardRect,
                mode = mapMode,
                scores = mapScores,
            )

            if (mapMode == 2) {
                drawMode2Bumper(
                    context = context,
                    canvas = canvas,
                    boardRect = boardRect,
                    imagePaint = imagePaint,
                )
            }
        } else {
            drawFallbackBoard(
                canvas = canvas,
                context = context,
                boardRect = boardRect,
                mapMode = mapMode,
                imagePaint = imagePaint,
            )
        }

        val playableRect = playableBoardRect(boardRect)

        val player1Bitmap = loadPuckBitmap(
            context = context,
            player = 1,
        )

        val player2Bitmap = loadPuckBitmap(
            context = context,
            player = 2,
        )

        val boardPucks = board.pucks.filter(::isPuckOnActualBoard)

        drawBoardPucks(
            canvas = canvas,
            playableRect = playableRect,
            pucks = boardPucks,
            player1Bitmap = player1Bitmap,
            player2Bitmap = player2Bitmap,
            imagePaint = imagePaint,
        )

        val player1Played = board.pucks.count { puck ->
            puck.player == 1 && !isReadyRowPuck(puck)
        }.coerceIn(0, PUCKS_PER_PLAYER)

        val player2Played = board.pucks.count { puck ->
            puck.player == 2 && !isReadyRowPuck(puck)
        }.coerceIn(0, PUCKS_PER_PLAYER)

        val player1Remaining = if (gameFinished) {
            0
        } else {
            (PUCKS_PER_PLAYER - player1Played).coerceIn(0, PUCKS_PER_PLAYER)
        }

        val player2Remaining = if (gameFinished) {
            0
        } else {
            (PUCKS_PER_PLAYER - player2Played).coerceIn(0, PUCKS_PER_PLAYER)
        }

        drawReserveIndicators(
            canvas = canvas,
            outputWidth = outputWidth,
            boardRect = boardRect,
            playableRect = playableRect,
            player1Remaining = player1Remaining,
            player2Remaining = player2Remaining,
            player1Bitmap = player1Bitmap,
            player2Bitmap = player2Bitmap,
            imagePaint = imagePaint,
        )

        return output
    }

    private fun drawBoardShadow(
        canvas: Canvas,
        boardRect: RectF,
    ) {
        val scale = boardScale(boardRect)

        val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.argb(70, 0, 0, 0)
        }

        val offsetX = 2f * scale
        val offsetY = 3f * scale
        val cornerRadius = 3f * scale

        canvas.drawRoundRect(
            RectF(
                boardRect.left + offsetX,
                boardRect.top + offsetY,
                boardRect.right + offsetX,
                boardRect.bottom + offsetY,
            ),
            cornerRadius,
            cornerRadius,
            shadowPaint,
        )
    }

    private fun drawFallbackBoard(
        canvas: Canvas,
        context: Context,
        boardRect: RectF,
        mapMode: Int,
        imagePaint: Paint,
    ) {
        val fallbackBitmap = loadBoardBitmap(
            context = context,
            mapMode = mapMode,
        )

        if (fallbackBitmap != null) {
            canvas.drawBitmap(
                fallbackBitmap,
                null,
                boardRect,
                imagePaint,
            )
            return
        }

        // Fallback if drawable cannot be decoded
        drawGeneratedShuffleBoard(
            canvas = canvas,
            boardRect = boardRect,
            mode = mapMode,
            scores = defaultMapScoresForMode(mapMode),
        )

        if (mapMode == 2) {
            drawMode2Bumper(
                context = context,
                canvas = canvas,
                boardRect = boardRect,
                imagePaint = imagePaint,
            )
        }
    }

    private data class ShuffleSegmentSpec(
        val points: List<Pair<Float, Float>>,
    )

    private fun seg(
        vararg points: Pair<Float, Float>,
    ): ShuffleSegmentSpec {
        return ShuffleSegmentSpec(points.toList())
    }

    private fun drawGeneratedShuffleBoard(
        canvas: Canvas,
        boardRect: RectF,
        mode: Int,
        scores: List<Int>,
    ) {
        val segments = shuffleSegmentSpecs(mode)
        val defaults = defaultMapScoresForMode(mode)
        val playableRect = playableBoardRect(boardRect)
        val scale = boardScale(boardRect)

        val wallPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = BOARD_WALL_COLOR
        }

        val cornerRadius = 3f * scale

        canvas.drawRoundRect(
            boardRect,
            cornerRadius,
            cornerRadius,
            wallPaint,
        )

        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = baseBoardColor(mode)
        }

        val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeJoin = Paint.Join.ROUND
            strokeCap = Paint.Cap.ROUND
        }

        val saveCount = canvas.save()
        canvas.clipRect(playableRect)

        canvas.drawRect(
            playableRect,
            fillPaint,
        )

        for (index in segments.indices) {
            val score = scores.getOrNull(index) ?: defaults.getOrNull(index) ?: 0

            fillPaint.color = segmentFillColor(
                mode = mode,
                score = score,
            )

            drawShuffleSegmentPolygon(
                canvas = canvas,
                boardRect = boardRect,
                points = segments[index].points,
                paint = fillPaint,
            )
        }

        linePaint.strokeWidth = 1.25f * scale
        linePaint.color = Color.argb(235, 255, 255, 255)

        for (segment in segments) {
            drawShuffleSegmentPolygonStroke(
                canvas = canvas,
                boardRect = boardRect,
                points = segment.points,
                paint = linePaint,
            )
        }

        drawGeneratedBoardLabels(
            canvas = canvas,
            boardRect = boardRect,
            mode = mode,
            scores = scores,
        )

        canvas.restoreToCount(saveCount)

        linePaint.strokeWidth = 2f * scale
        linePaint.color = Color.WHITE

        canvas.drawRect(
            playableRect,
            linePaint,
        )
    }

    private fun shuffleSegmentSpecs(
        mode: Int,
    ): List<ShuffleSegmentSpec> {
        return when (mode) {
            1 -> shuffleMode1SegmentSpecs()
            2 -> shuffleMode2SegmentSpecs()
            3 -> shuffleMode3SegmentSpecs()
            else -> shuffleMode1SegmentSpecs()
        }
    }

    private fun shuffleMode1SegmentSpecs(): List<ShuffleSegmentSpec> {
        return listOf(
            seg(-125f to 135f, -125f to -135f, -178f to -193f, -178f to 193f),
            seg(-70f to -76f, -70f to 76f, -125f to 135f, -125f to -135f),
            seg(-70f to -76f, 0f to 0f, -70f to 76f),
            seg(70f to -76f, 0f to 0f, 70f to 76f),
            seg(70f to -76f, 70f to 76f, 125f to 135f, 125f to -135f),
            seg(125f to 135f, 125f to -135f, 178f to -193f, 178f to 193f),
            seg(125f to 135f, -125f to 135f, -178f to 193f, 178f to 193f),
            seg(-70f to 76f, 70f to 76f, 125f to 135f, -125f to 135f),
            seg(-70f to 76f, 0f to 0f, 70f to 76f),
            seg(-70f to -76f, 0f to 0f, 70f to -76f),
            seg(-70f to -76f, 70f to -76f, 125f to -135f, -125f to -135f),
            seg(125f to -135f, -125f to -135f, -178f to -193f, 178f to -193f),
        )
    }

    private fun shuffleMode2SegmentSpecs(): List<ShuffleSegmentSpec> {
        return listOf(
            seg(0f to 0f, -64.5f to 69.5f, -129f to 0f, -64.5f to -69.5f),
            seg(0f to 0f, -64.5f to 69.5f, 0f to 139f, 64.5f to 69.5f),
            seg(0f to 0f, 64.5f to 69.5f, 129f to 0f, 64.5f to -69.5f),
            seg(0f to 0f, 64.5f to -69.5f, 0f to -139f, -64.5f to -69.5f),
            seg(-129f to 0f, -178f to 0f, -178f to 68f, -120f to 131f, -64.5f to 69.5f),
            seg(-120f to 131f, -64.5f to 69.5f, 0f to 139f, 0f to 193f, -63f to 193f),
            seg(129f to 0f, 178f to 0f, 178f to 68f, 120f to 131f, 64.5f to 69.5f),
            seg(120f to 131f, 64.5f to 69.5f, 0f to 139f, 0f to 193f, 63f to 193f),
            seg(129f to 0f, 178f to 0f, 178f to -68f, 120f to -131f, 64.5f to -69.5f),
            seg(120f to -131f, 64.5f to -69.5f, 0f to -139f, 0f to -193f, 63f to -193f),
            seg(-129f to 0f, -178f to 0f, -178f to -68f, -120f to -131f, -64.5f to -69.5f),
            seg(-120f to -131f, -64.5f to -69.5f, 0f to -139f, 0f to -193f, -63f to -193f),
            seg(-178f to 68f, -178f to 193f, -63f to 193f),
            seg(178f to 68f, 178f to 193f, 63f to 193f),
            seg(178f to -68f, 178f to -193f, 63f to -193f),
            seg(-178f to -68f, -178f to -193f, -63f to -193f),
        )
    }

    private fun shuffleMode3SegmentSpecs(): List<ShuffleSegmentSpec> {
        return listOf(
            seg(-35.5f to -38.5f, -35.5f to 38.5f, 35.5f to 38.5f, 35.5f to -38.5f),
            seg(-106.5f to -38.5f, -106.5f to 38.5f, -35.5f to 38.5f, -35.5f to -38.5f),
            seg(-106.5f to 38.5f, -106.5f to 115.5f, -35.5f to 115.5f, -35.5f to 38.5f),
            seg(-35.5f to 38.5f, -35.5f to 115.5f, 35.5f to 115.5f, 35.5f to 38.5f),
            seg(35.5f to 38.5f, 35.5f to 115.5f, 106.5f to 115.5f, 106.5f to 38.5f),
            seg(35.5f to -38.5f, 35.5f to 38.5f, 106.5f to 38.5f, 106.5f to -38.5f),
            seg(35.5f to -115.5f, 35.5f to -38.5f, 106.5f to -38.5f, 106.5f to -115.5f),
            seg(-35.5f to -115.5f, -35.5f to -38.5f, 35.5f to -38.5f, 35.5f to -115.5f),
            seg(-106.5f to -115.5f, -106.5f to -38.5f, -35.5f to -38.5f, -35.5f to -115.5f),
            seg(-177.5f to -115.5f, -177.5f to -38.5f, -106.5f to -38.5f, -106.5f to -115.5f),
            seg(-177.5f to -38.5f, -177.5f to 38.5f, -106.5f to 38.5f, -106.5f to -38.5f),
            seg(-177.5f to 38.5f, -177.5f to 115.5f, -106.5f to 115.5f, -106.5f to 38.5f),
            seg(106.5f to -115.5f, 106.5f to -38.5f, 177.5f to -38.5f, 177.5f to -115.5f),
            seg(106.5f to -38.5f, 106.5f to 38.5f, 177.5f to 38.5f, 177.5f to -38.5f),
            seg(106.5f to 38.5f, 106.5f to 115.5f, 177.5f to 115.5f, 177.5f to 38.5f),
            seg(-35.5f to -192.5f, -35.5f to -115.5f, 35.5f to -115.5f, 35.5f to -192.5f),
            seg(-35.5f to 115.5f, -35.5f to 192.5f, 35.5f to 192.5f, 35.5f to 115.5f),
            seg(-177.5f to -192.5f, -177.5f to -115.5f, -35.5f to -115.5f, -35.5f to -192.5f),
            seg(-177.5f to 115.5f, -177.5f to 192.5f, -35.5f to 192.5f, -35.5f to 115.5f),
            seg(35.5f to -192.5f, 35.5f to -115.5f, 177.5f to -115.5f, 177.5f to -192.5f),
            seg(35.5f to 115.5f, 35.5f to 192.5f, 177.5f to 192.5f, 177.5f to 115.5f),
        )
    }

    private fun drawShuffleSegmentPolygon(
        canvas: Canvas,
        boardRect: RectF,
        points: List<Pair<Float, Float>>,
        paint: Paint,
    ) {
        if (points.isEmpty()) {
            return
        }

        canvas.drawPath(
            buildSegmentPath(
                boardRect = boardRect,
                points = points,
            ),
            paint,
        )
    }

    private fun drawShuffleSegmentPolygonStroke(
        canvas: Canvas,
        boardRect: RectF,
        points: List<Pair<Float, Float>>,
        paint: Paint,
    ) {
        if (points.isEmpty()) {
            return
        }

        canvas.drawPath(
            buildSegmentPath(
                boardRect = boardRect,
                points = points,
            ),
            paint,
        )
    }

    private fun buildSegmentPath(
        boardRect: RectF,
        points: List<Pair<Float, Float>>,
    ): Path {
        return Path().apply {
            points.forEachIndexed { index, point ->
                val x = boardX(
                    worldX = point.first,
                    boardRect = boardRect,
                )

                val y = boardY(
                    worldY = point.second,
                    boardRect = boardRect,
                )

                if (index == 0) {
                    moveTo(x, y)
                } else {
                    lineTo(x, y)
                }
            }

            close()
        }
    }

    private fun drawGeneratedBoardLabels(
        canvas: Canvas,
        boardRect: RectF,
        mode: Int,
        scores: List<Int>,
    ) {
        val segments = shuffleSegmentSpecs(mode)
        val defaults = defaultMapScoresForMode(mode)
        val scale = boardScale(boardRect)

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(
                "sans-serif-black",
                Typeface.NORMAL,
            )
            isFakeBoldText = true
            style = Paint.Style.FILL
            textSize = when (mode) {
                1 -> 19f * scale
                2 -> 17f * scale
                3 -> 15.5f * scale
                else -> 19f * scale
            }
            color = Color.WHITE
        }

        for (index in segments.indices) {
            val score = scores.getOrNull(index) ?: defaults.getOrNull(index) ?: 0

            val center = segmentCentroid(
                points = segments[index].points,
                boardRect = boardRect,
            )

            val baseline = center.second - (textPaint.descent() + textPaint.ascent()) / 2f

            canvas.drawText(
                score.toString(),
                center.first,
                baseline,
                textPaint,
            )
        }
    }

    private fun segmentCentroid(
        points: List<Pair<Float, Float>>,
        boardRect: RectF,
    ): Pair<Float, Float> {
        if (points.isEmpty()) {
            return boardRect.centerX() to boardRect.centerY()
        }

        var x = 0f
        var y = 0f

        for (point in points) {
            x += boardX(
                worldX = point.first,
                boardRect = boardRect,
            )

            y += boardY(
                worldY = point.second,
                boardRect = boardRect,
            )
        }

        return (x / points.size.toFloat()) to (y / points.size.toFloat())
    }

    private fun baseBoardColor(
        mode: Int,
    ): Int {
        return when (mode) {
            1 -> Color.rgb(68, 139, 196)
            2 -> Color.rgb(126, 118, 199)
            3 -> Color.rgb(65, 178, 102)
            else -> Color.rgb(68, 139, 196)
        }
    }

    private fun segmentFillColor(
        mode: Int,
        score: Int,
    ): Int {
        return when (mode) {
            1 -> if (score == 10) {
                Color.rgb(56, 196, 97)
            } else {
                Color.rgb(68, 139, 196)
            }

            2 -> if (score == 10) {
                Color.rgb(56, 196, 97)
            } else {
                Color.rgb(126, 118, 199)
            }

            3 -> if (score == 10) {
                Color.rgb(195, 72, 76)
            } else {
                Color.rgb(65, 178, 102)
            }

            else -> Color.rgb(68, 139, 196)
        }
    }

    private fun drawMode2Bumper(
        context: Context,
        canvas: Canvas,
        boardRect: RectF,
        imagePaint: Paint,
    ) {
        val scale = boardScale(boardRect)
        val centerX = boardRect.centerX()
        val centerY = boardRect.centerY()
        val bumperSize = 53f * scale
        val shadowSize = 56f * scale

        val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.argb(65, 0, 0, 0)
        }

        canvas.drawCircle(
            centerX,
            centerY + 1.5f * scale,
            shadowSize / 2f,
            shadowPaint,
        )

        val bumperBitmap = loadBumperBitmap(context)

        if (bumperBitmap != null && !bumperBitmap.isRecycled) {
            val half = bumperSize / 2f

            canvas.drawBitmap(
                bumperBitmap,
                null,
                RectF(
                    centerX - half,
                    centerY - half,
                    centerX + half,
                    centerY + half,
                ),
                imagePaint,
            )

            return
        }

        val fallbackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.rgb(195, 72, 76)
        }

        canvas.drawCircle(
            centerX,
            centerY,
            bumperSize / 2f,
            fallbackPaint,
        )
    }

    private fun drawBoardPucks(
        canvas: Canvas,
        playableRect: RectF,
        pucks: List<ShufflePreviewPuck>,
        player1Bitmap: Bitmap?,
        player2Bitmap: Bitmap?,
        imagePaint: Paint,
    ) {
        val scaleX = playableRect.width() / (PLAYABLE_HALF_WIDTH * 2f)
        val scaleY = playableRect.height() / (PLAYABLE_HALF_HEIGHT * 2f)
        val worldScale = min(scaleX, scaleY)
        val puckSize = PUCK_DIAMETER_WORLD * worldScale

        pucks.forEach { puck ->
            val centerX = playableRect.centerX() + puck.x * scaleX
            val centerY = playableRect.centerY() - puck.y * scaleY

            drawPuck(
                canvas = canvas,
                centerX = centerX,
                centerY = centerY,
                size = puckSize,
                player = puck.player,
                rotation = puck.rotation,
                bitmap = if (puck.player == 1) {
                    player1Bitmap
                } else {
                    player2Bitmap
                },
                imagePaint = imagePaint,
            )
        }
    }

    private fun drawReserveIndicators(
        canvas: Canvas,
        outputWidth: Int,
        boardRect: RectF,
        playableRect: RectF,
        player1Remaining: Int,
        player2Remaining: Int,
        player1Bitmap: Bitmap?,
        player2Bitmap: Bitmap?,
        imagePaint: Paint,
    ) {
        val boardPuckSize = PUCK_DIAMETER_WORLD * min(
            playableRect.width() / (PLAYABLE_HALF_WIDTH * 2f),
            playableRect.height() / (PLAYABLE_HALF_HEIGHT * 2f),
        )

        val leftGutter = boardRect.left
        val rightGutter = outputWidth.toFloat() - boardRect.right
        val availableGutter = min(leftGutter, rightGutter)

        val indicatorSize = min(
            boardPuckSize * INDICATOR_SIZE_RATIO,
            availableGutter * 0.62f,
        ).coerceAtLeast(4f)

        val boardGap = indicatorSize * INDICATOR_BOARD_GAP_RATIO

        val player1CenterX = boardRect.left - boardGap - indicatorSize / 2f
        val player2CenterX = boardRect.right + boardGap + indicatorSize / 2f

        drawIndicatorStack(
            canvas = canvas,
            centerX = player1CenterX,
            centerY = boardRect.centerY(),
            count = player1Remaining,
            player = 1,
            size = indicatorSize,
            bitmap = player1Bitmap,
            imagePaint = imagePaint,
        )

        drawIndicatorStack(
            canvas = canvas,
            centerX = player2CenterX,
            centerY = boardRect.centerY(),
            count = player2Remaining,
            player = 2,
            size = indicatorSize,
            bitmap = player2Bitmap,
            imagePaint = imagePaint,
        )
    }

    private fun drawIndicatorStack(
        canvas: Canvas,
        centerX: Float,
        centerY: Float,
        count: Int,
        player: Int,
        size: Float,
        bitmap: Bitmap?,
        imagePaint: Paint,
    ) {
        if (count <= 0) {
            return
        }

        val spacing = size * INDICATOR_SPACING_RATIO
        val firstCenterY = centerY - (count - 1) * spacing / 2f

        repeat(count) { index ->
            drawPuck(
                canvas = canvas,
                centerX = centerX,
                centerY = firstCenterY + index * spacing,
                size = size,
                player = player,
                rotation = 0f,
                bitmap = bitmap,
                imagePaint = imagePaint,
            )
        }
    }

    private fun drawPuck(
        canvas: Canvas,
        centerX: Float,
        centerY: Float,
        size: Float,
        player: Int,
        rotation: Float,
        bitmap: Bitmap?,
        imagePaint: Paint,
    ) {
        val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(65, 0, 0, 0)
        }

        canvas.drawCircle(
            centerX,
            centerY + size * 0.10f,
            size * 0.43f,
            shadowPaint,
        )

        if (bitmap != null) {
            val half = size / 2f

            canvas.save()
            canvas.rotate(
                Math.toDegrees(rotation.toDouble()).toFloat(),
                centerX,
                centerY,
            )

            canvas.drawBitmap(
                bitmap,
                null,
                RectF(
                    centerX - half,
                    centerY - half,
                    centerX + half,
                    centerY + half,
                ),
                imagePaint,
            )

            canvas.restore()
            return
        }

        val fallbackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (player == 1) {
                Color.rgb(255, 215, 0)
            } else {
                Color.rgb(35, 35, 35)
            }
        }

        canvas.drawCircle(
            centerX,
            centerY,
            size / 2f,
            fallbackPaint,
        )
    }

    private fun isReadyRowPuck(
        puck: ShufflePreviewPuck,
    ): Boolean {
        return when (puck.player) {
            1 -> puck.y <= -READY_AREA_Y
            2 -> puck.y >= READY_AREA_Y
            else -> false
        }
    }

    private fun isPuckOnActualBoard(
        puck: ShufflePreviewPuck,
    ): Boolean {
        if (isReadyRowPuck(puck)) {
            return false
        }

        return abs(puck.x) <= PLAYABLE_HALF_WIDTH && abs(puck.y) <= PLAYABLE_HALF_HEIGHT
    }

    private fun calculateBoardRect(
        outputWidth: Int,
        outputHeight: Int,
    ): RectF {
        val maxWidth = outputWidth * BOARD_MAX_WIDTH_RATIO
        val maxHeight = outputHeight * BOARD_MAX_HEIGHT_RATIO
        val boardAspectRatio = BOARD_WORLD_WIDTH / BOARD_WORLD_HEIGHT

        var drawWidth = maxWidth
        var drawHeight = drawWidth / boardAspectRatio

        if (drawHeight > maxHeight) {
            drawHeight = maxHeight
            drawWidth = drawHeight * boardAspectRatio
        }

        val left = (outputWidth - drawWidth) / 2f
        val top = (outputHeight - drawHeight) / 2f

        return RectF(
            left,
            top,
            left + drawWidth,
            top + drawHeight,
        )
    }

    private fun expectedMapCountForMode(
        mode: Int,
    ): Int {
        return when (mode) {
            1 -> 12
            2 -> 16
            3 -> 21
            else -> 12
        }
    }

    private fun defaultMapScoresForMode(
        mode: Int,
    ): List<Int> {
        return when (mode) {
            1 -> DEFAULT_MAP_SCORES_MODE_1
            2 -> DEFAULT_MAP_SCORES_MODE_2
            3 -> DEFAULT_MAP_SCORES_MODE_3
            else -> DEFAULT_MAP_SCORES_MODE_1
        }
    }

    private fun playableBoardRect(
        boardRect: RectF,
    ): RectF {
        val inset = BOARD_INSET_WORLD * boardScale(boardRect)

        return RectF(
            boardRect.left + inset,
            boardRect.top + inset,
            boardRect.right - inset,
            boardRect.bottom - inset,
        )
    }

    private fun boardScale(
        boardRect: RectF,
    ): Float {
        return boardRect.width() / BOARD_WORLD_WIDTH
    }

    private fun boardX(
        worldX: Float,
        boardRect: RectF,
    ): Float {
        return boardRect.centerX() + worldX * boardScale(boardRect)
    }

    private fun boardY(
        worldY: Float,
        boardRect: RectF,
    ): Float {
        return boardRect.centerY() - worldY * boardScale(boardRect)
    }

    private fun loadBoardBitmap(
        context: Context,
        mapMode: Int,
    ): Bitmap? {
        val resourceId = boardDrawableForMap(mapMode)

        boardBitmapCache[resourceId]?.let { cached ->
            if (!cached.isRecycled) {
                return cached
            }
        }

        val decoded = BitmapFactory.decodeResource(
            context.resources,
            resourceId,
        ) ?: return null

        boardBitmapCache[resourceId] = decoded
        return decoded
    }

    private fun loadBumperBitmap(
        context: Context,
    ): Bitmap? {
        if (bumperBitmapLoaded) {
            return bumperBitmapCache
        }

        val bitmap = try {
            context.assets.open("shuffle/bumper.png").use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } catch (_: Exception) {
            null
        }

        bumperBitmapCache = bitmap
        bumperBitmapLoaded = true
        return bitmap
    }

    private fun loadPuckBitmap(
        context: Context,
        player: Int,
    ): Bitmap? {
        if (puckBitmapCache.containsKey(player)) {
            return puckBitmapCache[player]
        }

        val assetPath = if (player == 1) {
            "shuffle/puck1.png"
        } else {
            "shuffle/puck2.png"
        }

        val bitmap = try {
            context.assets.open(assetPath).use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } catch (_: Exception) {
            null
        }

        puckBitmapCache[player] = bitmap
        return bitmap
    }

    @DrawableRes
    private fun boardDrawableForMap(
        mapMode: Int,
    ): Int {
        return when (mapMode) {
            2 -> R.drawable.shuffle_map_2
            3 -> R.drawable.shuffle_map_3
            else -> R.drawable.shuffle_map_1
        }
    }

    private val BOARD_WALL_COLOR = Color.rgb(
        238,
        242,
        245,
    )

    private val DEFAULT_MAP_SCORES_MODE_1 = listOf(
        5, 10, 5, 2, 3, 10, 6, 3, 2, 5, 3, 6,
    )

    private val DEFAULT_MAP_SCORES_MODE_2 = listOf(
        6, 5, 8, 10, 10, 8, 5, 6, 6, 5, 6, 2, 5, 2, 7, 3,
    )

    private val DEFAULT_MAP_SCORES_MODE_3 = listOf(
        3, 2, 5, 10, 7, 7, 6, 5, 6, 4, 7, 8, 6, 10, 4, 4, 4, 8, 5, 3, 5,
    )
}