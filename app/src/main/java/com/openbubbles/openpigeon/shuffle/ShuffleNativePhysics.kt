package com.openbubbles.openpigeon.shuffle

import java.nio.ByteBuffer

object ShuffleNativePhysics {
    init {
        System.loadLibrary("openbubblesextension")
    }

    external fun createShuffleTable(): Long

    external fun destroyShuffleTable(
        tablePtr: Long
    )

    external fun clearShufflePucks(
        tablePtr: Long
    )

    external fun setShuffleMode(
        tablePtr: Long,
        mode: Int
    )

    external fun makeShufflePuck(
        tablePtr: Long,
        x: Float,
        y: Float,
        angle: Float,
        traceId: Int,
        player: Int,
        outputsBuffer: ByteBuffer
    )

    external fun moveShufflePuck(
        tablePtr: Long,
        traceId: Int,
        x: Float,
        y: Float,
        angle: Float
    )

    external fun fireShufflePuck(
        tablePtr: Long,
        traceId: Int,
        shootDirRadians: Float,
        dist: Float
    )

    external fun updateShuffle(
        tablePtr: Long
    ): Boolean

    external fun refreshShuffleOutputs(
        tablePtr: Long
    )
}