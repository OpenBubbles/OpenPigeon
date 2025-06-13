package com.openbubbles.openpigeon.wordhunt

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.toSize
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import kotlin.math.pow
import com.openbubbles.openpigeon.R
import kotlinx.coroutines.delay
import kotlin.math.min
import kotlin.math.sqrt

class GameUI {
    private lateinit var tilePositions: Array<Array<TilePosition>>

    private val fivoSansFamily = FontFamily(
        Font(R.font.fivosans_black, FontWeight.Black),
        Font(R.font.fivosans_heavy, FontWeight.ExtraBold),
        Font(R.font.fivosans_bold, FontWeight.Bold)
    )

    @OptIn(ExperimentalTextApi::class)
    private val interFamily = FontFamily(
        Font(
            R.font.inter_variable,
            variationSettings = FontVariation.Settings(
                FontVariation.weight(800),
            )
        )
    )

    sealed class Screen(val route: String) {
        data object Game : Screen("game")
        data object Score : Screen("score")
    }

    @Composable
    fun WordHuntNavigation(navController: NavHostController, startDestination: String, gameState: WordHuntGameState, onGameStart: () -> Unit, score: () -> MutableMap<String, String>) {

        NavHost(
            navController = navController,
            startDestination = startDestination
        ) {
            composable(
                route = Screen.Game.route,
                exitTransition = {
                    slideOutOfContainer(
                        AnimatedContentTransitionScope.SlideDirection.Left,
                        tween(700)
                    )
                }
            ) {
                GameScreen(
                    gameState = gameState,
                    onGameStart = onGameStart
                )
            }
            composable(
                route = Screen.Score.route,
                enterTransition = {
                    slideIntoContainer(
                        AnimatedContentTransitionScope.SlideDirection.Left,
                        tween(700)
                    )
                }
            ) {
                ScoreScreen(
                    score = score
                )
            }
        }
    }

    @Composable
    fun GameScreen(gameState: WordHuntGameState, onGameStart: () -> Unit) {
        LaunchedEffect(Unit) {
            onGameStart()
        }

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
                    .statusBarsPadding()
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
//                    Image(
//                        painter = painterResource(R.drawable.madrid_icon),
//                        contentDescription = "Icon",
//                        modifier = Modifier
//                            .size(70.dp)
//                    )
                    Column(
                        modifier = Modifier
                            .padding(10.dp, 0.dp, 0.dp, 0.dp),
                        verticalArrangement = Arrangement.spacedBy((-2).dp)
                    ) {
                        Text(
                            text = "WORDS: ${gameState.wordCount}",
                            fontFamily = interFamily,
                            fontWeight = FontWeight.Black,
                            fontSize = 20.sp
                        )
                        Text(
                            text = "SCORE: ${gameState.score.toString().padStart(4, '0')}",
                            fontFamily = interFamily,
                            fontWeight = FontWeight.Black,
                            fontSize = 35.sp,
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
            Image(
                painter = painterResource(gameState.mode.drawable),
                contentDescription = "",
                modifier = Modifier.fillMaxSize()
            )
            Box(
                modifier = Modifier
                    .align(alignment = Alignment.Center)
                    .fillMaxSize()
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
                                val distance = sqrt(
                                    (position.x - centerX).pow(2) +
                                            (position.y - centerY).pow(2)
                                )

                                // Check if within circle
                                val radius =
                                    hitboxScale * min(tileWidth, tileHeight) / 2

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
                                        val curDistance = sqrt(
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
                verticalArrangement = Arrangement.spacedBy((30/gameState.mode.gridSize).dp, Alignment.Top),
                modifier = Modifier
                    .padding(14.dp)
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
                    .size(335.dp) // TODO: fix this to be adaptive
                    .align(Alignment.Center)
            ) {
                val size = LocalDensity.current.run { 335.dp.toPx() }
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
                val pathColor = if(gameState.wordStatus == "INVALID") Color(0xB2FF8491) else Color(0xB2FFFFFF)
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
            horizontalArrangement = Arrangement.spacedBy((30/gameState.mode.gridSize).dp, Alignment.Start),
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
        val isSelected = gameState.selectedPositions.contains(Pair(row, col))
        val isValid = !gameState.mode.invalidPositions.contains(Pair(row, col))

        val scale by animateFloatAsState(
            targetValue = if (isSelected) 1.05f else 1f,
            animationSpec = spring(
                dampingRatio = Spring.DampingRatioLowBouncy,
                stiffness = Spring.StiffnessMediumLow
            ),
            label = "tile_scale"
        )

        val elevation by animateDpAsState(
            targetValue = if (isSelected) 20.dp else if (isValid) 10.dp else 0.dp,
            animationSpec = spring(
                dampingRatio = Spring.DampingRatioLowBouncy,
                stiffness = Spring.StiffnessMediumLow
            ),
            label = "tile_elevation"
        )

        Box(
            modifier = modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                }
                .shadow(
                    elevation = elevation,
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
                }
        ) {
            if (isValid) {
                Image(
                    painter = painterResource(id = R.drawable.wordhunt_letter_bg),
                    contentDescription = "Background",
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(shape = RoundedCornerShape(10.dp)),
                )

                if (isSelected) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .clip(shape = RoundedCornerShape(10.dp))
                            .background(gameState.wordStatusColor.copy(alpha = 0.8f))
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
    fun ScoreScreen(modifier: Modifier = Modifier, score: () -> MutableMap<String, String>) {
        BoxWithConstraints(modifier = Modifier
            .fillMaxSize()
        ) {
            val screenWidth = maxWidth
            val screenHeight = maxHeight

            val scoreData = score()
            // Background
            Image(
                painter = painterResource(R.drawable.wordhunt_background),
                contentDescription = null,
                modifier = Modifier
                    .fillMaxSize(),
                contentScale = ContentScale.Crop
            )

            if (!scoreData["words2"].isNullOrBlank()) {
                var text = "DRAW!"
                var bgColor = Color.White
                var textColor = Color.Black
                if (scoreData["score1"]!!.toInt() > scoreData["score2"]!!.toInt()) {
                    text = "YOU WON!"
                    bgColor = Color(0xffffe535)
                    textColor = Color.Black
                } else if (scoreData["score1"]!!.toInt() < scoreData["score2"]!!.toInt()) {
                    text = "YOU LOST!"
                    bgColor = Color.Black
                    textColor = Color(0xffea5860)
                }
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .statusBarsPadding()
                        .navigationBarsPadding()
                        .background(
                            bgColor,
                            shape = RoundedCornerShape(5.dp)
                        )
                        .padding(3.dp, 0.dp)
                ) {
                    Text(
                        modifier = Modifier.padding(8.dp),
                        text = text,
                        color = textColor,
                        fontSize = 16.sp,
                        fontFamily = interFamily,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxSize(),
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                    verticalAlignment = Alignment.Top,
                    modifier = modifier
                        .fillMaxSize()
                        .weight(1f)
                        .padding(start = screenWidth * 0.03f, end = screenWidth * 0.03f, top = 20.dp, bottom = 10.dp)
                        .statusBarsPadding()
                        .navigationBarsPadding()
                ) {
                    val wordList1 = scoreData["words_list1"]?.takeIf { it.isNotBlank() }?.split("|") ?: emptyList()
                    val wordList2 = scoreData["words_list2"]?.takeIf { it.isNotBlank() }?.split("|") ?: emptyList()

                    PlayerColumn(scoreData["words1"], scoreData["score1"], isLeft = true, wordList = wordList1, modifier = Modifier.weight(1f), screenHeight = screenHeight)
                    PlayerColumn(scoreData["words2"], scoreData["score2"], isLeft = false, wordList = wordList2, modifier = Modifier.weight(1f), screenHeight = screenHeight)
                }

                val dotCount = remember { mutableIntStateOf(1) }
                LaunchedEffect(Unit) {
                    while (true) {
                        dotCount.intValue = dotCount.intValue % 3 + 1
                        delay(500)
                    }
                }

                val dots = ".".repeat(dotCount.intValue)
                val isWaiting = scoreData["words2"].isNullOrBlank()

                Box(
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .padding(bottom = 20.dp)
                        .background(
                            if (isWaiting) Color(0xFF222E1F) else Color.Transparent,
                            shape = RoundedCornerShape(5.dp)
                        )
                        .width(250.dp)
                        .padding(8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        modifier = Modifier.padding(8.dp),
                        text = "Waiting for opponent$dots",
                        color = if (isWaiting) Color.White else Color.Transparent,
                        fontSize = 16.sp,
                        fontFamily = fivoSansFamily,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

        }
    }

    @OptIn(ExperimentalTextApi::class)
    @Composable
    fun PlayerColumn(words: String?, score: String?, wordList: List<String>, isLeft: Boolean, modifier: Modifier, screenHeight: Dp) {
        Column(
            verticalArrangement = Arrangement.spacedBy(5.dp),
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

            val scoreBackground = if (!words.isNullOrBlank()) Color(0xfffdfdfd) else Color.Transparent
            val scoreTextColor = if (!words.isNullOrBlank()) Color.Black else Color(0xFFC7CFC7)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(65.dp)
                    .background(scoreBackground)
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy((-2).dp),
                    horizontalAlignment = if (isLeft) Alignment.Start else Alignment.End,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(horizontal = 5.dp)

                ) {
                    Text(
                        text = "WORDS: ${if(words.isNullOrBlank()) "?" else words}",
                        color = scoreTextColor,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = interFamily,
                        textAlign = if (isLeft) TextAlign.Start else TextAlign.End,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Text(
                        text = "SCORE: ${if(score.isNullOrBlank()) "????" else score.padStart(4, '0')}",
                        color = scoreTextColor,
                        fontSize = 22.sp,
                        fontWeight = FontWeight.ExtraBold,
                        fontFamily = interFamily,
                        textAlign = if (isLeft) TextAlign.Start else TextAlign.End,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }

            val wordItemHeight = 25.dp + 10.dp
            val maxListHeight = screenHeight * 0.68f

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
                    .padding(horizontal = 7.dp, vertical = 7.dp)
            ) {
                visibleWords.forEach { word ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        val wordScoreFont = FontFamily(
                            Font(
                                R.font.inter_variable,
                                variationSettings = FontVariation.Settings(
                                    FontVariation.weight(600),
                                )
                            )
                        )
                        if (isLeft) {
                            WordBox(word)
                            Text(
                                text = WordHuntGameState.calculatePoints(word).toString(),
                                color = Color.White,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = wordScoreFont
                            )
                        } else {
                            Text(
                                text = WordHuntGameState.calculatePoints(word).toString(),
                                color = Color.White,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = wordScoreFont
                            )
                            WordBox(word)
                        }
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

    @Composable
    private fun WordBox(word: String) {
        Box(
            modifier = Modifier
                .wrapContentSize()
                .clip(RoundedCornerShape(3.dp))
                .background(Color(0xffCEAA71))
                .padding(start = 3.dp, end = 3.dp, top = 0.dp, bottom = 0.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = word,
                color = Color.Black,
                fontSize = 15.sp,
                fontWeight = FontWeight.Normal,
                fontFamily = FontFamily(Font(R.font.jellee_roman))
            )
        }
    }


    @Preview(widthDp = 400, heightDp = 700)
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
        fun getScore() = score
        ScoreScreen(Modifier) { getScore() }
    }
}