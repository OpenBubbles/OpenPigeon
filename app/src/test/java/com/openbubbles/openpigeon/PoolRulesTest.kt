package com.openbubbles.openpigeon

import com.openbubbles.openpigeon.pool.determineWinState
import com.openbubbles.openpigeon.pool.isScratch
import org.junit.Assert.*
import org.junit.Test

class PoolRulesTest {

    @Test
    fun `scratch on 8 ball in correct pocket is a loss`() {
        val result = determineWinState(
            blackBallSunk = true,
            cueBallSunk = true,
            remainingBalls = 0,
            blackBallInCalledPocket = true
        )
        assertEquals(false, result)
    }

    @Test
    fun `clean 8 ball in correct pocket with no balls remaining is a win`() {
        val result = determineWinState(
            blackBallSunk = true,
            cueBallSunk = false,
            remainingBalls = 0,
            blackBallInCalledPocket = true
        )
        assertEquals(true, result)
    }

    @Test
    fun `8 ball in wrong pocket is a loss`() {
        val result = determineWinState(
            blackBallSunk = true,
            cueBallSunk = false,
            remainingBalls = 0,
            blackBallInCalledPocket = false
        )
        assertEquals(false, result)
    }

    @Test
    fun `8 ball sunk with remaining balls is a loss`() {
        val result = determineWinState(
            blackBallSunk = true,
            cueBallSunk = false,
            remainingBalls = 2,
            blackBallInCalledPocket = true
        )
        assertEquals(false, result)
    }

    @Test
    fun `8 ball not sunk means no winner yet`() {
        val result = determineWinState(
            blackBallSunk = false,
            cueBallSunk = false,
            remainingBalls = 0,
            blackBallInCalledPocket = true
        )
        assertNull(result)
    }

    @Test
    fun `cue ball sunk while shooting 8 ball with no remaining balls is still a scratch`() {
        val result = isScratch(
            cueBallHitSomething = true,
            cueBallSunk = true,
            ballHitNumber = 8,
            ballHitIsSolid = false,
            ballHitIsStripe = false,
            iAmStripes = false,
            remainingBalls = 0
        )
        assertTrue(result)
    }

    @Test
    fun `hitting 8 ball cleanly with no remaining balls is not a scratch`() {
        val result = isScratch(
            cueBallHitSomething = true,
            cueBallSunk = false,
            ballHitNumber = 8,
            ballHitIsSolid = false,
            ballHitIsStripe = false,
            iAmStripes = false,
            remainingBalls = 0
        )
        assertFalse(result)
    }

    @Test
    fun `not hitting any ball is a scratch`() {
        val result = isScratch(
            cueBallHitSomething = false,
            cueBallSunk = false,
            ballHitNumber = null,
            ballHitIsSolid = false,
            ballHitIsStripe = false,
            iAmStripes = false,
            remainingBalls = 2
        )
        assertTrue(result)
    }

    @Test
    fun `hitting wrong ball type is a scratch`() {
        val result = isScratch(
            cueBallHitSomething = true,
            cueBallSunk = false,
            ballHitNumber = 1,
            ballHitIsSolid = true,
            ballHitIsStripe = false,
            iAmStripes = true, // player is stripes, hit a solid
            remainingBalls = 2
        )
        assertTrue(result)
    }
}
