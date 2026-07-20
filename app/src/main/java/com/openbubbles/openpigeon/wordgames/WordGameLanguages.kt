package com.openbubbles.openpigeon.wordgames

import android.content.Context
import android.util.Log
import androidx.annotation.RawRes
import com.openbubbles.openpigeon.R
import java.text.Normalizer
import java.util.Locale
import kotlin.random.Random

data class WordGameLanguage(
    val code: String,
    val optionLabel: String,
    val subcaption: String?,
    val alphabet: String,
    @RawRes val dictionaryResource: Int,
)

object WordGameLanguages {

    private const val LOG_TAG = "WordGameLanguages"

    val ENGLISH = WordGameLanguage(
        code = "en",
        optionLabel = "English",
        subcaption = null,
        alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        dictionaryResource = R.raw.op_wg_en,
    )

    val GERMAN = WordGameLanguage(
        code = "de",
        optionLabel = "🇩🇪 Deutsch",
        subcaption = "🇩🇪 Deutsch",
        alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ",
        dictionaryResource = R.raw.op_wg_de,
    )

    val SPANISH = WordGameLanguage(
        code = "es",
        optionLabel = "🇪🇸 Español",
        subcaption = "🇪🇸 Español",
        alphabet = "ABCDEFGHIJKLMNÑOPQRSTUVWXYZ",
        dictionaryResource = R.raw.op_wg_es,
    )

    val FRENCH = WordGameLanguage(
        code = "fr",
        optionLabel = "🇫🇷 Français",
        subcaption = "🇫🇷 Français",
        alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        dictionaryResource = R.raw.op_wg_fr,
    )

    val ITALIAN = WordGameLanguage(
        code = "it",
        optionLabel = "🇮🇹 Italiano",
        subcaption = "🇮🇹 Italiano",
        alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        dictionaryResource = R.raw.op_wg_it,
    )

    val RUSSIAN = WordGameLanguage(
        code = "ru",
        optionLabel = "🇷🇺 Русский",
        subcaption = "🇷🇺 Русский",
        alphabet = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ",
        dictionaryResource = R.raw.op_wg_ru,
    )

    val supportedLanguages: List<WordGameLanguage> = listOf(
        ENGLISH,
        SPANISH,
        FRENCH,
        GERMAN,
        RUSSIAN,
        ITALIAN,
    )

    val configurationOptions: List<String> =
        supportedLanguages.map { language ->
            language.optionLabel
        }

    var selectedOptionLabel: String =
        ENGLISH.optionLabel
        private set

    fun select(
        value: String?,
    ): WordGameLanguage {
        val selectedLanguage =
            fromSelection(value)

        selectedOptionLabel =
            selectedLanguage.optionLabel

        return selectedLanguage
    }

    fun fromSelection(
        value: String?,
    ): WordGameLanguage {
        val normalized = value
            ?.trim()
            ?.lowercase(Locale.ROOT)
            .orEmpty()

        return supportedLanguages.firstOrNull { language ->
            language.code == normalized ||
                    language.optionLabel
                        .lowercase(Locale.ROOT) == normalized
        } ?: ENGLISH
    }

    fun fromCode(
        value: String?,
    ): WordGameLanguage {
        val normalized = value
            ?.trim()
            ?.lowercase(Locale.ROOT)
            ?.substringBefore("-")
            ?.substringBefore("_")
            .orEmpty()

        return supportedLanguages.firstOrNull { language ->
            language.code == normalized
        } ?: ENGLISH
    }

    fun applyToGameData(
        gameData: MutableMap<String, String>,
        language: WordGameLanguage,
    ) {
        gameData["lang"] = language.code

        if (language.subcaption.isNullOrBlank()) {
            // English uses no language subcaption.
            gameData.remove("subcaption")
        } else {
            gameData["subcaption"] = language.subcaption
        }
    }

    fun loadDictionary(
        context: Context,
        language: WordGameLanguage,
    ): List<String> {
        return try {
            context.resources
                .openRawResource(language.dictionaryResource)
                .bufferedReader(Charsets.UTF_8)
                .useLines { lines ->
                    lines.mapNotNull { rawLine ->
                        val word = normalizeWord(rawLine)

                        word.takeIf {
                            it.isNotEmpty() &&
                                    it.all { character ->
                                        character.isLetter()
                                    }
                        }
                    }.toList()
                }
        } catch (exception: Exception) {
            Log.e(
                LOG_TAG,
                "Unable to load dictionary " +
                        "for language=${language.code}",
                exception,
            )

            emptyList()
        }
    }

    fun normalizeWord(
        value: String,
    ): String {
        return Normalizer.normalize(
            value.trim(),
            Normalizer.Form.NFC,
        ).uppercase(Locale.ROOT)
    }

    fun randomLetters(
        language: WordGameLanguage,
        count: Int,
        random: Random = Random.Default,
    ): String {
        if (
            count <= 0 ||
            language.alphabet.isEmpty()
        ) {
            return ""
        }

        return buildString(count) {
            repeat(count) {
                append(
                    language.alphabet[
                        random.nextInt(
                            language.alphabet.length,
                        )
                    ],
                )
            }
        }
    }
}