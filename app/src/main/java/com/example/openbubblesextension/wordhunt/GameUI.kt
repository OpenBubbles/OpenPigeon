package com.example.openbubblesextension.wordhunt

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.toSize
import com.bluebubbles.messaging.MadridMessage
import com.example.openbubblesextension.R
import kotlin.math.pow

class GameUI {
    private lateinit var tilePositions: Array<Array<TilePosition>>

    private val fivoSansFamily = FontFamily(
        Font(R.font.fivosans_black, FontWeight.Black),
        Font(R.font.fivosans_heavy, FontWeight.ExtraBold),
        Font(R.font.fivosans_bold, FontWeight.Bold)
    )

    @Composable
    fun GameScreen(gameState: WordHuntGameState) {
        tilePositions = Array(gameState.mode.gridSize) { Array(gameState.mode.gridSize) { TilePosition() } }
        Box(
            modifier = Modifier
                .fillMaxSize()
        ) {
            Image(
                painter = painterResource(R.drawable.wordhunt_background),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )

            ScoreDisplay(
                gameState = gameState,
                modifier = Modifier.align(Alignment.TopCenter)
            )

            if (gameState.currentWord != "") {
                CurrentWordDisplay(
                    gameState = gameState,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .offset(0.dp, (-125).dp)
                )
            }

            GameBoard(
                board = gameState.board(),
                gameState = gameState,
                modifier = Modifier
                    .align(Alignment.Center)
                    .offset(0.dp, 80.dp)
            )
        }
    }

    private fun formatSeconds(totalSeconds: Int): String {
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format("%02d:%02d", minutes, seconds)
    }

    @Composable
    private fun ScoreDisplay(
        gameState: WordHuntGameState,
        modifier: Modifier = Modifier
    ) {
        Box(
            modifier = modifier
        ) {
            //Timer
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .offset((-20).dp, 25.dp)
                    .background(
                        Color.hsl(0.0f, 0.0f, 0.05f,0.42f),
                        shape = RoundedCornerShape(10.dp)
                    )
                    .padding(8.dp, 8.dp)
                    .size(55.dp,15.dp)
            ) {
                Text(
                    text = formatSeconds(gameState.secondsLeft),
                    color = Color.White,
                    textAlign = TextAlign.Center,
                    fontFamily = fivoSansFamily,
                    fontWeight = FontWeight.ExtraBold,
                    modifier = Modifier
                        .fillMaxWidth()
                )
            }
            //Score
            Box (
                modifier = Modifier
                    .shadow(
                        elevation = 50.dp
                    )
                    .background(Color.White)
                    .size(300.dp, 100.dp)
                    .padding(16.dp)
            ) {
                Row {
                    Image(
                        painter = painterResource(R.drawable.madrid_icon),
                        contentDescription = "Icon",
                        modifier = Modifier
                            .size(70.dp)
                    )
                    Column(
                        modifier = Modifier
                            .padding(10.dp, 0.dp, 0.dp, 0.dp)
                    ) {
                        Text(
                            text = "WORDS: ${gameState.wordCount}",
                            fontFamily = fivoSansFamily,
                            fontWeight = FontWeight.Black,
                            fontSize = 20.sp
                        )
                        Text(
                            text = "SCORE: ${gameState.score}",
                            fontFamily = fivoSansFamily,
                            fontWeight = FontWeight.Black,
                            fontSize = 26.sp,
                        )
                    }
                }
            }
        }
    }

    @Composable
    fun GameBoard(
        board: Array<CharArray>,
        gameState: WordHuntGameState,
        modifier: Modifier = Modifier
    ) {
        Box(
            modifier = modifier
                .size(350.dp)
        ) {
            val gameBoardBackground = when (gameState.mode) {
                WordHuntActivity.GameMode.MODE1 -> R.drawable.wordhunt_board_mode1
                WordHuntActivity.GameMode.MODE2 -> R.drawable.wordhunt_board_mode2
                WordHuntActivity.GameMode.MODE3 -> R.drawable.wordhunt_board_mode3
                WordHuntActivity.GameMode.MODE4 -> R.drawable.wordhunt_board_mode1
            }
            Image(
                painter = painterResource(gameBoardBackground),
                contentDescription = "",
                modifier = Modifier.fillMaxSize()
            )
            Box(
                modifier = Modifier
                    .align(alignment = Alignment.Center)
                    .size(330.dp)
                    .clip(shape = RoundedCornerShape(10.dp))
                    .pointerInput(Unit) {
                        val size = this.size.toSize()
                        val tileWidth = size.width / gameState.mode.gridSize
                        val tileHeight = size.height / gameState.mode.gridSize

                        val hitboxScale = 0.9f

                        awaitPointerEventScope {
                            while (gameState.isGameActive) {
                                // Wait for the first touch
                                val downEvent = awaitFirstDown()
                                val position = downEvent.position

                                // Calculate tile position
                                val col = (position.x / tileWidth).toInt().coerceIn(0, gameState.mode.gridSize - 1)
                                val row = (position.y / tileHeight).toInt().coerceIn(0, gameState.mode.gridSize - 1)

                                // Calculate center of that tile
                                val centerX = (col + 0.5f) * tileWidth
                                val centerY = (row + 0.5f) * tileHeight

                                // Calculate distance from center
                                val distance = kotlin.math.sqrt(
                                    (position.x - centerX).pow(2) +
                                            (position.y - centerY).pow(2)
                                )

                                // Check if within circle
                                val radius =
                                    hitboxScale * kotlin.math.min(tileWidth, tileHeight) / 2

                                if (distance <= radius && !gameState.mode.invalidPositions.contains(Pair(row, col))) {
                                    // Start selection on touch down
                                    gameState.startSelection(row, col)

                                    // Now track drag movement
                                    do {
                                        val event = awaitPointerEvent()
                                        val currentPosition = event.changes.first().position

                                        val currentCol =
                                            (currentPosition.x / tileWidth).toInt().coerceIn(0, gameState.mode.gridSize - 1)
                                        val currentRow =
                                            (currentPosition.y / tileHeight).toInt().coerceIn(0, gameState.mode.gridSize - 1)

                                        // Calculate tile center
                                        val curCenterX = (currentCol + 0.5f) * tileWidth
                                        val curCenterY = (currentRow + 0.5f) * tileHeight

                                        // Calculate distance from center
                                        val curDistance = kotlin.math.sqrt(
                                            (currentPosition.x - curCenterX).pow(2) +
                                                    (currentPosition.y - curCenterY).pow(2)
                                        )

                                        if (curDistance <= radius && !gameState.mode.invalidPositions.contains(Pair(currentRow, currentCol))) {
                                            gameState.addToSelection(currentRow, currentCol)
                                        }

                                        // Exit condition - pointer up
                                    } while (event.changes.first().pressed)

                                    // End selection when finger is lifted
                                    gameState.endSelection()
                                }
                            }
                        }
                    })
            Column(
                verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.Top),
                modifier = Modifier
                    .padding(20.dp)
                    .fillMaxSize()
            ) {
                repeat(gameState.mode.gridSize) { row ->
                    TileRow(
                        gameState = gameState,
                        row = row,
                        board = board,
                        modifier = Modifier
                            .weight(weight = 1f/gameState.mode.gridSize))
                }
            }

            Box(
                modifier = Modifier
                    .size(315.dp) // TODO: fix this to be adaptive
                    .align(Alignment.Center)
            ) {
                val size = LocalDensity.current.run { 315.dp.toPx() }
                SelectionPathOverlay(
                    gameState = gameState,
                    tileSize = size / gameState.mode.gridSize,
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }

    @Composable
    fun SelectionPathOverlay(
        gameState: WordHuntGameState,
        tileSize: Float,
        modifier: Modifier = Modifier
    ) {
        val selectedPositions = gameState.selectedPositions

        Canvas(modifier = modifier.fillMaxSize()) {
            if (selectedPositions.isNotEmpty()) {
                // Define path styling
                val pathColor = Color(0xfff76576)
                val strokeWidth = 25f

                // Draw path connecting the tiles
                drawPath(
                    path = Path().apply {
                        // Start at first selected position
                        val firstPos = selectedPositions.first()
                        val startX = (firstPos.second + 0.5f) * tileSize
                        val startY = (firstPos.first + 0.5f) * tileSize
                        moveTo(startX, startY)
                        lineTo(startX, startY)

                        // Draw to each subsequent position
                        for (i in 1 until selectedPositions.size) {
                            val pos = selectedPositions[i]
                            val x = (pos.second + 0.5f) * tileSize
                            val y = (pos.first + 0.5f) * tileSize
                            lineTo(x, y)
                        }
                    },
                    color = pathColor,
                    style = Stroke(width = strokeWidth, cap = StrokeCap.Round, join = StrokeJoin.Round)
                )
            }
        }
    }

    @Composable
    fun TileRow(
        gameState: WordHuntGameState,
        row: Int,
        board: Array<CharArray>,
        modifier: Modifier = Modifier
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.Start),
            verticalAlignment = Alignment.CenterVertically,
            modifier = modifier
                .fillMaxSize()
        ) {
            repeat(gameState.mode.gridSize) { col ->
                Tile(
                    gameState = gameState,
                    row = row,
                    col = col,
                    letter = board[row][col],
                    modifier = Modifier
                        .weight(weight = 1f/gameState.mode.gridSize))
            }
        }
    }

    data class TilePosition(
        var left: Float = 0f,
        var top: Float = 0f,
        var right: Float = 0f,
        var bottom: Float = 0f
    )

    @Composable
    fun Tile(
        gameState: WordHuntGameState,
        row: Int,
        col: Int,
        letter: Char,
        modifier: Modifier = Modifier
    ) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .shadow(
                    elevation = if(!gameState.mode.invalidPositions.contains(Pair(row, col))) 10.dp else 0.dp,
                    shape = RoundedCornerShape(10.dp)
                )
                .onGloballyPositioned { coordinates ->
                    val position = coordinates.positionInParent()
                    val size = coordinates.size
                    tilePositions[row][col] = TilePosition(
                        position.x,
                        position.y,
                        position.x + size.width,
                        position.y + size.height
                    )
                    //Log.d("TilePosition", "Tile[$row][$col]: left=${position.x}, top=${position.y}, right=${position.x + size.width}, bottom=${position.y + size.height}")
                }
        ) {
            if (!gameState.mode.invalidPositions.contains(Pair(row, col))) {
                Image(
                    painter = painterResource(id = R.drawable.wordhunt_letter_bg),
                    contentDescription = "Background",
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(
                            shape = RoundedCornerShape(10.dp)
                        ),
                    //colorFilter = if(gameState.selectedPositions.contains(Pair(row, col))) ColorFilter.tint(gameState.wordStatusColor) else null
                )

                if (gameState.selectedPositions.contains(Pair(row, col))) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .clip(shape = RoundedCornerShape(10.dp))
                            .background(gameState.wordStatusColor.copy(alpha = 0.8f))  // Adjust alpha for transparency
                    )
                }

                Text(
                    text = letter.toString(),
                    color = Color.Black,
                    textAlign = TextAlign.Center,
                    style = TextStyle(
                        fontSize = if (gameState.mode.gridSize == 4) 60.sp else 40.sp,
                        fontWeight = FontWeight.Bold
                    ),
                    modifier = Modifier
                        .fillMaxSize()
                        .wrapContentHeight(align = Alignment.CenterVertically)
                )
            }
        }
    }

    @Composable
    private fun CurrentWordDisplay(
        gameState: WordHuntGameState,
        modifier: Modifier
    ) {
        Box(
            modifier = modifier
                .background(
                    gameState.wordStatusColor,
                    shape = RoundedCornerShape(5.dp)
                )
                .padding(10.dp, 5.dp)
        ) {
            Text(
                text = gameState.currentWord,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp
            )
        }
    }

    @Composable
    fun ScoreScreen(modifier: Modifier = Modifier, score: MutableMap<String, String>) {
        BoxWithConstraints(modifier = Modifier
            .fillMaxSize()
        ) {
            val screenWidth = maxWidth
            val screenHeight = maxHeight

            // Background
            Image(
                painter = painterResource(R.drawable.wordhunt_background),
                contentDescription = null,
                modifier = Modifier
                    .fillMaxSize(),
                contentScale = ContentScale.Crop
            )

            // Layout
            Row(
                horizontalArrangement = Arrangement.spacedBy(24.dp),
                verticalAlignment = Alignment.Top,
                modifier = modifier
                    .fillMaxSize()
                    .padding(horizontal = screenWidth * 0.05f, vertical = screenHeight * 0.05f)
            ) {
                val wordList1 = score["words_list1"]?.takeIf { it.isNotBlank() }?.split("|") ?: emptyList()
                val wordList2 = score["words_list2"]?.takeIf { it.isNotBlank() }?.split("|") ?: emptyList()


                PlayerColumn(score["words1"], score["score1"], isLeft = true, wordList = wordList1, modifier = Modifier.weight(1f), screenHeight = screenHeight)
                PlayerColumn(score["words2"], score["score2"], isLeft = false, wordList = wordList2, modifier = Modifier.weight(1f), screenHeight = screenHeight)
            }
        }
    }

    @Composable
    fun PlayerColumn(words: String?, score: String?, wordList: List<String>, isLeft: Boolean, modifier: Modifier, screenHeight: Dp) {
        Column(
            verticalArrangement = Arrangement.spacedBy(20.dp),
            horizontalAlignment = if (isLeft) Alignment.Start else Alignment.End,
            modifier = modifier
                .fillMaxHeight()
        ) {
            Box(
                modifier = Modifier
                    .width(60.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = if (isLeft) "You" else " ",
                    color = if (isLeft) Color.Black else Color.Transparent,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            Box(
                modifier = Modifier
                    .size(60.dp)
                    .clip(CircleShape)
                    .background(Color(0xffd9d9d9))
            )

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(85.dp)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color(0xfffdfdfd))
                )
                Column(
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    horizontalAlignment = if (isLeft) Alignment.Start else Alignment.End,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(horizontal = 12.dp)
                ) {
                    Text(
                        text = "WORDS: ${words.orEmpty()}",
                        color = Color.Black,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = if (isLeft) TextAlign.Start else TextAlign.End,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Text(
                        text = "SCORE: ${score.orEmpty()}",
                        color = Color.Black,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = if (isLeft) TextAlign.Start else TextAlign.End,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }

            val wordItemHeight = 25.dp + 10.dp
            val maxListHeight = screenHeight * 0.55f

            val maxItems = with(LocalDensity.current) { (maxListHeight / wordItemHeight).toInt() }
            val visibleWords = wordList.take(maxItems)
            val hiddenCount = wordList.size - visibleWords.size

            Column(
                verticalArrangement = Arrangement.spacedBy(10.dp),
                horizontalAlignment = if (isLeft) Alignment.Start else Alignment.End,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .clip(RoundedCornerShape(5.dp))
                    .background(Color(0xff385334))
                    .padding(horizontal = 16.dp, vertical = 29.dp)
            ) {
                visibleWords.forEach { word ->
                    Box(
                        modifier = Modifier
                            .wrapContentWidth()
                            .height(25.dp)
                            .clip(RoundedCornerShape(3.dp))
                            .background(Color(0xfff9edc3))
                            .padding(horizontal = 8.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = word,
                            color = Color.Black,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
                if (hiddenCount > 0) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(25.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "($hiddenCount more)",
                            color = Color.Black,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }


    @Preview(widthDp = 520, heightDp = 800)
    @Composable
    private fun ScoreScreenPreview() {
        val score =  mutableMapOf(
            "score1" to "2100",
            "score2" to "1200",
            "words1" to "2",
            "words2" to "10",
            "words_list1" to "HELP",
            "words_list2" to "THIS|WORLD|BEG|ANOTHER|WORD|UNDER|THE|SEA|GROW|SHOW|UNDER|OVER"
        )
        ScoreScreen(Modifier, score)
    }
}