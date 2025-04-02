package com.example.openbubblesextension

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.util.Log
import android.widget.RemoteViews
import com.bluebubbles.messaging.IKeyboardHandle
import com.bluebubbles.messaging.IMadridExtension
import com.bluebubbles.messaging.IMessageViewHandle
import com.bluebubbles.messaging.ITaskCompleteCallback
import com.bluebubbles.messaging.IViewUpdateCallback
import com.bluebubbles.messaging.MadridMessage


class MadridExtension(private val context: Context) : IMadridExtension.Stub() {

    companion object {
        var currentKeyboardHandle: IKeyboardHandle? = null
        val cryption = Cryption();
    }

    private var callback: IViewUpdateCallback? = null;

    override fun keyboardClosed() {
        currentKeyboardHandle = null
    }

    override fun keyboardOpened(callback: IViewUpdateCallback?, handle: IKeyboardHandle?): RemoteViews {
        this.callback = callback
        var view = RemoteViews(context.packageName, R.layout.keyboard)

        currentKeyboardHandle = handle

        val wordHuntIntentWithData = Intent(
            context,
            KeyboardClickReceiver::class.java
        ).apply {
            putExtra("game_name", "hunt")
        }

        val basketballIntentWithData = Intent(
            context,
            KeyboardClickReceiver::class.java
        ).apply {
            putExtra("game_name", "basketball")
        }

        val wordHuntPendingIntent = PendingIntent.getBroadcast(context, 7, wordHuntIntentWithData,
            PendingIntent.FLAG_IMMUTABLE)
        val basketballPendingIntent = PendingIntent.getBroadcast(context, 8, basketballIntentWithData,
            PendingIntent.FLAG_IMMUTABLE)

        view.setOnClickPendingIntent(R.id.wordHuntButton, wordHuntPendingIntent)
        view.setOnClickPendingIntent(R.id.basketballButton, basketballPendingIntent)

        return view
    }

    override fun didTapTemplate(message: MadridMessage?, handle: IMessageViewHandle?) {
//        val intent = Intent(context, MessageActivity::class.java)
//        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
//        context.startActivity(intent)
        handle?.lock()
        Log.i("here", message!!.caption)
        message.caption = "no way jose"
        handle!!.updateMessage(message, object : ITaskCompleteCallback.Stub() {
            override fun complete() {
                Log.i("sent!", "done")
                handle.unlock()
            }
        })
    }

    override fun getLiveView(
        callback: IViewUpdateCallback?,
        message: MadridMessage?,
        handle: IMessageViewHandle?
    ): RemoteViews {
        Log.i("live view", "init")
        var view = RemoteViews(context.packageName, R.layout.livemsg)

        val bitmap = BitmapFactory.decodeResource(context.resources, R.drawable.my_image)
        view.setImageViewBitmap(R.id.imageView, bitmap)

        return view
    }

    override fun messageUpdated(message: MadridMessage?) {
        val url = message?.url
        val session = message?.session
        val ldText = message?.ldText
        val isLive = message?.isLive
        val gamePigeon = url?.let { GamePigeon(it) }
        gamePigeon?.data()?.let { Log.i("Message JSON", it.toString(4)) }
        Log.i("update", "message")
    }

}