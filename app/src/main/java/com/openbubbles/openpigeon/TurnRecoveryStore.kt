package com.openbubbles.openpigeon

import android.content.Context
import android.util.Base64
import com.openbubbles.openpigeon.util.OpenPigeonLog
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream
import androidx.core.content.edit

data class TurnRecoveryRecord(
    val game: String,
    val baseNum: String,
    val progress: Map<String, String>,
    val pendingUpdates: Map<String, String>,
    val sendAttempted: Boolean,
    val savedAt: Long,
)

object TurnRecoveryStore {
    private const val TAG = "TurnRecovery"
    private const val PREFS_NAME = "openpigeon_turn_recovery"
    private const val VERSION = 1

    private const val COMPRESS_THRESHOLD_BYTES = 4096
    private const val MAX_AGE_MS = 30L * 24L * 60L * 60L * 1000L

    @Synchronized
    fun saveProgress(
        context: Context,
        sessionId: String,
        game: String,
        baseMessage: Map<String, String>,
        progress: Map<String, String>,
    ): Boolean {
        if (sessionId.isBlank() || game.isBlank()) {
            return false
        }

        prune(context)

        val existing = loadRaw(
            context,
            sessionId,
        )

        /*
         * Never allow normal gameplay checkpoints to overwrite a final
         * payload that is waiting to be retried.
         */
        if (existing?.sendAttempted == true) {
            return false
        }

        val record = TurnRecoveryRecord(
            game = game,
            baseNum = existing?.baseNum
                ?.takeIf { it.isNotBlank() }
                ?: baseMessage["num"].orEmpty(),
            progress = progress,
            pendingUpdates = emptyMap(),
            sendAttempted = false,
            savedAt = System.currentTimeMillis(),
        )

        return write(
            context,
            sessionId,
            record,
            reason = "progress",
        )
    }

    @Synchronized
    fun markSendAttempted(
        context: Context,
        sessionId: String,
        game: String,
        baseMessage: Map<String, String>,
        updates: Map<String, String>,
    ): Boolean {
        if (sessionId.isBlank() || game.isBlank() || updates.isEmpty()) {
            return false
        }

        prune(context)

        val existing = loadRaw(
            context,
            sessionId,
        )

        val record = TurnRecoveryRecord(
            game = game,
            baseNum = existing?.baseNum
                ?.takeIf { it.isNotBlank() }
                ?: baseMessage["num"].orEmpty(),
            progress = existing?.progress.orEmpty(),
            pendingUpdates = updates,
            sendAttempted = true,
            savedAt = System.currentTimeMillis(),
        )

        return write(
            context,
            sessionId,
            record,
            reason = "send_attempted",
        )
    }

    @Synchronized
    fun loadForMessage(
        context: Context,
        sessionId: String,
        currentMessage: Map<String, String>,
    ): TurnRecoveryRecord? {
        prune(context)

        val record = loadRaw(
            context,
            sessionId,
        ) ?: return null

        val currentGame = currentMessage["game"].orEmpty()

        if (
            currentGame.isNotBlank() &&
            record.game.isNotBlank() &&
            currentGame != record.game
        ) {
            clear(
                context,
                sessionId,
                "different_game",
            )

            return null
        }

        if (
            record.sendAttempted &&
            record.pendingUpdates.isNotEmpty() &&
            record.pendingUpdates.all { (key, value) ->
                currentMessage[key] == value
            }
        ) {
            clear(
                context,
                sessionId,
                "remote_acknowledged",
            )

            return null
        }

        /*
         * Conventional turn games advance num after a turn. If the remote
         * message has moved beyond the turn this recovery belongs to, the
         * local data is stale.
         *
         * We deliberately do NOT use sender/replay as the stale test because
         * games such as Word Hunt can receive opponent progress while the
         * local player's round is still active.
         */
        val currentNum = currentMessage["num"].orEmpty()

        if (
            record.baseNum.isNotBlank() &&
            currentNum.isNotBlank() &&
            record.baseNum != currentNum
        ) {
            clear(
                context,
                sessionId,
                "remote_turn_advanced",
            )

            return null
        }

        /*
         * A remotely completed game makes unfinished local state obsolete,
         * unless the winner value is itself part of our pending payload.
         */
        if (
            !currentMessage["winner"].isNullOrBlank() &&
            !record.pendingUpdates.containsKey("winner")
        ) {
            clear(
                context,
                sessionId,
                "game_complete",
            )

            return null
        }

        return record
    }

    @Synchronized
    fun load(
        context: Context,
        sessionId: String,
    ): TurnRecoveryRecord? {
        prune(context)
        return loadRaw(context, sessionId)
    }

    @Synchronized
    fun clear(
        context: Context,
        sessionId: String,
        reason: String,
    ) {
        if (sessionId.isBlank()) {
            return
        }

        val preferences = prefs(context)

        if (!preferences.contains(sessionId)) {
            return
        }

        preferences
            .edit(commit = true) {
                remove(sessionId)
            }

        OpenPigeonLog.i(
            TAG,
            "DELETE session=$sessionId reason=$reason",
        )

        logTotal(context)
    }

    @Synchronized
    fun prune(
        context: Context,
    ) {
        val preferences = prefs(context)

        val now = System.currentTimeMillis()

        val expired = preferences.all.keys.filter { sessionId ->
            val record = loadRaw(
                context,
                sessionId,
                pruneFirst = false,
            )

            record == null ||
                    now - record.savedAt > MAX_AGE_MS
        }

        if (expired.isEmpty()) {
            return
        }

        preferences.edit(commit = true) {

            expired.forEach {
                remove(it)
            }

        }

        OpenPigeonLog.i(
            TAG,
            "PRUNE removed=${expired.size}",
        )
    }

    private fun write(
        context: Context,
        sessionId: String,
        record: TurnRecoveryRecord,
        reason: String,
    ): Boolean {
        return try {
            val json = JSONObject().apply {
                put("version", VERSION)
                put("game", record.game)
                put("baseNum", record.baseNum)
                put("sendAttempted", record.sendAttempted)
                put("savedAt", record.savedAt)

                put(
                    "progress",
                    JSONObject(record.progress),
                )

                put(
                    "pendingUpdates",
                    JSONObject(record.pendingUpdates),
                )
            }.toString()

            val rawBytes = json.toByteArray(
                Charsets.UTF_8,
            )

            val encoded = if (
                rawBytes.size >= COMPRESS_THRESHOLD_BYTES
            ) {
                "G:" + Base64.encodeToString(
                    gzip(rawBytes),
                    Base64.NO_WRAP,
                )
            } else {
                "J:$json"
            }

            val saved = prefs(context)
                .edit()
                .putString(sessionId, encoded)
                .commit()

            if (saved) {
                OpenPigeonLog.i(
                    TAG,
                    "SAVE session=$sessionId " +
                            "game=${record.game} " +
                            "reason=$reason " +
                            "attempted=${record.sendAttempted} " +
                            "raw=${rawBytes.size}B " +
                            "stored=${encoded.toByteArray(Charsets.UTF_8).size}B",
                )

                logTotal(context)
            }

            saved
        } catch (throwable: Throwable) {
            OpenPigeonLog.e(
                TAG,
                "Unable to save recovery session=$sessionId",
                throwable,
            )

            false
        }
    }

    private fun loadRaw(
        context: Context,
        sessionId: String,
        pruneFirst: Boolean = false,
    ): TurnRecoveryRecord? {
        if (pruneFirst) {
            prune(context)
        }

        val encoded = prefs(context)
            .getString(
                sessionId,
                null,
            ) ?: return null

        return try {
            val json = when {
                encoded.startsWith("G:") -> {
                    val compressed = Base64.decode(
                        encoded.removePrefix("G:"),
                        Base64.NO_WRAP,
                    )

                    ungzip(compressed).toString(
                        Charsets.UTF_8,
                    )
                }

                encoded.startsWith("J:") -> {
                    encoded.removePrefix("J:")
                }

                else -> {
                    encoded
                }
            }

            val root = JSONObject(json)

            TurnRecoveryRecord(
                game = root.optString(
                    "game",
                ),
                baseNum = root.optString(
                    "baseNum",
                ),
                progress = root
                    .optJSONObject(
                        "progress",
                    )
                    ?.toStringMap()
                    .orEmpty(),
                pendingUpdates = root
                    .optJSONObject(
                        "pendingUpdates",
                    )
                    ?.toStringMap()
                    .orEmpty(),
                sendAttempted = root.optBoolean(
                    "sendAttempted",
                    false,
                ),
                savedAt = root.optLong(
                    "savedAt",
                    0L,
                ),
            )
        } catch (throwable: Throwable) {
            OpenPigeonLog.e(
                TAG,
                "Invalid recovery session=$sessionId",
                throwable,
            )

            prefs(context)
                .edit(commit = true) {
                    remove(sessionId)
                }

            null
        }
    }

    private fun JSONObject.toStringMap(): Map<String, String> {
        val output = mutableMapOf<String, String>()

        val iterator = keys()

        while (iterator.hasNext()) {
            val key = iterator.next()

            output[key] = optString(
                key,
                "",
            )
        }

        return output
    }

    private fun gzip(
        input: ByteArray,
    ): ByteArray {
        val output = ByteArrayOutputStream()

        GZIPOutputStream(output).use {
            it.write(input)
        }

        return output.toByteArray()
    }

    private fun ungzip(
        input: ByteArray,
    ): ByteArray {
        return GZIPInputStream(
            ByteArrayInputStream(input),
        ).use {
            it.readBytes()
        }
    }

    private fun logTotal(
        context: Context,
    ) {
        val values = prefs(context)
            .all
            .values
            .filterIsInstance<String>()

        val bytes = values.sumOf {
            it.toByteArray(
                Charsets.UTF_8,
            ).size
        }

        OpenPigeonLog.i(
            TAG,
            "TOTAL entries=${values.size} stored=${bytes}B",
        )
    }

    private fun prefs(
        context: Context,
    ) = context.applicationContext.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE,
    )
}