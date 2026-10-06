package com.openbubbles.openpigeon.pool

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PoolRulesTest {
    private val legalFinish = EightBallFinishFacts(
        eightBallPocketed = true,
        eightBallPresent = true,
        wasBreakShot = false,
        shooterGroupAssigned = true,
        remainingGroupBalls = 0,
        shotWasFoul = false,
        calledPocketSelected = true,
        eightBallInCalledPocket = true,
    )

    @Test
    fun legalCalledEightBallIsAWin() {
        assertTrue(evaluateEightBallFinish(legalFinish) == true)
    }

    @Test
    fun anyDetectedFoulWhilePocketingEightBallIsALoss() {
        assertEquals(
            false,
            evaluateEightBallFinish(legalFinish.copy(shotWasFoul = true)),
        )
    }

    @Test
    fun earlyEightBallIsALoss() {
        assertEquals(
            false,
            evaluateEightBallFinish(legalFinish.copy(remainingGroupBalls = 1)),
        )
    }

    @Test
    fun wrongCalledPocketIsALoss() {
        assertEquals(
            false,
            evaluateEightBallFinish(legalFinish.copy(eightBallInCalledPocket = false)),
        )
    }

    @Test
    fun noCalledPocketIsALoss() {
        assertEquals(
            false,
            evaluateEightBallFinish(legalFinish.copy(calledPocketSelected = false)),
        )
    }

    @Test
    fun unassignedGroupIsALoss() {
        assertEquals(
            false,
            evaluateEightBallFinish(legalFinish.copy(shooterGroupAssigned = false)),
        )
    }

    @Test
    fun missingEightBallStateCannotAwardAWin() {
        assertEquals(
            false,
            evaluateEightBallFinish(legalFinish.copy(eightBallPresent = false)),
        )
    }

    @Test
    fun eightBallOnBreakIsALossUnderCurrentGameRules() {
        assertEquals(
            false,
            evaluateEightBallFinish(legalFinish.copy(wasBreakShot = true)),
        )
    }

    @Test
    fun noEightBallPocketLeavesGameRunning() {
        assertNull(evaluateEightBallFinish(legalFinish.copy(eightBallPocketed = false)))
    }
}
