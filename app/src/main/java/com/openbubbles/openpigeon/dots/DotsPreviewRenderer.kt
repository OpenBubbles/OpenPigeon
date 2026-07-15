package com.openbubbles.openpigeon.dots

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.RectF
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.math.sqrt
import androidx.core.graphics.createBitmap

object DotsPreviewRenderer {
    private const val MIN_BOARD_SIZE = 4
    private const val MAX_BOARD_SIZE = 6

    private const val PREVIEW_SIZE = 720
    private const val OUTPUT_SIZE = 320

    private const val PAPER_LEFT = 48f
    private const val PAPER_TOP = 48f
    private const val PAPER_SIZE = 624f
    private const val GRID_PADDING_PCT = 0.12f

    private val paperRect = RectF(
        PAPER_LEFT,
        PAPER_TOP,
        PAPER_LEFT + PAPER_SIZE,
        PAPER_TOP + PAPER_SIZE
    )

    private val cacheLock = Any()
    private var attemptedAssetLoad = false
    private var cachedPaperTexture: Bitmap? = null

    private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val downsamplePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private data class PreviewLine(
        val owner: Int,
        val x1: Int,
        val y1: Int,
        val x2: Int,
        val y2: Int
    )

    private data class PreviewSquare(
        val owner: Int,
        val x: Int,
        val y: Int
    )

    private data class PreviewState(
        val lines: MutableList<PreviewLine> = mutableListOf(),
        val squares: MutableList<PreviewSquare> = mutableListOf()
    )

    fun render(
        context: Context,
        replay: String?,
        boardSize: Int
    ): Bitmap {
        return render(
            context = context,
            replay = replay,
            boardSize = boardSize,
            targetWidthPx = OUTPUT_SIZE,
            targetHeightPx = OUTPUT_SIZE
        )
    }

    fun render(
        context: Context,
        replay: String?,
        boardSize: Int,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap {
        ensureAssetCache(context)

        val safeBoardSize = boardSize.coerceIn(MIN_BOARD_SIZE, MAX_BOARD_SIZE)
        val state = parseReplay(replay, safeBoardSize)

        val logicalBitmap = createBitmap(PREVIEW_SIZE, PREVIEW_SIZE)

        val logicalCanvas = Canvas(logicalBitmap)

        logicalCanvas.drawColor(Color.rgb(148, 121, 114))

        drawPaper(logicalCanvas)
        drawSquares(logicalCanvas, state.squares, safeBoardSize)
        drawLines(logicalCanvas, state.lines, safeBoardSize)
        drawDots(logicalCanvas, safeBoardSize)

        return fitLogicalBitmap(
            source = logicalBitmap,
            targetWidthPx = targetWidthPx,
            targetHeightPx = targetHeightPx,
            backgroundColor = Color.rgb(148, 121, 114)
        )
    }

    private fun drawPaper(canvas: Canvas) {
        fillPaint.style = Paint.Style.FILL
        fillPaint.color = Color.argb(80, 0, 0, 0)

        canvas.drawRoundRect(
            RectF(
                paperRect.left + 6f,
                paperRect.top + 10f,
                paperRect.right + 6f,
                paperRect.bottom + 10f
            ),
            14f,
            14f,
            fillPaint
        )

        val paper = cachedPaperTexture

        if (paper != null) {
            canvas.drawBitmap(paper, null, paperRect, imagePaint)
        } else {
            fillPaint.color = Color.rgb(244, 241, 235)
            canvas.drawRoundRect(paperRect, 10f, 10f, fillPaint)
        }
    }

    private fun drawSquares(
        canvas: Canvas,
        squares: List<PreviewSquare>,
        boardSize: Int
    ) {
        val grid = gridRect()
        val step = grid.width() / (boardSize - 1).toFloat()
        val lineWidth = (step * 0.105f).coerceIn(7f, 12f)
        val shrink = step * 0.22f

        strokePaint.style = Paint.Style.STROKE
        strokePaint.strokeWidth = lineWidth * 0.75f

        for (square in squares) {
            if (!isValidSquare(square, boardSize)) continue

            strokePaint.color = playerColor(square.owner, alpha = 205)

            val topLeft = dotPosition(square.x, square.y + 1, boardSize)
            val topRight = dotPosition(square.x + 1, square.y + 1, boardSize)
            val bottomLeft = dotPosition(square.x, square.y, boardSize)
            val bottomRight = dotPosition(square.x + 1, square.y, boardSize)

            val center = PointF(
                (topLeft.x + bottomRight.x) * 0.5f,
                (topLeft.y + bottomRight.y) * 0.5f
            )

            val a0 = shrinkToward(center, topLeft, shrink)
            val a1 = shrinkToward(center, bottomRight, shrink)
            val b0 = shrinkToward(center, topRight, shrink)
            val b1 = shrinkToward(center, bottomLeft, shrink)

            canvas.drawLine(a0.x, a0.y, a1.x, a1.y, strokePaint)
            canvas.drawLine(b0.x, b0.y, b1.x, b1.y, strokePaint)
        }
    }

    private fun drawLines(
        canvas: Canvas,
        lines: List<PreviewLine>,
        boardSize: Int
    ) {
        val grid = gridRect()
        val step = grid.width() / (boardSize - 1).toFloat()
        val dotRadius = dotRadiusFor(boardSize)
        val lineWidth = (step * 0.13f).coerceIn(8f, 14f)

        strokePaint.style = Paint.Style.STROKE
        strokePaint.strokeWidth = lineWidth

        for (line in lines) {
            if (!isValidLine(line, boardSize)) continue

            val p0 = dotPosition(line.x1, line.y1, boardSize)
            val p1 = dotPosition(line.x2, line.y2, boardSize)

            val dx = p1.x - p0.x
            val dy = p1.y - p0.y
            val len = sqrt(dx * dx + dy * dy)

            if (len <= 0.0001f) continue

            val inset = dotRadius * 0.9f
            val nx = dx / len
            val ny = dy / len

            strokePaint.color = playerColor(line.owner, alpha = 215)

            canvas.drawLine(
                p0.x + nx * inset,
                p0.y + ny * inset,
                p1.x - nx * inset,
                p1.y - ny * inset,
                strokePaint
            )
        }
    }

    private fun drawDots(
        canvas: Canvas,
        boardSize: Int
    ) {
        fillPaint.style = Paint.Style.FILL
        fillPaint.color = Color.rgb(24, 24, 24)

        val radius = dotRadiusFor(boardSize)

        for (y in 0 until boardSize) {
            for (x in 0 until boardSize) {
                val p = dotPosition(x, y, boardSize)
                canvas.drawCircle(p.x, p.y, radius, fillPaint)
            }
        }
    }

    private fun dotRadiusFor(boardSize: Int): Float {
        return when (boardSize.coerceIn(MIN_BOARD_SIZE, MAX_BOARD_SIZE)) {
            4 -> 11.5f
            5 -> 10.5f
            else -> 9.5f
        }
    }

    private fun gridRect(): RectF {
        val pad = PAPER_SIZE * GRID_PADDING_PCT

        return RectF(
            paperRect.left + pad,
            paperRect.top + pad,
            paperRect.right - pad,
            paperRect.bottom - pad
        )
    }

    private fun dotPosition(
        x: Int,
        yBottomLeft: Int,
        boardSize: Int
    ): PointF {
        val grid = gridRect()
        val step = grid.width() / (boardSize - 1).toFloat()

        return PointF(
            grid.left + x * step,
            grid.bottom - yBottomLeft * step
        )
    }

    private fun shrinkToward(
        center: PointF,
        p: PointF,
        shrink: Float
    ): PointF {
        val vx = p.x - center.x
        val vy = p.y - center.y
        val len = sqrt(vx * vx + vy * vy)

        if (len <= 0.0001f) return p

        val newLen = (len - shrink).coerceAtLeast(0f)
        val scale = newLen / len

        return PointF(
            center.x + vx * scale,
            center.y + vy * scale
        )
    }

    private fun playerColor(
        owner: Int,
        alpha: Int
    ): Int {
        return if (owner == 1) {
            // Matches Godot p_colors[0] reasonably closely.
            Color.argb(alpha, 51, 140, 207)
        } else {
            // Uses the red marker side for player 2.
            Color.argb(alpha, 235, 33, 86)
        }
    }

    private fun parseReplay(
        replay: String?,
        boardSize: Int
    ): PreviewState {
        val state = PreviewState()

        if (replay.isNullOrBlank()) {
            return state
        }

        for (rawPart in replay.split("|")) {
            val part = rawPart.trim()

            when {
                part.startsWith("board:") -> {
                    state.lines.clear()
                    state.squares.clear()
                    parseBoardStringInto(
                        board = part.removePrefix("board:"),
                        state = state,
                        boardSize = boardSize
                    )
                }

                part.startsWith("line:") -> {
                    parseLine(part.removePrefix("line:"), boardSize)?.let {
                        addLine(state, it)
                    }
                }

                part.startsWith("square:") -> {
                    parseSquare(part.removePrefix("square:"), boardSize)?.let {
                        addSquare(state, it)
                    }
                }
            }
        }

        return state
    }

    private fun parseBoardStringInto(
        board: String,
        state: PreviewState,
        boardSize: Int
    ) {
        if (board.isBlank()) return

        for (rawChunk in board.split("#")) {
            val chunk = rawChunk.trim()
            if (chunk.isEmpty()) continue

            val values = csvToInts(chunk)

            when (values.size) {
                5 -> {
                    val line = PreviewLine(
                        owner = values[0],
                        x1 = values[1],
                        y1 = values[2],
                        x2 = values[3],
                        y2 = values[4]
                    )

                    if (isValidLine(line, boardSize)) {
                        addLine(state, line)
                    }
                }

                3 -> {
                    val square = PreviewSquare(
                        owner = values[0],
                        x = values[1],
                        y = values[2]
                    )

                    if (isValidSquare(square, boardSize)) {
                        addSquare(state, square)
                    }
                }
            }
        }
    }

    private fun parseLine(
        value: String,
        boardSize: Int
    ): PreviewLine? {
        val nums = csvToInts(value)

        if (nums.size < 5) {
            OpenPigeonLog.w(
                "DotsPreview",
                "Ignoring malformed line chunk=$value"
            )
            return null
        }

        val line = PreviewLine(
            owner = nums[0],
            x1 = nums[1],
            y1 = nums[2],
            x2 = nums[3],
            y2 = nums[4]
        )

        return if (isValidLine(line, boardSize)) {
            line
        } else {
            OpenPigeonLog.w(
                "DotsPreview",
                "Ignoring out-of-bounds line=$value size=$boardSize"
            )
            null
        }
    }

    private fun parseSquare(
        value: String,
        boardSize: Int
    ): PreviewSquare? {
        val nums = csvToInts(value)

        if (nums.size < 3) {
            OpenPigeonLog.w(
                "DotsPreview",
                "Ignoring malformed square chunk=$value"
            )
            return null
        }

        val square = PreviewSquare(
            owner = nums[0],
            x = nums[1],
            y = nums[2]
        )

        return if (isValidSquare(square, boardSize)) {
            square
        } else {
            OpenPigeonLog.w(
                "DotsPreview",
                "Ignoring out-of-bounds square=$value size=$boardSize"
            )
            null
        }
    }

    private fun csvToInts(value: String): List<Int> {
        return value
            .split(",")
            .mapNotNull { it.trim().toIntOrNull() }
    }

    private fun addLine(
        state: PreviewState,
        line: PreviewLine
    ) {
        val exists = state.lines.any {
            it.owner == line.owner &&
                    it.x1 == line.x1 &&
                    it.y1 == line.y1 &&
                    it.x2 == line.x2 &&
                    it.y2 == line.y2
        }

        if (!exists) {
            state.lines.add(line)
        }
    }

    private fun addSquare(
        state: PreviewState,
        square: PreviewSquare
    ) {
        val exists = state.squares.any {
            it.owner == square.owner &&
                    it.x == square.x &&
                    it.y == square.y
        }

        if (!exists) {
            state.squares.add(square)
        }
    }

    private fun isValidLine(
        line: PreviewLine,
        boardSize: Int
    ): Boolean {
        if (line.owner != 1 && line.owner != 2) return false

        if (
            line.x1 !in 0 until boardSize ||
            line.y1 !in 0 until boardSize ||
            line.x2 !in 0 until boardSize ||
            line.y2 !in 0 until boardSize
        ) {
            return false
        }

        val dx = kotlin.math.abs(line.x2 - line.x1)
        val dy = kotlin.math.abs(line.y2 - line.y1)

        return dx + dy == 1
    }

    private fun isValidSquare(
        square: PreviewSquare,
        boardSize: Int
    ): Boolean {
        if (square.owner != 1 && square.owner != 2) return false

        return square.x in 0 until boardSize - 1 &&
                square.y in 0 until boardSize - 1
    }

    private fun fitLogicalBitmap(
        source: Bitmap,
        targetWidthPx: Int,
        targetHeightPx: Int,
        backgroundColor: Int
    ): Bitmap {
        val outputWidth = targetWidthPx.coerceAtLeast(1)
        val outputHeight = targetHeightPx.coerceAtLeast(1)

        val output = createBitmap(outputWidth, outputHeight, Bitmap.Config.RGB_565)

        val canvas = Canvas(output)
        canvas.drawColor(backgroundColor)

        val scale = minOf(
            outputWidth.toFloat() / source.width,
            outputHeight.toFloat() / source.height
        )

        val drawWidth = source.width * scale
        val drawHeight = source.height * scale
        val left = (outputWidth - drawWidth) / 2f
        val top = (outputHeight - drawHeight) / 2f

        canvas.drawBitmap(
            source,
            null,
            RectF(left, top, left + drawWidth, top + drawHeight),
            downsamplePaint
        )

        return output
    }

    private fun ensureAssetCache(context: Context) {
        if (attemptedAssetLoad) {
            return
        }

        synchronized(cacheLock) {
            if (attemptedAssetLoad) {
                return
            }

            cachedPaperTexture = loadAssetBitmap(
                context,
                "dots/paper_tex.png",
                "paper_tex.png"
            )

            attemptedAssetLoad = true
        }
    }

    private fun loadAssetBitmap(
        context: Context,
        vararg paths: String
    ): Bitmap? {
        for (path in paths) {
            try {
                context.assets.open(path).use { stream ->
                    val bitmap = BitmapFactory.decodeStream(stream)

                    if (bitmap != null) {
                        OpenPigeonLog.i(
                            "DotsPreview",
                            "Loaded Dots preview asset from $path"
                        )
                        return bitmap
                    }
                }
            } catch (_: Exception) {
                // Try the next path.
            }
        }

        OpenPigeonLog.w(
            "DotsPreview",
            "Could not load Dots preview asset from paths=${paths.joinToString()}"
        )

        return null
    }
}