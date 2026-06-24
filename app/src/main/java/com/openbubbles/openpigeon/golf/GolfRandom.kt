package com.openbubbles.openpigeon.golf

class GolfRandom {
    private var state: Long = (0x1234ABCDL shl 16) or 0x330EL

    fun srand48(seed: Int) {
        state = (((seed.toLong() and 0xFFFFFFFFL) shl 16) or 0x330EL) and MASK
    }

    fun drand48(): Double {
        state = (MULT * state + ADD) and MASK
        return state.toDouble() / TWO_POW_48
    }

    fun nextInt(bound: Int): Int {
        if (bound <= 0) return 0
        return (drand48() * bound).toInt().coerceIn(0, bound - 1)
    }

    fun stateBits(): Long = state

    private companion object {
        const val MULT = 0x5DEECE66DL
        const val ADD = 0xBL
        const val MASK = 0xFFFFFFFFFFFFL
        const val TWO_POW_48 = 281474976710656.0
    }
}
