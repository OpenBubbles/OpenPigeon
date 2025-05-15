package com.example.openbubblesextension

import android.util.Base64
import android.util.Log
import androidx.core.net.toUri
import com.bluebubbles.messaging.MadridMessage
import org.json.JSONObject
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.Charset
import kotlin.math.floor
import kotlin.random.Random

object Cryption {
    class Rand48(seed: Long) {
        private var n: Long = seed

        fun seed(seed: Long) {
            n = seed
        }

        fun srand(seed: Int) {
            n = ((seed.toLong() shl 16) + 0x330e)
        }

        fun next(): Long {
            n = (25214903917L * n + 11) and (1L shl 48) - 1
            return n
        }

        fun drand(): Double {
            return next().toDouble() / (1L shl 48)
        }

        fun lrand(): Int {
            return (next() shr 17).toInt()
        }

        fun mrand(): Int {
            var num = (next() shr 16).toInt()
            if (num and (1 shl 31) != 0) {
                num -= (1 shl 32)
            }
            return num
        }
    }

    fun decrypt(string: String): String {
        val rand = Rand48(0)
        rand.srand(string.length * 0xef)

        val offsets = mutableListOf<Int>()
        var modifier = 0

        for (char in string) {
            offsets.add(floor(rand.drand() * (modifier + string.length)).toInt())
            modifier--
        }

        var output = ""
        for ((i, offset) in offsets.reversed().withIndex()) {
            val index = string.length - i - 1
            output = output.substring(0, offset) + string[index] + output.substring(offset)
        }

        return output
    }

    fun encrypt(string: String): String {
        val rand = Rand48(0)
        rand.srand(string.length * 0xef)

        var result = ""
        var remaining = string

        for (i in 0 until string.length) {
            val idx = floor(rand.drand() * remaining.length).toInt()
            result += remaining[idx]
            remaining = remaining.substring(0, idx) + remaining.substring(idx + 1)
        }

        return result
    }


    fun getId(): String {
        val randBytes = ByteArray(12)
        Random.nextBytes(randBytes)
        val id = Base64.encodeToString(randBytes, Base64.DEFAULT)
        return id
    }

    private const val PREFIX: String = "data:?ver=52&data="
}