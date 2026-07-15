package com.openbubbles.openpigeon.fill

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import kotlin.math.floor
import android.graphics.RectF
import androidx.core.graphics.createBitmap

object FillerPreviewRenderer {
    private const val BOARD_WIDTH = 8
    private const val BOARD_HEIGHT = 7
    private const val NUM_PIECES = 6
    private const val POLISH_ITERATIONS = 15

    private const val DRAND48_A = 0x5DEECE66DL
    private const val DRAND48_C = 0xBL
    private const val DRAND48_MASK = (1L shl 48) - 1L
    private const val DRAND48_DENOM = 281474976710656.0

    private const val LOGICAL_CELL = 36
    private const val LOGICAL_PADDING = 18

    private val outputPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }

    private val colors = intArrayOf(
        Color.rgb(235, 33, 110),
        Color.rgb(115, 191, 74),
        Color.rgb(245, 217, 33),
        Color.rgb(51, 143, 205),
        Color.rgb(91, 66, 137),
        Color.rgb(64, 64, 64)
    )

    private var state = 0L

    fun render(
        seed: Int,
        player: Int = 1
    ): Bitmap {
        return renderBoardArray(
            board = generateBoard(seed),
            player = player
        )
    }

    fun render(
        seed: Int,
        player: Int = 1,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap {
        return renderBoardArray(
            board = generateBoard(seed),
            player = player,
            targetWidthPx = targetWidthPx,
            targetHeightPx = targetHeightPx
        )
    }

    fun renderBoard(
        flatBoard: IntArray,
        player: Int = 1,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap {
        return renderBoardArray(
            board = boardFromFlatArray(flatBoard),
            player = player,
            targetWidthPx = targetWidthPx,
            targetHeightPx = targetHeightPx
        )
    }

    private fun boardFromFlatArray(
        flatBoard: IntArray
    ): Array<IntArray> {
        return Array(BOARD_HEIGHT) { y ->
            IntArray(BOARD_WIDTH) { x ->
                flatBoard
                    .getOrElse(y * BOARD_WIDTH + x) { 0 }
                    .coerceIn(0, colors.lastIndex)
            }
        }
    }

    private fun renderBoardArray(
        board: Array<IntArray>,
        player: Int
    ): Bitmap {
        val width =
            BOARD_WIDTH * LOGICAL_CELL +
                    LOGICAL_PADDING * 2

        val height =
            BOARD_HEIGHT * LOGICAL_CELL +
                    LOGICAL_PADDING * 2

        val bitmap = createBitmap(
            width,
            height,
            Bitmap.Config.ARGB_8888
        )

        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        canvas.drawColor(Color.rgb(232, 232, 232))

        paint.color = Color.argb(70, 0, 0, 0)

        canvas.drawRect(
            (LOGICAL_PADDING + 4).toFloat(),
            (LOGICAL_PADDING + 6).toFloat(),
            (
                    LOGICAL_PADDING +
                            BOARD_WIDTH * LOGICAL_CELL +
                            4
                    ).toFloat(),
            (
                    LOGICAL_PADDING +
                            BOARD_HEIGHT * LOGICAL_CELL +
                            6
                    ).toFloat(),
            paint
        )

        for (y in 0 until BOARD_HEIGHT) {
            for (x in 0 until BOARD_WIDTH) {
                val drawX =
                    if (player == 2) {
                        BOARD_WIDTH - 1 - x
                    } else {
                        x
                    }

                val drawY =
                    if (player == 2) {
                        y
                    } else {
                        BOARD_HEIGHT - 1 - y
                    }

                paint.color = colors[
                    board[y][x].coerceIn(0, colors.lastIndex)
                ]

                canvas.drawRect(
                    (
                            LOGICAL_PADDING +
                                    drawX * LOGICAL_CELL
                            ).toFloat(),
                    (
                            LOGICAL_PADDING +
                                    drawY * LOGICAL_CELL
                            ).toFloat(),
                    (
                            LOGICAL_PADDING +
                                    (drawX + 1) * LOGICAL_CELL
                            ).toFloat(),
                    (
                            LOGICAL_PADDING +
                                    (drawY + 1) * LOGICAL_CELL
                            ).toFloat(),
                    paint
                )
            }
        }

        return bitmap
    }

    private fun renderBoardArray(
        board: Array<IntArray>,
        player: Int,
        targetWidthPx: Int,
        targetHeightPx: Int
    ): Bitmap {
        val logical = renderBoardArray(
            board = board,
            player = player
        )

        val outputWidth = targetWidthPx.coerceAtLeast(1)
        val outputHeight = targetHeightPx.coerceAtLeast(1)

        val output = createBitmap(
            outputWidth,
            outputHeight,
            Bitmap.Config.ARGB_8888
        )

        val canvas = Canvas(output)
        canvas.drawColor(Color.rgb(232, 232, 232))

        val scale = minOf(
            outputWidth.toFloat() / logical.width,
            outputHeight.toFloat() / logical.height
        )

        val drawWidth = logical.width * scale
        val drawHeight = logical.height * scale
        val left = (outputWidth - drawWidth) / 2f
        val top = (outputHeight - drawHeight) / 2f

        canvas.drawBitmap(
            logical,
            null,
            RectF(
                left,
                top,
                left + drawWidth,
                top + drawHeight
            ),
            outputPaint
        )

        return output
    }

    private fun srand48(seed: Int) {
        val s32 = seed.toLong() and 0xFFFFFFFFL
        state = ((s32 shl 16) or 0x330EL) and DRAND48_MASK
    }

    private fun drand48(): Double {
        state = (DRAND48_A * state + DRAND48_C) and DRAND48_MASK
        return state.toDouble() / DRAND48_DENOM
    }

    private fun randPiece(): Int {
        return floor(drand48() * NUM_PIECES.toDouble()).toInt()
    }

    private fun generateBoard(seed: Int): Array<IntArray> {
        srand48(seed)

        val board = Array(BOARD_HEIGHT) { IntArray(BOARD_WIDTH) }
        val protected = Array(BOARD_HEIGHT) { BooleanArray(BOARD_WIDTH) }

        for (y in 0 until BOARD_HEIGHT) {
            for (x in 0 until BOARD_WIDTH) {
                board[y][x] = randPiece()
            }
        }

        protected[0][0] = true
        protected[1][0] = true
        protected[0][1] = true
        protected[BOARD_HEIGHT - 1][BOARD_WIDTH - 1] = true
        protected[BOARD_HEIGHT - 1][BOARD_WIDTH - 2] = true
        protected[BOARD_HEIGHT - 2][BOARD_WIDTH - 1] = true

        do {
            board[0][0] = randPiece()
            board[0][1] = randPiece()
            board[1][0] = randPiece()
        } while (
            board[0][0] == board[0][1] ||
            board[0][0] == board[1][0] ||
            board[0][1] == board[1][0]
        )

        do {
            board[BOARD_HEIGHT - 1][BOARD_WIDTH - 1] = randPiece()
            board[BOARD_HEIGHT - 1][BOARD_WIDTH - 2] = randPiece()
            board[BOARD_HEIGHT - 2][BOARD_WIDTH - 1] = randPiece()
        } while (
            board[BOARD_HEIGHT - 1][BOARD_WIDTH - 1] == board[BOARD_HEIGHT - 1][BOARD_WIDTH - 2] ||
            board[BOARD_HEIGHT - 1][BOARD_WIDTH - 1] == board[BOARD_HEIGHT - 2][BOARD_WIDTH - 1] ||
            board[BOARD_HEIGHT - 1][BOARD_WIDTH - 2] == board[BOARD_HEIGHT - 2][BOARD_WIDTH - 1]
        )

        repeat(POLISH_ITERATIONS) {
            for (y in 0 until BOARD_HEIGHT) {
                for (x in 0 until BOARD_WIDTH) {
                    val connected = flood(board, y, x, board[y][x])
                    if (connected.size >= 2) {
                        for ((cy, cx) in connected) {
                            if (!protected[cy][cx]) {
                                board[cy][cx] = randPiece()
                            }
                        }
                    }
                }
            }
        }

        return board
    }

    private fun flood(board: Array<IntArray>, y: Int, x: Int, color: Int): MutableList<Pair<Int, Int>> {
        val result = mutableListOf<Pair<Int, Int>>()
        val seen = Array(BOARD_HEIGHT) { BooleanArray(BOARD_WIDTH) }

        fun visit(cy: Int, cx: Int) {
            if (cy !in 0 until BOARD_HEIGHT || cx !in 0 until BOARD_WIDTH) return
            if (seen[cy][cx] || board[cy][cx] != color) return

            seen[cy][cx] = true
            result.add(cy to cx)

            visit(cy, cx - 1)
            visit(cy, cx + 1)
            visit(cy - 1, cx)
            visit(cy + 1, cx)
        }

        visit(y, x)
        return result
    }
}