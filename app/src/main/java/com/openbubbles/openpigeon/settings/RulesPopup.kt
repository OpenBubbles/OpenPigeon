package com.openbubbles.openpigeon.ui

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.*
import android.view.animation.OvershootInterpolator
import android.widget.*
import androidx.core.view.isVisible

object RulesPopup {

    data class Section(val header: String, val body: String)

    private const val Z_RULES_DIM = 70000f
    private const val Z_RULES_CARD = 70001f

    private fun setPopupLayer(view: View, layer: Float) {
        view.elevation = layer
        view.translationZ = 0f
        view.z = layer
    }

    // ── dp helpers ────────────────────────────────────────────────────────────
    private fun dp(context: Context, v: Float) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics).toInt()
    private fun dpf(context: Context, v: Float) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics)
    private fun sp(context: Context, v: Float) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_SP, v, context.resources.displayMetrics)

    fun show(
        context: Context,
        rootView: ViewGroup,
        title: String,
        sections: List<Section>
    ) {
        val screenW = context.resources.displayMetrics.widthPixels
        val screenH = context.resources.displayMetrics.heightPixels
        val popupW  = (screenW * 0.82f).toInt()
        val maxH    = (screenH * 0.80f).toInt()

        // ── Dim overlay ───────────────────────────────────────────────────────
        val dim = View(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setBackgroundColor(Color.argb(180, 0, 0, 0))
            alpha = 0f
            isVisible = true
            setPopupLayer(this, Z_RULES_DIM)
        }

        // ── Card ──────────────────────────────────────────────────────────────
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(popupW, ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#2a2a3e"))
                cornerRadius = dpf(context, 16f)
            }
            setPopupLayer(this, Z_RULES_CARD)
            clipToOutline = true
            outlineProvider = ViewOutlineProvider.BACKGROUND
            // Start scaled to 0 for pop-in
            scaleX = 0f; scaleY = 0f; alpha = 0f
        }

        // ── Title bar ─────────────────────────────────────────────────────────
        val titleBar = FrameLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(context, 52f))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1e1e2e"))
                // Only round the top corners
                cornerRadii = floatArrayOf(
                    dpf(context,16f), dpf(context,16f),
                    dpf(context,16f), dpf(context,16f),
                    0f, 0f, 0f, 0f)
            }
        }

        val titleTv = TextView(context).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 15f
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER)
        }
        titleBar.addView(titleTv)

        // Close button — loads close.png from assets, falls back to "✕"
        val closeBtn = ImageButton(context).apply {
            val size = dp(context, 36f)
            layoutParams = FrameLayout.LayoutParams(size, size,
                Gravity.END or Gravity.CENTER_VERTICAL).also {
                it.rightMargin = dp(context, 8f)
            }
            setBackgroundColor(Color.TRANSPARENT)
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            setPadding(dp(context, 6f), dp(context, 6f), dp(context, 6f), dp(context, 6f))
            try {
                val bm = context.assets.open("global/close.png")
                    .use { BitmapFactory.decodeStream(it) }
                setImageBitmap(bm)
            } catch (_: Exception) {
                // Fallback text button
                (this as? ImageButton)?.setImageDrawable(null)
            }
            contentDescription = "Close"
        }
        titleBar.addView(closeBtn)
        card.addView(titleBar)

        // ── Scrollable body ───────────────────────────────────────────────────
        val scroll = ScrollView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f).also {
                // Max height enforced by measuring in a post{}
            }
            isVerticalScrollBarEnabled = true
        }

        val body = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(context, 18f), dp(context, 14f), dp(context, 18f), dp(context, 20f))
        }

        sections.forEach { section ->
            if (section.header.isNotBlank()) {
                val tv = TextView(context).apply {
                    text = section.header
                    setTextColor(Color.WHITE)
                    textSize = 16f
                    typeface = android.graphics.Typeface.DEFAULT_BOLD
                }
                tv.layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).also { it.topMargin = dp(context, 10f); it.bottomMargin = dp(context, 4f) }
                body.addView(tv)
            }
            if (section.body.isNotBlank()) {
                val tv = TextView(context).apply {
                    text = section.body
                    setTextColor(Color.parseColor("#ccccdd"))
                    textSize = 13f
                    setLineSpacing(0f, 1.3f)
                }
                tv.layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).also { it.bottomMargin = dp(context, 4f) }
                body.addView(tv)
            }
        }

        scroll.addView(body)
        card.addView(scroll)

        // ── Add to root ───────────────────────────────────────────────────────
        (rootView as? FrameLayout)?.let { frame ->
            frame.addView(dim)
            frame.addView(card)

            frame.bringChildToFront(dim)
            frame.bringChildToFront(card)
            dim.bringToFront()
            card.bringToFront()

            frame.post {
                setPopupLayer(dim, Z_RULES_DIM)
                setPopupLayer(card, Z_RULES_CARD)
                frame.bringChildToFront(dim)
                frame.bringChildToFront(card)
                card.bringToFront()
            }

            frame.postDelayed({
                setPopupLayer(dim, Z_RULES_DIM)
                setPopupLayer(card, Z_RULES_CARD)
                frame.bringChildToFront(dim)
                frame.bringChildToFront(card)
                card.bringToFront()
            }, 100L)
        }

        // After layout, clamp scroll height to 80% of screen
        card.post {
            val titleH  = titleBar.height
            val bodyH   = body.height + dp(context, 2f) // tiny buffer
            val totalH  = titleH + bodyH
            val clampedScrollH = (maxH - titleH).coerceAtMost(bodyH)

            scroll.layoutParams = (scroll.layoutParams as LinearLayout.LayoutParams).also {
                it.height = clampedScrollH
                it.weight = 0f
            }
            scroll.requestLayout()
        }

        // ── Pop-in animation ──────────────────────────────────────────────────
        val scaleX = ObjectAnimator.ofFloat(card, "scaleX", 0f, 1f)
        val scaleY = ObjectAnimator.ofFloat(card, "scaleY", 0f, 1f)
        val fadeCard = ObjectAnimator.ofFloat(card, "alpha", 0f, 1f)
        val fadeDim  = ObjectAnimator.ofFloat(dim, "alpha", 0f, 1f)

        AnimatorSet().apply {
            playTogether(scaleX, scaleY, fadeCard, fadeDim)
            duration = 320
            interpolator = OvershootInterpolator(1.6f)
            start()
        }

        // ── Dismiss logic ─────────────────────────────────────────────────────
        fun dismiss() {
            val sX = ObjectAnimator.ofFloat(card, "scaleX", 1f, 0f)
            val sY = ObjectAnimator.ofFloat(card, "scaleY", 1f, 0f)
            val fC = ObjectAnimator.ofFloat(card, "alpha", 1f, 0f)
            val fD = ObjectAnimator.ofFloat(dim, "alpha", 1f, 0f)
            AnimatorSet().apply {
                playTogether(sX, sY, fC, fD)
                duration = 220
                interpolator = android.view.animation.AccelerateInterpolator(1.4f)
                addListener(object : android.animation.AnimatorListenerAdapter() {
                    override fun onAnimationEnd(a: android.animation.Animator) {
                        rootView.removeView(card)
                        rootView.removeView(dim)
                    }
                })
                start()
            }
        }

        closeBtn.setOnClickListener { dismiss() }
        dim.setOnClickListener { dismiss() }
        card.setOnClickListener { /* absorb clicks so dim doesn't fire */ }
    }
}
