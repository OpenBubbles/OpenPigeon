package com.openbubbles.openpigeon.knockout

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.Image
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
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.RenderConfigOption
import com.openbubbles.openpigeon.godot.GodotGameActivity
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

class KnockoutGame : Game {

    // ── Runtime map mode from configuration ────────────────────────────────────
    // 1: plain ice, 2: center hole, 3: bouncy mushrooms
    var mode = 1

    // ── Spawn + board sizing (mirror Godot scene) ─────────────────────────────
    private val BOARD_HALF = 327.01f / 2f              // Godot LOGICAL_BOARD_SIZE / 2
    private val POSITION_RANGE = 150f                  // random range
    private val PIECE_RADIUS = 24f                     // matches CircleShape2D
    private val MIN_PIECE_SEPARATION = (PIECE_RADIUS * 2f + 6f)
    private val MAX_SPAWN_ATTEMPTS = 500

    // Map 2: keep pieces fully out of the center hole (radius + safety pad)
    private val CENTER_HOLE_AVOID_RADIUS = 56f

    // Map 3: mushrooms (exactly where Godot spawns them)
    private val MUSHROOM_INSET = 75f
    private val MUSHROOM_TRIGGER_RADIUS = 26f
    // piece center must stay outside mushroom trigger + its own radius (+ small pad)
    private val MUSHROOM_AVOID_RADIUS = (PIECE_RADIUS + MUSHROOM_TRIGGER_RADIUS + 4f)

    // ── Game metadata ─────────────────────────────────────────────────────────
    override fun getVersion(): String = "5"
    override fun getName(): String = "knock"
    override fun displayName(): String = "Knockout"
    override fun isConfigurable(): Boolean = true
    override fun gameClass(): Class<*> = GodotGameActivity::class.java

    @Composable
    override fun Configuration(context: Context?) {
        val maps = listOf("Map 1", "Map 2", "Map 3")
        val selectedMode = maps[mode - 1]
        val keyboardModeImages = arrayOf(
            R.drawable.kom1ph,
            R.drawable.kom2ph,
            R.drawable.kom3ph
        )
        Box(modifier = GlanceModifier.padding(16.dp)) {
            Row(modifier = GlanceModifier.padding(horizontal = 8.dp)) {
                keyboardModeImages.forEachIndexed { index, image ->
                    Image(
                        ImageProvider(image),
                        "Mode",
                        modifier = GlanceModifier
                            .defaultWeight()
                            .padding(horizontal = 8.dp)
                            .clickable(
                                onClick = actionRunCallback<ConfigureCallback>(
                                    actionParametersOf(
                                        ActionParameters.Key<String>("game_name") to getName(),
                                        ActionParameters.Key<String>("configName") to "Map",
                                        ActionParameters.Key<String>("configVal") to maps[index]
                                    )
                                )
                            )
                    )
                }
            }
            RenderConfigOption(this, "Map", maps, selectedMode)
        }
    }

    override fun setConfigOption(name: String, value: String) {
        // value is "Map 1" | "Map 2" | "Map 3"
        mode = value.takeLast(1).toInt()
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        val mode = config?.get("mode")
        return when (mode) {
            "1" -> R.drawable.kom1ph
            "2" -> R.drawable.kom2ph
            "3" -> R.drawable.kom3ph
            else -> R.drawable.kom1ph
        }
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        return super.getNewGameData(context)?.apply {
            put("mode", "$mode")
            put("replay", getDefaultReplay())
        }
    }

    override fun getDefaultReplay(): String {
        // Godot accepts "board:" with our piece list; round number is optional
        return "board:" + generateBoardString()
    }

    // ──────────────────────── SPAWN HELPERS (safety checks) ────────────────────

    private fun mushroomPositions(): List<Pair<Float, Float>> {
        val h = BOARD_HALF
        val i = MUSHROOM_INSET
        return listOf(
            Pair(-h + i, -h + i), // top-left
            Pair(+h - i, -h + i), // top-right
            Pair(-h + i, +h - i), // bottom-left
            Pair(+h - i, +h - i)  // bottom-right
        )
    }

    private fun isInsideCenterHole(x: Float, y: Float): Boolean {
        val d2 = x * x + y * y
        val r = CENTER_HOLE_AVOID_RADIUS
        return d2 < r * r
    }

    private fun isOnAnyMushroom(x: Float, y: Float): Boolean {
        val r2 = MUSHROOM_AVOID_RADIUS * MUSHROOM_AVOID_RADIUS
        for ((mx, my) in mushroomPositions()) {
            val dx = x - mx
            val dy = y - my
            if (dx * dx + dy * dy <= r2) return true
        }
        return false
    }

    private fun tooCloseToExisting(
        x: Float,
        y: Float,
        existing: List<Pair<Float, Float>>
    ): Boolean {
        val r2 = MIN_PIECE_SEPARATION * MIN_PIECE_SEPARATION
        for ((ex, ey) in existing) {
            val dx = x - ex
            val dy = y - ey
            if (dx * dx + dy * dy < r2) return true
        }
        return false
    }

    private fun randomValidPos(
        existing: MutableList<Pair<Float, Float>>,
        mode: Int
    ): Pair<Float, Float> {
        var attempts = 0
        while (attempts++ < MAX_SPAWN_ATTEMPTS) {
            val x = Random.nextFloat() * 2f * POSITION_RANGE - POSITION_RANGE
            val y = Random.nextFloat() * 2f * POSITION_RANGE - POSITION_RANGE

            // Mode-specific keep-out rules
            if (mode == 2 && isInsideCenterHole(x, y)) continue
            if (mode == 3 && isOnAnyMushroom(x, y)) continue

            // Avoid stacking pieces
            if (tooCloseToExisting(x, y, existing)) continue

            return Pair(x, y)
        }

        // Fallback: place around a ring (rarely used)
        val idx = existing.size.coerceAtLeast(1)
        val n = 8 // total pieces
        val angle = (idx % n) / n.toFloat() * (2f * PI).toFloat()
        val baseR = (POSITION_RANGE - MIN_PIECE_SEPARATION).coerceAtLeast(60f)
        var x = cos(angle) * baseR
        var y = sin(angle) * baseR

        // If the fallback still violates a mode rule, nudge outward along the same angle
        if (mode == 2 && isInsideCenterHole(x, y)) {
            val rr = CENTER_HOLE_AVOID_RADIUS + MIN_PIECE_SEPARATION * 0.5f
            x = cos(angle) * rr
            y = sin(angle) * rr
        }
        if (mode == 3 && isOnAnyMushroom(x, y)) {
            val rr = baseR + MUSHROOM_AVOID_RADIUS
            x = cos(angle) * rr
            y = sin(angle) * rr
        }
        return Pair(x, y)
    }

    // ─────────────────────────── Piece list generator ──────────────────────────
    private fun generateBoardString(): String {
        val pieces = mutableListOf<String>()
        val placed = mutableListOf<Pair<Float, Float>>() // keep centers to avoid overlaps

        fun addPiecesForPlayer(player: Int, count: Int) {
            repeat(count) {
                val (px, py) = randomValidPos(placed, mode)
                placed += Pair(px, py)

                val rotation = Random.nextFloat() * 360.0f
                val shootDir = 0.0f
                val power = 0.0f

                pieces += "$px,$py,$player,$rotation,$shootDir,$power"
            }
        }

        addPiecesForPlayer(1, 4)
        addPiecesForPlayer(2, 4)

        println(pieces.joinToString("#"))
        return pieces.joinToString("#")
    }
}
