package com.openbubbles.openpigeon.wordhunt

import android.content.Context
import com.openbubbles.openpigeon.wordgames.WordGameLanguage
import com.openbubbles.openpigeon.wordgames.WordGameLanguages
import java.util.HashSet

class WordDictionary(
    context: Context,
    val language: WordGameLanguage,
) {
    private val wordSet = HashSet<String>()

    init {
        context.resources
            .openRawResource(language.dictionaryResource)
            .bufferedReader(Charsets.UTF_8)
            .useLines { lines ->
                lines.forEach { rawLine ->
                    val word = WordGameLanguages.normalizeWord(rawLine)

                    if (
                        word.length >= WordHuntActivity.MIN_WORD_LENGTH &&
                        word.all { character -> character.isLetter() }
                    ) {
                        wordSet.add(word)
                    }
                }
            }
    }

    fun isValidWord(word: String): Boolean {
        return wordSet.contains(
            WordGameLanguages.normalizeWord(word),
        )
    }

    fun size(): Int {
        return wordSet.size
    }
}