package com.openbubbles.openpigeon.shuffle

import android.content.Context
import com.openbubbles.openpigeon.godot.GameSessionIPC
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import android.view.Gravity
import android.view.Window
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.SettingsSheet
import com.openbubbles.openpigeon.util.OpenPigeonLog

class ShuffleActivity : AppCompatActivity() {
    private var sessionId: String = ""
    private var gameSessionIPC: GameSessionIPC? = null
    private var lastMessage: Map<String, String> = emptyMap()

    private lateinit var rootFrame: FrameLayout
    private lateinit var renderer: ShuffleRenderer
    private lateinit var settingsSheet: SettingsSheet

    private lateinit var myAvatarAnchor: FrameLayout
    private lateinit var opponentAvatarAnchor: FrameLayout
    private lateinit var settingsButton: ImageButton

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestWindowFeature(Window.FEATURE_NO_TITLE)
        supportActionBar?.hide()
        enableEdgeToEdge()

        AvatarData.init(applicationContext)

        rootFrame = FrameLayout(this)
        setContentView(rootFrame)

        ViewCompat.setOnApplyWindowInsetsListener(findViewById(android.R.id.content)) { _, insets ->
            insets
        }

        renderer = ShuffleRenderer(this)
        rootFrame.addView(
            renderer,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        settingsSheet = SettingsSheet(this, rootFrame)

        createAvatarHud()
        createSettingsButton()

        settingsSheet.attachGameAvatar(myAvatarAnchor)
        settingsSheet.attachOpponentAvatar(opponentAvatarAnchor)

        startGameSession()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        setIntent(intent)

        val directData = extractMessageData(intent)

        OpenPigeonLog.i(
            "ShuffleActivity",
            "onNewIntent directKeys=${directData.keys.sorted()} mode=${directData["mode"]} map=${directData["map"]}"
        )

        if (directData.isNotEmpty()) {
            handleMessage(directData)
        } else if (lastMessage.isNotEmpty()) {
            handleMessage(lastMessage)
        }
    }

    private fun startGameSession() {
        sessionId = intent.getStringExtra("SESSION") ?: ""

        val directData = extractMessageData(intent)

        OpenPigeonLog.i(
            "ShuffleActivity",
            "startGameSession sessionIdBlank=${sessionId.isBlank()} " +
                    "extras=${intent.extras?.keySet()?.sorted().orEmpty()} " +
                    "dataUri=${intent.data} directKeys=${directData.keys.sorted()} " +
                    "directMode=${directData["mode"]} directMap=${directData["map"]}"
        )

        if (directData.isNotEmpty() && hasUsableShuffleData(directData)) {
            handleMessage(directData)
        }

        if (sessionId.isBlank()) {
            if (directData.isEmpty()) {
                OpenPigeonLog.w(
                    "ShuffleActivity",
                    "No SESSION and no direct shuffle data; showing local fallback"
                )

                handleMessage(defaultLocalMessage())
            }

            return
        }

        GameSessionIPC(applicationContext) { ipc ->
            gameSessionIPC = ipc

            val currentMessage = try {
                OpenPigeonLog.i(
                    "ShuffleActivity",
                    "IPC getCurrentMessage start sessionIdBlank=${sessionId.isBlank()}"
                )

                ipc.getCurrentMessage(sessionId)
            } catch (t: Throwable) {
                OpenPigeonLog.e("ShuffleActivity", "IPC getCurrentMessage failed", t)
                emptyMap()
            }

            OpenPigeonLog.i(
                "ShuffleActivity",
                "IPC currentMessage ${messageSummary(currentMessage)}"
            )

            if (currentMessage.isNotEmpty()) {
                try {
                    ipc.lockMsgHandle(sessionId)
                } catch (t: Throwable) {
                    OpenPigeonLog.e("ShuffleActivity", "IPC lockMsgHandle failed", t)
                }

                try {
                    ipc.setSuppressNotifications(sessionId, true)
                } catch (t: Throwable) {
                    OpenPigeonLog.e("ShuffleActivity", "IPC setSuppressNotifications(true) failed", t)
                }

                try {
                    ipc.onMessageUpdated(sessionId) { msg ->
                        OpenPigeonLog.i(
                            "ShuffleActivity",
                            "IPC onMessageUpdated ${messageSummary(msg)}"
                        )

                        runOnUiThread {
                            handleMessage(msg)
                        }
                    }
                } catch (t: Throwable) {
                    OpenPigeonLog.e("ShuffleActivity", "IPC onMessageUpdated failed", t)
                }

                runOnUiThread {
                    handleMessage(currentMessage)
                }
            } else {
                runOnUiThread {
                    if (lastMessage.isEmpty()) {
                        OpenPigeonLog.w(
                            "ShuffleActivity",
                            "IPC currentMessage empty; showing local fallback"
                        )

                        handleMessage(defaultLocalMessage())
                    }
                }
            }
        }
    }

    private fun handleMessage(message: Map<String, String>) {
        if (message.isEmpty()) return

        val game = message["game"]

        if (!game.isNullOrBlank() && game != "shuffle") {
            OpenPigeonLog.w(
                "ShuffleActivity",
                "Ignoring non-shuffle message game=$game keys=${message.keys.sorted()}"
            )

            return
        }

        lastMessage = message

        OpenPigeonLog.i(
            "ShuffleActivity",
            "handleMessage ${messageSummary(message)}"
        )

        applyGameData(message)
    }

    private fun applyGameData(data: Map<String, String>) {
        OpenPigeonLog.i(
            "ShuffleActivity",
            "applyGameData mode=${data["mode"]} map=${data["map"]} replay=${data["replay"]?.take(80)}"
        )

        renderer.setGameData(data)
        applyOpponentAvatarFromMessage(data)

        myAvatarAnchor.bringToFront()
        opponentAvatarAnchor.bringToFront()
        settingsButton.bringToFront()
    }

    private fun createAvatarHud() {
        myAvatarAnchor = FrameLayout(this)
        opponentAvatarAnchor = FrameLayout(this)

        val avatarSize = dp(46f).toInt()

        rootFrame.addView(
            myAvatarAnchor,
            FrameLayout.LayoutParams(
                avatarSize,
                avatarSize,
                Gravity.TOP or Gravity.START
            ).apply {
                leftMargin = dp(10f).toInt()
                topMargin = dp(40f).toInt()
            }
        )

        rootFrame.addView(
            opponentAvatarAnchor,
            FrameLayout.LayoutParams(
                avatarSize,
                avatarSize,
                Gravity.TOP or Gravity.END
            ).apply {
                rightMargin = dp(10f).toInt()
                topMargin = dp(40f).toInt()
            }
        )
    }

    private fun createSettingsButton() {
        settingsButton = ImageButton(this).apply {
            background = null
            alpha = 0.86f
            scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(
                dp(4f).toInt(),
                dp(4f).toInt(),
                dp(4f).toInt(),
                dp(4f).toInt()
            )

            val settingsBitmap = loadAssetBitmap("global/settings.png")

            if (settingsBitmap != null) {
                setImageBitmap(settingsBitmap)
            } else {
                OpenPigeonLog.w("ShuffleActivity", "Missing asset: global/settings.png")
            }

            setOnClickListener {
                settingsSheet.open()
            }
        }

        val size = dp(48f).toInt()

        rootFrame.addView(
            settingsButton,
            FrameLayout.LayoutParams(
                size,
                size,
                Gravity.BOTTOM or Gravity.START
            ).apply {
                leftMargin = dp(0f).toInt()
                bottomMargin = dp(16f).toInt()
            }
        )
    }

    private fun applyOpponentAvatarFromMessage(data: Map<String, String>) {
        val localPlayer = resolveLocalPlayer(data)
        val opponentAvatarKey = if (localPlayer == 1) {
            "avatar2"
        } else {
            "avatar1"
        }

        val avatar = data[opponentAvatarKey]

        if (!avatar.isNullOrBlank()) {
            settingsSheet.applyOpponentAvatarString(avatar)
        }
    }

    private fun resolveLocalPlayer(data: Map<String, String>): Int {
        val messagePlayer = data["player"]
            ?.toIntOrNull()
            ?.coerceIn(1, 2)
            ?: 1

        val isYourTurn = parseBoolean(data["isYourTurn"])

        return if (isYourTurn) {
            messagePlayer
        } else {
            3 - messagePlayer
        }
    }

    private fun parseBoolean(value: String?): Boolean {
        return value.equals("true", ignoreCase = true) ||
                value == "1" ||
                value.equals("yes", ignoreCase = true)
    }

    private fun extractMessageData(intent: Intent?): Map<String, String> {
        val out = mutableMapOf<String, String>()

        val dataUri = intent?.data

        if (dataUri != null) {
            try {
                for (name in dataUri.queryParameterNames) {
                    out[name] = dataUri.getQueryParameter(name) ?: ""
                }
            } catch (t: Throwable) {
                OpenPigeonLog.e("ShuffleActivity", "Failed to parse intent.data=$dataUri", t)
            }
        }

        val extras = intent?.extras

        if (extras != null) {
            for (key in extras.keySet()) {
                val value = extras.get(key)

                when (value) {
                    is String -> {
                        out[key] = value

                        if (value.startsWith("data://")) {
                            parsePackedDataUri(value, out)
                        }
                    }

                    is ArrayList<*> -> {
                        val first = value.firstOrNull()
                        if (first != null) {
                            out[key] = first.toString()
                        }
                    }

                    is Array<*> -> {
                        val first = value.firstOrNull()
                        if (first != null) {
                            out[key] = first.toString()
                        }
                    }

                    else -> {
                        if (value != null) {
                            out[key] = value.toString()
                        }
                    }
                }
            }
        }

        return out
    }

    private fun parsePackedDataUri(
        raw: String,
        out: MutableMap<String, String>
    ) {
        try {
            val uri = android.net.Uri.parse(raw)

            for (name in uri.queryParameterNames) {
                out[name] = uri.getQueryParameter(name) ?: ""
            }
        } catch (t: Throwable) {
            OpenPigeonLog.e("ShuffleActivity", "Failed to parse packed data uri=$raw", t)
        }
    }

    private fun hasUsableShuffleData(data: Map<String, String>): Boolean {
        return data["mode"] != null ||
                data["map"] != null ||
                data["replay"] != null
    }

    private fun messageSummary(message: Map<String, String>): String {
        val map = message["map"]
        val mapCount = map
            ?.split(",")
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?.size
            ?: 0

        return "keys=${message.keys.sorted()} " +
                "game=${message["game"]} " +
                "mode=${message["mode"]} " +
                "mapCount=$mapCount " +
                "map=$map " +
                "player=${message["player"]} " +
                "num=${message["num"]} " +
                "replayLen=${message["replay"]?.length ?: 0}"
    }

    private fun defaultLocalMessage(): Map<String, String> {
        return mapOf(
            "game" to "shuffle",
            "mode" to "1",
            "map" to "5,10,5,2,3,10,6,3,2,5,3,6",
            "player" to "1",
            "num" to "1",
            "isYourTurn" to "true",
            "replay" to DEFAULT_REPLAY
        )
    }

    override fun onResume() {
        super.onResume()

        if (sessionId.isNotBlank()) {
            try {
                gameSessionIPC?.setSuppressNotifications(sessionId, true)
            } catch (t: Throwable) {
                OpenPigeonLog.e("ShuffleActivity", "onResume setSuppressNotifications(true) failed", t)
            }
        }
    }

    override fun onPause() {
        if (sessionId.isNotBlank()) {
            try {
                gameSessionIPC?.setSuppressNotifications(sessionId, false)
            } catch (t: Throwable) {
                OpenPigeonLog.e("ShuffleActivity", "onPause setSuppressNotifications(false) failed", t)
            }
        }

        super.onPause()
    }

    private fun loadAssetBitmap(path: String): Bitmap? {
        return try {
            assets.open(path).use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun dp(value: Float): Float {
        return value * resources.displayMetrics.density
    }

    private companion object {
        private const val DEFAULT_REPLAY =
            "board:0,0#" +
                    "0.000000,-215.000000,1,0.000000,0.000000,0.000000#" +
                    "0.000000,215.000000,2,0.000000,0.000000,0.000000#"
    }
}