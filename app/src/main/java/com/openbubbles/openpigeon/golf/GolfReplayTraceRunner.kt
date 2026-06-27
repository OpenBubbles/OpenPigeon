package com.openbubbles.openpigeon.golf

import android.graphics.PointF
import com.openbubbles.openpigeon.util.OpenPigeonLog
import kotlin.math.min

object GolfReplayTraceRunner {
    private const val TAG = "GolfNative"

    private const val TRACE_DT_SECONDS = 1f / 60f
    private const val MAX_FRAMES_PER_SHOT = 1200

    /*
     * These anchors are for the known iOS reference case:
     *
     * seed   = 1853352027
     * mapNum = 0
     * mode   = 3
     *
     * The purpose is to test native Box2D from exact iOS positions,
     * without carrying Android's small accumulated drift from shots 0-2.
     */
    private val IOS_ANCHOR_SHOTS = listOf(
        GolfAnchorShot(
            name = "ios_anchor_shot3",
            shotIndex = 3,
            startX = 46.567112f,
            startY = 60.493404f,
            dist = 188.931305f,
            rotation = 1.708533f
        ),
        GolfAnchorShot(
            name = "ios_anchor_shot4",
            shotIndex = 4,
            startX = -4.903124f,
            startY = 304.277740f,
            dist = 60.073299f,
            rotation = -2.299651f
        )
    )

    private data class GolfAnchorShot(
        val name: String,
        val shotIndex: Int,
        val startX: Float,
        val startY: Float,
        val dist: Float,
        val rotation: Float
    )

    private data class ShotTraceResult(
        val captured: Boolean,
        val frameCount: Int
    )

    fun runReplay(
        source: String,
        map: GolfMap,
        holeIndex: Int,
        slot: String,
        replay: String,
        maxShots: Int? = null
    ) {
        if (!GolfTrace.ENABLED) return

        if (replay.isBlank()) {
            logSkipReplayTrace(
                source = source,
                map = map,
                holeIndex = holeIndex,
                slot = slot,
                reason = "blank replay",
                segmentCount = null
            )
            return
        }

        val parsed = GolfReplay.parseNonRace(replay)
        val shots = parsed.getOrNull(holeIndex).orEmpty()

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_TRACE=" +
                    "{" +
                    "\"kind\":\"traceReplayParsed\"," +
                    "\"source\":\"${jsonEscape(source)}\"," +
                    "\"seed\":${map.seed}," +
                    "\"mode\":\"${jsonEscape(map.mode)}\"," +
                    "\"mapNum\":${map.mapNum}," +
                    "\"holeIndex\":$holeIndex," +
                    "\"slot\":\"${jsonEscape(slot)}\"," +
                    "\"rawReplay\":\"${jsonEscape(replay)}\"," +
                    "\"segmentCount\":${parsed.size}," +
                    "\"shotCount\":${shots.size}" +
                    "}"
        )

        if (shots.isEmpty()) {
            logSkipReplayTrace(
                source = source,
                map = map,
                holeIndex = holeIndex,
                slot = slot,
                reason = "no shots for hole index",
                segmentCount = parsed.size
            )
            return
        }

        val limit = min(maxShots ?: shots.size, shots.size).coerceAtLeast(0)
        if (limit <= 0) return

        /*
         * Important:
         * Every replay trace run must be isolated. Otherwise p1_firstShot,
         * p2_firstShot, p1_full, and p2_full can share native table state.
         */
        GolfNativePhysics.reset()

        val ball = startBallForSlot(map, slot)
        var captured = false

        try {
            for (shotIndex in 0 until limit) {
                val shot = shots[shotIndex]
                val velocity = velocityForReplayShot(shot)

                val runId =
                    "${source}_${map.seed}_${map.mapNum}_${slot}_shot$shotIndex"

                val result = runSingleShotTrace(
                    runId = runId,
                    source = source,
                    map = map,
                    holeIndex = holeIndex,
                    slot = slot,
                    shotIndex = shotIndex,
                    dist = shot.dist,
                    rotation = shot.rotation,
                    ball = ball,
                    velocity = velocity,
                    capturedAtStart = captured
                )

                captured = result.captured
            }
        } finally {
            GolfNativePhysics.clearTraceContext()
        }
    }

    /*
     * Call this from the same debug/menu path that currently runs p1_full.
     *
     * It runs isolated native shots from exact iOS start positions:
     *   - ios_anchor_shot3
     *   - ios_anchor_shot4
     *
     * Unlike runReplay(), these shots do NOT chain from Android's previous
     * final position. Each anchor shot resets the native table first.
     */
    fun runIosAnchorShots(
        source: String,
        map: GolfMap,
        holeIndex: Int = 0
    ) {
        if (!GolfTrace.ENABLED) return

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_TRACE=" +
                    "{" +
                    "\"kind\":\"traceAnchorParsed\"," +
                    "\"source\":\"${jsonEscape(source)}\"," +
                    "\"seed\":${map.seed}," +
                    "\"mode\":\"${jsonEscape(map.mode)}\"," +
                    "\"mapNum\":${map.mapNum}," +
                    "\"holeIndex\":$holeIndex," +
                    "\"slot\":\"ios_anchor\"," +
                    "\"anchorCount\":${IOS_ANCHOR_SHOTS.size}" +
                    "}"
        )

        for (anchor in IOS_ANCHOR_SHOTS) {
            /*
             * Reset before each anchor shot so shot3 and shot4 are truly isolated.
             */
            GolfNativePhysics.reset()

            val ball = PointF(anchor.startX, anchor.startY)
            val velocity = velocityForDistAndRotation(
                dist = anchor.dist,
                rotation = anchor.rotation
            )

            val runId =
                "${source}_${map.seed}_${map.mapNum}_${anchor.name}"

            try {
                runSingleShotTrace(
                    runId = runId,
                    source = source,
                    map = map,
                    holeIndex = holeIndex,
                    slot = "ios_anchor",
                    shotIndex = anchor.shotIndex,
                    dist = anchor.dist,
                    rotation = anchor.rotation,
                    ball = ball,
                    velocity = velocity,
                    capturedAtStart = false
                )
            } finally {
                GolfNativePhysics.clearTraceContext()
            }
        }
    }

    private fun runSingleShotTrace(
        runId: String,
        source: String,
        map: GolfMap,
        holeIndex: Int,
        slot: String,
        shotIndex: Int,
        dist: Float,
        rotation: Float,
        ball: PointF,
        velocity: PointF,
        capturedAtStart: Boolean
    ): ShotTraceResult {
        GolfTrace.beginShot(
            runId = runId,
            source = source,
            map = map,
            holeIndex = holeIndex,
            slot = slot,
            shotIndex = shotIndex,
            dist = dist,
            rotation = rotation,
            startPos = ball,
            velocity = velocity
        )

        var frame = 0
        var t = 0f
        var done = false
        var captured = capturedAtStart

        while (frame < MAX_FRAMES_PER_SHOT && !done) {
            GolfTrace.setFrame(frame)

            /*
             * This first context call also configures the native map if needed.
             * Therefore fixture logs are tied to this runId.
             */
            GolfNativePhysics.setTraceContext(
                map = map,
                runId = runId,
                shotIndex = shotIndex,
                frame = frame,
                phase = "beforeStep"
            )

            GolfTrace.frameSample(
                phase = "beforeStep",
                t = t,
                dt = TRACE_DT_SECONDS,
                pos = ball,
                vel = velocity,
                hole = map.hole,
                force = true
            )

            val stoppedByMotion = try {
                GolfNativePhysics.setTraceContext(
                    map = map,
                    runId = runId,
                    shotIndex = shotIndex,
                    frame = frame,
                    phase = "nativeStep"
                )

                GolfPhysics.step(
                    map = map,
                    positionCourse = ball,
                    velocityCourse = velocity,
                    dtSeconds = TRACE_DT_SECONDS
                )
            } finally {
                GolfNativePhysics.clearTraceContext()
            }

            val wasCaptured = captured

            val holeStep = GolfPhysics.applyHoleCup(
                map = map,
                positionCourse = ball,
                velocityCourse = velocity,
                dtSeconds = TRACE_DT_SECONDS,
                alreadyCaptured = captured
            )

            captured = holeStep.captured

            GolfTrace.holeCup(
                phase = "afterApplyHoleCup",
                map = map,
                pos = ball,
                vel = velocity,
                holeStep = holeStep,
                alreadyCaptured = wasCaptured
            )

            t += TRACE_DT_SECONDS

            GolfTrace.frameSample(
                phase = "afterStep",
                t = t,
                dt = TRACE_DT_SECONDS,
                pos = ball,
                vel = velocity,
                hole = map.hole,
                force = true
            )

            done = holeStep.settled || (stoppedByMotion && !holeStep.captured)

            frame += 1
        }

        GolfTrace.endShot(
            reason = if (done) "done" else "maxFrames",
            frameCount = frame,
            t = t,
            pos = ball,
            vel = velocity,
            hole = map.hole
        )

        return ShotTraceResult(
            captured = captured,
            frameCount = frame
        )
    }

    private fun startBallForSlot(map: GolfMap, slot: String): PointF {
        val start = if (slot.equals("p2", ignoreCase = true)) {
            map.ballStart2
        } else {
            map.ballStart1
        }

        return PointF(start.x, start.y)
    }

    private fun velocityForReplayShot(shot: GolfReplay.Shot): PointF {
        return velocityForDistAndRotation(
            dist = shot.dist,
            rotation = shot.rotation
        )
    }

    private fun velocityForDistAndRotation(
        dist: Float,
        rotation: Float
    ): PointF {
        /*
         * Replay rotation is already in course/SpriteKit space.
         * Do NOT call renderer.visualDeltaToCourseDelta here.
         */
        val velocityCourse = GolfShot.launchVelocityVisual(
            GolfShot.Aim(
                dist = dist,
                rotation = rotation
            )
        )

        return PointF(
            velocityCourse.x,
            velocityCourse.y
        )
    }

    private fun logSkipReplayTrace(
        source: String,
        map: GolfMap,
        holeIndex: Int,
        slot: String,
        reason: String,
        segmentCount: Int?
    ) {
        val segmentPart = if (segmentCount != null) {
            ",\"segmentCount\":$segmentCount"
        } else {
            ""
        }

        OpenPigeonLog.i(
            TAG,
            "GOLF_ANDROID_TRACE=" +
                    "{" +
                    "\"kind\":\"skipReplayTrace\"," +
                    "\"source\":\"${jsonEscape(source)}\"," +
                    "\"slot\":\"${jsonEscape(slot)}\"," +
                    "\"seed\":${map.seed}," +
                    "\"mode\":\"${jsonEscape(map.mode)}\"," +
                    "\"mapNum\":${map.mapNum}," +
                    "\"holeIndex\":$holeIndex," +
                    "\"reason\":\"${jsonEscape(reason)}\"" +
                    segmentPart +
                    "}"
        )
    }

    private fun jsonEscape(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
    }
}