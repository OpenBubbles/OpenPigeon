package com.openbubbles.openpigeon.chess

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import com.openbubbles.openpigeon.util.OpenPigeonLog
import androidx.core.graphics.createBitmap
import kotlin.math.min

object ChessPreviewRenderer {
    private const val BOARD_DIM = 8

    private const val PREVIEW_SIZE = 720
    private const val OUTPUT_SIZE = 384

    private const val BOARD_LEFT = 40f
    private const val BOARD_TOP = 40f
    private const val BOARD_SIZE = 640f
    private const val SQUARE_SIZE = BOARD_SIZE / BOARD_DIM

    private const val PIECE_FILL = 0.92f

    private val boardRect = RectF(
        BOARD_LEFT,
        BOARD_TOP,
        BOARD_LEFT + BOARD_SIZE,
        BOARD_TOP + BOARD_SIZE
    )

    private const val DEFAULT_BOARD =
        "12,13,14,15,16,14,13,12," +
                "11,11,11,11,11,11,11,11," +
                "0,0,0,0,0,0,0,0," +
                "0,0,0,0,0,0,0,0," +
                "0,0,0,0,0,0,0,0," +
                "0,0,0,0,0,0,0,0," +
                "21,21,21,21,21,21,21,21," +
                "22,23,24,25,26,24,23,22"

    private data class ChessMove(
        val fromFile: Int,
        val fromRank: Int,
        val toFile: Int,
        val toRank: Int
    )

    private class PreviewState(
        val board: IntArray,
        val move: ChessMove?
    )

    private val cacheLock = Any()
    private var attemptedAssetLoad = false

    private val pieceBitmaps = mutableMapOf<String, Bitmap>()

    private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
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
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }

    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
    }

    private val downsamplePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    fun render(
        context: Context,
        replay: String?,
        flipBoard: Boolean
    ): Bitmap {
        return render(
            context = context,
            replay = replay,
            flipBoard = flipBoard,
            targetWidthPx = OUTPUT_SIZE,
            targetHeightPx = OUTPUT_SIZE
        )
    }

    fun render(
        context: Context,
        replay: String?,
        flipBoard: Boolean,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap {
        ensureAssetCache(context)

        val state = parseReplay(replay)

        val logicalBitmap = createBitmap(
            PREVIEW_SIZE,
            PREVIEW_SIZE,
            Bitmap.Config.ARGB_8888
        )

        val logicalCanvas = Canvas(logicalBitmap)

        logicalCanvas.drawColor(Color.rgb(148, 121, 114))

        drawBoardShadow(logicalCanvas)
        drawBoardFrame(logicalCanvas)
        drawSquares(logicalCanvas, flipBoard)
        drawLastMoveHighlight(logicalCanvas, state.move, flipBoard)
        drawPieces(logicalCanvas, state.board, flipBoard)

        return fitLogicalBitmap(
            source = logicalBitmap,
            targetWidthPx = targetWidthPx,
            targetHeightPx = targetHeightPx,
            backgroundColor = Color.rgb(148, 121, 114)
        )
    }

    private fun drawBoardShadow(canvas: Canvas) {
        fillPaint.style = Paint.Style.FILL
        fillPaint.color = Color.argb(85, 0, 0, 0)

        canvas.drawRoundRect(
            RectF(
                boardRect.left + 8f,
                boardRect.top + 12f,
                boardRect.right + 8f,
                boardRect.bottom + 12f
            ),
            18f,
            18f,
            fillPaint
        )
    }

    private fun drawBoardFrame(canvas: Canvas) {
        fillPaint.style = Paint.Style.FILL
        fillPaint.color = Color.rgb(95, 61, 36)

        canvas.drawRoundRect(
            RectF(
                boardRect.left - 14f,
                boardRect.top - 14f,
                boardRect.right + 14f,
                boardRect.bottom + 14f
            ),
            18f,
            18f,
            fillPaint
        )

        strokePaint.style = Paint.Style.STROKE
        strokePaint.strokeWidth = 4f
        strokePaint.color = Color.argb(175, 35, 20, 10)

        canvas.drawRoundRect(
            RectF(
                boardRect.left - 14f,
                boardRect.top - 14f,
                boardRect.right + 14f,
                boardRect.bottom + 14f
            ),
            18f,
            18f,
            strokePaint
        )
    }

    private fun drawSquares(
        canvas: Canvas,
        flipBoard: Boolean
    ) {
        fillPaint.style = Paint.Style.FILL

        for (rank in 0 until BOARD_DIM) {
            for (file in 0 until BOARD_DIM) {
                fillPaint.color = squareColor(file, rank)

                val rect = squareRectFor(
                    file = file,
                    rank = rank,
                    flipBoard = flipBoard
                )

                canvas.drawRect(rect, fillPaint)
            }
        }
    }

    private fun drawLastMoveHighlight(
        canvas: Canvas,
        move: ChessMove?,
        flipBoard: Boolean
    ) {
        if (move == null) return

        fillPaint.style = Paint.Style.FILL
        fillPaint.color = Color.argb(92, 65, 205, 80)

        if (isSquareInBounds(move.fromFile, move.fromRank)) {
            canvas.drawRect(
                squareRectFor(
                    file = move.fromFile,
                    rank = move.fromRank,
                    flipBoard = flipBoard
                ),
                fillPaint
            )
        }

        if (isSquareInBounds(move.toFile, move.toRank)) {
            canvas.drawRect(
                squareRectFor(
                    file = move.toFile,
                    rank = move.toRank,
                    flipBoard = flipBoard
                ),
                fillPaint
            )
        }
    }

    private fun drawPieces(
        canvas: Canvas,
        board: IntArray,
        flipBoard: Boolean
    ) {
        for (rank in 0 until BOARD_DIM) {
            for (file in 0 until BOARD_DIM) {
                val index = file + rank * BOARD_DIM
                val code = board.getOrElse(index) { 0 }

                if (code == 0) continue

                val pieceKey = pieceKeyFromCode(code) ?: continue

                val square = squareRectFor(
                    file = file,
                    rank = rank,
                    flipBoard = flipBoard
                )

                val pieceSize = SQUARE_SIZE * PIECE_FILL
                val dest = RectF(
                    square.centerX() - pieceSize / 2f,
                    square.centerY() - pieceSize / 2f,
                    square.centerX() + pieceSize / 2f,
                    square.centerY() + pieceSize / 2f
                )

                drawRawPiece(
                    canvas = canvas,
                    dest = dest,
                    pieceKey = pieceKey
                )
            }
        }
    }

    private fun squareRectFor(
        file: Int,
        rank: Int,
        flipBoard: Boolean
    ): RectF {
        val drawCol = if (flipBoard) {
            BOARD_DIM - 1 - file
        } else {
            file
        }

        val drawRow = if (flipBoard) {
            rank
        } else {
            BOARD_DIM - 1 - rank
        }

        val left = BOARD_LEFT + drawCol * SQUARE_SIZE
        val top = BOARD_TOP + drawRow * SQUARE_SIZE

        return RectF(
            left,
            top,
            left + SQUARE_SIZE,
            top + SQUARE_SIZE
        )
    }

    private fun squareColor(
        file: Int,
        rank: Int
    ): Int {
        return if ((file + rank) % 2 == 0) {
            // a1 is dark.
            Color.rgb(181, 136, 99)
        } else {
            Color.rgb(240, 217, 181)
        }
    }

    private fun parseReplay(replay: String?): PreviewState {
        if (replay.isNullOrBlank()) {
            return PreviewState(
                board = parseBoard(DEFAULT_BOARD),
                move = null
            )
        }

        var latestBoard: String? = null
        var move: ChessMove? = null

        for (rawPart in replay.split("|")) {
            val part = rawPart.trim()

            when {
                part.startsWith("board:") -> {
                    latestBoard = part.removePrefix("board:")
                }

                part.startsWith("move:") -> {
                    move = parseMove(part.removePrefix("move:"))
                }
            }
        }

        return PreviewState(
            board = parseBoard(latestBoard ?: DEFAULT_BOARD),
            move = move
        )
    }

    private fun parseBoard(boardString: String): IntArray {
        val values = boardString
            .split(",")
            .mapNotNull { it.trim().toIntOrNull() }

        if (values.size < 64) {
            OpenPigeonLog.w(
                "ChessPreview",
                "Ignoring malformed chess board. Expected 64 values, got ${values.size}"
            )

            return DEFAULT_BOARD
                .split(",")
                .map { it.trim().toInt() }
                .toIntArray()
        }

        return values
            .take(64)
            .toIntArray()
    }

    private fun parseMove(moveString: String): ChessMove? {
        val values = moveString
            .split(",")
            .mapNotNull { it.trim().toIntOrNull() }

        if (values.size < 4) {
            OpenPigeonLog.w(
                "ChessPreview",
                "Ignoring malformed chess move=$moveString"
            )
            return null
        }

        val fromFile = values[0]
        val fromRank = values[1]
        val toFile = values[2]
        val toRank = values[3]

        if (
            !isSquareInBounds(fromFile, fromRank) ||
            !isSquareInBounds(toFile, toRank)
        ) {
            OpenPigeonLog.w(
                "ChessPreview",
                "Ignoring out-of-bounds chess move=$moveString"
            )
            return null
        }

        return ChessMove(
            fromFile = fromFile,
            fromRank = fromRank,
            toFile = toFile,
            toRank = toRank
        )
    }

    private fun isSquareInBounds(
        file: Int,
        rank: Int
    ): Boolean {
        return file in 0 until BOARD_DIM &&
                rank in 0 until BOARD_DIM
    }

    private fun pieceKeyFromCode(code: Int): String? {
        return when (code) {
            11 -> "wP"
            12 -> "wR"
            13 -> "wN"
            14 -> "wB"
            15 -> "wQ"
            16 -> "wK"

            21 -> "bP"
            22 -> "bR"
            23 -> "bN"
            24 -> "bB"
            25 -> "bQ"
            26 -> "bK"

            else -> null
        }
    }

    private fun fitLogicalBitmap(
        source: Bitmap,
        targetWidthPx: Int,
        targetHeightPx: Int,
        backgroundColor: Int
    ): Bitmap {
        val outputWidth = targetWidthPx.coerceAtLeast(1)
        val outputHeight = targetHeightPx.coerceAtLeast(1)

        val output = createBitmap(
            outputWidth,
            outputHeight,
            Bitmap.Config.RGB_565
        )

        val canvas = Canvas(output)
        canvas.drawColor(backgroundColor)

        val scale = minOf(
            outputWidth.toFloat() / source.width.toFloat(),
            outputHeight.toFloat() / source.height.toFloat()
        )

        val drawWidth = source.width * scale
        val drawHeight = source.height * scale

        val left = (outputWidth - drawWidth) / 2f
        val top = (outputHeight - drawHeight) / 2f

        canvas.drawBitmap(
            source,
            null,
            RectF(
                left,
                top,
                left + drawWidth,
                top + drawHeight
            ),
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

            val keys = listOf(
                "wP", "wR", "wN", "wB", "wQ", "wK",
                "bP", "bR", "bN", "bB", "bQ", "bK"
            )

            for (key in keys) {
                val bitmap = loadAssetBitmap(
                    context,
                    "chess/pieces/chess_$key.png",
                    "assets/chess/pieces/chess_$key.png",
                    "chess_$key.png"
                )

                if (bitmap != null) {
                    val trimmed = trimTransparentPadding(bitmap)
                    pieceBitmaps[key] = trimmed

                    OpenPigeonLog.i(
                        "ChessPreview",
                        "Cached raw chess piece $key src=${bitmap.width}x${bitmap.height} trimmed=${trimmed.width}x${trimmed.height}"
                    )
                }
            }

            OpenPigeonLog.i(
                "ChessPreview",
                "Raw chess pieces loaded=${pieceBitmaps.size}"
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
                            "ChessPreview",
                            "Loaded Chess preview asset from $path"
                        )
                        return bitmap
                    }
                }
            } catch (_: Exception) {
                // Try the next path.
            }
        }

        OpenPigeonLog.w(
            "ChessPreview",
            "Could not load Chess preview asset from paths=${paths.joinToString()}"
        )

        return null
    }

    private fun drawRawPiece(
        canvas: Canvas,
        dest: RectF,
        pieceKey: String
    ) {
        val bitmap = pieceBitmaps[pieceKey]

        if (bitmap != null) {
            canvas.drawBitmap(bitmap, null, dest, imagePaint)
        } else {
            drawFallbackPiece(
                canvas = canvas,
                dest = dest,
                pieceKey = pieceKey
            )
        }
    }

    private fun drawFallbackPiece(
        canvas: Canvas,
        dest: RectF,
        pieceKey: String
    ) {
        val isWhitePiece = pieceKey.startsWith("w")
        val pieceLetter = pieceKey.lastOrNull()?.toString().orEmpty()

        fillPaint.style = Paint.Style.FILL
        fillPaint.color = Color.argb(80, 0, 0, 0)

        canvas.drawOval(
            RectF(
                dest.left + 3f,
                dest.top + 4f,
                dest.right + 3f,
                dest.bottom + 4f
            ),
            fillPaint
        )

        fillPaint.color = if (isWhitePiece) {
            Color.rgb(238, 238, 232)
        } else {
            Color.rgb(28, 28, 28)
        }

        canvas.drawOval(dest, fillPaint)

        strokePaint.style = Paint.Style.STROKE
        strokePaint.strokeWidth = 2.5f
        strokePaint.color = if (isWhitePiece) {
            Color.rgb(185, 185, 178)
        } else {
            Color.rgb(95, 95, 95)
        }

        canvas.drawOval(dest, strokePaint)

        textPaint.textSize = dest.height() * 0.42f
        textPaint.color = if (isWhitePiece) {
            Color.rgb(35, 35, 35)
        } else {
            Color.rgb(245, 245, 245)
        }

        val baseline = dest.centerY() - (textPaint.descent() + textPaint.ascent()) / 2f

        canvas.drawText(
            pieceLetter,
            dest.centerX(),
            baseline,
            textPaint
        )
    }

    private fun trimTransparentPadding(source: Bitmap): Bitmap {
        val bitmap = if (source.config == Bitmap.Config.ARGB_8888) {
            source
        } else {
            source.copy(Bitmap.Config.ARGB_8888, false)
        }

        val width = bitmap.width
        val height = bitmap.height

        if (width <= 1 || height <= 1) {
            return bitmap
        }

        val pixels = IntArray(width * height)

        bitmap.getPixels(
            pixels,
            0,
            width,
            0,
            0,
            width,
            height
        )

        var left = width
        var top = height
        var right = -1
        var bottom = -1

        for (y in 0 until height) {
            for (x in 0 until width) {
                val alpha = Color.alpha(pixels[y * width + x])

                if (alpha > 8) {
                    if (x < left) left = x
                    if (x > right) right = x
                    if (y < top) top = y
                    if (y > bottom) bottom = y
                }
            }
        }

        if (right < left || bottom < top) {
            return bitmap
        }

        val cropWidth = right - left + 1
        val cropHeight = bottom - top + 1

        if (
            cropWidth == width &&
            cropHeight == height
        ) {
            return bitmap
        }

        val pad = min(width, height) * 0.04f
        val padInt = pad.toInt().coerceAtLeast(1)

        val paddedLeft = (left - padInt).coerceAtLeast(0)
        val paddedTop = (top - padInt).coerceAtLeast(0)
        val paddedRight = (right + padInt).coerceAtMost(width - 1)
        val paddedBottom = (bottom + padInt).coerceAtMost(height - 1)

        val outWidth = paddedRight - paddedLeft + 1
        val outHeight = paddedBottom - paddedTop + 1

        return Bitmap.createBitmap(
            bitmap,
            paddedLeft,
            paddedTop,
            outWidth,
            outHeight
        )
    }
}