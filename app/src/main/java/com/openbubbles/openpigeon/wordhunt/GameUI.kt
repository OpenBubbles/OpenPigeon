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
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
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
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
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
import kotlin.random.Random
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.animation.core.Animatable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.setValue
import androidx.compose.ui.zIndex

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
        data object Intro : Screen("intro")
        data object Game : Screen("game")
        data object Score : Screen("score")
    }

    @Composable
    fun WordHuntNavigation(
        navController: NavHostController,
        startDestination: String,
        gameState: WordHuntGameState,
        onGameStart: () -> Unit,
        score: () -> MutableMap<String, String>
    ) {
        Box(
            modifier = Modifier.fillMaxSize()
        ) {
            // Static background that never moves
            Image(
                painter = painterResource(R.drawable.wordhunt_background),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )

            // Only this foreground content layer transitions
            NavHost(
                navController = navController,
                startDestination = startDestination,
                modifier = Modifier.fillMaxSize()
            ) {
                composable(
                    route = Screen.Intro.route,
                    enterTransition = { null },
                    exitTransition = {
                        slideOutOfContainer(
                            AnimatedContentTransitionScope.SlideDirection.Left,
                            tween(450)
                        )
                    },
                    popEnterTransition = {
                        slideIntoContainer(
                            AnimatedContentTransitionScope.SlideDirection.Right,
                            tween(450)
                        )
                    },
                    popExitTransition = { null }
                ) {
                    IntroScreen(
                        gameState = gameState,
                        onStartClicked = {
                            navController.navigate(Screen.Game.route)
                            onGameStart()
                        }
                    )
                }

                composable(
                    route = Screen.Game.route,
                    enterTransition = {
                        slideIntoContainer(
                            AnimatedContentTransitionScope.SlideDirection.Left,
                            tween(450)
                        )
                    },
                    exitTransition = {
                        slideOutOfContainer(
                            AnimatedContentTransitionScope.SlideDirection.Left,
                            tween(450)
                        )
                    },
                    popEnterTransition = {
                        slideIntoContainer(
                            AnimatedContentTransitionScope.SlideDirection.Right,
                            tween(450)
                        )
                    },
                    popExitTransition = {
                        slideOutOfContainer(
                            AnimatedContentTransitionScope.SlideDirection.Right,
                            tween(450)
                        )
                    }
                ) {
                    GameScreen(
                        gameState = gameState
                    )
                }

                composable(
                    route = Screen.Score.route,
                    enterTransition = {
                        slideIntoContainer(
                            AnimatedContentTransitionScope.SlideDirection.Left,
                            tween(450)
                        )
                    },
                    exitTransition = { null },
                    popEnterTransition = {
                        slideIntoContainer(
                            AnimatedContentTransitionScope.SlideDirection.Right,
                            tween(450)
                        )
                    },
                    popExitTransition = {
                        slideOutOfContainer(
                            AnimatedContentTransitionScope.SlideDirection.Right,
                            tween(450)
                        )
                    }
                ) {
                    ScoreScreen(
                        score = score
                    )
                }
            }
        }
    }

    @Composable
    fun IntroScreen(gameState: WordHuntGameState, onStartClicked: () -> Unit) {
        Box(modifier = Modifier.fillMaxSize()) {
            // Centered how-to card
            Box(
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(horizontal = 32.dp)
                    .shadow(16.dp, RoundedCornerShape(20.dp))
                    .background(Color.White, RoundedCornerShape(20.dp))
                    .padding(24.dp)
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(
                        text = "How to Play",
                        fontSize = 38.sp,
                        fontWeight = FontWeight.ExtraBold,
                        fontFamily = fivoSansFamily,
                        color = Color.Black
                    )
                    Text(
                        text = "Connect letters together by dragging your finger. Make as many words as you can.",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Normal,
                        color = Color(0xFF333333),
                        textAlign = TextAlign.Center
                    )

                    Image(
                        painter = painterResource(R.drawable.wordbites_preview),
                        contentDescription = "Word Bites preview",
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(190.dp)
                            .clip(RoundedCornerShape(12.dp)),
                        contentScale = ContentScale.Fit
                    )

                    // Start button
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .shadow(6.dp, RoundedCornerShape(50.dp))
                            .background(Color(0xFF86FE8C), RoundedCornerShape(50.dp))
                            .clickable { onStartClicked() }
                            .padding(vertical = 14.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "START",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.ExtraBold,
                            fontFamily = fivoSansFamily,
                            color = Color.Black
                        )
                    }
                }
            }
        }
    }

    @Composable
    fun GameScreen(gameState: WordHuntGameState) {
        val context = LocalContext.current
        val validWordTrigger = gameState.validWordTrigger

        LaunchedEffect(validWordTrigger) {
            if (validWordTrigger > 0) {
                vibrateStrongTap(context)
            }
        }

        tilePositions = Array(gameState.mode.gridSize) { Array(gameState.mode.gridSize) { TilePosition() } }

        Box(
            modifier = Modifier.fillMaxSize()
        ) {
            ScoreDisplay(
                gameState = gameState,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 50.dp)
            )

            GameBoard(
                board = gameState.board(),
                gameState = gameState,
                modifier = Modifier
                    .align(Alignment.Center)
                    .offset(x = 0.dp, y = 80.dp)
            )

            if (gameState.currentWord != "") {
                CurrentWordDisplay(
                    gameState = gameState,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .offset(x = 0.dp, y = (-150).dp)
                        .zIndex(2f)
                )
            }

            AwardedWordPopup(
                gameState = gameState,
                modifier = Modifier
                    .align(Alignment.Center)
                    .offset(x = 0.dp, y = (-150).dp)
                    .zIndex(2f)
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
        var displayedScore by remember { mutableIntStateOf(gameState.score) }

        LaunchedEffect(gameState.score) {
            val target = gameState.score
            if (displayedScore == target) return@LaunchedEffect

            while (displayedScore < target) {
                val remaining = target - displayedScore

                val step = maxOf(1, remaining / 3)
                displayedScore = minOf(displayedScore + step, target)

                delay(8L)
            }
        }

        Box(
            modifier = modifier
        ) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = (-20).dp, y = 25.dp)
                    .background(
                        Color.hsl(0.0f, 0.0f, 0.05f, 0.42f),
                        shape = RoundedCornerShape(10.dp)
                    )
                    .padding(8.dp)
                    .size(width = 55.dp, height = 15.dp)
            ) {
                Text(
                    text = formatSeconds(gameState.secondsLeft),
                    color = Color.White,
                    textAlign = TextAlign.Center,
                    fontFamily = fivoSansFamily,
                    fontWeight = FontWeight.ExtraBold,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Box(
                modifier = Modifier
                    .shadow(
                        elevation = 50.dp,
                        shape = TornPaperShape(),
                        clip = false
                    )
                    .clip(TornPaperShape())
                    .background(Color.White)
                    .size(300.dp, 100.dp)
                    .padding(16.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    androidx.compose.ui.viewinterop.AndroidView(
                        factory = { ctx ->
                            com.openbubbles.openpigeon.settings.AvatarView(ctx).apply {
                                applyFromAvatarData()
                            }
                        },
                        modifier = Modifier
                            .size(70.dp, 56.dp)
                            .clip(RoundedCornerShape(8.dp))
                    )

                    Column(
                        modifier = Modifier.padding(start = 10.dp),
                        verticalArrangement = Arrangement.spacedBy((-2).dp)
                    ) {
                        Text(
                            text = "WORDS: ${gameState.wordCount}",
                            fontFamily = interFamily,
                            fontWeight = FontWeight.Black,
                            fontSize = 18.sp,
                            color = Color.Black
                        )

                        Text(
                            text = "SCORE: ${displayedScore.toString().padStart(4, '0')}",
                            fontFamily = interFamily,
                            fontWeight = FontWeight.Black,
                            fontSize = 26.sp,
                            color = Color.Black,
                            maxLines = 1
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
    fun ScoreScreen(
        modifier: Modifier = Modifier,
        score: () -> MutableMap<String, String>
    ) {
        val configuration = androidx.compose.ui.platform.LocalConfiguration.current
        val screenWidth = configuration.screenWidthDp.dp
        val screenHeight = configuration.screenHeightDp.dp
        val scoreData = score()

        Box(
            modifier = modifier.fillMaxSize()
        ) {
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
                        .padding(top = 50.dp)
                        .padding(horizontal = 3.dp)
                        .shadow(10.dp)
                        .background(
                            bgColor,
                            shape = RoundedCornerShape(5.dp)
                        )
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
                modifier = Modifier.fillMaxSize()
            ) {
                val wordList1 = scoreData["words_list1"]
                    ?.takeIf { it.isNotBlank() }
                    ?.split("|")
                    ?: emptyList()

                val wordList2 = scoreData["words_list2"]
                    ?.takeIf { it.isNotBlank() }
                    ?.split("|")
                    ?: emptyList()

                Row(
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                    verticalAlignment = Alignment.Top,
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .padding(
                            start = screenWidth * 0.03f,
                            end = screenWidth * 0.03f,
                            top = 95.dp,
                            bottom = 93.dp
                        )
                ) {
                    PlayerColumn(
                        words = scoreData["words1"],
                        score = scoreData["score1"],
                        wordList = wordList1,
                        isLeft = true,
                        modifier = Modifier.weight(1f),
                        screenHeight = screenHeight,
                        avatarString = null
                    )

                    PlayerColumn(
                        words = scoreData["words2"],
                        score = scoreData["score2"],
                        wordList = wordList2,
                        isLeft = false,
                        modifier = Modifier.weight(1f),
                        screenHeight = screenHeight,
                        avatarString = scoreData["opponent_avatar"]
                    )
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
                            if (isWaiting) Color(0xD2222E1F) else Color.Transparent,
                            shape = RoundedCornerShape(5.dp)
                        )
                        .width(260.dp)
                        .padding(8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        modifier = Modifier.padding(8.dp),
                        text = "WAITING FOR OPPONENT$dots",
                        color = if (isWaiting) Color.White else Color.Transparent,
                        fontSize = 13.sp,
                        fontFamily = fivoSansFamily,
                        fontWeight = FontWeight.ExtraBold
                    )
                }
            }
        }
    }

    private fun vibrateStrongTap(context: Context) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

        if (!vibrator.hasVibrator()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(80, 200))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(80)
        }
    }

    @OptIn(ExperimentalTextApi::class)
    @Composable
    fun PlayerColumn(words: String?, score: String?, wordList: List<String>, isLeft: Boolean, modifier: Modifier, screenHeight: Dp, avatarString: String? = null) {
        Column(
            verticalArrangement = Arrangement.spacedBy(5.dp),
            horizontalAlignment = if (isLeft) Alignment.Start else Alignment.End,
            modifier = modifier
                .fillMaxHeight()
        ) {
            // "You" label + avatar
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.width(80.dp)
            ) {
                Text(
                    text = if (isLeft) "You" else " ",
                    color = if (isLeft) Color.Black else Color.Transparent,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold
                )
                // Avatar — player shows their own, opponent shows received string
                if (isLeft) {
                    androidx.compose.ui.viewinterop.AndroidView(
                        factory = { ctx ->
                            com.openbubbles.openpigeon.settings.AvatarView(ctx).apply {
                                applyFromAvatarData()
                            }
                        },
                        modifier = Modifier
                            .size(80.dp, 64.dp)
                            .clip(RoundedCornerShape(8.dp))
                    )
                } else {
                    androidx.compose.ui.viewinterop.AndroidView(
                        factory = { ctx ->
                            com.openbubbles.openpigeon.settings.AvatarView(ctx).apply {
                                if (!avatarString.isNullOrBlank()) {
                                    applyFromOpponentString(avatarString)
                                } else {
                                    showPlaceholder()
                                }
                            }
                        },
                        update = { view ->
                            if (!avatarString.isNullOrBlank()) {
                                view.applyFromOpponentString(avatarString)
                            } else {
                                view.showPlaceholder()
                            }
                        },
                        modifier = Modifier
                            .size(80.dp, 64.dp)
                            .clip(RoundedCornerShape(8.dp))
                    )
                }
            }

            val scoreBackground = if (!words.isNullOrBlank()) Color(0xfffdfdfd) else Color.Transparent
            val scoreTextColor = if (!words.isNullOrBlank()) Color.Black else Color(0xB2C7CFC7)

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(65.dp)
                    .clip(TornPaperShape())
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
                            color = Color(0xB2C7CFC7),
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

    @Composable
    private fun AwardedWordPopup(
        gameState: WordHuntGameState,
        modifier: Modifier = Modifier
    ) {
        val awardedText = gameState.lastAwardedText
        val trigger = gameState.lastAwardedTrigger

        val scale = remember { Animatable(1f) }
        val popupAlpha = remember { Animatable(0f) }

        LaunchedEffect(trigger) {
            gameState.lastAwardedText ?: return@LaunchedEffect

            scale.snapTo(0.92f)
            popupAlpha.snapTo(1f)

            scale.animateTo(
                targetValue = 1.08f,
                animationSpec = tween(140)
            )

            delay(300)

            popupAlpha.animateTo(
                targetValue = 0f,
                animationSpec = tween(300)
            )

            gameState.clearLastAwardedText()
        }

        if (awardedText != null && popupAlpha.value > 0f) {
            Box(
                modifier = modifier
                    .zIndex(2f)
                    .graphicsLayer {
                        scaleX = scale.value
                        scaleY = scale.value
                        alpha = popupAlpha.value
                    }
                    .background(
                        Color(0xFF86FE8C),
                        shape = RoundedCornerShape(8.dp)
                    )
                    .padding(horizontal = 14.dp, vertical = 8.dp)
            ) {
                Text(
                    text = awardedText,
                    color = Color.Black,
                    fontWeight = FontWeight.ExtraBold,
                    fontSize = 18.sp,
                    fontFamily = fivoSansFamily
                )
            }
        }
    }

    class TornPaperShape(private val tearIntensity: Float = 1f) : Shape {
        override fun createOutline(
            size: Size,
            layoutDirection: LayoutDirection,
            density: Density
        ): Outline {
            // Use a seed based on size to make it consistent across recompositions
            val random = Random(size.width.toInt() + size.height.toInt())

            val path = Path().apply {
                // Very fine tears - scale with component size but keep subtle
                val maxTearHeight = (2f + tearIntensity * 2f) // Maximum 2-6 pixels
                val tearStep = 5f + random.nextFloat() * 4f // Step between tears

                // Start from top-left
                moveTo(0f, 0f)

                // Create fine torn top edge
                var x = 0f
                while (x < size.width) {
                    val tearHeight = random.nextFloat() * maxTearHeight
                    x += tearStep + random.nextFloat() * 4f
                    if (x >= size.width) {
                        lineTo(size.width, random.nextFloat() * maxTearHeight * 0.5f)
                        break
                    } else {
                        lineTo(x, tearHeight)
                    }
                }

                // Straight right edge
                lineTo(size.width, size.height)

                // Create fine torn bottom edge
                x = size.width
                while (x > 0f) {
                    val tearHeight = size.height - (random.nextFloat() * maxTearHeight)
                    x -= tearStep + random.nextFloat() * 4f
                    if (x <= 0f) {
                        lineTo(0f, size.height - random.nextFloat() * maxTearHeight * 0.5f)
                        break
                    } else {
                        lineTo(x, tearHeight)
                    }
                }

                // Straight left edge
                close()
            }
            return Outline.Generic(path)
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