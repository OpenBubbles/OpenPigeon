package com.example.openbubblesextension.wordhunt

import android.content.Context
import com.example.openbubblesextension.R
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.HashSet

class WordDictionary(context: Context) {
    private val wordSet = HashSet<String>()

    private val inputStream = context.resources.openRawResource(R.raw.gp_en2)
    private val reader = BufferedReader(InputStreamReader(inputStream))

    private var line = reader.readLine()

    init {
        while (line != null) {
            if (line.length >= 3) {
                wordSet.add(line.uppercase())
            }
            line = reader.readLine()
        }

        reader.close()
        inputStream.close()
    }

    fun isValidWord(word: String): Boolean {
        return wordSet.contains(word.uppercase())
    }
}