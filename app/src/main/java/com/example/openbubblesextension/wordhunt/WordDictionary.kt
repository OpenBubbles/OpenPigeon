package com.example.openbubblesextension.wordhunt

import android.content.Context
import com.example.openbubblesextension.R
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.HashSet

class WordDictionary(context: Context) {
    private val wordSet = HashSet<String>()

    init {
        try {
            // Load dictionary from a raw resource file
            // This assumes you have a words.txt file in the res/raw folder
            val inputStream = context.resources.openRawResource(R.raw.words_alpha)
            val reader = BufferedReader(InputStreamReader(inputStream))

            var line = reader.readLine()
            while (line != null) {
                if (line.length >= 3) {
                    wordSet.add(line.uppercase())
                }
                line = reader.readLine()
            }

            reader.close()
            inputStream.close()
        } catch (e: Exception) {
            e.printStackTrace()
            // Fallback with some common words if dictionary fails to load
            addFallbackWords()
        }
    }

    private fun addFallbackWords() {
        // Add some common English words as fallback
        val commonWords = arrayOf(
            "THE", "AND", "THAT", "HAVE", "FOR", "NOT", "WITH", "YOU", "THIS", "BUT",
            "HIS", "FROM", "SAY", "SHE", "WILL", "ONE", "ALL", "WOULD", "THERE", "THEIR",
            "WHAT", "OUT", "ABOUT", "WHO", "GET", "WHICH", "WHEN", "MAKE", "CAN", "LIKE",
            "TIME", "JUST", "HIM", "KNOW", "TAKE", "PEOPLE", "INTO", "YEAR", "YOUR", "GOOD",
            "SOME", "COULD", "THEM", "SEE", "OTHER", "THAN", "THEN", "NOW", "LOOK", "ONLY",
            "COME", "ITS", "OVER", "THINK", "ALSO", "BACK", "AFTER", "USE", "TWO", "HOW",
            "OUR", "WORK", "FIRST", "WELL", "WAY", "EVEN", "NEW", "WANT", "BECAUSE", "ANY",
            "THESE", "GIVE", "DAY", "MOST", "HERE", "GAME", "PLAY", "WORD", "FIND", "PATH"
        )

        wordSet.addAll(commonWords)
    }

    fun isValidWord(word: String): Boolean {
        return wordSet.contains(word.uppercase())
    }
}