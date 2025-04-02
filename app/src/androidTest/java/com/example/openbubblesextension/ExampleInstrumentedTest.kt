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
        val cryption = Cryption()
        val basketballDataUrl = "data:?ver=52&data=Cs5750rnoC74%25k00baeet5tll.tkr%26C%3D9%26ec,2%26eo%251De6l%3D5%26iEe8sv96dr0%3D4f60oCd,212atbaa7n7k4oC3c3%3Da49.273oeer!ol7c%26m953%25B0m8o9070-Esg0Cs84_0.7pg3er%26s%26im0r,%262dl%25_07o53J_1F7vFvn,%25Bh,iho,e1rtr5,%25Co9%3D12?6s0cUellFnw98da%26a%3DysdtkCy255-0aioi32%3DBs%3Dser2834ec0y-%25lW7dhD91m9c7,s%25sciby0r4mCvlaC,aes,91%266Ceeuip4D5a73rse004%265hh9ogD0y17%25Ul3%26sp%26Cfy.1tb2C6r23Cn-.15C2,a.ooCo-s-b72ge5%26.gkek,l7%3Dad.o9.sma2h%26lV%2515lUe-474Aa%25c50co%3D4eoiy7lCo5o%3DoA4k5d6%3Dp0C3ec51%25s917%3Dy100_%3D%3Ds50_5o0n0o3o8brt%3De.6a,02rul..%26,1_%2506apb1n0%26,,0pLk%26r%3DF%268b3fmrce,_Bcetta7sera51a7t,eClG7l18anh,-1%3D32%25s2ol0r0cA-b%26008sAr590%3DP%25m.%3Die25%2663uF9a025,csa61td2tBik2sv,uc.c%3D0,A7p10s%3D2bbdCn'iB87n"
        val wordHuntDataUrl = "data:?ver=52&data=5kc59o?a20ai3n2%3D,Ub8C,3of,78i%3D00oCI%2547a%25d.%25a0%3D2%26_NH55t-Htre%260eip0e-5yiY1A04023.or2m5B76Q4%25%25o0UbeI71beEt_5C%25eocfcc2,-C6k04c%3Don99%3DlC0e%26%3DLc%3Dsg,o%26o2lcld62or%2695u%25%25rL2eFsV7CDCln%3De062vm531,al7e.tt-orC528l717CTsW.96,%258%267a5e0h60u3l-ACFcta,atA%3D1h.8y-Scdrn5ot.1Cih2%3D9Zt59-e9ed5Y7te%3DCrnH_O416usn,o,v.yryC05.5%26,kle7,a%3D1.m0%3D0tC7O,Fgc_n58g703!4iT%25C0Ads61,3atn0hn31ACobp02B%26t9,41f%25m2dEo7CDUd4s.r39in_n10e0E%256,nr21x,5qb%267l55%26-HlpC8ihHyae%25DrwehFn%267%3DmB%3D4o0y9rCdp4s,003CeOor9lpmsla7h,00732ai%26al5I0sHA7s%26Vsavs.%3Ds20,u43Bsr%26r%25aVCc3Fa%252t%3Da,toW'k8n7Ch8v,govDe0u%26%26e4udE.t0y%257aoso334r717a4h01.0.0%25rg91"
        println(cryption.decryptUrl(basketballDataUrl))
        println(cryption.decryptUrl(wordHuntDataUrl))
        println(cryption.parseDataUrlToJson(wordHuntDataUrl))
        val wordhunt = WordHunt()
        println(wordhunt.baseData)
        println(wordhunt.newGameData())
    }
}