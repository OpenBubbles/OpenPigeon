package com.openbubbles.openpigeon.wordhunt

object WordHuntSolver {
    fun solve(
        board: Array<CharArray>,
        gridSize: Int,
        invalidPositions: List<Pair<Int, Int>>,
        dictionary: WordDictionary,
        minLength: Int,
    ): List<String> {
        val cells = ArrayList<Pair<Int, Int>>()
        val letters = HashMap<Pair<Int, Int>, Char>()
        val allowed = HashSet<Char>()

        for (row in 0 until gridSize) {
            for (col in 0 until gridSize) {
                if (invalidPositions.contains(Pair(row, col))) {
                    continue
                }

                val normalized = dictionary.normalize(board[row][col].toString())

                if (normalized.length != 1) {
                    continue
                }

                cells.add(Pair(row, col))
                letters[Pair(row, col)] = normalized[0]
                allowed.add(normalized[0])
            }
        }

        if (cells.isEmpty()) {
            return dictionary.allWords().sortedWith(
                compareByDescending<String> { WordHuntGameState.calculatePoints(it) }
                    .thenBy { it }
            )
        }

        if (cells.isEmpty()) {
            return dictionary.allWords().sortedWith(
                compareByDescending<String> { WordHuntGameState.calculatePoints(it) }
                    .thenBy { it }
            )
        }

        val root = dictionary.buildTrie(allowed, cells.size)
        val found = HashSet<String>()
        val visited = HashSet<Pair<Int, Int>>()
        val builder = StringBuilder()

        fun walk(cell: Pair<Int, Int>, node: WordDictionary.TrieNode) {
            val letter = letters[cell] ?: return
            val next = node.children[letter] ?: return

            visited.add(cell)
            builder.append(letter)

            if (next.terminal && builder.length >= minLength) {
                found.add(builder.toString())
            }

            if (next.children.isNotEmpty()) {
                for (rowStep in -1..1) {
                    for (colStep in -1..1) {
                        if (rowStep == 0 && colStep == 0) {
                            continue
                        }

                        val neighbour = Pair(cell.first + rowStep, cell.second + colStep)

                        if (
                            neighbour.first in 0 until gridSize &&
                            neighbour.second in 0 until gridSize &&
                            letters.containsKey(neighbour) &&
                            neighbour !in visited
                        ) {
                            walk(neighbour, next)
                        }
                    }
                }
            }

            builder.setLength(builder.length - 1)
            visited.remove(cell)
        }

        for (cell in cells) {
            walk(cell, root)
        }

        return found.sortedWith(
            compareByDescending<String> { WordHuntGameState.calculatePoints(it) }
                .thenBy { it }
        )
    }
}