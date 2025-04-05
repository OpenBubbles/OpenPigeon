package com.example.openbubblesextension

import android.util.Log
import androidx.core.net.toUri
import com.bluebubbles.messaging.MadridMessage
import org.json.JSONObject
import java.net.URLDecoder
import java.net.URLEncoder
import kotlin.math.floor

enum class GAME {
    WORDHUNT,
    BASKETBALL,
}

class Cryption {
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

    private fun decrypt(string: String): String {
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

    fun decryptUrl(url: String): String {
        var slicedUrl = ""
        if (url.startsWith(PREFIX)) {
            slicedUrl = url.substring(PREFIX.length)
        } else {
            assert(false)
        }
        val decodedUrl = URLDecoder.decode(slicedUrl, "UTF-8")
        return decrypt(decodedUrl)
    }

    private fun encrypt(string: String): String {
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

    fun encryptUrl(url: String): String {
        val encryptedUrl = encrypt(url)
        val encodedUrl = URLEncoder.encode(encryptedUrl, "UTF-8")
        return PREFIX.plus(encodedUrl)
    }


    fun parseDataUrlToJson(url: String): JSONObject {
        val uri = decryptUrl(url).toUri() // Use KTX extension function
        val json = JSONObject()

        for (param in uri.queryParameterNames) {
            val value = uri.getQueryParameter(param)?.let { URLDecoder.decode(it, "UTF-8") } ?: ""
            json.put(param, value)
        }

        return json
    }

    fun jsonToDataUrl(json: JSONObject): String {
        val queryParams = json.keys().asSequence()
            .joinToString("&") { key ->
                val value = URLEncoder.encode(json.getString(key), "UTF-8")
                "$key=$value"
            }
        return encryptUrl("?$queryParams")
    }

    fun whichGame(message: MadridMessage?): GAME {
        val game = message?.ldText
        return when (game) {
            "Word Hunt" -> GAME.WORDHUNT
            "Basketball" -> GAME.BASKETBALL
            else -> {
                Log.e("Error", "game not present in Game enum")
                return GAME.WORDHUNT
            }
        }
    }

    companion object {
        private const val PREFIX: String = "data:?ver=52&data="
    }
}