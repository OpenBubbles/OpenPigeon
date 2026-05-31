package com.openbubbles.openpigeon.godot

import com.openbubbles.openpigeon.util.OpenPigeonLog
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

class OpenPigeonGodotLogPlugin(godot: Godot) : GodotPlugin(godot) {
    override fun getPluginName(): String {
        return "OpenPigeonLog"
    }

    @UsedByGodot
    fun log(level: String, tag: String, message: String) {
        OpenPigeonLog.godotLog(level, tag, message)
    }

    @UsedByGodot
    fun event(tag: String, message: String) {
        OpenPigeonLog.godotEvent(tag, message)
    }

    @UsedByGodot
    fun d(tag: String, message: String) {
        OpenPigeonLog.godotD(tag, message)
    }

    @UsedByGodot
    fun i(tag: String, message: String) {
        OpenPigeonLog.godotI(tag, message)
    }

    @UsedByGodot
    fun w(tag: String, message: String) {
        OpenPigeonLog.godotW(tag, message)
    }

    @UsedByGodot
    fun e(tag: String, message: String) {
        OpenPigeonLog.godotE(tag, message)
    }
}