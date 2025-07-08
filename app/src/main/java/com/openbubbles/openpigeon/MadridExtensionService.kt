package com.openbubbles.openpigeon

import android.annotation.SuppressLint
import android.app.Service
import android.content.Intent
import android.os.IBinder

class MadridExtensionService : Service() {

    companion object {
        @SuppressLint("StaticFieldLeak")
        var extension: MadridExtension? = null
    }

    override fun onBind(intent: Intent): IBinder {
        if (extension == null) {
            extension = MadridExtension(this)
        }
        return extension!!
    }

    override fun onCreate() {
        super.onCreate()
        if (extension == null) {
            extension = MadridExtension(this)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        extension = null
    }
}