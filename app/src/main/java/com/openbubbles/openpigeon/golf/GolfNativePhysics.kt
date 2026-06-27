package com.openbubbles.openpigeon.golf

import android.graphics.PointF
import com.openbubbles.openpigeon.util.OpenPigeonLog
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.max

object GolfNativePhysics {
    private const val TAG = "GolfNative"

    private const val OBSTACLE_SQUARE = 0
    private const val OBSTACLE_SQUARE2 = 1
    private const val OBSTACLE_BAR = 2
    private const val OBSTACLE_BAR2 = 3
    private const val OBSTACLE_ROUND = 4
    private const val OBSTACLE_ROUND2 = 5
    private const val OBSTACLE_TRIANGLE = 6
    private const val OBSTACLE_TRIANGLE2 = 7
    private const val OBSTACLE_CROSS = 8

    private const val STATE_EPS = 0.01f

    private var table: Long = 0L
    private var configuredKey: String? = null
    private var ballCreated = false

    private val outputs: FloatBuffer = ByteBuffer.allocateDirect(8 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()

    init {
        System.loadLibrary("openbubblesextension")
    }

    external fun createGolfTable(): Long
    external fun destroyGolfTable(table: Long)

    external fun configureGolfTable(
        table: Long,
        tileSize: Float,
        mapSize: Float,
        rows: Int,
        cols: Int,
        openMask: IntArray,
        obstacleData: FloatArray,
        obstacleKinds: IntArray,
        obstacleBouncy: BooleanArray,
        slopeData: FloatArray
    )

    external fun setGolfTraceContext(
        table: Long,
        runId: String,
        shotIndex: Int,
        frame: Int,
        phase: String
    )

    external fun clearGolfTraceContext(table: Long)

    external fun makeGolfBall(
        table: Long,
        x: Float,
        y: Float,
        outputs: FloatBuffer
    )

    external fun setGolfBallState(
        table: Long,
        x: Float,
        y: Float,
        vx: Float,
        vy: Float
    )

    external fun fireGolfBall(
        table: Long,
        directionRadians: Float,
        power: Float
    )

    external fun updateGolfTable(
        table: Long,
        dtSeconds: Float
    ): Boolean

    external fun refreshGolfOutputs(table: Long)

    fun reset() {
        val old = table
        table = 0L
        configuredKey = null
        ballCreated = false

        if (old != 0L) {
            destroyGolfTable(old)
        }
    }

    fun setTraceContext(
        map: GolfMap,
        runId: String,
        shotIndex: Int,
        frame: Int,
        phase: String
    ) {
        val nativeTable = ensureTable()

        setGolfTraceContext(
            nativeTable,
            runId,
            shotIndex,
            frame,
            phase
        )

        val key = map.nativePhysicsKey()
        if (configuredKey != key) {
            configure(nativeTable, map)
            configuredKey = key
            ballCreated = false
        }
    }

    fun clearTraceContext() {
        val nativeTable = table
        if (nativeTable != 0L) {
            clearGolfTraceContext(nativeTable)
        }
    }

    fun step(
        map: GolfMap,
        positionCourse: PointF,
        velocityCourse: PointF,
        dtSeconds: Float
    ): Boolean {
        val nativeTable = ensureTable()

        val key = map.nativePhysicsKey()
        if (configuredKey != key) {
            configure(nativeTable, map)
            configuredKey = key
            ballCreated = false
        }

        if (!ballCreated) {
            makeGolfBall(nativeTable, positionCourse.x, positionCourse.y, outputs)
            ballCreated = true
        }

        val nativeX = outputs.get(0)
        val nativeY = outputs.get(1)
        val nativeVx = outputs.get(3)
        val nativeVy = outputs.get(4)

        val callerChangedState =
            abs(nativeX - positionCourse.x) > STATE_EPS ||
                    abs(nativeY - positionCourse.y) > STATE_EPS ||
                    abs(nativeVx - velocityCourse.x) > STATE_EPS ||
                    abs(nativeVy - velocityCourse.y) > STATE_EPS

        if (callerChangedState) {
            setGolfBallState(
                nativeTable,
                positionCourse.x,
                positionCourse.y,
                velocityCourse.x,
                velocityCourse.y
            )
        }

        val moving = updateGolfTable(nativeTable, dtSeconds)

        positionCourse.x = outputs.get(0)
        positionCourse.y = outputs.get(1)
        velocityCourse.x = outputs.get(3)
        velocityCourse.y = outputs.get(4)

        return !moving
    }

    fun fire(
        map: GolfMap,
        positionCourse: PointF,
        directionRadians: Float,
        power: Float
    ) {
        val nativeTable = ensureTable()

        val key = map.nativePhysicsKey()
        if (configuredKey != key) {
            configure(nativeTable, map)
            configuredKey = key
            ballCreated = false
        }

        if (!ballCreated) {
            makeGolfBall(nativeTable, positionCourse.x, positionCourse.y, outputs)
            ballCreated = true
        } else {
            setGolfBallState(nativeTable, positionCourse.x, positionCourse.y, 0f, 0f)
        }

        fireGolfBall(nativeTable, directionRadians, power)
        refreshGolfOutputs(nativeTable)
    }

    private fun ensureTable(): Long {
        if (table == 0L) {
            table = createGolfTable()
        }

        return table
    }

    private fun configure(table: Long, map: GolfMap) {
        val rows = map.grid.size
        val cols = map.grid.maxOfOrNull { it.size } ?: 0

        val openMask = IntArray(rows * cols)
        var openCells = 0
        var blockedCells = 0
        var special3Cells = 0

        for (row in 0 until rows) {
            for (col in 0 until cols) {
                val rawCellValue = map.grid
                    .getOrNull(row)
                    ?.getOrNull(col)
                    ?: 1

                openMask[row * cols + col] = rawCellValue

                when (rawCellValue) {
                    0 -> openCells += 1
                    1 -> blockedCells += 1
                    3 -> special3Cells += 1
                }
            }
        }

        val obstacleData = FloatArray(map.obstacles.size * 4)
        val obstacleKinds = IntArray(map.obstacles.size)
        val obstacleBouncy = BooleanArray(map.obstacles.size)

        map.obstacles.forEachIndexed { index, obstacle ->
            obstacleData[index * 4 + 0] = obstacle.x
            obstacleData[index * 4 + 1] = obstacle.y
            obstacleData[index * 4 + 2] = obstacle.rotation
            obstacleData[index * 4 + 3] = obstacle.scale

            obstacleKinds[index] = obstacleKind(obstacle)
            obstacleBouncy[index] = obstacle.bouncy
        }

        val slopeData = FloatArray(map.slopes.size * 5)

        map.slopes.forEachIndexed { index, slope ->
            slopeData[index * 5 + 0] = slope.x
            slopeData[index * 5 + 1] = slope.y
            slopeData[index * 5 + 2] = slope.vx
            slopeData[index * 5 + 3] = slope.vy
            slopeData[index * 5 + 4] =
                if (!slope.rotation.isNaN() && !slope.rotation.isInfinite()) {
                    slope.rotation
                } else {
                    atan2(-slope.vx, slope.vy)
                }
        }

        configureGolfTable(
            table = table,
            tileSize = GolfConstants.TILE_SIZE,
            mapSize = map.mapSize,
            rows = rows,
            cols = cols,
            openMask = openMask,
            obstacleData = obstacleData,
            obstacleKinds = obstacleKinds,
            obstacleBouncy = obstacleBouncy,
            slopeData = slopeData
        )

        OpenPigeonLog.i(
            TAG,
            "Golf Box2D configured seed=${map.seed} mapNum=${map.mapNum} " +
                    "rows=$rows cols=$cols obstacles=${map.obstacles.size} slopes=${map.slopes.size}"
        )
    }

    private fun obstacleKind(obstacle: GolfObstacle): Int {
        val image = obstacle.image.ifBlank {
            when {
                obstacle.bouncy -> "golf_obstacle_round"
                obstacle.type == 2 -> "golf_obstacle_bar"
                obstacle.type == 3 -> "golf_obstacle_triangle"
                obstacle.type == 4 -> "golf_obstacle_round"
                obstacle.type == 5 -> "golf_obstacle_cross"
                else -> "golf_obstacle_square"
            }
        }

        return when (image) {
            "golf_obstacle_square" -> OBSTACLE_SQUARE
            "golf_obstacle_square2" -> OBSTACLE_SQUARE2
            "golf_obstacle_bar" -> OBSTACLE_BAR
            "golf_obstacle_bar2",
            "golf_obstacles_bar2" -> OBSTACLE_BAR2
            "golf_obstacle_round" -> OBSTACLE_ROUND
            "golf_obstacle_round2",
            "golf_obstacles_round2" -> OBSTACLE_ROUND2
            "golf_obstacle_triangle" -> OBSTACLE_TRIANGLE
            "golf_obstacle_triangle2" -> OBSTACLE_TRIANGLE2
            "golf_obstacle_cross" -> OBSTACLE_CROSS
            else -> OBSTACLE_SQUARE
        }
    }

    private fun GolfMap.nativePhysicsKey(): String {
        val obstacleHash = obstacles.joinToString(";") {
            "${it.image}:${it.type}:${it.bouncy}:${it.x}:${it.y}:${it.rotation}:${it.scale}"
        }

        val slopeHash = slopes.joinToString(";") {
            "${it.image}:${it.x}:${it.y}:${it.vx}:${it.vy}:${it.rotation}"
        }

        val gridHash = grid.joinToString("|") { row ->
            row.joinToString("")
        }

        return "$seed|$mode|$mapNum|$mapSize|$gridHash|$obstacleHash|$slopeHash"
    }
}
