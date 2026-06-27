package com.openbubbles.openpigeon.golf

import android.graphics.PointF
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

class GolfMapGenerator(private val rng: GolfRandom = GolfRandom()) {

    companion object {
        private const val TAG = "GolfNative"
        private const val MAX_CANDIDATE_ATTEMPT_MULTIPLIER = 64

    }

    fun createMap(seed: Int, mapNum: Int, mode: String): GolfMap {
        val startedAt = android.os.SystemClock.elapsedRealtime()
        val normalizedMode = normalizeMode(mode)
        val hole = mapNum.coerceAtLeast(0)

        OpenPigeonLog.i(
            TAG,
            "Generator.createMap enter seed=$seed mode=$mode normalizedMode=$normalizedMode mapNum=$mapNum hole=$hole"
        )

        val (xCells, yCells) = GolfConstants.dimensionsFor(normalizedMode, hole)

        val mapSize = xCells * GolfConstants.TILE_SIZE
        val mapSize2 = yCells * GolfConstants.TILE_SIZE

        rng.srand48(seed)

        repeat(hole) {
            val skipped = rng.drand48()
            OpenPigeonLog.i(TAG, "Generator.seedSkip mapIndex=$it skipped=$skipped")
        }

        val carveTarget = computeCarveTarget(xCells, yCells)
        val baseGrid = generateIosCarveGrid(xCells, yCells, carveTarget)

        val longestPath = pathFinderGetLongest(baseGrid).ifEmpty {
            buildVisualPath(baseGrid)
        }

        val finalGrid = copyGrid(baseGrid)

        if (normalizedMode == GolfConstants.MODE_RACE) {
            clearRaceStartPad(finalGrid, longestPath)
        } else {
            applyPostLongestSpecialTiles(finalGrid, longestPath)
        }

        val start = longestPath.firstOrNull() ?: firstOpenCell(finalGrid) ?: Cell(0, 0)
        val end = longestPath.lastOrNull() ?: lastOpenCell(finalGrid) ?: start

        val objectGrid = copyGrid(finalGrid)

        val ball1: PointF
        val ball2: PointF
        val holePoint: PointF
        val generatedSlopes: List<GolfSlope>
        val generatedObstacles: List<GolfObstacle>

        if (normalizedMode == GolfConstants.MODE_RACE) {
            ball1 = cellCenter(start)
            ball2 = PointF(ball1.x, (ball1.y + 12f).coerceAtMost(mapSize2 - 8f))
            holePoint = cellCenter(end)
            generatedSlopes = emptyList()
            generatedObstacles = emptyList()
        } else {
            val loopD = runPlacementLoopD(finalGrid, objectGrid, longestPath)
            ball1 = loopD.ball1
            ball2 = loopD.ball2
            holePoint = loopD.hole
            generatedSlopes = loopD.slopes
            generatedObstacles = generateObstacles(
                grid = finalGrid,
                objectGrid = objectGrid,
                longestPath = longestPath
            )
        }

        val map = GolfMap(
            seed = seed,
            mapNum = hole,
            mode = normalizedMode,
            xCells = xCells,
            yCells = yCells,
            mapSize = mapSize,
            mapSize2 = mapSize2,
            carveTarget = carveTarget,
            grid = finalGrid,
            grid2 = objectGrid,
            longestPath = longestPath,
            ballStart1 = ball1,
            ballStart2 = ball2,
            hole = holePoint,
            complete = false,
            slopes = generatedSlopes,
            obstacles = generatedObstacles
        )

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID=" + androidLikeTruthJson(map)
        )

        OpenPigeonLog.i(
            TAG,
            "Generator.createMap complete source=fromSeed elapsedMs=${android.os.SystemClock.elapsedRealtime() - startedAt} " +
                    "seed=$seed mode=$normalizedMode mapNum=$hole cells=${xCells}x${yCells} mapSize=$mapSize mapSize2=$mapSize2 " +
                    "carveTarget=$carveTarget openCells=${countOpen(finalGrid)} blockedCells=${countBlocked(finalGrid)} path=${longestPath.size} " +
                    "slopes=${generatedSlopes.size} obstacles=${generatedObstacles.size} " +
                    "start=$start end=$end baseGrid=${gridSummary(baseGrid)} finalGrid=${gridSummary(finalGrid)} objectGrid=${gridSummary(objectGrid)}"
        )

        return map
    }

    fun dumpMatch(seed: Int, mode: String): String = buildString {
        OpenPigeonLog.i(TAG, "Generator.dumpMatch seed=$seed mode=$mode")
        val normalizedMode = normalizeMode(mode)
        val holes = GolfConstants.holeCountFor(normalizedMode)

        for (h in 0 until holes) {
            append(createMap(seed, h, normalizedMode).dump())
            appendLine("----")
        }
    }

    private fun androidLikeTruthJson(map: GolfMap): String {
        fun esc(value: String): String {
            return value.replace("\\", "\\\\").replace("\"", "\\\"")
        }

        val finalGrid = map.grid.joinToString(prefix = "[", postfix = "]") { row ->
            "\"" + row.joinToString("") + "\""
        }

        val slopes = map.slopes.joinToString(prefix = "[", postfix = "]") { slope ->
            "{" +
                    "\"imageName\":\"${esc(slope.image)}\"," +
                    "\"x\":${slope.x}," +
                    "\"y\":${slope.y}," +
                    "\"rotation\":${slope.rotation}," +
                    "\"vx\":${slope.vx}," +
                    "\"vy\":${slope.vy}" +
                    "}"
        }

        val obstacles = map.obstacles.joinToString(prefix = "[", postfix = "]") { obstacle ->
            "{" +
                    "\"imageName\":\"${esc(obstacle.image)}\"," +
                    "\"type\":${obstacle.type}," +
                    "\"x\":${obstacle.x}," +
                    "\"y\":${obstacle.y}," +
                    "\"rotation\":${obstacle.rotation}," +
                    "\"scale\":${obstacle.scale}," +
                    "\"bouncy\":${obstacle.bouncy}" +
                    "}"
        }

        return "{" +
                "\"seed\":${map.seed}," +
                "\"mode\":\"${esc(map.mode)}\"," +
                "\"map_num\":${map.mapNum}," +
                "\"finalGrid\":$finalGrid," +
                "\"slopes\":$slopes," +
                "\"obstacles\":$obstacles" +
                "}"
    }

    private fun objectGridPoint(cell: Cell): PointF {
        return PointF(
            cell.y * GolfConstants.TILE_SIZE,
            cell.x * GolfConstants.TILE_SIZE
        )
    }

    private fun normalizeMode(mode: String): String {
        val trimmed = mode.trim()

        return when (trimmed) {
            "5" -> "5"
            "3" -> "3"
            GolfConstants.MODE_RACE -> GolfConstants.MODE_RACE
            "" -> GolfConstants.DEFAULT_MODE
            else -> trimmed
        }
    }

    private fun computeCarveTarget(xCells: Int, yCells: Int): Float {
        val cells = (xCells * yCells).toDouble()
        val r0 = rng.drand48()
        val target = (floor(r0 * cells * 0.5) + cells * 0.13).toFloat()

        OpenPigeonLog.i(TAG, "Generator.computeCarveTarget cells=$cells r0=$r0 target=$target")

        return target
    }

    private fun generateIosCarveGrid(
        xCells: Int,
        yCells: Int,
        carveTarget: Float
    ): Array<IntArray> {
        val startedAt = android.os.SystemClock.elapsedRealtime()
        val grid = Array(xCells) { IntArray(yCells) }

        val cells = xCells * yCells
        val targetAcceptedBlocks = ceil(carveTarget.toDouble()).toInt().coerceAtLeast(0)

        OpenPigeonLog.i(
            TAG,
            "Generator.iosCarve enter xCells=$xCells yCells=$yCells carveTarget=$carveTarget targetAcceptedBlocks=$targetAcceptedBlocks"
        )

        var acceptedBlocks = 0
        var totalCandidateAttempts = 0
        var checkFailures = 0
        var noCandidateIterations = 0

        while (acceptedBlocks < targetAcceptedBlocks) {
            var scanCount = -1
            var acceptedThisIteration = false

            while (scanCount != cells) {
                scanCount += 1

                val candidate = chooseCandidate(
                    grid = grid,
                    maxAttempts = cells * MAX_CANDIDATE_ATTEMPT_MULTIPLIER
                )

                totalCandidateAttempts += candidate.attempts

                if (candidate.innerX < 0 || candidate.outerY < 0) {
                    noCandidateIterations += 1
                    OpenPigeonLog.w(
                        TAG,
                        "Generator.iosCarve no candidate scanCount=$scanCount cells=$cells acceptedBlocks=$acceptedBlocks"
                    )
                    break
                }

                grid[candidate.outerY][candidate.innerX] = 1

                if (checkGrid(grid)) {
                    acceptedBlocks += 1
                    acceptedThisIteration = true
                    break
                }

                grid[candidate.outerY][candidate.innerX] = 0
                checkFailures += 1
            }

            if (!acceptedThisIteration) {
                OpenPigeonLog.w(
                    TAG,
                    "Generator.iosCarve iteration ended without accepted block acceptedBlocks=$acceptedBlocks target=$targetAcceptedBlocks"
                )
                break
            }
        }

        val surroundedFilled = fillSurroundedOpenCells(grid)
        val randomFilled = fillLargeEmptyOpenCells(grid)

        OpenPigeonLog.i(
            TAG,
            "Generator.iosCarve complete elapsedMs=${android.os.SystemClock.elapsedRealtime() - startedAt} " +
                    "targetAcceptedBlocks=$targetAcceptedBlocks acceptedBlocks=$acceptedBlocks checkFailures=$checkFailures " +
                    "candidateAttempts=$totalCandidateAttempts noCandidateIterations=$noCandidateIterations " +
                    "surroundedFilled=$surroundedFilled randomFilled=$randomFilled grid=${gridSummary(grid)}"
        )

        return grid
    }

    private data class Candidate(
        val innerX: Int,
        val outerY: Int,
        val attempts: Int
    )

    private fun chooseCandidate(grid: Array<IntArray>, maxAttempts: Int): Candidate {
        val xCells = grid.size
        val yCells = grid.firstOrNull()?.size ?: 0

        if (xCells <= 0 || yCells <= 0) {
            return Candidate(-1, -1, 0)
        }

        var attempts = 0

        while (attempts < maxAttempts) {
            attempts += 1

            val innerX = floor(rng.drand48() * yCells.toDouble())
                .toInt()
                .coerceIn(0, yCells - 1)

            val outerY = floor(rng.drand48() * xCells.toDouble())
                .toInt()
                .coerceIn(0, xCells - 1)

            var placeable = true

            val left = innerX - 1
            val right = innerX + 1
            val up = outerY - 1
            val down = outerY + 1

            if (left >= 0 && up >= 0 && right < yCells && down < xCells) {
                val leftBlocked = gridGet(grid, left, outerY) == 1
                val rightBlocked = gridGet(grid, right, outerY) == 1
                val upBlocked = gridGet(grid, innerX, up) == 1
                val downBlocked = gridGet(grid, innerX, down) == 1

                placeable = if (!leftBlocked && !rightBlocked && !upBlocked && !downBlocked) {
                    false
                } else {
                    var diagonalGate = if (gridGet(grid, left, up) != 1) {
                        true
                    } else if (gridGet(grid, left, outerY) == 0) {
                        gridGet(grid, innerX, up) != 0
                    } else {
                        true
                    }

                    if (
                        gridGet(grid, right, down) == 1 &&
                        gridGet(grid, right, outerY) == 0 &&
                        gridGet(grid, innerX, down) == 0
                    ) {
                        diagonalGate = false
                    }

                    if (
                        gridGet(grid, right, up) == 1 &&
                        gridGet(grid, right, outerY) == 0 &&
                        gridGet(grid, innerX, up) == 0
                    ) {
                        diagonalGate = false
                    }

                    var allowed = diagonalGate

                    if (gridGet(grid, left, down) == 1 && gridGet(grid, left, outerY) == 0) {
                        val reject = if (gridGet(grid, innerX, down) != 0) {
                            !diagonalGate
                        } else {
                            true
                        }

                        allowed = !reject
                    }

                    allowed
                }
            }

            if (grid[outerY][innerX] == 1) {
                placeable = false
            }

            if (placeable) {
                return Candidate(innerX, outerY, attempts)
            }
        }

        return Candidate(-1, -1, attempts)
    }

    private fun fillSurroundedOpenCells(grid: Array<IntArray>): Int {
        var filled = 0

        for (outerY in grid.indices) {
            for (innerX in grid[outerY].indices) {
                if (
                    gridGet(grid, innerX, outerY) == 0 &&
                    gridGet(grid, innerX + 1, outerY) != 0 &&
                    gridGet(grid, innerX - 1, outerY) != 0 &&
                    gridGet(grid, innerX, outerY - 1) != 0 &&
                    gridGet(grid, innerX, outerY + 1) != 0
                ) {
                    grid[outerY][innerX] = 1
                    filled += 1
                }
            }
        }

        return filled
    }

    private fun fillLargeEmptyOpenCells(grid: Array<IntArray>): Int {
        var filled = 0

        for (outerY in grid.indices) {
            for (innerX in grid[outerY].indices) {
                if (
                    gridGet(grid, innerX, outerY) == 0 &&
                    gridGet(grid, innerX + 1, outerY) == 0 &&
                    gridGet(grid, innerX - 1, outerY) == 0 &&
                    gridGet(grid, innerX, outerY - 1) == 0 &&
                    gridGet(grid, innerX, outerY + 1) == 0 &&
                    gridGet(grid, innerX + 1, outerY + 1) == 0 &&
                    gridGet(grid, innerX - 1, outerY - 1) == 0 &&
                    gridGet(grid, innerX - 1, outerY + 1) == 0 &&
                    gridGet(grid, innerX + 1, outerY - 1) == 0 &&
                    rng.drand48() < 0.24
                ) {
                    grid[outerY][innerX] = 1
                    filled += 1
                }
            }
        }

        return filled
    }

    private fun applyPostLongestSpecialTiles(grid: Array<IntArray>, longestPath: List<Cell>) {
        if (longestPath.isEmpty()) {
            OpenPigeonLog.w(TAG, "Generator.postLongest3 skipped: empty longestPath")
            return
        }

        var converted = 0
        var rngChecks = 0

        for (outerY in grid.indices) {
            for (innerX in grid[outerY].indices) {
                if (gridGet(grid, innerX, outerY) != 0) continue
                if (isPathEndpoint(longestPath, outerY, innerX)) continue

                rngChecks += 1
                if (rng.drand48() >= 0.5) continue

                val top = gridGet(grid, innerX, outerY - 1)
                val bottom = gridGet(grid, innerX, outerY + 1)
                val left = gridGet(grid, innerX - 1, outerY)
                val right = gridGet(grid, innerX + 1, outerY)

                val shouldBecomeSpecial =
                    (top != 0 && bottom == 0 && left != 0 && right == 0) ||
                            (top != 0 && bottom == 0 && left == 0 && right != 0) ||
                            (top == 0 && bottom != 0 && left == 0 && right != 0) ||
                            (top == 0 && bottom != 0 && left != 0 && right == 0)

                if (shouldBecomeSpecial) {
                    grid[outerY][innerX] = 3
                    converted += 1
                }
            }
        }

        OpenPigeonLog.i(
            TAG,
            "Generator.postLongest3 complete rngChecks=$rngChecks converted=$converted grid=${gridSummary(grid)}"
        )
    }

    private fun clearRaceStartPad(grid: Array<IntArray>, longestPath: List<Cell>) {
        val start = longestPath.firstOrNull() ?: return

        val offsets = arrayOf(
            1 to 1,
            1 to -1,
            -1 to 1,
            -1 to -1,
            0 to 1,
            0 to -1,
            1 to 0,
            -1 to 0
        )

        var cleared = 0

        for ((dx, dy) in offsets) {
            val outerY = start.x + dy
            val innerX = start.y + dx

            if (gridSet(grid, innerX, outerY, 0)) {
                cleared += 1
            }
        }

        OpenPigeonLog.i(TAG, "Generator.clearRaceStartPad start=$start cleared=$cleared")
    }

    private data class LoopDResult(
        val slopes: List<GolfSlope>,
        val ball1: PointF,
        val ball2: PointF,
        val hole: PointF
    )

    private fun runPlacementLoopD(
        grid: Array<IntArray>,
        objectGrid: Array<IntArray>,
        longestPath: List<Cell>
    ): LoopDResult {
        val slopes = mutableListOf<GolfSlope>()

        val ballCell = longestPath.firstOrNull()   // path[0]   = finish = ball cell
        val holeCell = longestPath.lastOrNull()     // path[last] = start  = hole cell

        var ball1 = PointF(0f, 0f)
        var ball2 = PointF(0f, 0f)
        var hole = PointF(0f, 0f)

        val tile = GolfConstants.TILE_SIZE

        for (outerY in grid.indices) {
            for (innerX in grid[outerY].indices) {
                if (!isRawOpenCell(grid, innerX, outerY)) continue

                // 1. Ball at path[0]: mark grid2=3, then 2x drand48 jitter (+/-10).
                if (ballCell != null && ballCell.x == outerY && ballCell.y == innerX) {
                    reserveObjectCell(objectGrid, innerX, outerY)
                    val bx = innerX * tile - 10f + rng.drand48().toFloat() * 20f
                    val by = outerY * tile - 10f + rng.drand48().toFloat() * 20f
                    ball1 = PointF(bx, by)
                    ball2 = PointF(bx, by)   // iOS sets golf_ball1 and golf_ball2 identically
                }

                // 2. Hole at path[last]: mark grid2=3, then 2x drand48 jitter (+/-10).
                if (holeCell != null && holeCell.x == outerY && holeCell.y == innerX) {
                    reserveObjectCell(objectGrid, innerX, outerY)
                    val hx = innerX * tile - 10f + rng.drand48().toFloat() * 20f
                    val hy = outerY * tile - 10f + rng.drand48().toFloat() * 20f
                    hole = PointF(hx, hy)
                }

                // 3. Slope gate 1: drand48 consumed for EVERY open cell (endpoints incl.).
                val firstSlopeGate = rng.drand48()
                if (firstSlopeGate < 0.5 && isObjectCellFree(objectGrid, innerX, outerY)) {
                    val top = gridGet(grid, innerX, outerY - 1)
                    val bottom = gridGet(grid, innerX, outerY + 1)
                    val left = gridGet(grid, innerX - 1, outerY)
                    val right = gridGet(grid, innerX + 1, outerY)

                    if (top == 0 && bottom == 0 && left != 0 && right != 0) {
                        // vertical corridor -> vertical slope (rot 0). default up (vy=1).
                        val center = objectGridPoint(Cell(outerY, innerX))
                        val down = rng.drand48() < 0.5
                        slopes += GolfSlope(
                            x = center.x, y = center.y,
                            vx = 0f, vy = if (down) -1f else 1f,
                            image = if (down) "golf_slope_down" else "golf_slope_up"
                        )
                        reserveObjectCell(objectGrid, innerX, outerY)
                    } else if (top != 0 && bottom != 0 && left == 0 && right == 0) {
                        // horizontal corridor -> horizontal slope (rot pi/2). default up (vx=-1).
                        val center = objectGridPoint(Cell(outerY, innerX))
                        val down = rng.drand48() < 0.5
                        slopes += GolfSlope(
                            x = center.x, y = center.y,
                            vx = if (down) 1f else -1f, vy = 0f,
                            image = if (down) "golf_slope_down" else "golf_slope_up"
                        )
                        reserveObjectCell(objectGrid, innerX, outerY)
                    }
                }

                // 4. Slope gate 2: drand48 consumed for EVERY open cell. Two-cell ramp pair.
                val secondSlopeGate = rng.drand48()
                if (
                    secondSlopeGate < 0.4 &&
                    isObjectCellFree(objectGrid, innerX, outerY) &&
                    isObjectCellFree(objectGrid, innerX + 1, outerY) &&
                    gridGet(grid, innerX, outerY - 1) == 0 &&
                    gridGet(grid, innerX, outerY + 1) == 0 &&
                    gridGet(grid, innerX - 1, outerY) != 0 &&
                    gridGet(grid, innerX + 1, outerY) == 0 &&
                    gridGet(grid, innerX + 2, outerY) != 0 &&
                    gridGet(grid, innerX + 1, outerY - 1) == 0 &&
                    gridGet(grid, innerX + 1, outerY + 1) == 0
                ) {
                    val down = rng.drand48() < 0.5
                    val centerA = objectGridPoint(Cell(outerY, innerX))
                    val centerB = objectGridPoint(Cell(outerY, innerX + 1))
                    val vy = if (down) -1f else 1f
                    val img = if (down) "golf_slope_down" else "golf_slope_up"
                    slopes += GolfSlope(x = centerA.x, y = centerA.y, vx = 0f, vy = vy, image = img)
                    slopes += GolfSlope(x = centerB.x, y = centerB.y, vx = 0f, vy = vy, image = img)
                    reserveObjectCell(objectGrid, innerX, outerY)
                    reserveObjectCell(objectGrid, innerX + 1, outerY)
                }
            }
        }

        OpenPigeonLog.i(
            TAG,
            "Generator.loopD slopes=${slopes.size} ball=(${ball1.x},${ball1.y}) hole=(${hole.x},${hole.y})"
        )
        slopes.forEachIndexed { index, slope ->
            OpenPigeonLog.i(
                TAG,
                "Generator.slope[$index] image=${slope.image} pos=(${slope.x},${slope.y}) v=(${slope.vx},${slope.vy})"
            )
        }

        return LoopDResult(slopes, ball1, ball2, hole)
    }

    private fun generateObstacles(
        grid: Array<IntArray>,
        objectGrid: Array<IntArray>,
        longestPath: List<Cell>
    ): List<GolfObstacle> {
        val obstacles = mutableListOf<GolfObstacle>()

        val rows = objectGrid.size
        if (rows <= 0) return obstacles

        val cols = objectGrid.firstOrNull()?.size ?: 0
        if (cols <= 0) return obstacles

        for (outerY in 0 until rows) {
            for (innerX in 0 until cols) {
                if (!canPlaceLargeObstacleBlock(grid, objectGrid, innerX, outerY)) {
                    continue
                }

                // Binary: d8 = 0.5, then drand48 is compared with d8.
                if (rng.drand48() >= 0.5) {
                    continue
                }

                reserveLargeObstacleBlock(objectGrid, innerX, outerY)

                val typeRand = rng.drand48()
                val image: String
                val type: Int
                val bouncy = false
                var scale = 1f

                when {
                    typeRand < 0.2 -> {
                        image = "golf_obstacle_square2"
                        type = 1
                        scale = randomLargeScale()
                    }

                    typeRand < 0.4 -> {
                        // iOS string is golf_obstacle_bar2. Renderer falls back to
                        // golf_obstacles_bar2_Normal@3x.png if that exact asset is absent.
                        image = "golf_obstacle_bar2"
                        type = 2
                    }

                    typeRand < 0.6 -> {
                        image = "golf_obstacle_triangle2"
                        type = 3
                        scale = randomLargeScale()
                    }

                    typeRand < 0.8 -> {
                        image = "golf_obstacle_round2"
                        type = 4
                        scale = randomLargeScale()
                    }

                    else -> {
                        image = "golf_obstacle_cross"
                        type = 5
                    }
                }

                obstacles += GolfObstacle(
                    type = type,
                    x = innerX * GolfConstants.TILE_SIZE + GolfConstants.TILE_SIZE * 0.5f,
                    y = outerY * GolfConstants.TILE_SIZE + GolfConstants.TILE_SIZE * 0.5f,
                    rotation = randomRotation(),
                    scale = scale,
                    bouncy = bouncy,
                    image = image
                )
            }
        }

        val openCount = countRawOpenObjectCells(objectGrid)
        val base = floor(openCount.toDouble() * 2.0 / 3.0).toInt()

        // iOS consumes this RNG here even if the final count becomes zero.
        val smallCount = floor(base.toDouble() / 3.0).toInt() +
                floor(rng.drand48() * base.toDouble() * 2.0 / 3.0).toInt()

        if (smallCount > 0) {
            repeat(smallCount) {
                val candidate = pickOpenObjectCell(objectGrid, rows, cols)
                    ?: return@repeat

                val outerY = candidate.x
                val innerX = candidate.y

                objectGrid[outerY][innerX] = 3

                val typeRand = rng.drand48().toFloat()
                val image: String
                val type: Int
                var scale = 1f
                var bouncy = false

                when {
                    typeRand < 0.25f -> {
                        image = "golf_obstacle_square"
                        type = 1
                        scale = randomSmallScale()
                    }

                    typeRand < 0.5f -> {
                        image = "golf_obstacle_bar"
                        type = 2
                    }

                    typeRand < 0.75f -> {
                        image = "golf_obstacle_triangle"
                        type = 3
                        scale = randomSmallScale()
                    }

                    else -> {
                        image = "golf_obstacle_round"
                        type = 4
                        bouncy = true
                    }
                }

                val rotation = randomRotation()
                val x = innerX * GolfConstants.TILE_SIZE - 10f +
                        rng.drand48().toFloat() * 20f
                val y = outerY * GolfConstants.TILE_SIZE - 10f +
                        rng.drand48().toFloat() * 20f

                obstacles += GolfObstacle(
                    type = type,
                    x = x,
                    y = y,
                    rotation = rotation,
                    scale = scale,
                    bouncy = bouncy,
                    image = image
                )
            }
        }

        OpenPigeonLog.i(
            TAG,
            "Generator.generateObstacles count=${obstacles.size} openCount=$openCount smallCount=$smallCount"
        )

        obstacles.forEachIndexed { index, obstacle ->
            OpenPigeonLog.i(
                TAG,
                "Generator.obstacle[$index] image=${obstacle.image} type=${obstacle.type} " +
                        "pos=(${obstacle.x},${obstacle.y}) rotation=${obstacle.rotation} scale=${obstacle.scale} bouncy=${obstacle.bouncy}"
            )
        }

        return obstacles
    }

    private fun canPlaceLargeObstacleBlock(
        grid: Array<IntArray>,
        objectGrid: Array<IntArray>,
        innerX: Int,
        outerY: Int
    ): Boolean {
        val innerX2 = innerX + 1
        val outerY2 = outerY + 1

        return isRawOpenCell(grid, innerX, outerY) &&
                isRawOpenCell(grid, innerX2, outerY) &&
                isRawOpenCell(grid, innerX, outerY2) &&
                isRawOpenCell(grid, innerX2, outerY2) &&
                isObjectCellFree(objectGrid, innerX, outerY) &&
                isObjectCellFree(objectGrid, innerX2, outerY) &&
                isObjectCellFree(objectGrid, innerX, outerY2) &&
                isObjectCellFree(objectGrid, innerX2, outerY2)
    }

    private fun reserveLargeObstacleBlock(
        objectGrid: Array<IntArray>,
        innerX: Int,
        outerY: Int
    ) {
        objectGrid[outerY][innerX] = 3
        objectGrid[outerY][innerX + 1] = 3
        objectGrid[outerY + 1][innerX] = 3
        objectGrid[outerY + 1][innerX + 1] = 3
    }

    private fun countRawOpenObjectCells(objectGrid: Array<IntArray>): Int {
        var count = 0

        for (outerY in objectGrid.indices) {
            for (innerX in objectGrid[outerY].indices) {
                if (objectGrid[outerY][innerX] == 0) {
                    count++
                }
            }
        }

        return count
    }

    private fun pickOpenObjectCell(
        objectGrid: Array<IntArray>,
        rows: Int,
        cols: Int
    ): Cell? {
        if (countRawOpenObjectCells(objectGrid) <= 0) {
            return null
        }

        while (true) {
            val innerX = floor(rng.drand48() * cols.toDouble()).toInt()
            val outerY = floor(rng.drand48() * rows.toDouble()).toInt()

            if (objectGrid[outerY][innerX] == 0) {
                return Cell(outerY, innerX)
            }
        }
    }

    private fun randomLargeScale(): Float {
        return (0.7 + rng.drand48() * 0.3).toFloat()
    }

    private fun randomSmallScale(): Float {
        return (0.5 + rng.drand48() * 0.5).toFloat()
    }

    private fun randomRotation(): Float {
        return (rng.drand48() * Math.PI * 2.0).toFloat()
    }

    private fun isRawOpenCell(grid: Array<IntArray>, innerX: Int, outerY: Int): Boolean {
        return rawCell(grid, innerX, outerY) == 0
    }

    private fun isObjectCellFree(objectGrid: Array<IntArray>, innerX: Int, outerY: Int): Boolean {
        return rawCell(objectGrid, innerX, outerY) == 0
    }

    private fun reserveObjectCell(objectGrid: Array<IntArray>, innerX: Int, outerY: Int): Boolean {
        if (outerY !in objectGrid.indices) return false
        if (innerX !in objectGrid[outerY].indices) return false
        if (objectGrid[outerY][innerX] != 0) return false

        objectGrid[outerY][innerX] = 3
        return true
    }

    private fun isPathEndpoint(path: List<Cell>, outerY: Int, innerX: Int): Boolean {
        val first = path.firstOrNull()
        val last = path.lastOrNull()

        return (first != null && first.x == outerY && first.y == innerX) ||
                (last != null && last.x == outerY && last.y == innerX)
    }

    private fun gridSet(grid: Array<IntArray>, innerX: Int, outerY: Int, value: Int): Boolean {
        if (outerY !in grid.indices) return false
        if (innerX !in grid[outerY].indices) return false
        if (grid[outerY][innerX] == 3) return false
        if (grid[outerY][innerX] == value) return false

        grid[outerY][innerX] = value
        return true
    }

    private fun gridGet(grid: Array<IntArray>, innerX: Int, outerY: Int): Int {
        if (outerY !in grid.indices) return -1
        if (innerX !in grid[outerY].indices) return -1

        val value = grid[outerY][innerX]
        return if (value == 3) 0 else value
    }

    private fun rawCell(grid: Array<IntArray>, innerX: Int, outerY: Int): Int {
        if (outerY !in grid.indices) return -1
        if (innerX !in grid[outerY].indices) return -1
        return grid[outerY][innerX]
    }

    private fun checkGrid(grid: Array<IntArray>): Boolean {
        val xCells = grid.size
        val yCells = grid.firstOrNull()?.size ?: return false

        if (xCells == 0 || yCells == 0) {
            return false
        }

        val topMin = firstOpenOnOuterRow(grid, outerY = 0, fromRight = false)
        val topMax = firstOpenOnOuterRow(grid, outerY = 0, fromRight = true)
        val bottomMin = firstOpenOnOuterRow(grid, outerY = xCells - 1, fromRight = false)
        val bottomMax = firstOpenOnOuterRow(grid, outerY = xCells - 1, fromRight = true)

        if (topMin == null || topMax == null || bottomMin == null || bottomMax == null) {
            return false
        }

        val pathA = pathFinderGo(
            grid = grid,
            xIni = topMin.y,
            yIni = topMin.x,
            xFin = bottomMax.y,
            yFin = bottomMax.x
        )

        if (pathA.isEmpty()) {
            return false
        }

        val pathB = pathFinderGo(
            grid = grid,
            xIni = topMax.y,
            yIni = topMax.x,
            xFin = bottomMin.y,
            yFin = bottomMin.x
        )

        return pathB.isNotEmpty()
    }

    private fun firstOpenOnOuterRow(grid: Array<IntArray>, outerY: Int, fromRight: Boolean): Cell? {
        if (outerY !in grid.indices) return null

        val range = if (fromRight) {
            grid[outerY].indices.reversed()
        } else {
            grid[outerY].indices
        }

        for (innerX in range) {
            if (gridGet(grid, innerX, outerY) == 0) {
                return Cell(outerY, innerX)
            }
        }

        return null
    }

    private fun pathFinderGetLongest(grid: Array<IntArray>): List<Cell> {
        val xCells = grid.size
        val yCells = grid.firstOrNull()?.size ?: 0
        if (xCells == 0 || yCells == 0) return emptyList()

        /*
         * iOS getLongest is not an all-open-cell diameter search.
         *
         * The map generator's checkGrid proves the iOS constraint is top/bottom-row
         * connectivity. For normal Mini Golf maps, the selected course path runs
         * between outer row 0 and outer row xCells - 1.
         *
         * The previous Android version searched every open cell pair, so on seed
         * 680056098 it incorrectly chose Cell(x=2,y=3) -> Cell(x=5,y=3), because
         * that has the same length as the real top/bottom path. That made the ball
         * spawn, hole jitter, slope RNG, and object placement drift from iOS.
         */
        val finishOuterY = 0
        val startOuterY = xCells - 1

        var best: List<Cell>? = null

        /*
         * Scan right-to-left to match the existing iOS-style endpoint preference.
         *
         * Returned path is finish -> start because the rest of the generator expects:
         *   path.first() = ball cell
         *   path.last()  = hole cell
         */
        for (startInnerX in yCells - 1 downTo 0) {
            if (!isPathOpenCell(grid, startInnerX, startOuterY)) continue

            for (finishInnerX in yCells - 1 downTo 0) {
                if (!isPathOpenCell(grid, finishInnerX, finishOuterY)) continue

                val candidate = shortestPathBfs(
                    grid = grid,
                    startInnerX = startInnerX,
                    startOuterY = startOuterY,
                    finishInnerX = finishInnerX,
                    finishOuterY = finishOuterY
                )

                if (candidate.isEmpty()) continue

                val current = best
                if (current == null || candidate.size > current.size) {
                    best = candidate
                }
            }
        }

        val result = best ?: emptyList()

        OpenPigeonLog.i(
            TAG,
            "Generator.getLongest boundaryOnly=true pathSize=${result.size} " +
                    "finish=${result.firstOrNull()} start=${result.lastOrNull()} " +
                    "path=${result.joinToString(prefix = "[", postfix = "]")}"
        )

        return result
    }

    private fun shortestPathBfs(
        grid: Array<IntArray>,
        startInnerX: Int,
        startOuterY: Int,
        finishInnerX: Int,
        finishOuterY: Int
    ): List<Cell> {
        val height = grid.size
        val width = grid.firstOrNull()?.size ?: 0

        if (height == 0 || width == 0) return emptyList()

        if (!isPathOpenCell(grid, startInnerX, startOuterY)) return emptyList()
        if (!isPathOpenCell(grid, finishInnerX, finishOuterY)) return emptyList()

        fun index(innerX: Int, outerY: Int): Int {
            return outerY * width + innerX
        }

        val startIndex = index(startInnerX, startOuterY)
        val finishIndex = index(finishInnerX, finishOuterY)

        val parent = IntArray(width * height) { -1 }
        val queue = java.util.ArrayDeque<Int>()

        parent[startIndex] = startIndex
        queue.add(startIndex)

        val directions = arrayOf(
            0 to -1,   // up
            -1 to 0,   // left
            1 to 0,    // right
            0 to 1     // down
        )

        while (!queue.isEmpty()) {
            val current = queue.removeFirst()

            if (current == finishIndex) {
                break
            }

            val currentOuterY = current / width
            val currentInnerX = current % width

            for ((dx, dy) in directions) {
                val nextInnerX = currentInnerX + dx
                val nextOuterY = currentOuterY + dy

                if (!isPathOpenCell(grid, nextInnerX, nextOuterY)) continue

                val nextIndex = index(nextInnerX, nextOuterY)
                if (parent[nextIndex] != -1) continue

                parent[nextIndex] = current
                queue.add(nextIndex)
            }
        }

        if (parent[finishIndex] == -1) {
            return emptyList()
        }

        val result = ArrayList<Cell>()
        var cursor = finishIndex

        while (true) {
            val outerY = cursor / width
            val innerX = cursor % width

            result += Cell(
                x = outerY,
                y = innerX
            )

            if (cursor == startIndex) {
                break
            }

            cursor = parent[cursor]
        }

        return result
    }

    private fun isPathOpenCell(
        grid: Array<IntArray>,
        innerX: Int,
        outerY: Int
    ): Boolean {
        return gridGet(grid, innerX, outerY) == 0
    }

    private fun pathFinderGo(
        grid: Array<IntArray>,
        xIni: Int,
        yIni: Int,
        xFin: Int,
        yFin: Int
    ): List<Cell> {
        if (xIni > 500 || yIni > 500 || xFin > 500 || yFin > 500) return emptyList()
        if (xIni < 0 || yIni < 0 || xFin < 0 || yFin < 0) return emptyList()

        val startOpen = rawCell(grid, xIni, yIni) == 0
        val endOpen = rawCell(grid, xFin, yFin) == 0

        if (!startOpen && !endOpen) {
            return emptyList()
        }

        return PathSearch(grid, xFin, yFin).run(xIni, yIni)
    }

    private class PathNode(
        val x: Int,
        val y: Int,
        val g: Int,
        val h: Int,
        val parent: PathNode?
    )

    private class PathSearch(
        private val grid: Array<IntArray>,
        private val finX: Int,
        private val finY: Int
    ) {
        private val openList = LinkedHashMap<String, PathNode>()
        private val closedList = HashMap<String, PathNode>()
        private val path = ArrayList<Cell>()

        private val width = grid.firstOrNull()?.size ?: 0
        private val height = grid.size

        fun run(xIni: Int, yIni: Int): List<Cell> {
            openList["${xIni}_$yIni"] = PathNode(xIni, yIni, 0, 0, null)
            searchLevel()
            return path
        }

        private fun searchLevel() {
            while (true) {
                var best: PathNode? = null
                var bestF = 100000

                for (node in openList.values) {
                    val f = node.h + node.g
                    if (bestF > f) {
                        bestF = f
                        best = node
                    }
                }

                val current = best ?: return

                val key = key(current.x, current.y)
                openList.remove(key)
                closedList[key] = current

                if (current.x == finX && current.y == finY) {
                    retrace(current)
                    return
                }

                expand(current, -1, 0)
                expand(current, 0, -1)
                expand(current, 0, 1)
                expand(current, 1, 0)
            }
        }

        private fun expand(node: PathNode, dx: Int, dy: Int) {
            val nx = node.x + dx
            val ny = node.y + dy

            if (nx < 0 || nx >= width) return
            if (ny < 0 || ny >= height) return
            if (grid[ny][nx] != 0) return

            val key = key(nx, ny)

            if (closedList.containsKey(key)) return
            if (openList.containsKey(key)) return

            val h = abs(nx - finX) + abs(ny - finY) * 10
            openList[key] = PathNode(nx, ny, 10, h, node)
        }

        private fun retrace(node: PathNode) {
            var current: PathNode? = node

            while (current != null) {
                path.add(Cell(current.y, current.x))
                current = if (current.g >= 1) current.parent else null
            }
        }

        private fun key(x: Int, y: Int): String {
            return "${x}_$y"
        }
    }

    private fun buildVisualPath(grid: Array<IntArray>): List<Cell> {
        val path = mutableListOf<Cell>()

        for (x in grid.indices) {
            val yRange = if (x % 2 == 0) {
                grid[x].indices
            } else {
                grid[x].indices.reversed()
            }

            for (y in yRange) {
                if (isOpen(grid, x, y)) {
                    path += Cell(x, y)
                }
            }
        }

        OpenPigeonLog.i(TAG, "Generator.buildVisualPath pathSize=${path.size}")

        return path
    }

    private fun firstOpenCell(grid: Array<IntArray>): Cell? {
        for (x in grid.indices) {
            for (y in grid[x].indices) {
                if (isOpen(grid, x, y)) {
                    return Cell(x, y)
                }
            }
        }

        return null
    }

    private fun lastOpenCell(grid: Array<IntArray>): Cell? {
        for (x in grid.indices.reversed()) {
            for (y in grid[x].indices.reversed()) {
                if (isOpen(grid, x, y)) {
                    return Cell(x, y)
                }
            }
        }

        return null
    }

    private fun cellCenter(cell: Cell): PointF {
        return PointF(
            cell.x * GolfConstants.TILE_SIZE + GolfConstants.TILE_SIZE * 0.5f,
            cell.y * GolfConstants.TILE_SIZE + GolfConstants.TILE_SIZE * 0.5f
        )
    }

    private fun isOpen(grid: Array<IntArray>, x: Int, y: Int): Boolean {
        if (x !in grid.indices) return false
        if (y !in grid[x].indices) return false

        return grid[x][y] == 0 || grid[x][y] == 3
    }

    private fun countOpen(grid: Array<IntArray>): Int {
        return grid.sumOf { row -> row.count { it == 0 || it == 3 } }
    }

    private fun countBlocked(grid: Array<IntArray>): Int {
        return grid.sumOf { row -> row.count { it == 1 } }
    }

    private fun copyGrid(source: Array<IntArray>): Array<IntArray> {
        return Array(source.size) { x -> source[x].copyOf() }
    }

    private fun gridSummary(grid: Array<IntArray>): String = buildString {
        append(grid.size)
        append("x")
        append(grid.firstOrNull()?.size ?: 0)
        append("[")

        grid.forEachIndexed { index, row ->
            if (index > 0) append(";")
            row.forEach { append(it) }
        }

        append("]")
    }
}