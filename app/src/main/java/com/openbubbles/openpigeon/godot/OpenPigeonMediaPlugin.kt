package com.openbubbles.openpigeon.godot

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.openbubbles.openpigeon.util.OpenPigeonLog
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

class OpenPigeonMediaPlugin(godot: Godot) : GodotPlugin(godot) {
    private var musicTrack: AudioTrack? = null
    private var currentPath: String? = null
    private var currentVolume = 0.55f
    private var musicEnabled = true

    companion object {
        private const val PREFS_NAME = "avatar_settings"
        private const val MUSIC_ENABLED_KEY = "global/music_enabled"
        private const val TAG = "OpenPigeonMedia"
    }

    override fun getPluginName(): String {
        return "OpenPigeonMedia"
    }

    private data class WavLoopData(
        val pcm: ByteArray,
        val sampleRate: Int,
        val channelMask: Int,
        val encoding: Int,
        val frameCount: Int
    )

    private fun context(): Context? {
        return activity?.applicationContext
    }

    private fun readMusicEnabled(): Boolean {
        val ctx = context() ?: return true
        return ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(MUSIC_ENABLED_KEY, true)
    }

    private fun writeMusicEnabled(enabled: Boolean) {
        val ctx = context() ?: return

        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(MUSIC_ENABLED_KEY, enabled)
            .apply()
    }

    @UsedByGodot
    fun isMusicEnabled(): Boolean {
        musicEnabled = readMusicEnabled()
        return musicEnabled
    }

    @UsedByGodot
    fun setMusicEnabled(enabled: Boolean) {
        musicEnabled = enabled
        writeMusicEnabled(enabled)

        if (enabled) {
            resumeMusic()
        } else {
            stopMusic()
        }
    }

    @UsedByGodot
    fun playMusic(path: String) {
        playMusicWithVolume(path, currentVolume.toDouble())
    }

    @UsedByGodot
    fun playMusicWithVolume(path: String, volume: Double) {
        musicEnabled = readMusicEnabled()
        val previousPath = currentPath
        currentPath = path
        currentVolume = volume.toFloat().coerceIn(0f, 1f)

        if (!musicEnabled) {
            stopMusic()
            return
        }

        if (musicTrack != null && previousPath == path) {
            resumeMusic()
            return
        }

        releaseMusicPlayer()

        try {
            val wav = loadPcm16Wav(path)

            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(wav.sampleRate)
                        .setChannelMask(wav.channelMask)
                        .setEncoding(wav.encoding)
                        .build()
                )
                .setBufferSizeInBytes(wav.pcm.size)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            track.write(wav.pcm, 0, wav.pcm.size)
            track.setLoopPoints(0, wav.frameCount, -1)
            track.setVolume(currentVolume)

            musicTrack = track
            track.play()

            OpenPigeonLog.i(TAG, "Playing music track $path")
        } catch (e: Exception) {
            OpenPigeonLog.e(TAG, "Unable to play music track $path", e)

            musicEnabled = false
            writeMusicEnabled(false)
            releaseMusicPlayer()
        }
    }

    @UsedByGodot
    fun pauseMusic() {
        try {
            musicTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                }
            }
        } catch (e: Exception) {
            OpenPigeonLog.w(TAG, "Unable to pause music", e)
        }
    }

    @UsedByGodot
    fun resumeMusic() {
        musicEnabled = readMusicEnabled()

        if (!musicEnabled) {
            stopMusic()
            return
        }

        try {
            val track = musicTrack

            if (track == null) {
                currentPath?.let { playMusicWithVolume(it, currentVolume.toDouble()) }
            } else if (track.playState != AudioTrack.PLAYSTATE_PLAYING) {
                track.play()
            }
        } catch (e: Exception) {
            OpenPigeonLog.w(TAG, "Unable to resume music, restarting", e)
            releaseMusicPlayer()
            currentPath?.let { playMusicWithVolume(it, currentVolume.toDouble()) }
        }
    }

    @UsedByGodot
    fun stopMusic() {
        releaseMusicPlayer()
    }

    private fun releaseMusicPlayer() {
        val track = musicTrack ?: return
        musicTrack = null

        try {
            track.pause()
        } catch (_: Exception) {
        }

        try {
            track.release()
        } catch (_: Exception) {
        }
    }

    private fun loadPcm16Wav(path: String): WavLoopData {
        val ctx = context() ?: throw IllegalStateException("Context is not available")
        val bytes = ctx.assets.open(path).use { it.readBytes() }

        if (bytes.size < 44 || chunkName(bytes, 0) != "RIFF" || chunkName(bytes, 8) != "WAVE") {
            throw IllegalArgumentException("Invalid WAV file: $path")
        }

        var offset = 12
        var audioFormat = 0
        var channelCount = 0
        var sampleRate = 0
        var bitsPerSample = 0
        var dataStart = -1
        var dataSize = 0

        while (offset + 8 <= bytes.size) {
            val name = chunkName(bytes, offset)
            val size = readLeInt(bytes, offset + 4)
            val start = offset + 8

            if (start + size > bytes.size) break

            when (name) {
                "fmt " -> {
                    audioFormat = readLeShort(bytes, start)
                    channelCount = readLeShort(bytes, start + 2)
                    sampleRate = readLeInt(bytes, start + 4)
                    bitsPerSample = readLeShort(bytes, start + 14)
                }
                "data" -> {
                    dataStart = start
                    dataSize = size
                }
            }

            offset = start + size + (size and 1)
        }

        if (audioFormat != 1 || bitsPerSample != 16 || channelCount !in 1..2 || dataStart < 0 || dataSize <= 0) {
            throw IllegalArgumentException("WAV must be 16-bit PCM mono/stereo: $path")
        }

        val pcm = bytes.copyOfRange(dataStart, dataStart + dataSize)
        val frameSize = channelCount * 2
        val frameCount = pcm.size / frameSize
        val channelMask = if (channelCount == 1) {
            AudioFormat.CHANNEL_OUT_MONO
        } else {
            AudioFormat.CHANNEL_OUT_STEREO
        }

        return WavLoopData(
            pcm = pcm,
            sampleRate = sampleRate,
            channelMask = channelMask,
            encoding = AudioFormat.ENCODING_PCM_16BIT,
            frameCount = frameCount
        )
    }

    private fun readLeShort(bytes: ByteArray, offset: Int): Int {
        return (bytes[offset].toInt() and 0xff) or
                ((bytes[offset + 1].toInt() and 0xff) shl 8)
    }

    private fun readLeInt(bytes: ByteArray, offset: Int): Int {
        return (bytes[offset].toInt() and 0xff) or
                ((bytes[offset + 1].toInt() and 0xff) shl 8) or
                ((bytes[offset + 2].toInt() and 0xff) shl 16) or
                ((bytes[offset + 3].toInt() and 0xff) shl 24)
    }

    private fun chunkName(bytes: ByteArray, offset: Int): String {
        return String(
            byteArrayOf(
                bytes[offset],
                bytes[offset + 1],
                bytes[offset + 2],
                bytes[offset + 3]
            )
        )
    }
}