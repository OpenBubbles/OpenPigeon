package com.openbubbles.openpigeon.knockout

import java.util.Locale

sealed class KnockoutReplayToken {
    data class BoardToken(val board: KnockoutBoard) : KnockoutReplayToken()
    object ShootToken : KnockoutReplayToken()
}

data class KnockoutBoard(
    val index: Int = 0,
    val pieces: List<KnockoutPieceState> = emptyList()
)

data class KnockoutPieceState(
    val x: Float,
    val y: Float,
    val player: Int,
    val rotation: Float,
    val shootDir: Float,
    val power: Float
)

data class KnockoutReplay(
    val tokens: List<KnockoutReplayToken>,
    val boards: List<KnockoutBoard>,
    val shouldShoot: Boolean
)

object KnockoutReplayParser {
    private const val READY_POWER_EPS = 0.5f

    fun parse(replay: String?): KnockoutReplay {
        if (replay.isNullOrBlank()) return KnockoutReplay(emptyList(), emptyList(), false)

        val tokens = mutableListOf<KnockoutReplayToken>()
        val boards = mutableListOf<KnockoutBoard>()
        var shoot = false

        replay.split('|').forEach { raw ->
            val token = raw.trim()
            when {
                token.startsWith("board:") -> parseBoard(token.removePrefix("board:"))?.let { board ->
                    boards += board
                    tokens += KnockoutReplayToken.BoardToken(board)
                }
                token.startsWith("shoot:") -> {
                    if (token.removePrefix("shoot:").trim().toIntOrNull() == 1) {
                        shoot = true
                        tokens += KnockoutReplayToken.ShootToken
                    }
                }
            }
        }
        return KnockoutReplay(tokens, boards, shoot)
    }

    fun parseBoard(body: String): KnockoutBoard? {
        if (body.isBlank()) return KnockoutBoard(0, emptyList())

        val rawParts = body
            .split('#')
            .map { it.trim() }
            .filter { it.isNotBlank() }

        if (rawParts.isEmpty()) return KnockoutBoard(0, emptyList())

        val possibleIndex = rawParts.firstOrNull()?.toIntOrNull()
        val index: Int
        val pieceParts: List<String>

        if (possibleIndex != null) {
            index = possibleIndex
            pieceParts = rawParts.drop(1)
        } else {
            index = 0
            pieceParts = rawParts
        }

        val pieces = pieceParts.mapNotNull { p ->
            val v = p.split(',').map { it.trim() }

            if (v.size != 6) return@mapNotNull null

            KnockoutPieceState(
                x = v[0].toFloatOrNull() ?: return@mapNotNull null,
                y = v[1].toFloatOrNull() ?: return@mapNotNull null,
                player = v[2].toIntOrNull() ?: return@mapNotNull null,
                rotation = v[3].toFloatOrNull() ?: return@mapNotNull null,
                shootDir = v[4].toFloatOrNull() ?: return@mapNotNull null,
                power = v[5].toFloatOrNull() ?: return@mapNotNull null,
            )
        }

        return KnockoutBoard(index, pieces)
    }

    fun isBoardComplete(board: KnockoutBoard): Boolean {
        return board.pieces.isNotEmpty() && board.pieces.all { it.power > READY_POWER_EPS }
    }

    fun missingPowerPlayers(board: KnockoutBoard): Set<Int> {
        return board.pieces
            .filter { it.power <= READY_POWER_EPS }
            .map { it.player }
            .toSet()
    }

    fun nextBoardToken(tokens: List<KnockoutReplayToken>): KnockoutBoard? {
        return tokens.firstOrNull { it is KnockoutReplayToken.BoardToken }
            ?.let { (it as KnockoutReplayToken.BoardToken).board }
    }

    fun boardFromLivePieces(index: Int, pieces: List<KnockoutPiece>, zeroPower: Boolean = false): KnockoutBoard {
        return KnockoutBoard(
            index = index,
            pieces = pieces.filter { it.alive }.sortedBy { it.traceId }.map { p ->
                KnockoutPieceState(
                    x = p.x,
                    y = p.y,
                    player = p.player,
                    rotation = p.rotation,
                    shootDir = if (zeroPower) 0f else p.shootDir,
                    power = if (zeroPower) 0f else p.power
                )
            }
        )
    }

    fun applyLiveAimsToBoard(board: KnockoutBoard, player: Int, pieces: List<KnockoutPiece>): KnockoutBoard {
        val byTrace = pieces.associateBy { it.traceId }
        return board.copy(
            pieces = board.pieces.mapIndexed { idx, old ->
                val live = byTrace[idx]
                if (old.player == player && live != null) {
                    old.copy(
                        rotation = live.rotation,
                        shootDir = live.shootDir,
                        power = live.power
                    )
                } else {
                    old
                }
            }
        )
    }

    fun clearPowers(board: KnockoutBoard): KnockoutBoard {
        return clearAims(board)
    }

    fun clearAims(board: KnockoutBoard): KnockoutBoard {
        return board.copy(
            pieces = board.pieces.map {
                it.copy(
                    shootDir = 0f,
                    power = 0f
                )
            }
        )
    }

    fun serializeBoard(board: KnockoutBoard): String {
        val body = board.pieces.joinToString("#") { p ->
            String.format(
                Locale.US,
                "%.6f,%.6f,%d,%.6f,%.6f,%.6f",
                p.x,
                p.y,
                p.player,
                p.rotation,
                p.shootDir,
                p.power
            )
        }
        return "board:${board.index}#$body"
    }

    fun serializeBoard(index: Int, pieces: List<KnockoutPiece>, zeroPower: Boolean = false): String {
        return serializeBoard(boardFromLivePieces(index, pieces, zeroPower))
    }

    fun serializeTokens(tokens: List<KnockoutReplayToken>): String {
        return tokens.joinToString("|") { token ->
            when (token) {
                is KnockoutReplayToken.BoardToken -> serializeBoard(token.board)
                KnockoutReplayToken.ShootToken -> "shoot:1"
            }
        }
    }

    fun emptyDefault(): String {
        return "board:0#-100.000000,100.000000,1,0.000000,0.000000,0.000000#-35.000000,100.000000,1,0.000000,0.000000,0.000000#35.000000,100.000000,1,0.000000,0.000000,0.000000#100.000000,100.000000,1,0.000000,0.000000,0.000000#-100.000000,-100.000000,2,3.141593,0.000000,0.000000#-35.000000,-100.000000,2,3.141593,0.000000,0.000000#35.000000,-100.000000,2,3.141593,0.000000,0.000000#100.000000,-100.000000,2,3.141593,0.000000,0.000000"
    }
}
