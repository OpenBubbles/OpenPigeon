package com.openbubbles.openpigeon.util

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack

class LoopingWavPlayer(
    private val context: Context,
    private val assetPath: String,
    private val volume: Float = 0.55f,
) {
    private data class WavData(
        val pcm: ByteArray,
        val sampleRate: Int,
        val channelMask: Int,
        val frameCount: Int,
    )

    private var track: AudioTrack? = null

    @Synchronized
    fun start(): Boolean {
        if (track != null) {
            return resume()
        }

        return try {
            val wav =
                loadWav()

            val newTrack =
                AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(
                                AudioAttributes.USAGE_GAME,
                            )
                            .setContentType(
                                AudioAttributes.CONTENT_TYPE_MUSIC,
                            )
                            .build(),
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setSampleRate(
                                wav.sampleRate,
                            )
                            .setChannelMask(
                                wav.channelMask,
                            )
                            .setEncoding(
                                AudioFormat.ENCODING_PCM_16BIT,
                            )
                            .build(),
                    )
                    .setBufferSizeInBytes(
                        wav.pcm.size,
                    )
                    .setTransferMode(
                        AudioTrack.MODE_STATIC,
                    )
                    .build()

            newTrack.write(
                wav.pcm,
                0,
                wav.pcm.size,
            )

            newTrack.setLoopPoints(
                0,
                wav.frameCount,
                -1,
            )

            newTrack.setVolume(
                volume,
            )

            track =
                newTrack

            newTrack.play()

            true
        } catch (throwable: Throwable) {
            OpenPigeonLog.e(
                "Music",
                "Unable to play $assetPath",
                throwable,
            )

            stop()
            false
        }
    }

    @Synchronized
    fun pause() {
        try {
            track
                ?.takeIf {
                    it.playState ==
                            AudioTrack.PLAYSTATE_PLAYING
                }
                ?.pause()
        } catch (throwable: Throwable) {
            OpenPigeonLog.w(
                "Music",
                "Unable to pause $assetPath",
                throwable,
            )
        }
    }

    @Synchronized
    fun resume(): Boolean {
        val current =
            track
                ?: return start()

        return try {
            if (
                current.playState !=
                AudioTrack.PLAYSTATE_PLAYING
            ) {
                current.play()
            }

            true
        } catch (throwable: Throwable) {
            OpenPigeonLog.w(
                "Music",
                "Unable to resume $assetPath",
                throwable,
            )

            stop()
            start()
        }
    }

    @Synchronized
    fun stop() {
        val current =
            track
                ?: return

        track = null

        try {
            current.pause()
        } catch (_: Throwable) {
        }

        try {
            current.flush()
        } catch (_: Throwable) {
        }

        try {
            current.release()
        } catch (_: Throwable) {
        }
    }

    private fun loadWav(): WavData {
        val bytes =
            context.assets
                .open(
                    assetPath,
                )
                .use {
                    it.readBytes()
                }

        require(
            bytes.size >= 44 &&
                    chunkName(
                        bytes,
                        0,
                    ) == "RIFF" &&
                    chunkName(
                        bytes,
                        8,
                    ) == "WAVE",
        ) {
            "Invalid WAV file: $assetPath"
        }

        var offset = 12
        var audioFormat = 0
        var channels = 0
        var sampleRate = 0
        var bitsPerSample = 0
        var dataStart = -1
        var dataSize = 0

        while (
            offset + 8 <=
            bytes.size
        ) {
            val name =
                chunkName(
                    bytes,
                    offset,
                )

            val size =
                readLeInt(
                    bytes,
                    offset + 4,
                )

            val start =
                offset + 8

            if (
                size < 0 ||
                start + size >
                bytes.size
            ) {
                break
            }

            when (name) {
                "fmt " -> {
                    audioFormat =
                        readLeShort(
                            bytes,
                            start,
                        )

                    channels =
                        readLeShort(
                            bytes,
                            start + 2,
                        )

                    sampleRate =
                        readLeInt(
                            bytes,
                            start + 4,
                        )

                    bitsPerSample =
                        readLeShort(
                            bytes,
                            start + 14,
                        )
                }

                "data" -> {
                    dataStart =
                        start

                    dataSize =
                        size
                }
            }

            offset =
                start +
                        size +
                        (
                                size and 1
                                )
        }

        require(
            audioFormat == 1 &&
                    bitsPerSample == 16 &&
                    channels in 1..2 &&
                    sampleRate > 0 &&
                    dataStart >= 0 &&
                    dataSize > 0,
        ) {
            "WAV must be 16-bit PCM mono/stereo: $assetPath"
        }

        val pcm =
            bytes.copyOfRange(
                dataStart,
                dataStart + dataSize,
            )

        val frameSize =
            channels * 2

        return WavData(
            pcm = pcm,
            sampleRate = sampleRate,
            channelMask =
                if (channels == 1) {
                    AudioFormat.CHANNEL_OUT_MONO
                } else {
                    AudioFormat.CHANNEL_OUT_STEREO
                },
            frameCount =
                pcm.size /
                        frameSize,
        )
    }

    private fun readLeShort(
        bytes: ByteArray,
        offset: Int,
    ): Int {
        return (
                bytes[offset].toInt() and
                        0xff
                ) or
                (
                        (
                                bytes[
                                    offset + 1
                                ].toInt() and
                                        0xff
                                ) shl 8
                        )
    }

    private fun readLeInt(
        bytes: ByteArray,
        offset: Int,
    ): Int {
        return (
                bytes[offset].toInt() and
                        0xff
                ) or
                (
                        (
                                bytes[
                                    offset + 1
                                ].toInt() and
                                        0xff
                                ) shl 8
                        ) or
                (
                        (
                                bytes[
                                    offset + 2
                                ].toInt() and
                                        0xff
                                ) shl 16
                        ) or
                (
                        (
                                bytes[
                                    offset + 3
                                ].toInt() and
                                        0xff
                                ) shl 24
                        )
    }

    private fun chunkName(
        bytes: ByteArray,
        offset: Int,
    ): String {
        return String(
            bytes =
                bytes,
            offset =
                offset,
            length =
                4,
            charset =
                Charsets.US_ASCII,
        )
    }
}