package com.openbubbles.openpigeon.pool

// iAmStripes is null until the first ball is sunk and solids/stripes are assigned
fun isScratch(
    cueBallHitSomething: Boolean,
    cueBallSunk: Boolean,
    ballHitNumber: Int?,        // null if cue ball hit nothing
    ballHitIsSolid: Boolean,
    ballHitIsStripe: Boolean,
    iAmStripes: Boolean?,       // null = not yet assigned
    remainingBalls: Int
): Boolean {
    // missed entirely or sunk the cue ball — always a scratch
    if (!cueBallHitSomething || cueBallSunk) return true

    // cueBall hit something but we have no ball info — not a scratch
    if (ballHitNumber == null) return false

    // hitting the 8-ball as your final shot is valid, not a scratch
    if (ballHitNumber == 8 && remainingBalls == 0) return false

    // hitting the opponent's ball type is a foul
    val hitOpponentsBall = iAmStripes != null && if (iAmStripes) ballHitIsSolid else ballHitIsStripe
    return hitOpponentsBall
}

// Returns true = win, false = loss, null = game still in progress
fun determineWinState(
    blackBallSunk: Boolean,
    cueBallSunk: Boolean,
    remainingBalls: Int,
    blackBallInCalledPocket: Boolean
): Boolean? {
    if (!blackBallSunk) return null

    // win only if: no balls left, 8-ball in the called pocket, and no scratch
    return remainingBalls == 0 && blackBallInCalledPocket && !cueBallSunk
}
