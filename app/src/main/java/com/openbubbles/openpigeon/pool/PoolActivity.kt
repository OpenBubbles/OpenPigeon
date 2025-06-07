package com.openbubbles.openpigeon.pool

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.RectF
import android.os.Bundle
import android.os.Handler
import android.util.Log
import android.util.TypedValue
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.View
import android.view.Window
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.animation.doOnEnd
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GameSessionIPC
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.min
import kotlin.math.sqrt

class PoolActivity : AppCompatActivity() {
    lateinit var sessionId: String
    var gameSessionIPC: GameSessionIPC? = null
    var baseGame = PoolGame()

    var table: Long = 0L

    lateinit var renderer: PoolRenderer

    enum class PoolMode {
        Playing,
        Aiming,
        Disabled,
        ReplayAiming,
    }


    var mode = PoolMode.Disabled

    var lastAngle = 0f

    var touchDownCueX = 0f
    fun setCueDrawAmount(power: Float) {
        val frac = power / 2000
        // negative cue draw is used for the hit animation, don't show in the draw
        val tip = findViewById<ImageView>(R.id.cueTip)
        val width = findViewById<FrameLayout>(R.id.cueContainer).width
        tip.translationX = min(-frac * width, 0f)
        renderer.cueDraw = frac * 500
    }

    var setSpinX = 0f
    var setSpinY = 0f
    var draggingCue = false
    var calledPocket: List<Int> = listOf()

    val holes = listOf(
        listOf(40, 40),
        listOf(744, 40),
        listOf(40, 400),
        listOf(744, 400),
        listOf(392, 28),
        listOf(392, 412),
    )

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestWindowFeature(Window.FEATURE_NO_TITLE)
        supportActionBar?.hide()

        table = createPoolTable()

        enableEdgeToEdge()
        setContentView(R.layout.activity_pool)
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.surfaceView)) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }

        val cueView = findViewById<FrameLayout>(R.id.cueView)
        val cueDot = findViewById<ImageView>(R.id.cueDot)
        cueView.setOnTouchListener { v, event ->
            if (mode != PoolMode.Aiming) return@setOnTouchListener true
            val dotRadiusPx = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                4f,
                resources.displayMetrics
            )
            val normalizedX = ((event.x - dotRadiusPx) / (cueView.width - dotRadiusPx * 2)) * 2 - 1
            val normalizedY = ((event.y - dotRadiusPx) / (cueView.height - dotRadiusPx * 2)) * 2 - 1
            val dist = normalizedY * normalizedY + normalizedX * normalizedX
            // need to subtract the distance of the rest of the red ball
            if (dist > 1) {
                // we are a unit circle, if we're more than a unit, that means we are outside the circle
                return@setOnTouchListener true
            }
            setSpinX = normalizedX * 30
            setSpinY = normalizedY * 30
            cueDot.translationX = event.x - dotRadiusPx // center radius
            cueDot.translationY = event.y - dotRadiusPx
            true
        }

        findViewById<Button>(R.id.skip_replay).setOnClickListener {
            synchronized(this@PoolActivity) {
                finishReplay()
            }
        }

        val container = findViewById<FrameLayout>(R.id.cueContainer)
        container.setOnTouchListener { v, event ->
            if (mode != PoolMode.Aiming) return@setOnTouchListener true

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    touchDownCueX = event.x
                }
                MotionEvent.ACTION_MOVE -> {
                    val power = -min(event.x - touchDownCueX, 0.0f) / container.width * 2000
                    setCueDrawAmount(power)
                }
                MotionEvent.ACTION_UP -> {
                    disableSend = false
                    val power = -min(event.x - touchDownCueX, 0.0f) / container.width * 2000
                    if (power < 100) {
                        setCueDrawAmount(0f)
                        return@setOnTouchListener true
                    }
                    // snap back and hit
                    val hit = BallHit(renderer.cueRot, power, setSpinX, setSpinY, iAmStripes)
                    outgoingReplayHits.add(hit)
                    animateShoot(power, hit)
                }
            }
            true
        }


        val view = findViewById<SurfaceView>(R.id.surfaceView)
        renderer = PoolRenderer(view.holder, this)

        view.setOnTouchListener { v, event ->
            val inverted = Matrix()
            renderer.transform.invert(inverted)

            val points = floatArrayOf(event.x, event.y)
            inverted.mapPoints(points)
            if (call8Ball) {
                val clickedHole = holes.find {
                    val distX = points[0] - it[0]
                    val distY = points[1] - it[1]
                    val dist = sqrt(distX * distX + distY * distY)
                    dist < 20
                }
                if (clickedHole == null) return@setOnTouchListener true
                call8Ball = false
                calledPocket = clickedHole

                val label = findViewById<TextView>(R.id.state_label)
                label.visibility = View.GONE

                mode = PoolMode.Aiming
                renderer.setCueVisible(true)
            } else if (mode == PoolMode.Aiming) {
                val origPoints = points.copyOf()

                // get distance between ball and finger
                points[0] -= cueBall.x
                points[1] -= cueBall.y

                val position = -atan2(points[0], points[1])

                when(event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        if (scratch && abs(points[0]) < 20 && abs(points[1]) < 20) {
                            draggingCue = true
                        }
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (draggingCue) {
                            for (ball in poolBalls) {
                                if (ball.number == 0) continue
                                val distX = ball.x - origPoints[0]
                                val distY = ball.y - origPoints[1]
                                val distance = sqrt(distX * distX + distY * distY)
                                if (distance < 20f) {
                                    // we overslap another ball, reject this move
                                    return@setOnTouchListener true
                                }
                            }
                            synchronized(this) {
                                moveBall(table, 0, origPoints[0], origPoints[1], 0f)
                            }
                        } else {
                            var diff = position - lastAngle
                            if (diff > PI) {
                                diff -= PI.toFloat() * 2
                            }
                            if (diff < -PI) {
                                diff += PI.toFloat() * 2
                            }
                            renderer.cueRot += diff * 0.5f
                        }
                    }
                    MotionEvent.ACTION_UP -> {
                        draggingCue = false
                    }
                }
                lastAngle = position
                // this is our direction vector
                Log.i("Point", "${points[0]} ${points[1]}")
            }
            true
        }

        sessionId = intent.getStringExtra("SESSION")!!

        GameSessionIPC(applicationContext) { gameSessionIPC ->
            this.gameSessionIPC = gameSessionIPC
            val currentMessage = gameSessionIPC.getCurrentMessage(sessionId)
            if (currentMessage.isNotEmpty()) {
                gameSessionIPC.lockMsgHandle(sessionId)
                gameSessionIPC.setSuppressNotifications(sessionId, true)
                gameSessionIPC.onMessageUpdated(sessionId) {
                    Log.i("what", "sdf")
                    synchronized(this) {
                        handleMessage(it)
                    }
                }
                handleMessage(currentMessage)
            } else {
                Log.e("openpigeon-${baseGame.getName()}", "$sessionId does not exist!")
                finish()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.i("Table", "Destroying")
        if (table != 0L) {
            destroyPoolTable(table)
            table = 0L
        }
        renderer.running = false
    }

    override fun onResume() {
        if (gameSessionIPC != null) {
            gameSessionIPC?.setSuppressNotifications(sessionId, true)
        } else {
            Log.w("openpigeon-${baseGame.getName()}", "onResume called before gameSessionIPC was initialized!")
        }
        super.onResume()
    }

    override fun onPause() {
        gameSessionIPC!!.setSuppressNotifications(sessionId, false)
        super.onPause()
    }

    external fun createPoolTable(): Long
    external fun destroyPoolTable(table: Long)
    external fun makeBall(table: Long, x: Float, y: Float, rot: Float, density: Float, number: Int, shouldGoIn: Int, outputs: FloatBuffer)
    external fun hitBall(table: Long, number: Int, dir: Float, power: Float, spinX: Float, spinY: Float, first: Boolean)
    external fun moveBall(table: Long, number: Int, x: Float, y: Float, rot: Float)

    external fun clearBalls(table: Long)

    data class BallHit(val direction: Float, val power: Float, val spinX: Float, val spinY: Float, var wasStripes: Boolean?) {
        fun hit(activity: PoolActivity) {
            if (!activity.replaying)
                activity.scratch = false
            activity.mode = PoolMode.Playing
            Log.i("Hitting ball", "Direction: $direction power: $power spinX: $spinX spinY: $spinY scratch: $wasStripes first ${activity.isFirst}")
            activity.hitBall(activity.table, 0 /*white*/, direction, power, spinX, spinY, activity.isFirst)
            activity.wasFirst = activity.isFirst
            activity.isFirst = false
        }
    }

    var replaying = false
    var isFirst = false
    var wasFirst = false

    fun animateShoot(power: Float, hit: BallHit) {
        var cancelled = false
        val animator = ValueAnimator.ofFloat(power, -100f)
        animator.duration = 100L
        animator.addUpdateListener { animation ->
            setCueDrawAmount(animation.animatedValue as Float)
        }
        animator.doOnEnd {
            synchronized(this@PoolActivity) {
                if (cancelled) return@synchronized
                renderer.cuePos = floatArrayOf(cueBall.x, cueBall.y)
                if (scratch && !replaying) {
                    finalBalls = exportBalls(false)
                    scratch = false
                }
                poolBalls.retainAll { !it.sunk }
                hit.hit(this)
                val clearHandler = Handler(mainLooper)
                clearHandler.postDelayed({
                    renderer.setCueVisible(false)
                    setCueDrawAmount(0f)
                    setSpinX = 0f
                    setSpinY = 0f
                    val cueDot = findViewById<ImageView>(R.id.cueDot)
                    cueDot.translationX = TypedValue.applyDimension(
                        TypedValue.COMPLEX_UNIT_DIP,
                        21f,
                        resources.displayMetrics
                    )
                    cueDot.translationY = TypedValue.applyDimension(
                        TypedValue.COMPLEX_UNIT_DIP,
                        21f,
                        resources.displayMetrics
                    )
                    cancelAllShots = {}
                }, 300)
                cancelAllShots = {
                    clearHandler.removeCallbacksAndMessages(null)
                }
            }
        }
        animator.start()
        cancelAllShots = {
            cancelled = true
            animator.cancel()
        }
    }

    var cancelAllShots: () -> Unit = { }
    fun playNextReplay() {
        mode = PoolMode.ReplayAiming
        renderer.cueRot = replayHits[0].direction
        runOnUiThread { renderer.setCueVisible(true) }
        val handler = Handler(mainLooper)
        handler.postDelayed({
            val animator = ValueAnimator.ofFloat(0f, replayHits[0].power)
            animator.duration = 300L
            animator.addUpdateListener { animation -> setCueDrawAmount(animation.animatedValue as Float) }
            animator.doOnEnd {
                val hit = replayHits.removeAt(0)
                animateShoot(hit.power, hit)
            }
            animator.start()
            cancelAllShots = {
                animator.cancel()
            }
        }, 500)
        cancelAllShots = {
            handler.removeCallbacksAndMessages(null)
        }
    }

    var scratch = false

    fun tableIsScratch(): Boolean {
        var scratch = !cueBall.hitBall || cueBall.sunk

        if (cueBall.ballHit != -1) {
            val ballHit = poolBalls.find { it.number == cueBall.ballHit } ?: return false
            val stripes = iAmStripes
            val hasMoreBalls = stripes == null || poolBalls.count { !it.sunk && ((stripes && it.isStripe) || (!stripes && it.isSolid)) } != 0
            if (ballHit.number == 8 && !hasMoreBalls) {
                scratch = false
            } else if (iAmStripes != null && ((!ballHit.isSolid && !iAmStripes!!) || (!ballHit.isStripe && iAmStripes!!))) {
                // we hit the wrong ball
                scratch = true
            }
        }
        return scratch
    }

    var didIWin: Boolean? = null
    var disableSend = false

    fun finishReplay() {
        disableSend = true
        mode = PoolMode.Disabled
        cancelAllShots()
        cancelAllShots = {}

        setCueDrawAmount(0.0f)


        outgoingReplayHits.clear()
        replayHits.clear()

        runOnUiThread {
            val controls = findViewById<LinearLayout>(R.id.controls)
            controls.visibility = View.VISIBLE
            findViewById<Button>(R.id.skip_replay).visibility = View.GONE
        }
        replaying = false

        Log.i("Pool", "Scratch $scratch")

        clearBalls(table)
        val oldBalls = poolBalls
        poolBalls = arrayListOf()

        buildBalls(finalBalls, null)
        for (ball in poolBalls) {
            val old = oldBalls.find { it.number == ball.number }
            if (old == null) continue
            // prevent a flash as Box2d gets it's bearings
            ball.data.put(old.data)
        }

        if (didIWin != null) {
            runOnUiThread {
                val label = findViewById<TextView>(R.id.state_label)
                label.visibility = View.VISIBLE
                if (didIWin!!) {
                    label.text = "You won!"
                } else {
                    label.text = "They won!"
                }
            }
            return
        }

        val stripes = iAmStripes
        val hasMoreBalls = stripes == null || poolBalls.count { !it.sunk && ((stripes && it.isStripe) || (!stripes && it.isSolid)) } != 0
        if (!hasMoreBalls) {
            call8Ball = true
            mode = PoolMode.Aiming
            runOnUiThread {
                val label = findViewById<TextView>(R.id.state_label)
                label.visibility = View.VISIBLE
                label.text = "Choose a pocket"
            }
            return
        }

        mode = PoolMode.Aiming
        runOnUiThread {
            renderer.setCueVisible(true)
        }
    }

    var call8Ball = false

    fun handleFinishPlay() {
        if (disableSend) return
        cancelAllShots()
        cancelAllShots = {}
        if (replayHits.isNotEmpty()) {
            playNextReplay()
        } else if (replaying) {
            finishReplay()
        } else {
            val scratch = tableIsScratch()

            mode = PoolMode.Disabled


            var winState: Boolean? = null
            val blackBall = poolBalls.find { it.number == 8 }!!
            if (blackBall.sunk) {
                if (iAmStripes == null || poolBalls.count { !it.sunk && ((iAmStripes!! && it.isStripe) || (!iAmStripes!! && it.isSolid)) } != 0
                    || blackBall.holeX != calledPocket[0].toFloat() || blackBall.holeY != calledPocket[1].toFloat()) {
                    // I lose, there are more balls to pocket, or the white ball went in too, or I put it in the wrong hole
                    winState = false
                } else {
                    // this person win
                    winState = true
                }
            }

            if (poolBalls.any { it.sunk } && !scratch && winState == null) {
                if (iAmStripes == null && !wasFirst) {
                    // first sunk ball that is a stripe or not
                    iAmStripes = poolBalls.find {
                        Log.i("order", "${it.sunkOrder}")
                        it.sunkOrder == 0
                    }!!.isStripe
                }

                val stripes = iAmStripes
                val hasMoreBalls = stripes == null || poolBalls.count { !it.sunk && ((stripes && it.isStripe) || (!stripes && it.isSolid)) } != 0
                if (!hasMoreBalls) {
                    call8Ball = true
                    mode = PoolMode.Aiming
                    runOnUiThread {
                        val label = findViewById<TextView>(R.id.state_label)
                        label.visibility = View.VISIBLE
                        label.text = "Choose a pocket"
                    }
                    return
                }

                // you get another turn
                mode = PoolMode.Aiming
                runOnUiThread {
                    renderer.setCueVisible(true)
                }
                return
            }

            runOnUiThread {
                val label = findViewById<TextView>(R.id.state_label)
                label.visibility = View.VISIBLE
                label.text = "Waiting for opponent..."
            }

            // send replay
            Log.i("sending replay", "here")
            var replays = outgoingReplayHits.mapIndexed { index, hit ->
                val wasStripes = if (hit.wasStripes == null) 0 else if (hit.wasStripes!!) player else if (player == 1) 2 else 1
                val replay = "&d:${hit.direction}&x:${hit.spinX}&y:${hit.spinY}&p:${hit.power}&s:$wasStripes"
                if (index == 0) {
                    "$replay&balls:$finalBalls"
                } else {
                    replay
                }
            }.joinToString("|")
            replays += "|balls:${exportBalls(scratch)}&stripes:${if (iAmStripes == null) 0 else if (iAmStripes!!) player else if (player == 1) 2 else 1}"

            if (scratch) {
                replays += "&move:1"
            }

            if (winState != null) {
                replays += "&win:${if (winState) 1 else -1}"
                runOnUiThread {
                    val label = findViewById<TextView>(R.id.state_label)
                    label.visibility = View.VISIBLE
                    if (winState) {
                        label.text = "You won!"
                    } else {
                        label.text = "They won!"
                    }
                }
            }

            val currentMessage = gameSessionIPC!!.getCurrentMessage(sessionId)
            val msgUpdates = mapOf(
                "player" to if (currentMessage["player"] == "2") "1" else "2",
                "num" to (currentMessage["num"]?.toInt()!! + 1).toString(),
                "sender" to gameSessionIPC!!.getSenderUUID(sessionId),
                "replay" to replays,
            ).toMutableMap()

            if (winState != null) {
                msgUpdates["winner"] = "${gameSessionIPC!!.getSenderUUID(sessionId)}|${if (winState) "1" else "-1"}"
            }

            gameSessionIPC!!.updateSession(msgUpdates, sessionId) {
                Log.i("openpigeon-${baseGame.getName()}", "Game session updated")
            }
        }
    }

    var iAmStripes: Boolean? = null

    data class PoolBall(val number: Int, val data: FloatBuffer, val resources: Resources, val density: Float) {
        companion object {
            val ballOrder = listOf(
                R.drawable.ball_16,
                R.drawable.ball_1,
                R.drawable.ball_2,
                R.drawable.ball_3,
                R.drawable.ball_4,
                R.drawable.ball_5,
                R.drawable.ball_6,
                R.drawable.ball_7,
                R.drawable.ball_8,
                R.drawable.ball_9,
                R.drawable.ball_10,
                R.drawable.ball_11,
                R.drawable.ball_12,
                R.drawable.ball_13,
                R.drawable.ball_14,
                R.drawable.ball_15,
            )
        }

        val bitmap: Bitmap = BitmapFactory.decodeResource(resources, ballOrder[number])

        val x: Float
            get() = data.get(0)
        val y: Float
            get() = data.get(1)
        val rot: Float
            get() = data.get(2)

        val sunk: Boolean
            get() = data.get(3) != -1f
        val sunkOrder: Int
            get() = data.get(3).toInt()

        val hitBall: Boolean
            get() = data.get(4) != -1f

        val ballHit: Int
            get() = data.get(4).toInt()

        val isSolid: Boolean
            get() = number in 1..7

        val isStripe: Boolean
            get() = number in 9..15

        val holeX: Float
            get() = data.get(5)
        val holeY: Float
            get() = data.get(6)

        fun draw(canvas: Canvas) {
            canvas.save()
            canvas.translate(x, y)
            canvas.rotate(Math.toDegrees(rot.toDouble()).toFloat())
            canvas.drawBitmap(bitmap, null, RectF(-10.0f, -10.0f, 10.0f, 10.0f), null)
            canvas.restore()
        }
    }

    var poolBalls = arrayListOf<PoolBall>()
    val replayHits = arrayListOf<BallHit>()
    val outgoingReplayHits = arrayListOf<BallHit>()

    private var finalBalls = ""
    lateinit var cueBall: PoolBall

    private fun exportBalls(centerScratch: Boolean): String {
        return poolBalls.filter { !it.sunk || (centerScratch && it.number == 0) }.map {
            val density = if (isFirst) it.density else 1
            if (centerScratch && it.number == 0) {
                Log.i("White", "scratching")
                return@map "#392.000000,220.000000,0.000000,$density,0,5.632916,7.415801,5.384167"
            }

            "#${it.x},${it.y},${it.rot},$density,${it.number},5.632916,7.415801,5.384167"
        }.joinToString("")
    }

    private fun buildBalls(balls: String, skew: String?) {
        val ballsThatShouldNotGoIn = skew?.let {
            val items = arrayListOf<Int>()
            for (ball in skew.split("#")) {
                if (ball == "")
                    continue
                val details = ball.split(",")
                items.add(details[4].toInt())
            }
            items
        }

        for (ball in balls.split("#")) {
            if (ball == "")
                continue
            val details = ball.split(",")
            val number = details[4].toInt()

            val buffer = ByteBuffer.allocateDirect(4 /*f32*/ * 7)
            buffer.order(ByteOrder.nativeOrder())

            val floatBuffer = buffer.asFloatBuffer()

            // 5, 6, 7 are rotation_3d
            Log.i("Making ball", "x: ${details[0].toFloat()} y: ${details[1].toFloat()} rot: ${details[2].toFloat()} density: ${details[3].toFloat()} number: $number")

            val shouldGoInMode = if (ballsThatShouldNotGoIn == null) 0 else if (ballsThatShouldNotGoIn.contains(number)) 2 else 1
            makeBall(table, details[0].toFloat(), details[1].toFloat(), details[2].toFloat(), details[3].toFloat(), number, shouldGoInMode, floatBuffer)
            val ball = PoolBall(number, floatBuffer, resources, details[3].toFloat())
            poolBalls.add(ball)
            if (number == 0) {
                cueBall = ball
            }
        }
    }

    var isHard = false
    var player = 0
    var uuid1: String? = null
    var uuid2: String? = null
    fun handleMessage(msg: Map<String, String>) {
        if (table == 0L) return; // we are dead
        clearBalls(table)
        poolBalls.clear()
        replayHits.clear()
        isHard = msg["mode"]!! != "n"
        val num = msg["num"]!!
        uuid1 = msg["player1"]
        uuid2 = msg["player2"]
        Log.i("number", "$num")
        if (num == "2") {
            isFirst = true // for replay
        }
        val playerA = msg["player"]!!.toInt()
        player = if (playerA == 1) 2 else 1

        scratch = false

        runOnUiThread {
            val label = findViewById<TextView>(R.id.state_label)
            label.visibility = View.VISIBLE
        }

        val isYourTurn = msg["sender"]!! != gameSessionIPC!!.getSenderUUID(sessionId)
        var stagingBalls: String? = null
        if (msg.containsKey("replay")) {
            val replay = msg["replay"]!!
            for ((index, value) in replay.split("|").withIndex()) {
                val output = mutableMapOf<String, String>()
                for (element in value.split("&")) {
                    val parts = element.split(":")
                    if (parts[0] == "")
                        continue // JSON will BLOW Vitalii Zlotskii's MIND
                    output[parts[0]] = parts[1]
                }

                output["balls"]?.let { balls ->
                    if (isYourTurn) {
                        if (index > 0) {
                            finalBalls = balls
                            return@let
                        }
                        stagingBalls = balls
                    } else if (index > 0) {
                        stagingBalls = balls
                    }
                }

                if (output["stripes"] != null) {
                    val stripes = output["stripes"]!!.toInt()
                    iAmStripes = if(stripes == 0) null else player == stripes
                    Log.i("Me", "$iAmStripes")
                }

                if (output["move"] != null) {
                    scratch = output["move"] == "1"
                }

                if (output["win"] != null) {
                    val win = output["win"]!!.toInt()
                    didIWin = if (!isYourTurn) win == 1 else win != 1
                }

                if (output["d"] != null) {
                    replayHits.add(
                        BallHit(
                            output["d"]!!.toFloat(),
                            output["p"]!!.toFloat(),
                            output["x"]!!.toFloat(),
                            output["y"]!!.toFloat(),
                            output["s"]!!.toInt().let { stripes ->
                                if(stripes == 0) null else player == stripes
                            }
                        )
                    )
                }
            }
            stagingBalls?.let {
                buildBalls(it, finalBalls)
            }
        } else {
            if (!isYourTurn) {
                runOnUiThread {
                    findViewById<Button>(R.id.skip_replay).visibility = View.GONE
                }

                mode = PoolMode.Disabled
                if (!renderer.isAlive) {
                    renderer.start()
                }
                return
            }
            iAmStripes = null
            finalBalls = "#632.746155,178.000000,0.000000,0.801981,9,5.632916,7.415801,5.384167#632.746155,199.000000,0.000000,0.050000,10,-1.479509,5.981912,-0.639594#632.746155,220.000000,0.000000,0.145560,7,-4.857441,-3.796834,-5.439248#632.746155,241.000000,0.000000,0.050000,6,3.548234,-7.060621,-3.771457#632.746155,262.000000,0.000000,0.964504,1,7.809305,-4.673173,7.553514#614.559570,188.500000,0.000000,0.868768,12,6.889496,7.963203,-4.292648#614.559570,209.500000,0.000000,0.759525,13,4.140916,-0.562560,-5.371364#614.559570,230.500000,0.000000,0.839745,15,-7.863293,-3.022674,-7.419384#614.559570,251.500000,0.000000,1.153367,11,-5.802108,7.468212,-7.951379#596.373047,199.000000,0.000000,1.053345,4,1.589040,2.324956,0.526632#596.373047,220.000000,0.000000,1.437710,8,3.826384,-4.029884,3.487882#596.373047,241.000000,0.000000,1.085851,3,4.912686,3.917787,5.660569#578.186523,209.500000,0.000000,1.100000,2,-5.776122,-4.926837,0.760138#578.186523,230.500000,0.000000,0.900000,5,-1.848043,-0.386153,6.410922#560.000000,220.000000,0.000000,1.000000,14,2.079596,7.069168,-7.283604#220.000000,220.000000,0.000000,0.990000,0,4.519086,0.074793,-2.054408"
            buildBalls(finalBalls, null)
            scratch = true

            mode = PoolMode.Aiming
            runOnUiThread {
                renderer.setCueVisible(true)
                val label = findViewById<TextView>(R.id.state_label)
                label.visibility = View.GONE
                findViewById<Button>(R.id.skip_replay).visibility = View.GONE
            }
            isFirst = true

            if (!renderer.isAlive) {
                renderer.start()
            }

            return
        }

        if (!renderer.isAlive) {
            renderer.start()
        }

        if (!isYourTurn) {
            runOnUiThread {
                findViewById<Button>(R.id.skip_replay).visibility = View.GONE
                if (didIWin != null) {
                    val label = findViewById<TextView>(R.id.state_label)
                    label.visibility = View.VISIBLE
                    if (didIWin!!) {
                        label.text = "You won!"
                    } else {
                        label.text = "They won!"
                    }
                }
            }
            mode = PoolMode.Disabled
        } else {
            runOnUiThread {
                val label = findViewById<TextView>(R.id.state_label)
                label.visibility = View.GONE
                val controls = findViewById<LinearLayout>(R.id.controls)
                controls.visibility = View.INVISIBLE
                findViewById<Button>(R.id.skip_replay).visibility = View.VISIBLE
            }

            replaying = true
            playNextReplay()
        }
    }

    companion object {
        init {
            System.loadLibrary("openbubblesextension")
        }
    }
}