package com.openbubbles.openpigeon.golf

import android.graphics.PointF

data class GolfMap(
    val seed: Int,
    val mapNum: Int,
    val mode: String,
    val xCells: Int,
    val yCells: Int,
    val mapSize: Float,
    val mapSize2: Float,
    val carveTarget: Float,
    val grid: Array<IntArray>,
    val grid2: Array<IntArray>,
    val longestPath: List<Cell>,
    val ballStart1: PointF,
    val ballStart2: PointF,
    val hole: PointF,
    val complete: Boolean,
    val slopes: List<GolfSlope> = emptyList(),
    val obstacles: List<GolfObstacle> = emptyList()
) {
    val holeNumber: Int get() = mapNum + 1
    val holeCount: Int get() = GolfConstants.holeCountFor(mode)

    fun isOpen(x: Int, y: Int): Boolean {
        if (x !in 0 until xCells || y !in 0 until yCells) return false
        return grid[x][y] == 0 || grid[x][y] == 3
    }

    fun dump(): String = buildString {
        appendLine("seed=$seed mode=$mode mapNum=$mapNum")
        appendLine("xCells=$xCells yCells=$yCells mapSize=$mapSize mapSize2=$mapSize2")
        appendLine("carveTarget=$carveTarget complete=$complete")
        appendLine("ball1=(${ballStart1.x},${ballStart1.y}) ball2=(${ballStart2.x},${ballStart2.y}) hole=(${hole.x},${hole.y})")
        appendLine("slopes=${slopes.size} obstacles=${obstacles.size}")

        if (slopes.isNotEmpty()) {
            appendLine("slopes:")
            slopes.forEachIndexed { index, slope ->
                appendLine(
                    "  $index image=${slope.image} pos=(${slope.x},${slope.y}) " +
                            "v=(${slope.vx},${slope.vy}) rotation=${slope.rotation}"
                )
            }
        }

        if (obstacles.isNotEmpty()) {
            appendLine("obstacles:")
            obstacles.forEachIndexed { index, obstacle ->
                appendLine(
                    "  $index image=${obstacle.image} type=${obstacle.type} " +
                            "pos=(${obstacle.x},${obstacle.y}) rotation=${obstacle.rotation} " +
                            "scale=${obstacle.scale} bouncy=${obstacle.bouncy}"
                )
            }
        }

        appendLine("grid:")
        for (x in 0 until xCells) {
            val line = StringBuilder()
            for (y in 0 until yCells) line.append(grid[x][y])
            appendLine(("000$x").takeLast(3) + ": " + line)
        }
    }

    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = System.identityHashCode(this)
}

data class Cell(val x: Int, val y: Int)

data class GolfSlope(
    val x: Float,
    val y: Float,
    val vx: Float,
    val vy: Float,
    val image: String = if (vx < 0f || vy < 0f) "golf_slope_down" else "golf_slope_up",
    val rotation: Float = Float.NaN
)

data class GolfObstacle(
    val type: Int,
    val x: Float,
    val y: Float,
    val rotation: Float,
    val scale: Float,
    val bouncy: Boolean,
    val image: String = ""
)