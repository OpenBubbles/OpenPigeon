package com.example.openbubblesextension

import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4

import org.junit.Test
import org.junit.runner.RunWith

import org.junit.Assert.*

/**
 * Instrumented test, which will execute on an Android device.
 *
 * See [testing documentation](http://d.android.com/tools/testing).
 */
@RunWith(AndroidJUnit4::class)
class ExampleInstrumentedTest {
    @Test
    fun useAppContext() {
        // Context of the app under test.
        val appContext = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals("com.example.openbubblesextension", appContext.packageName)
    }
    @Test
    fun testSwitch() {
        val dataUrl = "data:?ver=52&data=Cs5750rnoC74%25k00baeet5tll.tkr%26C%3D9%26ec,2%26eo%251De6l%3D5%26iEe8sv96dr0%3D4f60oCd,212atbaa7n7k4oC3c3%3Da49.273oeer!ol7c%26m953%25B0m8o9070-Esg0Cs84_0.7pg3er%26s%26im0r,%262dl%25_07o53J_1F7vFvn,%25Bh,iho,e1rtr5,%25Co9%3D12?6s0cUellFnw98da%26a%3DysdtkCy255-0aioi32%3DBs%3Dser2834ec0y-%25lW7dhD91m9c7,s%25sciby0r4mCvlaC,aes,91%266Ceeuip4D5a73rse004%265hh9ogD0y17%25Ul3%26sp%26Cfy.1tb2C6r23Cn-.15C2,a.ooCo-s-b72ge5%26.gkek,l7%3Dad.o9.sma2h%26lV%2515lUe-474Aa%25c50co%3D4eoiy7lCo5o%3DoA4k5d6%3Dp0C3ec51%25s917%3Dy100_%3D%3Ds50_5o0n0o3o8brt%3De.6a,02rul..%26,1_%2506apb1n0%26,,0pLk%26r%3DF%268b3fmrce,_Bcetta7sera51a7t,eClG7l18anh,-1%3D32%25s2ol0r0cA-b%26008sAr590%3DP%25m.%3Die25%2663uF9a025,csa61td2tBik2sv,uc.c%3D0,A7p10s%3D2bbdCn'iB87n"
        val switch = GamePigeon(dataUrl)
        switch.main()
    }
}