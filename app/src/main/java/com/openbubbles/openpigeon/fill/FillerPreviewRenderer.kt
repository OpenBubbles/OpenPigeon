package com.openbubbles.openpigeon.fill

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import kotlin.math.floor

object FillerPreviewRenderer {
    private const val BOARD_WIDTH = 8
    private const val BOARD_HEIGHT = 7
    private const val NUM_PIECES = 6
    private const val POLISH_ITERATIONS = 15

    private const val DRAND48_A = 0x5DEECE66DL
    private const val DRAND48_C = 0xBL
    private const val DRAND48_MASK = (1L shl 48) - 1L
    private const val DRAND48_DENOM = 281474976710656.0

    private val colors = intArrayOf(
        Color.rgb(235, 33, 110),
        Color.rgb(115, 191, 74),
        Color.rgb(245, 217, 33),
        Color.rgb(51, 143, 205),
        Color.rgb(91, 66, 137),
        Color.rgb(64, 64, 64)
    )

    private var state = 0L

    fun render(seed: Int): Bitmap {
        return renderBoardArray(generateBoard(seed))
    }

    fun renderBoard(flatBoard: IntArray): Bitmap {
        val board = Array(BOARD_HEIGHT) { y ->
            IntArray(BOARD_WIDTH) { x ->
                flatBoard.getOrElse(y * BOARD_WIDTH + x) { 0 }.coerceIn(0, colors.lastIndex)
            }
        }

        return renderBoardArray(board)
    }

    private fun renderBoardArray(board: Array<IntArray>): Bitmap {
        val cell = 36
        val padding = 18
        val width = BOARD_WIDTH * cell + padding * 2
        val height = BOARD_HEIGHT * cell + padding * 2

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        canvas.drawColor(Color.rgb(232, 232, 232))

        paint.color = Color.argb(70, 0, 0, 0)
        canvas.drawRect(
            (padding + 4).toFloat(),
            (padding + 6).toFloat(),
            (padding + BOARD_WIDTH * cell + 4).toFloat(),
            (padding + BOARD_HEIGHT * cell + 6).toFloat(),
            paint
        )

        for (y in 0 until BOARD_HEIGHT) {
            for (x in 0 until BOARD_WIDTH) {
                paint.color = colors[board[y][x].coerceIn(0, colors.lastIndex)]
                canvas.drawRect(
                    (padding + x * cell).toFloat(),
                    (padding + y * cell).toFloat(),
                    (padding + (x + 1) * cell).toFloat(),
                    (padding + (y + 1) * cell).toFloat(),
                    paint
                )
            }
        }

        return bitmap
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

        for (passIndex in 0 until POLISH_ITERATIONS) {
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