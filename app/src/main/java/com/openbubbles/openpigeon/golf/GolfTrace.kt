package com.openbubbles.openpigeon.golf

import android.graphics.PointF
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.math.sqrt

object GolfTrace {
    val ENABLED: Boolean
        get() = GolfConstants.debugToolsEnabled

    private const val TAG = "GolfNative"
    private const val PREFIX = "GOLF_ANDROID_TRACE="

    private var liveFrameCounter = 0

    data class Context(
        val runId: String,
        val source: String,
        val seed: Int,
        val mode: String,
        val mapNum: Int,
        val holeIndex: Int,
        val slot: String,
        val shotIndex: Int,
        val dist: Float,
        val rotation: Float
    )

    private val contextLocal = ThreadLocal<Context?>()
    private val frameLocal = ThreadLocal.withInitial { -1 }

    val context: Context?
        get() = contextLocal.get()

    val frame: Int
        get() = frameLocal.get() ?: -1

    fun beginShot(
        runId: String,
        source: String,
        map: GolfMap,
        holeIndex: Int,
        slot: String,
        shotIndex: Int,
        dist: Float,
        rotation: Float,
        startPos: PointF,
        velocity: PointF
    ) {
        if (!ENABLED) return

        contextLocal.set(
            Context(
                runId = runId,
                source = source,
                seed = map.seed,
                mode = map.mode,
                mapNum = map.mapNum,
                holeIndex = holeIndex,
                slot = slot,
                shotIndex = shotIndex,
                dist = dist,
                rotation = rotation
            )
        )

        frameLocal.set(0)

        log(
            "{" +
                    "\"kind\":\"shotStart\"," +
                    contextJsonFields() + "," +
                    "\"startPos\":${pointJson(startPos)}," +
                    "\"velocity\":${pointJson(velocity)}," +
                    "\"speed\":${speed(velocity)}," +
                    "\"hole\":${pointJson(map.hole)}" +
                    "}"
        )
    }

    fun setFrame(value: Int) {
        frameLocal.set(value)
    }

    fun frameSample(
        phase: String,
        t: Float,
        dt: Float,
        pos: PointF,
        vel: PointF,
        hole: PointF,
        force: Boolean = false
    ) {
        if (!ENABLED) return

        log(
            "{" +
                    "\"kind\":\"frame\"," +
                    contextJsonFields() + "," +
                    "\"phase\":\"${escape(phase)}\"," +
                    "\"frame\":$frame," +
                    "\"t\":$t," +
                    "\"dt\":$dt," +
                    "\"pos\":${pointJson(pos)}," +
                    "\"vel\":${pointJson(vel)}," +
                    "\"speed\":${speed(vel)}," +
                    "\"distanceToHole\":${distance(pos, hole)}" +
                    "}"
        )
    }

    fun holeCup(
        phase: String,
        map: GolfMap,
        pos: PointF,
        vel: PointF,
        holeStep: GolfPhysics.HoleStep,
        alreadyCaptured: Boolean
    ) {
        if (!ENABLED) return

        val shouldLog =
            holeStep.flagPulled ||
                    holeStep.captured ||
                    holeStep.settled ||
                    distance(pos, map.hole) < 40f

        if (!shouldLog) return

        log(
            "{" +
                    "\"kind\":\"holeCup\"," +
                    "\"phase\":\"${escape(phase)}\"," +
                    "\"trace\":${contextJsonOrNull()}," +
                    "\"pos\":${pointJson(pos)}," +
                    "\"vel\":${pointJson(vel)}," +
                    "\"speed\":${speed(vel)}," +
                    "\"hole\":${pointJson(map.hole)}," +
                    "\"distanceToHole\":${distance(pos, map.hole)}," +
                    "\"alreadyCaptured\":$alreadyCaptured," +
                    "\"flagPulled\":${holeStep.flagPulled}," +
                    "\"captured\":${holeStep.captured}," +
                    "\"settled\":${holeStep.settled}" +
                    "}"
        )
    }

    fun endShot(
        reason: String,
        frameCount: Int,
        t: Float,
        pos: PointF,
        vel: PointF,
        hole: PointF
    ) {
        if (!ENABLED) return

        log(
            "{" +
                    "\"kind\":\"shotStop\"," +
                    contextJsonFields() + "," +
                    "\"reason\":\"${escape(reason)}\"," +
                    "\"frameCount\":$frameCount," +
                    "\"t\":$t," +
                    "\"finalPos\":${pointJson(pos)}," +
                    "\"finalVel\":${pointJson(vel)}," +
                    "\"finalSpeed\":${speed(vel)}," +
                    "\"distanceToHole\":${distance(pos, hole)}" +
                    "}"
        )

        contextLocal.remove()
        frameLocal.remove()
    }

    fun replaySummary(
        source: String,
        seed: Int,
        mode: String,
        mapNum: Int,
        p1Replay: String,
        p2Replay: String
    ) {
        if (!ENABLED) return

        log(
            "{" +
                    "\"kind\":\"replaySummary\"," +
                    "\"source\":\"${escape(source)}\"," +
                    "\"seed\":$seed," +
                    "\"mode\":\"${escape(mode)}\"," +
                    "\"mapNum\":$mapNum," +
                    "\"p1Replay\":\"${escape(p1Replay)}\"," +
                    "\"p2Replay\":\"${escape(p2Replay)}\"" +
                    "}"
        )
    }

    fun mapTruth(reason: String, map: GolfMap) {
        if (!ENABLED) return

        log(
            "{" +
                    "\"kind\":\"mapTruth\"," +
                    "\"reason\":\"${escape(reason)}\"," +
                    "\"seed\":${map.seed}," +
                    "\"mode\":\"${escape(map.mode)}\"," +
                    "\"mapNum\":${map.mapNum}," +
                    "\"xCells\":${map.xCells}," +
                    "\"yCells\":${map.yCells}," +
                    "\"mapSize\":${map.mapSize}," +
                    "\"mapSize2\":${map.mapSize2}," +
                    "\"ballStart1\":${pointJson(map.ballStart1)}," +
                    "\"ballStart2\":${pointJson(map.ballStart2)}," +
                    "\"hole\":${pointJson(map.hole)}," +
                    "\"grid\":${gridJson(map)}," +
                    "\"slopes\":${slopesJson(map)}," +
                    "\"obstacles\":${obstaclesJson(map)}" +
                    "}"
        )
    }

    fun localLaunch(
        map: GolfMap?,
        localPlayer: Int,
        mapNum: Int,
        shotIndex: Int,
        ballCourse: PointF,
        ballVisual: PointF,
        dist: Float,
        rotation: Float,
        velocityVisual: PointF,
        velocityCourse: PointF,
        replay: String
    ) {
        if (!ENABLED) return

        log(
            "{" +
                    "\"kind\":\"localLaunch\"," +
                    "\"seed\":${map?.seed}," +
                    "\"mode\":\"${escape(map?.mode ?: "")}\"," +
                    "\"mapNum\":$mapNum," +
                    "\"localPlayer\":$localPlayer," +
                    "\"shotIndex\":$shotIndex," +
                    "\"ballCourse\":${pointJson(ballCourse)}," +
                    "\"ballVisual\":${pointJson(ballVisual)}," +
                    "\"dist\":$dist," +
                    "\"rotation\":$rotation," +
                    "\"velocityVisual\":${pointJson(velocityVisual)}," +
                    "\"velocityCourse\":${pointJson(velocityCourse)}," +
                    "\"replay\":\"${escape(replay)}\"" +
                    "}"
        )
    }

    fun replayFire(
        map: GolfMap?,
        localPlayer: Int,
        mapNum: Int,
        shotIndex: Int,
        mineShot: GolfReplay.Shot?,
        opponentShot: GolfReplay.Shot?,
        mineBallCourse: PointF,
        opponentBallCourse: PointF,
        mineVelocityCourse: PointF,
        opponentVelocityCourse: PointF
    ) {
        if (!ENABLED) return

        log(
            "{" +
                    "\"kind\":\"replayFire\"," +
                    "\"seed\":${map?.seed}," +
                    "\"mode\":\"${escape(map?.mode ?: "")}\"," +
                    "\"mapNum\":$mapNum," +
                    "\"localPlayer\":$localPlayer," +
                    "\"shotIndex\":$shotIndex," +
                    "\"mineShot\":${shotJson(mineShot)}," +
                    "\"opponentShot\":${shotJson(opponentShot)}," +
                    "\"mineBallCourse\":${pointJson(mineBallCourse)}," +
                    "\"opponentBallCourse\":${pointJson(opponentBallCourse)}," +
                    "\"mineVelocityCourse\":${pointJson(mineVelocityCourse)}," +
                    "\"opponentVelocityCourse\":${pointJson(opponentVelocityCourse)}" +
                    "}"
        )
    }

    fun frame(
        kind: String,
        map: GolfMap?,
        localPlayer: Int,
        mapNum: Int,
        shotIndex: Int,
        mineBallCourse: PointF,
        opponentBallCourse: PointF?,
        mineVelocityCourse: PointF,
        opponentVelocityCourse: PointF?
    ) {
        if (!ENABLED) return

        liveFrameCounter += 1
        val force =
            liveFrameCounter <= 20 ||
                    liveFrameCounter % 6 == 0 ||
                    speed(mineVelocityCourse) < 20f ||
                    (opponentVelocityCourse != null && speed(opponentVelocityCourse) < 20f)

        if (!force) return

        log(
            "{" +
                    "\"kind\":\"${escape(kind)}\"," +
                    "\"frame\":$liveFrameCounter," +
                    "\"seed\":${map?.seed}," +
                    "\"mode\":\"${escape(map?.mode ?: "")}\"," +
                    "\"mapNum\":$mapNum," +
                    "\"localPlayer\":$localPlayer," +
                    "\"shotIndex\":$shotIndex," +
                    "\"mineBallCourse\":${pointJson(mineBallCourse)}," +
                    "\"opponentBallCourse\":${pointJsonOrNull(opponentBallCourse)}," +
                    "\"mineVelocityCourse\":${pointJson(mineVelocityCourse)}," +
                    "\"opponentVelocityCourse\":${pointJsonOrNull(opponentVelocityCourse)}," +
                    "\"mineSpeed\":${speed(mineVelocityCourse)}," +
                    "\"opponentSpeed\":${opponentVelocityCourse?.let { speed(it) }}" +
                    "}"
        )
    }

    fun contextJsonOrNull(): String {
        val c = contextLocal.get() ?: return "null"
        return "{" + contextJsonFields(c) + ",\"frame\":${frameLocal.get() ?: -1}}"
    }

    private fun contextJsonFields(): String {
        return contextJsonFields(context)
    }

    private fun contextJsonFields(c: Context?): String {
        if (c == null) {
            return "\"runId\":null,\"source\":null,\"slot\":null,\"shotIndex\":null"
        }

        return "\"runId\":\"${escape(c.runId)}\"," +
                "\"source\":\"${escape(c.source)}\"," +
                "\"seed\":${c.seed}," +
                "\"mode\":\"${escape(c.mode)}\"," +
                "\"mapNum\":${c.mapNum}," +
                "\"holeIndex\":${c.holeIndex}," +
                "\"slot\":\"${escape(c.slot)}\"," +
                "\"shotIndex\":${c.shotIndex}," +
                "\"dist\":${c.dist}," +
                "\"rotation\":${c.rotation}"
    }

    private fun log(json: String) {
        OpenPigeonLog.i(TAG, PREFIX + json)
    }

    private fun pointJson(p: PointF): String {
        return "{\"x\":${p.x},\"y\":${p.y}}"
    }

    private fun pointJsonOrNull(p: PointF?): String {
        return if (p == null) "null" else pointJson(p)
    }

    private fun shotJson(shot: GolfReplay.Shot?): String {
        return if (shot == null) {
            "null"
        } else {
            "{\"dist\":${shot.dist},\"rotation\":${shot.rotation}}"
        }
    }

    private fun speed(v: PointF): Float {
        return sqrt(v.x * v.x + v.y * v.y)
    }

    private fun distance(a: PointF, b: PointF): Float {
        val dx = a.x - b.x
        val dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private fun gridJson(map: GolfMap): String {
        return buildString {
            append("[")
            for (x in 0 until map.xCells) {
                if (x > 0) append(",")
                append("\"")
                for (y in 0 until map.yCells) {
                    append(map.grid[x][y])
                }
                append("\"")
            }
            append("]")
        }
    }

    private fun slopesJson(map: GolfMap): String {
        return map.slopes.joinToString(prefix = "[", postfix = "]") { slope ->
            "{" +
                    "\"x\":${slope.x}," +
                    "\"y\":${slope.y}," +
                    "\"vx\":${slope.vx}," +
                    "\"vy\":${slope.vy}," +
                    "\"image\":\"${escape(slope.image)}\"," +
                    "\"rotation\":${slope.rotation}" +
                    "}"
        }
    }

    private fun obstaclesJson(map: GolfMap): String {
        return map.obstacles.joinToString(prefix = "[", postfix = "]") { obstacle ->
            "{" +
                    "\"type\":${obstacle.type}," +
                    "\"x\":${obstacle.x}," +
                    "\"y\":${obstacle.y}," +
                    "\"rotation\":${obstacle.rotation}," +
                    "\"scale\":${obstacle.scale}," +
                    "\"bouncy\":${obstacle.bouncy}," +
                    "\"image\":\"${escape(obstacle.image)}\"" +
                    "}"
        }
    }

    private fun escape(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
    }
}