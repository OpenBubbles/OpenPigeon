package com.openbubbles.openpigeon.wordbites

import android.content.Context
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import kotlin.random.Random

class WordbitesGame : Game {

    override fun getVersion(): String {
        return "1"
    }

    override fun getName(): String {
        return "wordbites"
    }

    override fun displayName(): String {
        return "Word Bites"
    }

    override fun gameClass(): Class<*> {
        return GodotGameActivity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.wordbites
    }

    private fun loadDictionary(context: Context): List<String> {
        val list = mutableListOf<String>()
        context.resources.openRawResource(R.raw.gp_en2).bufferedReader().useLines { lines ->
            lines.forEach { line ->
                val w = line.trim().uppercase()
                if (w.length in 3..9) {
                    list.add(w)
                }
            }
        }
        return list
    }

    private fun chooseLetterBank(dict: List<String>): String {
        val fives = dict.filter { it.length == 5 }
        val fours = dict.filter { it.length == 4 }

        if (fives.size >= 2 && fours.size >= 2) {
            val fiveShuffled = fives.shuffled()
            val fourShuffled = fours.shuffled()

            val w1 = fiveShuffled[0]
            val w2 = fiveShuffled[1]
            val w3 = fourShuffled[0]
            val w4 = fourShuffled[1]

            val combined = (w1 + w2 + w3 + w4).toMutableList()
            combined.shuffle()
            return combined.joinToString("")
        }

        // Fallback: random letters (should basically never happen)
        val randomChars = CharArray(18) { ('A'..'Z').random() }
        return String(randomChars)
    }

    private fun generatePieces(letterBank: String): List<String> {
        val chars = letterBank.toMutableList()

        val singles = mutableListOf<String>()
        val doubles = mutableListOf<String>()

        // --- 6 single-letter tiles ---
        repeat(6) {
            if (chars.isNotEmpty()) {
                singles.add(chars.removeAt(0).toString())
            }
        }

        // --- 6 multi-letter tiles (2 letters each) ---
        repeat(5) {
            if (chars.size >= 2) {
                val a = chars.removeAt(0)
                val b = chars.removeAt(0)
                doubles.add("$a$b")
            }
        }

        // Combine and shuffle so singles/doubles are mixed
        val pieces = mutableListOf<String>()
        pieces.addAll(singles)
        pieces.addAll(doubles)

        return pieces.shuffled()
    }

    private fun toLevelString(pieces: List<String>): String {
        val rand = Random(System.currentTimeMillis())

        repeat(50) {
            val used = Array(9) { BooleanArray(8) }
            val blocked = Array(9) { BooleanArray(8) }
            val result = StringBuilder()
            var failed = false

            fun markPiece(x: Int, y: Int, w: Int, h: Int) {
                // Actual occupied cells
                for (ry in y until y + h) {
                    for (rx in x until x + w) {
                        used[ry][rx] = true
                    }
                }

                // Actual cells + 1-cell buffer
                for (ry in (y - 1)..(y + h)) {
                    for (rx in (x - 1)..(x + w)) {
                        if (ry in 0..8 && rx in 0..7) {
                            blocked[ry][rx] = true
                        }
                    }
                }
            }

            for (run in pieces.shuffled(rand)) {
                val dirs = when (run.length) {
                    1 -> listOf(0)
                    else -> if (rand.nextBoolean()) listOf(1, 2) else listOf(2, 1)
                }

                var placed = false

                // First try with spacing/buffer. If that fails, allow touching but still no overlap.
                for (requireBuffer in listOf(true, false)) {
                    for (dir in dirs) {
                        val w = if (dir == 1) 2 else 1
                        val h = if (dir == 2) 2 else 1
                        val pos = findValidPosition(w, h, used, if (requireBuffer) blocked else null, rand)

                        if (pos != null) {
                            val (x, y) = pos
                            markPiece(x, y, w, h)

                            if (result.isNotEmpty()) result.append("&")
                            result.append("$dir|$x|$y|$run")

                            placed = true
                            break
                        }
                    }

                    if (placed) break
                }

                if (!placed) {
                    failed = true
                    break
                }
            }

            if (!failed) {
                return result.toString()
            }
        }

        // Extremely defensive fallback: should not happen, but never return overlapping 0,0 data.
        throw IllegalStateException("Unable to generate non-overlapping Word Bites board")
    }

    private fun findValidPosition(
        w: Int,
        h: Int,
        used: Array<BooleanArray>,
        blocked: Array<BooleanArray>?,
        rand: Random
    ): Pair<Int, Int>? {
        val maxX = 8 - w
        val maxY = 9 - h
        val candidates = mutableListOf<Pair<Int, Int>>()

        for (y in 0..maxY) {
            for (x in 0..maxX) {
                candidates.add(Pair(x, y))
            }
        }

        candidates.shuffle(rand)

        for ((x, y) in candidates) {
            var ok = true

            // Check actual piece cells first. These can never overlap.
            for (ry in y until y + h) {
                for (rx in x until x + w) {
                    if (used[ry][rx]) {
                        ok = false
                        break
                    }
                }
                if (!ok) break
            }

            if (!ok) continue

            // Optional spacing check.
            if (blocked != null) {
                for (ry in (y - 1)..(y + h)) {
                    for (rx in (x - 1)..(x + w)) {
                        if (ry in 0..8 && rx in 0..7 && blocked[ry][rx]) {
                            ok = false
                            break
                        }
                    }
                    if (!ok) break
                }
            }

            if (ok) {
                return Pair(x, y)
            }
        }

        return null
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)
        return super.getNewGameData(context)?.apply {
            // Match the Godot side expectations
            put("lang", "en")
            put("mode", "1")
            put("letters", "AAA")

            // 1) Load dictionary (same file as Godot: gp_en2)
            val dict = loadDictionary(context)

            // 2) Build a strong letter bank from real words
            val bank = chooseLetterBank(dict)

            // 3) Split into 6 single tiles + 5 multi-letter tiles
            val pieces = generatePieces(bank)

            // 4) Encode into the level string for Godot
            val levelString = toLevelString(pieces)

            // 5) Send it down to Godot
            put("level", levelString)
            put("avatar2", AvatarView.buildAvatarString())
        }
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}
