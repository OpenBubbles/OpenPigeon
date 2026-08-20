package com.openbubbles.openpigeon.settings

import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.isVisible

private const val WIN_BURST_WIDTH_DP =
    136f

private const val WIN_BURST_HEIGHT_DP =
    108f

private const val WIN_BURST_RAY_COUNT =
    18

class AvatarWinBurstController(
    private val root: FrameLayout,
    private val localAnchor: View,
    private val opponentAnchor: View,
) {
    private val layer =
        FrameLayout(
            root.context,
        ).apply {
            clipChildren =
                false

            clipToPadding =
                false

            isClickable =
                false

            isFocusable =
                false

            visibility =
                View.GONE
        }

    private val localBurst =
        createBurst()

    private val opponentBurst =
        createBurst()

    private var shownResult: Int? =
        null

    private val layoutListener =
        View.OnLayoutChangeListener {
                _,
                _,
                _,
                _,
                _,
                _,
                _,
                _,
                _
            ->
            positionBursts()
        }

    init {
        root.clipChildren =
            false

        root.clipToPadding =
            false

        val insertionIndex =
            listOf(
                directChildUnderRoot(
                    localAnchor,
                ),
                directChildUnderRoot(
                    opponentAnchor,
                ),
            ).mapNotNull { child ->
                child?.let {
                    root.indexOfChild(
                        it,
                    ).takeIf { index ->
                        index >= 0
                    }
                }
            }.minOrNull()
                ?: root.childCount

        root.addView(
            layer,
            insertionIndex,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        layer.addView(
            localBurst,
            burstLayoutParams(),
        )

        layer.addView(
            opponentBurst,
            burstLayoutParams(),
        )

        root.addOnLayoutChangeListener(
            layoutListener,
        )

        layer.post {
            positionBursts()
        }
    }

    private fun createBurst(): AvatarWinBurstView {
        return AvatarWinBurstView(
            root.context,
        ).apply {
            setRayColor(
                Color.rgb(
                    255,
                    214,
                    0,
                ),
            )

            setRayCount(
                WIN_BURST_RAY_COUNT,
            )

            isClickable =
                false

            isFocusable =
                false
        }
    }

    private fun burstLayoutParams(): FrameLayout.LayoutParams {
        return FrameLayout.LayoutParams(
            dp(
                WIN_BURST_WIDTH_DP,
            ).toInt(),
            dp(
                WIN_BURST_HEIGHT_DP,
            ).toInt(),
        )
    }

    private fun dp(
        value: Float,
    ): Float {
        return value *
                root.resources.displayMetrics.density
    }

    private fun directChildUnderRoot(
        view: View,
    ): View? {
        var current =
            view

        while (true) {
            val parent =
                current.parent

            if (parent === root) {
                return current
            }

            if (parent !is View) {
                return null
            }

            current =
                parent
        }
    }

    private fun positionBursts() {
        positionBurst(
            burst = localBurst,
            anchor = localAnchor,
        )

        positionBurst(
            burst = opponentBurst,
            anchor = opponentAnchor,
        )
    }

    private fun positionBurst(
        burst: AvatarWinBurstView,
        anchor: View,
    ) {
        if (
            anchor.width <= 0 ||
            anchor.height <= 0 ||
            burst.width <= 0 ||
            burst.height <= 0 ||
            layer.width <= 0 ||
            layer.height <= 0
        ) {
            return
        }

        val anchorLocation =
            IntArray(
                2,
            )

        val layerLocation =
            IntArray(
                2,
            )

        anchor.getLocationOnScreen(
            anchorLocation,
        )

        layer.getLocationOnScreen(
            layerLocation,
        )

        val anchorLeft =
            (
                    anchorLocation[0] -
                            layerLocation[0]
                    ).toFloat()

        val anchorTop =
            (
                    anchorLocation[1] -
                            layerLocation[1]
                    ).toFloat()

        burst.x =
            anchorLeft +
                    (
                            anchor.width -
                                    burst.width
                            ) /
                    2f

        burst.y =
            anchorTop +
                    (
                            anchor.height -
                                    burst.height
                            ) /
                    2f
    }

    private fun bringAvatarBranchesToFront() {
        val localBranch =
            directChildUnderRoot(
                localAnchor,
            )

        val opponentBranch =
            directChildUnderRoot(
                opponentAnchor,
            )

        localBranch?.bringToFront()

        if (opponentBranch !== localBranch) {
            opponentBranch?.bringToFront()
        }
    }

    fun show(
        result: Int,
        dimView: View? = null,
        label: View? = null,
    ) {
        val safeResult =
            result.coerceIn(
                -1,
                1,
            )

        if (
            shownResult == safeResult &&
            layer.isVisible
        ) {
            dimView?.bringToFront()
            layer.bringToFront()
            bringAvatarBranchesToFront()
            label?.bringToFront()
            return
        }

        clear()

        shownResult =
            safeResult

        dimView?.bringToFront()

        layer.visibility =
            View.VISIBLE

        layer.bringToFront()

        bringAvatarBranchesToFront()

        label?.bringToFront()

        layer.post {
            positionBursts()

            when (safeResult) {
                1 -> {
                    localBurst.play()
                }

                -1 -> {
                    opponentBurst.play()
                }

                0 -> {
                    localBurst.play()
                    opponentBurst.play()
                }
            }

            bringAvatarBranchesToFront()
            label?.bringToFront()
        }
    }

    fun clear() {
        shownResult =
            null

        localBurst.stop(
            immediate = true,
        )

        opponentBurst.stop(
            immediate = true,
        )

        layer.visibility =
            View.GONE
    }

    fun destroy() {
        clear()

        root.removeOnLayoutChangeListener(
            layoutListener,
        )

        (
                layer.parent as? ViewGroup
                )?.removeView(
                layer,
            )
    }
}

@Composable
fun AvatarWinBurstOverlay(
    active: Boolean,
    modifier: Modifier = Modifier,
) {
    if (!active) {
        return
    }

    val viewHolder =
        remember {
            arrayOfNulls<AvatarWinBurstView>(
                1,
            )
        }

    DisposableEffect(
        Unit,
    ) {
        onDispose {
            viewHolder[0]?.stop(
                immediate = true,
            )

            viewHolder[0] =
                null
        }
    }

    AndroidView(
        modifier =
            modifier,
        factory = { context ->
            AvatarWinBurstView(
                context,
            ).apply {
                setRayColor(
                    Color.rgb(
                        255,
                        214,
                        0,
                    ),
                )

                setRayCount(
                    WIN_BURST_RAY_COUNT,
                )

                isClickable =
                    false

                isFocusable =
                    false

                tag =
                    false
            }.also { burst ->
                viewHolder[0] =
                    burst

                burst.post {
                    if (burst.tag != true) {
                        burst.tag =
                            true

                        burst.play()
                    }
                }
            }
        },
        update = { burst ->
            if (burst.tag != true) {
                burst.tag =
                    true

                burst.post {
                    burst.play()
                }
            }
        },
    )
}