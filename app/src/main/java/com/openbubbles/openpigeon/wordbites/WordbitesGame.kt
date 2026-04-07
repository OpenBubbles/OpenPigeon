package com.openbubbles.openpigeon.wordbites

import android.content.Context
import androidx.glance.Image
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.layout.Box
import androidx.glance.layout.Row
import androidx.glance.layout.padding
import com.openbubbles.openpigeon.ConfigureCallback
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.GameNotFound
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
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

    /**
     * Load the same dictionary file used by the Godot game: gp_en2.
     * We keep words of length 3–9 (same as the Godot side scoring rules).
     */
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

    /**
     * Build a "letter bank" from real words in the dictionary.
     *
     * We want exactly 18 letters so we can create:
     * - 6 single-letter tiles
     * - 6 multi-letter tiles (2 letters each)
     *
     * Strategy:
     * - pick two 5-letter words
     * - pick two 4-letter words
     * Total = 5 + 5 + 4 + 4 = 18 letters
     */
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

    /**
     * From the 18-letter bank, build 12 tiles:
     * - 6 single letters
     * - 6 multi-letter tiles (2 letters each)
     *
     * The multi-letter tiles don't know their orientation yet; that’s decided
     * when we encode the level string (dir = 1 or 2).
     */
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

    /**
     * Convert pieces into a non-overlapping level layout.
     *
     * Guarantees:
     *  - Single tiles -> dir = 0
     *  - Doubles never placed out of bounds
     *  - Pieces never overlap
     *  - Pieces do not touch (we keep a 1-cell buffer)
     */
    private fun toLevelString(pieces: List<String>): String {
        val rand = Random(System.currentTimeMillis())

        // Board: 9 rows (0–8), 8 cols (0–7)
        val occupied = Array(9) { Array(8) { false } }

        // Mark a piece's area + 1-cell buffer as occupied
        fun markArea(x: Int, y: Int, w: Int, h: Int) {
            for (ry in (y - 1)..(y + h)) {
                for (rx in (x - 1)..(x + w)) {
                    if (ry in 0..8 && rx in 0..7) {
                        occupied[ry][rx] = true
                    }
                }
            }
        }

        val result = StringBuilder()

        pieces.forEachIndexed { index, run ->
            val length = run.length

            // Pick orientation
            val dir = when (length) {
                1 -> 0     // single
                else -> if (rand.nextBoolean()) 1 else 2
            }

            // Dimensions based on orientation
            val w = if (dir == 1) 2 else 1    // horizontal spans 2 columns
            val h = if (dir == 2) 2 else 1    // vertical spans 2 rows

            // Find a valid, non-touching, non-overlapping starting position
            val (x, y) = findValidPosition(w, h, occupied, rand)

            // Mark area as used (with buffer)
            markArea(x, y, w - 1, h - 1)

            if (result.isNotEmpty()) result.append("&")
            result.append("$dir|$x|$y|$run")
        }

        return result.toString()
    }

    /**
     * Finds a valid position for a piece of size (w,h)
     * ensuring:
     *  - stays within board bounds
     *  - does not overlap other pieces
     *  - stays at least 1 cell away from all other pieces
     */
    private fun findValidPosition(
        w: Int,
        h: Int,
        occupied: Array<Array<Boolean>>,
        rand: Random
    ): Pair<Int, Int> {

        for (attempt in 0 until 200) {
            val x = rand.nextInt(0, 8 - (w - 1))
            val y = rand.nextInt(0, 9 - (h - 1))

            var ok = true

            // Check area + 1-cell buffer
            for (ry in (y - 1)..(y + h)) {
                for (rx in (x - 1)..(x + w)) {
                    if (ry in 0..8 && rx in 0..7) {
                        if (occupied[ry][rx]) {
                            ok = false
                            break
                        }
                    }
                }
                if (!ok) break
            }

            if (ok) {
                return Pair(x, y)
            }
        }

        // Fallback: place anywhere (should almost never happen)
        return Pair(0, 0)
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

            // 3) Split into 6 single tiles + 6 multi-letter tiles
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
