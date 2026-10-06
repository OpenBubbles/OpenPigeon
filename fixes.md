# 8-Ball Fix Log

This file records implemented gameplay fixes for OpenPigeon's 8-Ball game.

## F-001: Preserve cue-ball scratches after the native re-spot

- **Problem:** Native code can move the cue ball back onto the table and clear
  its pocket fields before Kotlin evaluates the completed shot. That can erase
  the evidence that the cue ball entered a pocket.
- **Fix:** `PoolTable` now latches the exact cue-ball pocket event for the
  duration of the shot. JNI exposes that state to `PoolActivity`, which combines
  it with the existing UI-side checks when determining whether the shot is a
  foul.
- **Result:** Repositioning the cue ball no longer turns a scratch into a legal
  shot. The latch resets when the next shot begins or the table is cleared.

## F-002: Treat every foul while pocketing the 8-ball as a loss

- **Problem:** The old win condition checked only whether the cue ball was
  pocketed. It could still award a win when the 8-ball entered the called pocket
  during another foul, such as contacting the opponent's ball first.
- **Fix:** The completed shot's full foul result is now passed to
  `evaluateEightBallFinish()`. A pocketed 8-ball can win only when the shot is
  legal, the player's group is cleared, and the called pocket matches.
- **Result:** A cue-ball scratch or any other detected foul while pocketing the
  8-ball ends the game as a loss.
