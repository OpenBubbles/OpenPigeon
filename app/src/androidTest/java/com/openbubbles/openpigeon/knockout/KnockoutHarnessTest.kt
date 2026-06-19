package com.openbubbles.openpigeon.knockout

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class KnockoutHarnessTest {

    @Test
    fun dumpTrace() {
        val csv = KnockoutHarness.runTrace(360)
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val out = File(ctx.getExternalFilesDir(null), "knock_android_trace.csv")
        out.writeText(csv)
        println("KNOCK_TRACE rows=${csv.lines().size} path=${out.absolutePath}")
    }

    @Test
    fun dumpIosSeedTrace() {
        val csv = KnockoutHarness.runIosSeedTrace(360)
        val args = InstrumentationRegistry.getArguments()
        val outputDir = args.getString("additionalTestOutputDir")

        val outDir = if (!outputDir.isNullOrBlank()) {
            File(outputDir)
        } else {
            val ctx = InstrumentationRegistry.getInstrumentation().targetContext
            ctx.getExternalFilesDir(null)!!
        }

        outDir.mkdirs()

        val out = File(outDir, "knock_android_ios_seed_trace.csv")
        out.writeText(csv)

        println("KNOCK_IOS_SEED_TRACE rows=${csv.lines().size} path=${out.absolutePath}")
    }
}