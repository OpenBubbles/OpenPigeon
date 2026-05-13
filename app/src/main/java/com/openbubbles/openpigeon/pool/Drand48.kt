package com.openbubbles.openpigeon.pool

class Drand48 {
    private var state: Long = 0L

    fun srand48(seed: Long) {
        // POSIX: state high 32 bits = seed low 32, low 16 = 0x330E
        state = ((seed and 0xFFFFFFFFL) shl 16) or 0x330EL
    }

    fun drand48(): Double {
        // LCG: state = (state * 0x5DEECE66D + 0xB) mod 2^48
        state = (state * 0x5DEECE66DL + 0xBL) and 0xFFFFFFFFFFFFL
        return state.toDouble() / (1L shl 48).toDouble()
    }
}