package com.openbubbles.openpigeon.pool

/**
 * Facts available when an 8-ball shot has stopped.
 *
 * A nullable result from [evaluateEightBallFinish] means that the 8-ball was not
 * pocketed and the game should continue. A non-null result ends the game: true
 * is a win for the shooter and false is a loss.
 */
internal data class EightBallFinishFacts(
    val eightBallPocketed: Boolean,
    val eightBallPresent: Boolean,
    val wasBreakShot: Boolean,
    val shooterGroupAssigned: Boolean,
    val remainingGroupBalls: Int,
    val shotWasFoul: Boolean,
    val calledPocketSelected: Boolean,
    val eightBallInCalledPocket: Boolean,
)

internal fun evaluateEightBallFinish(facts: EightBallFinishFacts): Boolean? {
    if (!facts.eightBallPocketed) {
        return null
    }

    return !(
        facts.wasBreakShot ||
            !facts.shooterGroupAssigned ||
            !facts.eightBallPresent ||
            facts.remainingGroupBalls != 0 ||
            facts.shotWasFoul ||
            !facts.calledPocketSelected ||
            !facts.eightBallInCalledPocket
        )
}
