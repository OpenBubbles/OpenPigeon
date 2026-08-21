package com.openbubbles.openpigeon.wordhunt

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
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
import androidx.compose.ui.platform.LocalContext
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
import androidx.compose.ui.zIndex
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.settings.AvatarWinBurstOverlay
import com.openbubbles.openpigeon.ui.TurnRecoveryOverlay
import kotlinx.coroutines.delay
import java.util.Locale
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt
import kotlin.random.Random
import kotlin.time.Duration.Companion.milliseconds

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
            R.font.inter_variable, variationSettings = FontVariation.Settings(
                FontVariation.weight(800),
            )
        )
    )

    sealed class Screen(val route: String) {
        data object Intro : Screen("intro")
        data object Game : Screen("game")
        data object Score : Screen("score")
        data object AllWords : Screen("allwords")
    }

    @Composable
    fun WordHuntNavigation(
        navController: NavHostController,
        startDestination: String,
        gameState: WordHuntGameState,
        spectatorMode: Boolean,
        onGameStart: () -> Unit,
        onExit: () -> Unit,
        pendingSend: Boolean,
        onRetrySend: () -> Unit,
        score: () -> MutableMap<String, String>,
        onRefresh: () -> Unit = {},
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
                            AnimatedContentTransitionScope.SlideDirection.Left, tween(450)
                        )
                    },
                    popEnterTransition = {
                        slideIntoContainer(
                            AnimatedContentTransitionScope.SlideDirection.Right, tween(450)
                        )
                    },
                    popExitTransition = { null }) {
                    BackHandler(onBack = onExit)

                    IntroScreen(
                        onStartClicked = {
                            navController.navigate(
                                Screen.Game.route,
                            ) {
                                launchSingleTop = true

                                popUpTo(
                                    Screen.Intro.route,
                                ) {
                                    inclusive = true
                                }
                            }

                            onGameStart()
                        },
                    )
                }

                composable(route = Screen.Game.route, enterTransition = {
                    slideIntoContainer(
                        AnimatedContentTransitionScope.SlideDirection.Left, tween(450)
                    )
                }, exitTransition = {
                    slideOutOfContainer(
                        AnimatedContentTransitionScope.SlideDirection.Left, tween(450)
                    )
                }, popEnterTransition = {
                    slideIntoContainer(
                        AnimatedContentTransitionScope.SlideDirection.Right, tween(450)
                    )
                }, popExitTransition = {
                    slideOutOfContainer(
                        AnimatedContentTransitionScope.SlideDirection.Right, tween(450)
                    )
                }) {
                    BackHandler(onBack = onExit)

                    GameScreen(
                        gameState = gameState
                    )
                }

                composable(route = Screen.Score.route, enterTransition = {
                    slideIntoContainer(
                        AnimatedContentTransitionScope.SlideDirection.Left, tween(450)
                    )
                }, exitTransition = { null }, popEnterTransition = {
                    slideIntoContainer(
                        AnimatedContentTransitionScope.SlideDirection.Right, tween(450)
                    )
                }, popExitTransition = {
                    slideOutOfContainer(
                        AnimatedContentTransitionScope.SlideDirection.Right, tween(450)
                    )
                }) {
                    BackHandler(onBack = onExit)

                    ScoreScreen(
                        score = score,
                        spectatorMode = spectatorMode,
                        onRefresh = onRefresh,
                        onShowAllWords = {
                            navController.navigate(
                                Screen.AllWords.route,
                            )
                        },
                    )
                }

                composable(route = Screen.AllWords.route, enterTransition = {
                    slideIntoContainer(
                        AnimatedContentTransitionScope.SlideDirection.Left, tween(450)
                    )
                }, exitTransition = { null }, popEnterTransition = { null }, popExitTransition = {
                    slideOutOfContainer(
                        AnimatedContentTransitionScope.SlideDirection.Right, tween(450)
                    )
                }) {
                    val returnToScore = {
                        if (!navController.popBackStack(
                                Screen.Score.route,
                                inclusive = false,
                            )
                        ) {
                            navController.navigate(Screen.Score.route) {
                                launchSingleTop = true
                            }
                        }
                    }

                    BackHandler(onBack = returnToScore)

                    AllWordsScreen(
                        score = score,
                        onBack = returnToScore,
                    )
                }
            }

            TurnRecoveryOverlay(
                visible = pendingSend,
                onRetry = onRetrySend,
            )
        }
    }

    @Composable
    fun IntroScreen(
        onStartClicked: () -> Unit,
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
        ) {
            Box(
                modifier = Modifier
                    .align(
                        Alignment.Center,
                    )
                    .padding(
                        horizontal = 32.dp,
                    )
                    .shadow(
                        elevation = 16.dp,
                        shape = RoundedCornerShape(
                            20.dp,
                        ),
                    )
                    .background(
                        color = Color.White,
                        shape = RoundedCornerShape(
                            20.dp,
                        ),
                    )
                    .padding(
                        24.dp,
                    ),
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(
                        16.dp,
                    ),
                ) {
                    Text(
                        text = "How to Play",
                        fontSize = 38.sp,
                        fontWeight = FontWeight.ExtraBold,
                        fontFamily = fivoSansFamily,
                        color = Color.Black,
                    )

                    Text(
                        text = "Connect letters together by dragging your finger. " + "Make as many words as you can.",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Normal,
                        color = Color(
                            0xFF333333,
                        ),
                        textAlign = TextAlign.Center,
                    )

                    Image(
                        painter = painterResource(
                            R.drawable.wordbites_preview,
                        ),
                        contentDescription = "Word Hunt preview",
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(
                                190.dp,
                            )
                            .clip(
                                RoundedCornerShape(
                                    12.dp,
                                ),
                            ),
                        contentScale = ContentScale.Fit,
                    )

                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .shadow(
                                elevation = 6.dp,
                                shape = RoundedCornerShape(
                                    50.dp,
                                ),
                            )
                            .background(
                                color = Color(
                                    0xFF86FE8C,
                                ),
                                shape = RoundedCornerShape(
                                    50.dp,
                                ),
                            )
                            .clickable(
                                onClick = onStartClicked,
                            )
                            .padding(
                                vertical = 14.dp,
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "START",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.ExtraBold,
                            fontFamily = fivoSansFamily,
                            color = Color.Black,
                        )
                    }
                }
            }
        }
    }

    @Composable
    fun GameScreen(
        gameState: WordHuntGameState,
    ) {
        val context =
            LocalContext.current

        val validWordTrigger =
            gameState.validWordTrigger

        LaunchedEffect(
            validWordTrigger,
        ) {
            if (validWordTrigger > 0) {
                vibrateStrongTap(
                    context,
                )
            }
        }

        tilePositions =
            Array(
                gameState.mode.gridSize,
            ) {
                Array(
                    gameState.mode.gridSize,
                ) {
                    TilePosition()
                }
            }

        BoxWithConstraints(
            modifier = Modifier.fillMaxSize(),
        ) {
            val availableWidth =
                this.maxWidth

            val availableHeight =
                this.maxHeight

            val landscape =
                availableWidth >
                        availableHeight

            val boardSide =
                if (landscape) {
                    minOf(
                        availableHeight * 0.9f,
                        availableWidth * 0.55f,
                    )
                } else {
                    350.dp
                }

            val gutter =
                (
                        availableWidth -
                                boardSide
                        ) / 2

            val scoreScale =
                if (landscape) {
                    (
                            gutter *
                                    0.9f
                            ) / 300.dp
                } else {
                    1f
                }

            ScoreDisplay(
                gameState = gameState,
                modifier = if (landscape) {
                    Modifier
                        .align(
                            Alignment.CenterStart,
                        )
                        .padding(
                            start =
                                gutter * 0.05f,
                        )
                } else {
                    Modifier
                        .align(
                            Alignment.TopCenter,
                        )
                        .padding(
                            top = 50.dp,
                        )
                },
                scale = scoreScale,
            )

            GameBoard(
                board =
                    gameState.board(),
                gameState =
                    gameState,
                modifier = Modifier
                    .align(
                        Alignment.Center,
                    )
                    .offset(
                        x = 0.dp,
                        y = if (landscape) {
                            0.dp
                        } else {
                            80.dp
                        },
                    ),
                boardSide =
                    boardSide,
            )

            if (
                gameState.currentWord
                    .isNotEmpty()
            ) {
                CurrentWordDisplay(
                    gameState =
                        gameState,
                    modifier = Modifier
                        .align(
                            Alignment.Center,
                        )
                        .offset(
                            x = 0.dp,
                            y = (-150).dp,
                        )
                        .zIndex(
                            2f,
                        ),
                )
            }

            AwardedWordPopup(
                gameState =
                    gameState,
                modifier = Modifier
                    .align(
                        Alignment.Center,
                    )
                    .offset(
                        x = 0.dp,
                        y = (-150).dp,
                    )
                    .zIndex(
                        2f,
                    ),
            )
        }
    }

    private fun formatSeconds(totalSeconds: Int): String {
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format(
            Locale.US,
            "%02d:%02d",
            minutes,
            seconds,
        )
    }

    @Composable
    private fun ScoreDisplay(
        gameState: WordHuntGameState,
        modifier: Modifier = Modifier,
        scale: Float = 1f,
    ) {
        var displayedScore by remember { mutableIntStateOf(gameState.score) }

        val formattedScore = displayedScore.toString().padStart(
                4,
                '0',
            )

        val scoreFontSize = when {
            formattedScore.length >= 7 -> 18.sp
            formattedScore.length == 6 -> 20.sp
            formattedScore.length == 5 -> 22.sp
            else -> 26.sp
        } * scale

        LaunchedEffect(gameState.score) {
            val target = gameState.score
            if (displayedScore == target) return@LaunchedEffect

            while (displayedScore < target) {
                val remaining = target - displayedScore

                val step = maxOf(1, remaining / 3)
                displayedScore = minOf(displayedScore + step, target)

                delay(
                    8.milliseconds,
                )
            }
        }

        Box(
            modifier = modifier
        ) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = (-20).dp * scale, y = 25.dp * scale)
                    .background(
                        Color.hsl(0.0f, 0.0f, 0.05f, 0.42f), shape = RoundedCornerShape(10.dp)
                    )
                    .padding(8.dp * scale)
                    .size(width = 55.dp * scale, height = 15.dp * scale)
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
                        elevation = 50.dp * scale, shape = TornPaperShape(), clip = false
                    )
                    .clip(TornPaperShape())
                    .background(Color.White)
                    .size(300.dp * scale, 100.dp * scale)
                    .padding(16.dp * scale)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    androidx.compose.ui.viewinterop.AndroidView(
                        factory = { ctx ->
                            com.openbubbles.openpigeon.settings.AvatarView(ctx).apply {
                                tag = WordHuntActivity.LOCAL_AVATAR_VIEW_TAG
                                applyFromAvatarData()
                            }
                        },
                        update = { avatarView ->
                            avatarView.applyFromAvatarData()
                        },
                        modifier = Modifier
                            .offset(
                                y = (-12).dp * scale,
                            )
                            .size(
                                width = 47.dp * scale,
                                height = 68.dp * scale,
                            ),
                    )

                    Column(
                        modifier = Modifier
                            .padding(
                                start = 10.dp * scale,
                            )
                            .weight(
                                1f,
                            ),
                        verticalArrangement = Arrangement.spacedBy(
                            (-2).dp,
                        ),
                    ) {
                        Text(
                            text = "WORDS: ${gameState.wordCount}",
                            fontFamily = interFamily,
                            fontWeight = FontWeight.Black,
                            fontSize = 18.sp * scale,
                            color = Color.Black
                        )

                        Text(
                            text = "SCORE: $formattedScore",
                            fontFamily = interFamily,
                            fontWeight = FontWeight.Black,
                            fontSize = scoreFontSize,
                            color = Color.Black,
                            maxLines = 1,
                            softWrap = false,
                            modifier = Modifier.fillMaxWidth(),
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
        modifier: Modifier = Modifier,
        boardSide: Dp = 350.dp,
    ) {
        Box(
            modifier = modifier.size(boardSide)
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
                    .pointerInput(boardSide, gameState.mode.gridSize) {
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
                                val col = (position.x / tileWidth).toInt()
                                    .coerceIn(0, gameState.mode.gridSize - 1)
                                val row = (position.y / tileHeight).toInt()
                                    .coerceIn(0, gameState.mode.gridSize - 1)

                                // Calculate center of that tile
                                val centerX = (col + 0.5f) * tileWidth
                                val centerY = (row + 0.5f) * tileHeight

                                // Calculate distance from center
                                val distance = sqrt(
                                    (position.x - centerX).pow(2) + (position.y - centerY).pow(2)
                                )

                                // Check if within circle
                                val radius = hitboxScale * min(tileWidth, tileHeight) / 2

                                if (distance <= radius && !gameState.mode.invalidPositions.contains(
                                        Pair(row, col)
                                    )
                                ) {
                                    // Start selection on touch down
                                    gameState.startSelection(row, col)

                                    // Now track drag movement
                                    do {
                                        val event = awaitPointerEvent()
                                        val currentPosition = event.changes.first().position

                                        val currentCol = (currentPosition.x / tileWidth).toInt()
                                            .coerceIn(0, gameState.mode.gridSize - 1)
                                        val currentRow = (currentPosition.y / tileHeight).toInt()
                                            .coerceIn(0, gameState.mode.gridSize - 1)

                                        // Calculate tile center
                                        val curCenterX = (currentCol + 0.5f) * tileWidth
                                        val curCenterY = (currentRow + 0.5f) * tileHeight

                                        // Calculate distance from center
                                        val curDistance = sqrt(
                                            (currentPosition.x - curCenterX).pow(2) + (currentPosition.y - curCenterY).pow(
                                                2
                                            )
                                        )

                                        if (curDistance <= radius && !gameState.mode.invalidPositions.contains(
                                                Pair(currentRow, currentCol)
                                            )
                                        ) {
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
                verticalArrangement = Arrangement.spacedBy(
                    (30 / gameState.mode.gridSize).dp, Alignment.Top
                ), modifier = Modifier
                    .padding(14.dp)
                    .fillMaxSize()
            ) {
                repeat(gameState.mode.gridSize) { row ->
                    TileRow(
                        gameState = gameState,
                        row = row,
                        board = board,
                        modifier = Modifier.weight(weight = 1f / gameState.mode.gridSize)
                    )
                }
            }

            Box(
                modifier = Modifier
                    .size(boardSide - 15.dp)
                    .align(Alignment.Center)
            ) {
                val size = LocalDensity.current.run { (boardSide - 15.dp).toPx() }
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
        gameState: WordHuntGameState, tileSize: Float, modifier: Modifier = Modifier
    ) {
        val selectedPositions = gameState.selectedPositions

        Canvas(modifier = modifier.fillMaxSize()) {
            if (selectedPositions.isNotEmpty()) {
                // Define path styling
                val pathColor =
                    if (gameState.wordStatus == "INVALID") Color(0xB2FF8491) else Color(0xB2FFFFFF)
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
                    }, color = pathColor, style = Stroke(
                        width = strokeWidth, cap = StrokeCap.Round, join = StrokeJoin.Round
                    )
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
            horizontalArrangement = Arrangement.spacedBy(
                (30 / gameState.mode.gridSize).dp, Alignment.Start
            ), verticalAlignment = Alignment.CenterVertically, modifier = modifier.fillMaxSize()
        ) {
            repeat(gameState.mode.gridSize) { col ->
                Tile(
                    gameState = gameState,
                    row = row,
                    col = col,
                    letter = board[row][col],
                    modifier = Modifier.weight(weight = 1f / gameState.mode.gridSize)
                )
            }
        }
    }

    data class TilePosition(
        var left: Float = 0f, var top: Float = 0f, var right: Float = 0f, var bottom: Float = 0f
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
            targetValue = if (isSelected) 1.05f else 1f, animationSpec = spring(
                dampingRatio = Spring.DampingRatioLowBouncy, stiffness = Spring.StiffnessMediumLow
            ), label = "tile_scale"
        )

        val elevation by animateDpAsState(
            targetValue = if (isSelected) 20.dp else if (isValid) 10.dp else 0.dp,
            animationSpec = spring(
                dampingRatio = Spring.DampingRatioLowBouncy, stiffness = Spring.StiffnessMediumLow
            ),
            label = "tile_elevation"
        )

        Box(modifier = modifier
            .fillMaxSize()
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .shadow(
                elevation = elevation, shape = RoundedCornerShape(10.dp)
            )
            .onGloballyPositioned { coordinates ->
                val position = coordinates.positionInParent()
                val size = coordinates.size
                tilePositions[row][col] = TilePosition(
                    position.x, position.y, position.x + size.width, position.y + size.height
                )
            }) {
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
        gameState: WordHuntGameState, modifier: Modifier
    ) {
        Box(
            modifier = modifier
                .background(
                    gameState.wordStatusColor, shape = RoundedCornerShape(5.dp)
                )
                .padding(10.dp, 5.dp)
        ) {
            Text(
                text = gameState.currentWord, fontWeight = FontWeight.Bold, fontSize = 16.sp
            )
        }
    }

    @Composable
    fun ScoreScreen(
        modifier: Modifier = Modifier,
        score: () -> MutableMap<String, String>,
        spectatorMode: Boolean = false,
        onShowAllWords: () -> Unit = {},
        onRefresh: () -> Unit = {},
    ) {
        val scoreData = score()

        val winnerSlot = scoreData["winner_slot"].orEmpty()

        val parsedScore1 = scoreData["score1"]?.toIntOrNull()

        val parsedScore2 = scoreData["score2"]?.toIntOrNull()

        val bothPlayersFinished =
            (!scoreData["words1"].isNullOrBlank() && !scoreData["words2"].isNullOrBlank() && parsedScore1 != null && parsedScore2 != null)

        BoxWithConstraints(
            modifier = modifier.fillMaxSize(),
        ) {
            val screenWidth = this.maxWidth
            val screenHeight = this.maxHeight
            val landscape = screenWidth > screenHeight
            val avatarScale = if (landscape) 0.62f else 1f

            if (spectatorMode) {
                Text(
                    text = "Spectating...",
                    color = Color.White,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .align(
                            Alignment.TopCenter,
                        )
                        .padding(
                            top = 30.dp,
                        )
                        .zIndex(
                            3f,
                        ),
                )
            }

            if (bothPlayersFinished) {
                val (
                    text,
                    bgColor,
                    textColor,
                ) = when {
                    parsedScore1 > parsedScore2 -> {
                        Triple(
                            if (spectatorMode) {
                                "PLAYER 1 WINS!"
                            } else {
                                "YOU WON!"
                            },
                            Color(
                                0xFFFFE535,
                            ),
                            Color.Black,
                        )
                    }

                    parsedScore1 < parsedScore2 -> {
                        Triple(
                            if (spectatorMode) {
                                "PLAYER 2 WINS!"
                            } else {
                                "YOU LOST!"
                            },
                            Color.Black,
                            Color(
                                0xFFEA5860,
                            ),
                        )
                    }

                    else -> {
                        Triple(
                            "DRAW!",
                            Color.White,
                            Color.Black,
                        )
                    }
                }

                Box(
                    modifier = Modifier
                        .align(
                            Alignment.TopCenter,
                        )
                        .padding(
                            top = if (spectatorMode) {
                                68.dp
                            } else {
                                50.dp
                            },
                        )
                        .padding(
                            horizontal = 3.dp,
                        )
                        .shadow(
                            10.dp,
                        )
                        .background(
                            bgColor,
                            shape = RoundedCornerShape(
                                5.dp,
                            ),
                        )
                        .zIndex(
                            2f,
                        ),
                ) {
                    Text(
                        modifier = Modifier.padding(
                            8.dp,
                        ),
                        text = text,
                        color = textColor,
                        fontSize = 16.sp,
                        fontFamily = interFamily,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }

            Column(
                modifier = Modifier.fillMaxSize(),
            ) {
                val wordList1 = scoreData["words_list1"]?.takeIf {
                    it.isNotBlank()
                }?.split(
                    "|",
                ) ?: emptyList()

                val wordList2 = scoreData["words_list2"]?.takeIf {
                    it.isNotBlank()
                }?.split(
                    "|",
                ) ?: emptyList()

                Row(
                    horizontalArrangement = Arrangement.spacedBy(
                        24.dp,
                    ),
                    verticalAlignment = Alignment.Top,
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(
                            1f,
                        )
                        .padding(
                            start = screenWidth * 0.03f,
                            end = screenWidth * 0.03f,
                            top = if (landscape) {
                                if (spectatorMode) 62.dp else 46.dp
                            } else {
                                if (spectatorMode) 120.dp else 95.dp
                            },
                            bottom = if (landscape) 8.dp else 93.dp,
                        ),
                ) {
                    PlayerColumn(
                        words = scoreData["words1"],
                        score = scoreData["score1"],
                        wordList = wordList1,
                        isLeft = true,
                        modifier = Modifier.weight(
                            1f,
                        ),
                        avatarScale = avatarScale,
                        avatarString = if (spectatorMode) {
                            scoreData["avatar1"]
                        } else {
                            null
                        },
                        useLocalAvatar = !spectatorMode,
                        playerLabel = if (spectatorMode) {
                            "Player 1"
                        } else {
                            "You"
                        },
                        showWinBurst = (bothPlayersFinished && (winnerSlot == "local" || winnerSlot == "draw")),
                    )

                    PlayerColumn(
                        words = scoreData["words2"],
                        score = scoreData["score2"],
                        wordList = wordList2,
                        isLeft = false,
                        modifier = Modifier.weight(
                            1f,
                        ),
                        avatarScale = avatarScale,
                        avatarString = if (spectatorMode) {
                            scoreData["avatar2"]
                        } else {
                            scoreData["opponent_avatar"]
                        },
                        useLocalAvatar = false,
                        playerLabel = if (spectatorMode) {
                            "Player 2"
                        } else {
                            ""
                        },
                        showWinBurst = (bothPlayersFinished && (winnerSlot == "opponent" || winnerSlot == "draw")),
                    )
                }

                val dotCount = remember {
                    mutableIntStateOf(
                        1,
                    )
                }

                LaunchedEffect(Unit) {
                    while (true) {
                        dotCount.intValue = (dotCount.intValue % 3 + 1)

                        delay(
                            500.milliseconds,
                        )
                    }
                }

                val dots = ".".repeat(
                    dotCount.intValue,
                )

                val isWaiting = if (spectatorMode) {
                    (scoreData["words1"].isNullOrBlank() || scoreData["words2"].isNullOrBlank())
                } else {
                    scoreData["words2"].isNullOrBlank()
                }

                LaunchedEffect(isWaiting) {
                    while (isWaiting) {
                        delay(1000.milliseconds)
                        onRefresh()
                    }
                }

                if (bothPlayersFinished) {
                    Box(
                        modifier = Modifier
                            .align(
                                Alignment.CenterHorizontally,
                            )
                            .padding(
                                bottom = 20.dp,
                            )
                            .shadow(
                                elevation = 6.dp,
                                shape = RoundedCornerShape(
                                    10.dp,
                                ),
                            )
                            .background(
                                color = Color.White,
                                shape = RoundedCornerShape(
                                    10.dp,
                                ),
                            )
                            .clickable(
                                onClick = onShowAllWords,
                            )
                            .width(
                                260.dp,
                            )
                            .padding(
                                vertical = 14.dp,
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "VIEW ALL WORDS",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.ExtraBold,
                            fontFamily = fivoSansFamily,
                            color = Color.Black,
                        )
                    }

                    return@Column
                }

                Box(
                    modifier = Modifier
                        .align(
                            Alignment.CenterHorizontally,
                        )
                        .padding(
                            bottom = 20.dp,
                        )
                        .background(
                            if (isWaiting) {
                                Color(
                                    0xD2222E1F,
                                )
                            } else {
                                Color.Transparent
                            },
                            shape = RoundedCornerShape(
                                5.dp,
                            ),
                        )
                        .width(
                            260.dp,
                        )
                        .padding(
                            8.dp,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        modifier = Modifier.padding(
                            8.dp,
                        ),
                        text = "WAITING FOR OPPONENT$dots",
                        color = if (isWaiting) {
                            Color.White
                        } else {
                            Color.Transparent
                        },
                        fontSize = 13.sp,
                        fontFamily = fivoSansFamily,
                        fontWeight = FontWeight.ExtraBold,
                    )
                }
            }
        }
    }

    @Composable
    private fun WordPathPopup(
        board: String,
        gridSize: Int,
        invalid: Set<Int>,
        path: List<Int>,
        onDismiss: () -> Unit,
    ) {
        val pathCells = path.toSet()

        val fade = remember { Animatable(0f) }

        LaunchedEffect(Unit) {
            fade.animateTo(
                targetValue = 1f,
                animationSpec = tween(
                    durationMillis = 160,
                    easing = LinearOutSlowInEasing,
                ),
            )
        }

        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    alpha = fade.value
                }
                .background(
                    Color(
                        0x99000000,
                    ),
                )
                .clickable(
                    onClick = onDismiss,
                )
                .zIndex(
                    3f,
                ),
            contentAlignment = Alignment.Center,
        ) {
            val boardSide = minOf(
                this.maxWidth * 0.66f,
                this.maxHeight * 0.44f,
            )

            Box(
                modifier = Modifier
                    .clip(
                        RoundedCornerShape(
                            10.dp,
                        ),
                    )
                    .background(
                        Color(
                            0xfffdfdfd,
                        ),
                    )
                    .padding(
                        10.dp,
                    ),
            ) {
                Box(
                    modifier = Modifier.size(
                        boardSide,
                    ),
                ) {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        repeat(gridSize) { row ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .weight(
                                        1f,
                                    ),
                            ) {
                                repeat(gridSize) { col ->
                                    val index = row * gridSize + col

                                    Box(
                                        modifier = Modifier
                                            .fillMaxHeight()
                                            .weight(
                                                1f,
                                            )
                                            .padding(
                                                2.dp,
                                            )
                                            .clip(
                                                RoundedCornerShape(
                                                    4.dp,
                                                ),
                                            )
                                            .background(
                                                when {
                                                    invalid.contains(index) -> Color.Transparent
                                                    pathCells.contains(index) -> Color(0xffE0B052)
                                                    else -> Color(0xffF2DE8A)
                                                },
                                            ),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        if (!invalid.contains(index)) {
                                            Text(
                                                text = board[index].toString(),
                                                color = Color(
                                                    0xff385334,
                                                ),
                                                fontSize = (boardSide.value / gridSize * 0.42f).sp,
                                                fontWeight = FontWeight.ExtraBold,
                                                fontFamily = interFamily,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Canvas(
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        val step = size.width / gridSize

                        val centres = path.map { index ->
                            Offset(
                                x = (index % gridSize + 0.5f) * step,
                                y = (index / gridSize + 0.5f) * step,
                            )
                        }

                        for (i in 0 until centres.size - 1) {
                            drawLine(
                                color = Color(
                                    0xcc2C4128,
                                ),
                                start = centres[i],
                                end = centres[i + 1],
                                strokeWidth = step * 0.13f,
                                cap = StrokeCap.Round,
                            )
                        }

                        centres.firstOrNull()?.let { start ->
                            drawCircle(
                                color = Color(
                                    0xcc2C4128,
                                ),
                                radius = step * 0.17f,
                                center = start,
                            )
                        }
                    }
                }
            }
        }
    }

    @Composable
    fun AllWordsScreen(
        score: () -> MutableMap<String, String>,
        onBack: () -> Unit,
    ) {
        val scoreData = score()

        val words = scoreData["all_words"]?.takeIf {
            it.isNotBlank()
        }?.split(
            "|",
        ) ?: emptyList()

        val foundWords = remember(scoreData["words_list1"]) {
            scoreData["words_list1"]?.takeIf {
                it.isNotBlank()
            }?.split(
                "|",
            )?.toSet() ?: emptySet()
        }

        val paths = scoreData["all_paths"]?.takeIf {
            it.isNotBlank()
        }?.split(
            "|",
        ) ?: emptyList()

        val board = scoreData["board"].orEmpty()

        val gridSize = scoreData["grid_size"]?.toIntOrNull()
            ?: sqrt(board.length.toFloat()).toInt().coerceAtLeast(1)

        val invalidCells = remember(scoreData["invalid_cells"]) {
            WordHuntSolver.decodePath(
                scoreData["invalid_cells"].orEmpty(),
            ).toSet()
        }

        var selected by remember { mutableIntStateOf(-1) }

        val listScroll = rememberScrollState()

        Box(
            modifier = Modifier.fillMaxSize(),
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(
                        listScroll,
                    )
                    .padding(
                        top = 90.dp,
                        bottom = 24.dp,
                    ),
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(
                        6.dp,
                    ),
                    modifier = Modifier
                        .width(
                            260.dp,
                        )
                        .clip(
                            RoundedCornerShape(
                                5.dp,
                            ),
                        )
                        .background(
                            Color(
                                0xff385334,
                            ),
                        )
                        .padding(
                            horizontal = 10.dp,
                            vertical = 7.dp,
                        ),
                ) {
                    words.forEachIndexed { index, word ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    selected = index
                                },
                        ) {
                            WordBox(
                                word = word,
                                found = foundWords.contains(word),
                            )

                            Text(
                                text = WordHuntGameState.calculatePoints(
                                    word,
                                ).toString(),
                                color = Color.White,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = interFamily,
                            )
                        }
                    }
                }
            }

            Box(
                modifier = Modifier
                    .align(
                        Alignment.TopStart,
                    )
                    .padding(
                        16.dp,
                    )
                    .size(
                        48.dp,
                    )
                    .clickable(
                        onClick = onBack,
                    )
                    .zIndex(
                        2f,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    painter = painterResource(
                        R.drawable.back,
                    ),
                    contentDescription = "Back",
                    modifier = Modifier.fillMaxSize(),
                )
            }

            if (selected >= 0 && board.length >= gridSize * gridSize) {
                WordPathPopup(
                    board = board,
                    gridSize = gridSize,
                    invalid = invalidCells,
                    path = WordHuntSolver.decodePath(
                        paths.getOrElse(selected) { "" },
                    ),
                    onDismiss = {
                        selected = -1
                    },
                )
            }
        }
    }

    private fun vibrateStrongTap(
        context: Context,
    ) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(
                Context.VIBRATOR_MANAGER_SERVICE,
            ) as VibratorManager

            manager.defaultVibrator
        } else {
            @Suppress(
                "DEPRECATION",
            ) context.getSystemService(
                Context.VIBRATOR_SERVICE,
            ) as Vibrator
        }

        if (!vibrator.hasVibrator()) {
            return
        }

        vibrator.vibrate(
            VibrationEffect.createOneShot(
                80L,
                200,
            ),
        )
    }

    @OptIn(ExperimentalTextApi::class)
    @Composable
    fun PlayerColumn(
        words: String?,
        score: String?,
        wordList: List<String>,
        isLeft: Boolean,
        modifier: Modifier,
        avatarScale: Float = 1f,
        avatarString: String? = null,
        useLocalAvatar: Boolean = false,
        playerLabel: String = "",
        showWinBurst: Boolean = false,
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(
                5.dp,
            ),
            horizontalAlignment = if (isLeft) {
                Alignment.Start
            } else {
                Alignment.End
            },
            modifier = modifier.fillMaxHeight(),
        ) {
            /*
             * Avatar and label.
             */
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.width(
                    72.dp * avatarScale,
                ),
            ) {
                Text(
                    text = playerLabel.ifBlank {
                        " "
                    },
                    color = if (playerLabel.isBlank()) {
                        Color.Transparent
                    } else {
                        Color.Black
                    },
                    fontSize = 17.sp * avatarScale,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .offset(
                            y = if (playerLabel == "You") {
                                12.dp * avatarScale
                            } else {
                                0.dp
                            },
                        )
                        .zIndex(
                            3f,
                        ),
                )

                Box(
                    modifier = Modifier
                        .size(
                            width = 80.dp * avatarScale,
                            height = 117.dp * avatarScale,
                        )
                        .zIndex(
                            1f,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    AvatarWinBurstOverlay(
                        active = showWinBurst,
                        modifier = Modifier
                            .requiredSize(
                                80.dp * avatarScale * 1.7f,
                            )
                            .offset(
                                y = 24.dp * avatarScale,
                            )
                            .zIndex(
                                0f,
                            ),
                    )

                    if (useLocalAvatar) {
                        androidx.compose.ui.viewinterop.AndroidView(
                            factory = { context ->
                                com.openbubbles.openpigeon.settings.AvatarView(
                                    context,
                                ).apply {
                                    tag = WordHuntActivity.LOCAL_AVATAR_VIEW_TAG
                                    applyFromAvatarData()
                                }
                            },
                            update = { avatarView ->
                                avatarView.applyFromAvatarData()
                            },
                            modifier = Modifier
                                .fillMaxSize()
                                .zIndex(
                                    1f,
                                ),
                        )
                    } else {
                        androidx.compose.ui.viewinterop.AndroidView(
                            factory = { context ->
                                com.openbubbles.openpigeon.settings.AvatarView(
                                    context,
                                ).apply {
                                    if (!avatarString.isNullOrBlank()) {
                                        applyFromOpponentString(
                                            avatarString,
                                        )
                                    } else {
                                        showPlaceholder()
                                    }
                                }
                            },
                            update = { avatarView ->
                                if (!avatarString.isNullOrBlank()) {
                                    avatarView.applyFromOpponentString(
                                        avatarString,
                                    )
                                } else {
                                    avatarView.showPlaceholder()
                                }
                            },
                            modifier = Modifier
                                .fillMaxSize()
                                .zIndex(
                                    1f,
                                ),
                        )
                    }
                }
            }

            val scoreBackground = if (!words.isNullOrBlank()) {
                Color(
                    0xfffdfdfd,
                )
            } else {
                Color.Transparent
            }

            val scoreTextColor = if (!words.isNullOrBlank()) {
                Color.Black
            } else {
                Color(
                    0xB2C7CFC7,
                )
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(
                        65.dp * avatarScale,
                    )
                    .clip(
                        TornPaperShape(),
                    )
                    .background(
                        scoreBackground,
                    ),
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(
                        (-2).dp,
                    ),
                    horizontalAlignment = if (isLeft) {
                        Alignment.Start
                    } else {
                        Alignment.End
                    },
                    modifier = Modifier
                        .align(
                            Alignment.Center,
                        )
                        .padding(
                            horizontal = 5.dp,
                        ),
                ) {
                    Text(
                        text = "WORDS: ${
                            if (words.isNullOrBlank()) {
                                "?"
                            } else {
                                words
                            }
                        }",
                        color = scoreTextColor,
                        fontSize = 17.sp * avatarScale,
                        fontWeight = FontWeight.Bold,
                        fontFamily = interFamily,
                        textAlign = if (isLeft) {
                            TextAlign.Start
                        } else {
                            TextAlign.End
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )

                    Text(
                        text = "SCORE: ${
                            if (score.isNullOrBlank()) {
                                "????"
                            } else {
                                score.padStart(
                                    4,
                                    '0',
                                )
                            }
                        }",
                        color = scoreTextColor,
                        fontSize = 22.sp * avatarScale,
                        fontWeight = FontWeight.ExtraBold,
                        fontFamily = interFamily,
                        textAlign = if (isLeft) {
                            TextAlign.Start
                        } else {
                            TextAlign.End
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            val listScroll = rememberScrollState()

            Column(
                verticalArrangement = Arrangement.spacedBy(
                    10.dp,
                ),
                horizontalAlignment = if (isLeft) {
                    Alignment.Start
                } else {
                    Alignment.End
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(
                        1f,
                    )
                    .clip(
                        RoundedCornerShape(
                            5.dp,
                        ),
                    )
                    .background(
                        Color(
                            0xff385334,
                        ),
                    )
                    .wordScrollbar(
                        listScroll,
                    )
                    .verticalScroll(
                        listScroll,
                    )
                    .padding(
                        horizontal = 7.dp,
                        vertical = 7.dp,
                    ),
            ) {
                wordList.forEach { word ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        val wordScoreFont = FontFamily(
                            Font(
                                R.font.inter_variable,
                                variationSettings = FontVariation.Settings(
                                    FontVariation.weight(
                                        600,
                                    ),
                                ),
                            ),
                        )

                        if (isLeft) {
                            WordBox(
                                word,
                            )

                            Text(
                                text = WordHuntGameState.calculatePoints(
                                    word,
                                ).toString(),
                                color = Color.White,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = wordScoreFont,
                            )
                        } else {
                            Text(
                                text = WordHuntGameState.calculatePoints(
                                    word,
                                ).toString(),
                                color = Color.White,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = wordScoreFont,
                            )

                            WordBox(
                                word,
                            )
                        }
                    }
                }
            }
        }
    }

    private fun Modifier.wordScrollbar(state: ScrollState): Modifier = this.drawWithContent {
        drawContent()

        val range = state.maxValue

        if (range <= 0) {
            return@drawWithContent
        }

        val trackHeight = size.height
        val thumbHeight = (trackHeight * trackHeight / (trackHeight + range)).coerceAtLeast(24f)
        val progress = state.value.toFloat() / range.toFloat()

        drawRoundRect(
            color = Color(0x88FFFFFF),
            topLeft = Offset(size.width - 7f, (trackHeight - thumbHeight) * progress),
            size = Size(5f, thumbHeight),
            cornerRadius = CornerRadius(2.5f, 2.5f),
        )
    }

    @Composable
    private fun WordBox(word: String, found: Boolean = false) {
        Box(
            modifier = Modifier
                .wrapContentSize()
                .clip(RoundedCornerShape(3.dp))
                .background(
                    if (found) {
                        Color(0xffF2DE8A)
                    } else {
                        Color(0xffCEAA71)
                    }
                )
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
        gameState: WordHuntGameState, modifier: Modifier = Modifier
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
                targetValue = 1.08f, animationSpec = tween(140)
            )

            delay(
                300.milliseconds,
            )

            popupAlpha.animateTo(
                targetValue = 0f, animationSpec = tween(300)
            )

            gameState.clearLastAwardedText()
        }

        if (awardedText != null && popupAlpha.value > 0f) {
            Box(modifier = modifier
                .zIndex(2f)
                .graphicsLayer {
                    scaleX = scale.value
                    scaleY = scale.value
                    alpha = popupAlpha.value
                }
                .background(
                    Color(0xFF86FE8C), shape = RoundedCornerShape(8.dp)
                )
                .padding(horizontal = 14.dp, vertical = 8.dp)) {
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
            size: Size, layoutDirection: LayoutDirection, density: Density
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
        val score = mutableMapOf(
            "score1" to "2100",
            "score2" to "1200",
            "words1" to "2",
            "words2" to "10",
            "words_list1" to "HELP",
            "words_list2" to "THIS|WORLD|BEG|ANOTHER|WORD|UNDER|THE|SEA|GROW|SHOW|UNDER|OVER",
            "winner_slot" to "local",
        )

        fun getScore() = score

        ScoreScreen(
            modifier = Modifier,
            score = {
                getScore()
            },
            spectatorMode = false,
        )
    }
}