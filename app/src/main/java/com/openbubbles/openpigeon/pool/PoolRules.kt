package com.openbubbles.openpigeon.pool

fun isScratch(
    cueBallHitSomething: Boolean,
    cueBallSunk: Boolean,
    ballHitNumber: Int?,
    ballHitIsSolid: Boolean,
    ballHitIsStripe: Boolean,
    iAmStripes: Boolean?,
    remainingBalls: Int
): Boolean {
    if (!cueBallHitSomething || cueBallSunk) return true
    if (ballHitNumber == null) return false

    if (ballHitNumber == 8 && remainingBalls == 0) return false

    val hitOpponentsBall = iAmStripes != null && if (iAmStripes) ballHitIsSolid else ballHitIsStripe
    return hitOpponentsBall
}

fun determineWinState(
    blackBallSunk: Boolean,
    cueBallSunk: Boolean,
    remainingBalls: Int,
    blackBallInCalledPocket: Boolean
): Boolean? {
    if (!blackBallSunk) return null
    return remainingBalls == 0 && blackBallInCalledPocket && !cueBallSunk
}
