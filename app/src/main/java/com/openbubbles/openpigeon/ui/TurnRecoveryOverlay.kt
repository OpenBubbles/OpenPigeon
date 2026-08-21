package com.openbubbles.openpigeon.ui

import android.os.Looper
import android.view.View
import android.view.ViewGroup
import androidx.compose.animation.core.EaseInOutSine
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.core.view.isVisible

private const val SEND_PULSE_MIN = 1f
private const val SEND_PULSE_MAX = 1.3f
private const val SEND_PULSE_MS = 1200

@Composable
fun TurnRecoveryOverlay(
    visible: Boolean,
    onRetry: () -> Unit,
) {
    if (!visible) {
        return
    }

    val pulse by rememberInfiniteTransition(
        label = "sendPulse",
    ).animateFloat(
        initialValue = SEND_PULSE_MIN,
        targetValue = SEND_PULSE_MAX,
        animationSpec = infiniteRepeatable(
            animation = tween(
                durationMillis = SEND_PULSE_MS,
                easing = EaseInOutSine,
            ),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "sendPulseScale",
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .zIndex(1000f),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Color.Black.copy(
                        alpha = 0.35f,
                    ),
                )
                .clickable(
                    onClick = {},
                ),
        )

        Box(
            modifier = Modifier
                .width(180.dp)
                .height(52.dp)
                .graphicsLayer(
                    scaleX = pulse,
                    scaleY = pulse,
                )
                .shadow(
                    elevation = 8.dp,
                    shape = RoundedCornerShape(12.dp),
                )
                .background(
                    color = Color.White,
                    shape = RoundedCornerShape(12.dp),
                )
                .clickable(
                    onClick = onRetry,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "SEND GAME",
                color = Color.Black,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

class TurnRecoveryOverlayController internal constructor(
    private val composeView: ComposeView,
    private val visibleState: MutableState<Boolean>,
) {
    fun showRetry() {
        onViewThread {
            visibleState.value =
                true

            composeView.visibility =
                View.VISIBLE

            composeView.bringToFront()
        }
    }

    fun hideRetry() {
        onViewThread {
            visibleState.value =
                false

            composeView.visibility =
                View.GONE
        }
    }

    fun isShowingRetry(): Boolean {
        return composeView.isVisible &&
                visibleState.value
    }

    fun destroy() {
        onViewThread {
            composeView.disposeComposition()

            (composeView.parent as? ViewGroup)
                ?.removeView(
                    composeView,
                )
        }
    }

    private fun onViewThread(
        block: () -> Unit,
    ) {
        if (
            Looper.myLooper() ==
            Looper.getMainLooper()
        ) {
            block()
        } else {
            composeView.post(
                block,
            )
        }
    }
}

fun attachTurnRecoveryOverlay(
    parent: ViewGroup,
    onRetry: () -> Unit,
): TurnRecoveryOverlayController {
    val visibleState =
        mutableStateOf(
            false,
        )

    val composeView =
        ComposeView(
            parent.context,
        ).apply {
            visibility =
                View.GONE

            setViewCompositionStrategy(
                ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed,
            )

            setContent {
                TurnRecoveryOverlay(
                    visible = visibleState.value,
                    onRetry = onRetry,
                )
            }
        }

    parent.addView(
        composeView,
        ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        ),
    )

    return TurnRecoveryOverlayController(
        composeView = composeView,
        visibleState = visibleState,
    )
}