package com.openbubbles.openpigeon.knockout

object KnockoutHarness {
    init { System.loadLibrary("openbubblesextension") }

    external fun runTrace(frames: Int): String

    external fun runIosSeedTrace(frames: Int): String
}