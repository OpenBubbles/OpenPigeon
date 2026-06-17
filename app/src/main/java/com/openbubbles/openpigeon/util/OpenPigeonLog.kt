package com.openbubbles.openpigeon.util

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.openbubbles.openpigeon.BuildConfig
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale
import android.app.ActivityManager
import android.os.Process
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

object OpenPigeonLog {
    private const val MAX_AGE_MS = 5 * 60 * 1000L
    private const val MAX_ENTRIES = 1000
    private const val LOG_FILE_NAME = "openpigeon_diagnostic.log"
    private const val MAX_FILE_BYTES = 512 * 1024
    private val fileLogEnabled = AtomicBoolean(true)
    private val crashHandlerInstalled = AtomicBoolean(false)

    @Volatile
    private var appContext: Context? = null

    @JvmStatic
    fun installContext(context: Context) {
        appContext = context.applicationContext
        fileLogEnabled.set(true)
        installCrashHandler()
    }

    private fun installCrashHandler() {
        if (!crashHandlerInstalled.compareAndSet(false, true)) {
            return
        }

        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()

        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                e(
                    "UncaughtException",
                    "Uncaught exception on thread=${thread.name}",
                    throwable
                )
            } catch (_: Throwable) {
                // Never let diagnostic logging block the actual crash handler.
            }

            if (previousHandler != null) {
                previousHandler.uncaughtException(thread, throwable)
            } else {
                Process.killProcess(Process.myPid())
                System.exit(10)
            }
        }
    }

    private val formatter = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
    private val entries = ArrayDeque<Entry>()

    private var lastTitleKey: String = ""
    private var lastTitleMs: Long = 0L

    private data class Entry(
        val timeMs: Long,
        val level: String,
        val tag: String,
        val message: String
    )

    @Synchronized
    fun event(tag: String, message: String) {
        add("EVENT", tag, message)
        Log.i(tag, message)
    }

    @Synchronized
    fun title(tag: String, titleText: String, details: String = "") {
        val now = System.currentTimeMillis()
        val key = "$tag|$titleText"

        // Avoid duplicate title blocks if an Activity initializes twice quickly.
        if (key == lastTitleKey && now - lastTitleMs < 1000L) {
            return
        }

        lastTitleKey = key
        lastTitleMs = now

        val stamp = formatter.format(Date(now))

        event(tag, "============================================================")
        if (details.isBlank()) {
            event(tag, "GAME OPENED: $titleText | $stamp")
        } else {
            event(tag, "GAME OPENED: $titleText | $stamp | $details")
        }
        event(tag, "============================================================")
    }

    @Synchronized
    fun gameOpened(gameName: String, details: String = "") {
        title(gameName, gameName, details)
    }

    @Synchronized
    fun w(tag: String, message: String, throwable: Throwable? = null) {
        val finalMessage = messageWithThrowable(message, throwable)
        add("WARN", tag, finalMessage)
        Log.w(tag, message, throwable)
    }

    @Synchronized
    fun e(tag: String, message: String, throwable: Throwable? = null) {
        val finalMessage = messageWithThrowable(message, throwable)
        add("ERROR", tag, finalMessage)
        Log.e(tag, message, throwable)
    }

    @Synchronized
    fun i(tag: String, message: String, throwable: Throwable? = null) {
        val finalMessage = messageWithThrowable(message, throwable)
        add("INFO", tag, finalMessage)
        Log.i(tag, message, throwable)
    }

    @Synchronized
    fun d(tag: String, message: String, throwable: Throwable? = null) {
        val finalMessage = messageWithThrowable(message, throwable)
        add("DEBUG", tag, finalMessage)
        Log.d(tag, message, throwable)
    }

    @JvmStatic
    fun godotLog(level: String, tag: String, message: String) {
        val safeTag = godotTag(tag)
        val safeMessage = sanitize(message).take(3000)

        when (level.uppercase(Locale.US)) {
            "D", "DEBUG" -> d(safeTag, safeMessage)
            "I", "INFO" -> i(safeTag, safeMessage)
            "W", "WARN", "WARNING" -> w(safeTag, safeMessage)
            "E", "ERROR" -> e(safeTag, safeMessage)
            "EVENT" -> event(safeTag, safeMessage)
            else -> i(safeTag, safeMessage)
        }
    }

    @JvmStatic
    fun godotEvent(tag: String, message: String) {
        event(godotTag(tag), sanitize(message).take(3000))
    }

    @JvmStatic
    fun godotD(tag: String, message: String) {
        d(godotTag(tag), sanitize(message).take(3000))
    }

    @JvmStatic
    fun godotI(tag: String, message: String) {
        i(godotTag(tag), sanitize(message).take(3000))
    }

    @JvmStatic
    fun godotW(tag: String, message: String) {
        w(godotTag(tag), sanitize(message).take(3000))
    }

    @JvmStatic
    fun godotE(tag: String, message: String) {
        e(godotTag(tag), sanitize(message).take(3000))
    }

    private fun godotTag(tag: String): String {
        val cleanTag = sanitize(tag)
            .replace(Regex("""[^A-Za-z0-9_.-]"""), "_")
            .ifBlank { "Game" }

        return "Godot-${cleanTag.take(17)}"
    }

    @Synchronized
    private fun add(level: String, tag: String, rawMessage: String) {
        val now = System.currentTimeMillis()
        trimOld(now)

        val safeTag = sanitize(tag).take(48)
        val safeMessage = sanitize(rawMessage).take(3000)

        entries.addLast(
            Entry(
                timeMs = now,
                level = level,
                tag = safeTag,
                message = safeMessage
            )
        )

        while (entries.size > MAX_ENTRIES) {
            entries.removeFirst()
        }

        appendToSharedFile(now, level, safeTag, safeMessage)
    }

    @Synchronized
    private fun trimOld(now: Long = System.currentTimeMillis()) {
        while (entries.isNotEmpty() && now - entries.first().timeMs > MAX_AGE_MS) {
            entries.removeFirst()
        }
    }

    @Synchronized
    fun buildReport(context: Context): String {
        installContext(context)
        val now = System.currentTimeMillis()
        trimOld(now)

        return buildString {
            appendLine("OpenPigeon Diagnostic Report")
            appendLine("Generated: ${Date(now)}")
            appendLine("App version: ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            appendLine("Android: ${Build.VERSION.RELEASE} API ${Build.VERSION.SDK_INT}").appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("Process: ${currentProcessName(context)} pid=${Process.myPid()}")
            appendLine("Captured entries in this process: ${entries.size}")
            appendLine("Window: last ${MAX_AGE_MS / 1000} seconds")
            appendLine()
            appendLine("Privacy:")
            appendLine("This report is sanitized. It should not include player names, messages, session IDs, room IDs, avatars, emails, URLs, IP addresses, or auth tokens.")
            appendLine()
            appendLine("Entries:")

            if (entries.isEmpty()) {
                appendLine("(No captured logs)")
            } else {
                for (entry in entries) {
                    appendLine("${formatter.format(Date(entry.timeMs))} ${entry.level}/${entry.tag}: ${entry.message}")
                }
            }

            val fileEntries = readSharedFile(context)

            appendLine()
            appendLine("Shared file entries:")

            if (fileEntries.isEmpty()) {
                appendLine("(No shared file logs)")
            } else {
                for (line in fileEntries) {
                    appendLine(line)
                }
            }
        }
    }

    fun shareReport(activity: Activity) {
        val report = buildReport(activity)

        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, "OpenPigeon Diagnostic Report")
            putExtra(Intent.EXTRA_TEXT, report)
        }

        activity.startActivity(Intent.createChooser(intent, "Send diagnostic report"))
    }

    private fun appendToSharedFile(timeMs: Long, level: String, tag: String, message: String) {
        if (!fileLogEnabled.get()) return

        try {
            val context = appContext ?: return
            val file = File(context.filesDir, LOG_FILE_NAME)

            if (file.exists() && file.length() > MAX_FILE_BYTES) {
                file.delete()
            }

            val oneLineMessage = message
                .replace("\r", "\\r")
                .replace("\n", "\\n")

            file.appendText(
                "$timeMs|${formatter.format(Date(timeMs))} $level/$tag: $oneLineMessage\n"
            )
        } catch (_: Throwable) {
            fileLogEnabled.set(false)
        }
    }

    private fun readSharedFile(context: Context): List<String> {
        return try {
            val file = File(context.filesDir, LOG_FILE_NAME)
            if (!file.exists()) return emptyList()

            val cutoff = System.currentTimeMillis() - MAX_AGE_MS

            file.readLines()
                .takeLast(MAX_ENTRIES * 3)
                .mapNotNull { line ->
                    val separator = line.indexOf('|')
                    if (separator <= 0) return@mapNotNull null

                    val timeMs = line.substring(0, separator).toLongOrNull()
                        ?: return@mapNotNull null

                    if (timeMs < cutoff) {
                        return@mapNotNull null
                    }

                    line.substring(separator + 1)
                }
                .takeLast(MAX_ENTRIES)
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun messageWithThrowable(message: String, throwable: Throwable?): String {
        if (throwable == null) return message

        val stack = throwable.stackTrace
            .filter { it.className.startsWith("com.openbubbles.openpigeon") }
            .take(12)
            .joinToString("\n") { "\tat $it" }

        return buildString {
            appendLine(message)
            appendLine("${throwable.javaClass.simpleName}: ${throwable.message.orEmpty()}")
            if (stack.isNotBlank()) {
                append(stack)
            }
        }
    }

    private fun currentProcessName(context: Context): String {
        val pid = Process.myPid()
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager

        return manager?.runningAppProcesses
            ?.firstOrNull { it.pid == pid }
            ?.processName
            ?: context.packageName
    }

    private fun sanitize(input: String): String {
        var output = input

        output = output.replace(
            Regex("""[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"""),
            "[email]"
        )

        output = output.replace(
            Regex("""\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"""),
            "[uuid]"
        )

        output = output.replace(
            Regex("""\b(?:\d{1,3}\.){3}\d{1,3}\b"""),
            "[ip]"
        )

        output = output.replace(
            Regex("""https?://\S+"""),
            "[url]"
        )

        output = output.replace(
            Regex("""(?i)\b(session|token|auth|secret|password|sender|player1|player2|room|avatar)\s*[:=]\s*[^,\s|&}]+"""),
            "$1=[redacted]"
        )

        output = output.replace(
            Regex("""(?i)\b(name|message|chat)\s*[:=]\s*[^,\n}]+"""),
            "$1=[redacted]"
        )

        return output
    }
}