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

    class TrieNode {
        val children = HashMap<Char, TrieNode>()
        var terminal = false
    }

    fun buildTrie(
        allowedLetters: Set<Char>,
        maxLength: Int,
    ): TrieNode {
        val root = TrieNode()

        for (word in wordSet) {
            if (word.length > maxLength) {
                continue
            }

            if (!word.all { character -> character in allowedLetters }) {
                continue
            }

            var node = root

            for (character in word) {
                node = node.children.getOrPut(character) { TrieNode() }
            }

            node.terminal = true
        }

        return root
    }

    fun allWords(): List<String> {
        return wordSet.toList()
    }

    fun normalize(word: String): String {
        return WordGameLanguages.normalizeWord(word)
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