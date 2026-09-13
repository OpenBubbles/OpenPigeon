package com.openbubbles.openpigeon.util

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import java.io.File
import java.util.ArrayDeque

class GameSfxPlayer(context: Context, maxStreams: Int = 8) {
    private data class PendingPlay(val volume: Float, val rate: Float)

    private val appContext = context.applicationContext
    private val soundPool = SoundPool.Builder()
        .setMaxStreams(maxStreams)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build()

    private val soundIds = mutableMapOf<String, Int>()
    private val soundPathsById = mutableMapOf<Int, String>()
    private val loadedSoundIds = mutableSetOf<Int>()
    private val pendingPlays = mutableMapOf<Int, MutableList<PendingPlay>>()
    private val recentStreams = ArrayDeque<Int>()
    private var enabled = true
    private var released = false

    init {
        soundPool.setOnLoadCompleteListener { pool, soundId, status ->
            synchronized(this) {
                if (!released) {
                    if (status == 0) {
                        loadedSoundIds += soundId
                        val pending = pendingPlays.remove(soundId).orEmpty()
                        if (enabled) pending.forEach { playLoaded(pool, soundId, it) }
                    } else {
                        pendingPlays.remove(soundId)
                        soundPathsById.remove(soundId)?.let { soundIds.remove(it) }
                        OpenPigeonLog.e("SFX", "Unable to load sound id=$soundId status=$status")
                    }
                }
            }
        }
    }

    @Synchronized
    fun setEnabled(value: Boolean) {
        if (released) return
        enabled = value
        if (!enabled) stopAllLocked()
    }

    @Synchronized
    fun preload(assetPath: String) {
        if (released) return
        ensureLoaded(assetPath)
    }

    @Synchronized
    fun play(assetPath: String, volume: Float = 0.7f, rate: Float = 1.0f) {
        if (released || !enabled) return

        val soundId = ensureLoaded(assetPath) ?: return
        val request = PendingPlay(volume.coerceIn(0f, 1f), rate.coerceIn(0.5f, 2f))

        if (soundId in loadedSoundIds) {
            playLoaded(soundPool, soundId, request)
        } else {
            pendingPlays.getOrPut(soundId) { mutableListOf() }.add(request)
        }
    }

    @Synchronized
    fun stopAll() {
        if (released) return
        stopAllLocked()
    }

    @Synchronized
    fun release() {
        if (released) return
        stopAllLocked()
        released = true
        soundPool.release()
        soundIds.clear()
        soundPathsById.clear()
        loadedSoundIds.clear()
        pendingPlays.clear()
    }

    private fun ensureLoaded(assetPath: String): Int? {
        if (assetPath.isBlank()) return null
        soundIds[assetPath]?.let { return it }

        return try {
            val soundId = try {
                appContext.assets.openFd(assetPath).use { soundPool.load(it, 1) }
            } catch (_: Throwable) {
                val cacheDir = File(appContext.cacheDir, "openpigeon_sfx")
                cacheDir.mkdirs()
                val cacheFile = File(cacheDir, "${assetPath.hashCode()}_${File(assetPath).name}")
                appContext.assets.open(assetPath).use { input -> cacheFile.outputStream().use { output -> input.copyTo(output) } }
                soundPool.load(cacheFile.absolutePath, 1)
            }

            if (soundId == 0) {
                OpenPigeonLog.e("SFX", "Unable to queue sound asset=$assetPath")
                null
            } else {
                soundIds[assetPath] = soundId
                soundPathsById[soundId] = assetPath
                soundId
            }
        } catch (throwable: Throwable) {
            OpenPigeonLog.e("SFX", "Unable to load sound asset=$assetPath", throwable)
            null
        }
    }

    private fun playLoaded(pool: SoundPool, soundId: Int, request: PendingPlay) {
        val streamId = pool.play(soundId, request.volume, request.volume, 1, 0, request.rate)
        if (streamId == 0) return
        recentStreams.addLast(streamId)
        while (recentStreams.size > 64) recentStreams.removeFirst()
    }

    private fun stopAllLocked() {
        pendingPlays.clear()
        while (recentStreams.isNotEmpty()) soundPool.stop(recentStreams.removeFirst())
    }
}