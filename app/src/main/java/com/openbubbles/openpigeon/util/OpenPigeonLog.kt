package com.openbubbles.openpigeon.util

import android.app.Activity
import android.app.ActivityManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.util.Log
import androidx.core.content.FileProvider
import com.openbubbles.openpigeon.BuildConfig
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.system.exitProcess
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.os.StatFs
import android.os.SystemClock
import java.util.concurrent.ConcurrentHashMap

object OpenPigeonLog {
    private const val DIAGNOSTIC_EMAIL = "support@colerabe.com"
    private const val REPORT_FORMAT_VERSION = 2
    private const val SANITIZER_VERSION = 2
    private const val REPORT_DIRECTORY = "diagnostic_reports"
    private const val REPORT_RETENTION_MS = 24L * 60L * 60L * 1000L
    private const val MAX_DIAGNOSTIC_STATE_ENTRIES = 40
    private const val MAX_DIAGNOSTIC_STATE_VALUE_LENGTH = 256
    private val diagnosticState = ConcurrentHashMap<String, String>()

    private val diagnosticStateKeyRegex =
        Regex("""^[A-Za-z0-9_.-]{1,48}$""")

    private val uuidRegex = Regex(
        """(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?:[A-Za-z0-9_-]+)?\b"""
    )

    private val identifierAliases = linkedMapOf<String, String>()
    private val aliasRedirects = linkedMapOf<String, String>()
    private var nextGenericUid = 1
    private var nextSession = 1
    private var nextRoom = 1
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
                exitProcess(10)
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

    @Suppress("unused")
    @JvmStatic
    fun setDiagnosticState(key: String, value: String) {
        if (!diagnosticStateKeyRegex.matches(key)) {
            w(
                "Diagnostics",
                "Rejected invalid diagnostic state key"
            )
            return
        }

        if (
            !diagnosticState.containsKey(key) &&
            diagnosticState.size >= MAX_DIAGNOSTIC_STATE_ENTRIES
        ) {
            w(
                "Diagnostics",
                "Diagnostic state entry limit reached"
            )
            return
        }

        diagnosticState[key] = sanitize(value)
            .replace("\r", " ")
            .replace("\n", " ")
            .take(MAX_DIAGNOSTIC_STATE_VALUE_LENGTH)
    }

    @Suppress("unused")
    @JvmStatic
    fun removeDiagnosticState(key: String) {
        diagnosticState.remove(key)
    }

    @Suppress("unused")
    @JvmStatic
    fun clearDiagnosticState() {
        diagnosticState.clear()
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
        val cleanTag = normalizeAliasRedirects(
            sanitize(tag)
        )
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

        val memoryEntries = entries.map { entry ->
            val normalizedTag = normalizeAliasRedirects(entry.tag)
            val normalizedMessage = normalizeAliasRedirects(entry.message)

            "${formatter.format(Date(entry.timeMs))} " +
                    "${entry.level}/$normalizedTag: $normalizedMessage"
        }

        val fileEntries = readSharedFile(context)
            .map(::normalizeAliasRedirects)

        return buildString {
            appendLine("OpenPigeon Diagnostic Report")
            appendLine("Report format: $REPORT_FORMAT_VERSION")
            appendLine("Sanitizer version: $SANITIZER_VERSION")
            appendLine("Generated UTC: ${formatUtc(now)}")
            appendLine(
                "App version: ${BuildConfig.VERSION_NAME} " +
                        "(${BuildConfig.VERSION_CODE})"
            )
            appendLine("Build type: ${BuildConfig.BUILD_TYPE}")
            appendLine(
                "Android: ${Build.VERSION.RELEASE} " +
                        "API ${Build.VERSION.SDK_INT}"
            )
            appendLine(
                "Device: ${Build.MANUFACTURER} ${Build.MODEL}"
            )
            appendLine("Device code: ${Build.DEVICE}")
            appendLine(
                "Process: ${currentProcessName(context)} " +
                        "pid=${Process.myPid()}"
            )

            val metrics = context.resources.displayMetrics
            val configuration = context.resources.configuration

            val locale =
                if (configuration.locales.isEmpty) {
                    Locale.getDefault()
                } else {
                    configuration.locales[0]
                }

            appendLine(
                "Screen: ${metrics.widthPixels}x${metrics.heightPixels}px"
            )
            appendLine("Density DPI: ${metrics.densityDpi}")
            appendLine("Font scale: ${configuration.fontScale}")
            appendLine("Orientation: ${configuration.orientation}")

            appendLine("Locale: $locale")

            appendLine("Captured memory entries: ${memoryEntries.size}")
            appendLine("Captured shared entries: ${fileEntries.size}")
            appendLine("Window: last ${MAX_AGE_MS / 1000} seconds")
            appendLine()

            appendLine("Privacy")
            appendLine(
                "Known identifiers are replaced with stable aliases such as " +
                        "p1uid, p2uid, myuid, uid1, session1, and room1."
            )
            appendLine(
                "Emails, URLs, IP addresses, credentials, avatar data, " +
                        "contact names, and user-message fields are removed."
            )
            appendLine()

            appendLine("Entries from current process")
            if (memoryEntries.isEmpty()) {
                appendLine("(No captured logs)")
            } else {
                memoryEntries.forEach(::appendLine)
            }

            appendLine()
            appendLine("Entries from shared process log")
            if (fileEntries.isEmpty()) {
                appendLine("(No shared file logs)")
            } else {
                fileEntries.forEach(::appendLine)
            }
        }
    }

    private fun buildStateSnapshot(activity: Activity): String {
        val activityManager =
            activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        val audioManager =
            activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val internalStorage = StatFs(activity.filesDir.absolutePath)

        val totalInternalBytes =
            internalStorage.blockCountLong * internalStorage.blockSizeLong

        val availableInternalBytes =
            internalStorage.availableBlocksLong * internalStorage.blockSizeLong

        val packageInfo = activity.packageManager.getPackageInfo(
            activity.packageName,
            0
        )

        val installer = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                activity.packageManager
                    .getInstallSourceInfo(activity.packageName)
                    .installingPackageName
            } else {
                @Suppress("DEPRECATION")
                activity.packageManager
                    .getInstallerPackageName(activity.packageName)
            }
        }.getOrNull() ?: "unknown"

        val windowSize = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = activity.windowManager
                .currentWindowMetrics
                .bounds

            "${bounds.width()}x${bounds.height()}"
        } else {
            val metrics = activity.resources.displayMetrics
            "${metrics.widthPixels}x${metrics.heightPixels}"
        }

        val orientation = when (
            activity.resources.configuration.orientation
        ) {
            Configuration.ORIENTATION_LANDSCAPE -> "landscape"
            Configuration.ORIENTATION_PORTRAIT -> "portrait"
            else -> "undefined"
        }

        val keyboardType = when (
            activity.resources.configuration.keyboard
        ) {
            Configuration.KEYBOARD_NOKEYS -> "none"
            Configuration.KEYBOARD_QWERTY -> "qwerty"
            Configuration.KEYBOARD_12KEY -> "12-key"
            else -> "undefined"
        }

        val touchscreenPresent =
            activity.packageManager.hasSystemFeature(
                PackageManager.FEATURE_TOUCHSCREEN
            )

        val diagnosticFile = File(
            activity.filesDir,
            LOG_FILE_NAME
        )

        return buildString {
            appendLine("OpenPigeon Diagnostic State")
            appendLine("Generated UTC: ${formatUtc(System.currentTimeMillis())}")
            appendLine()

            appendLine("[Application]")
            appendLine("Activity: ${activity.javaClass.simpleName}")
            appendLine("Process: ${currentProcessName(activity)}")
            appendLine("PID: ${Process.myPid()}")
            appendLine("App uptime: ${formatDuration(SystemClock.elapsedRealtime())}")
            appendLine("Foreground activity finishing: ${activity.isFinishing}")
            appendLine("Multi-window: ${activity.isInMultiWindowMode}")
            appendLine("Installer: $installer")
            appendLine("First installed UTC: ${formatUtc(packageInfo.firstInstallTime)}")
            appendLine("Last updated UTC: ${formatUtc(packageInfo.lastUpdateTime)}")
            appendLine()

            appendLine("[Window]")
            appendLine("Window size: $windowSize")
            appendLine("Orientation: $orientation")
            appendLine(
                "Density DPI: ${activity.resources.displayMetrics.densityDpi}"
            )
            appendLine(
                "Font scale: ${activity.resources.configuration.fontScale}"
            )
            appendLine()

            appendLine("[Device]")
            appendLine("Manufacturer: ${Build.MANUFACTURER}")
            appendLine("Model: ${Build.MODEL}")
            appendLine("Device code: ${Build.DEVICE}")
            appendLine("Supported ABIs: ${Build.SUPPORTED_ABIS.joinToString()}")
            appendLine("Touchscreen present: $touchscreenPresent")
            appendLine("Hardware keyboard: $keyboardType")
            appendLine()

            appendLine("[Memory]")
            appendLine(
                "Available system memory: ${formatBytes(memoryInfo.availMem)}"
            )
            appendLine(
                "Total system memory: ${formatBytes(memoryInfo.totalMem)}"
            )
            appendLine("Low-memory state: ${memoryInfo.lowMemory}")
            appendLine(
                "Low-memory threshold: ${formatBytes(memoryInfo.threshold)}"
            )
            appendLine(
                "Runtime memory used: ${
                    formatBytes(
                        Runtime.getRuntime().totalMemory() -
                                Runtime.getRuntime().freeMemory()
                    )
                }"
            )
            appendLine(
                "Runtime memory maximum: ${
                    formatBytes(Runtime.getRuntime().maxMemory())
                }"
            )
            appendLine()

            appendLine("[Storage]")
            appendLine(
                "Internal storage available: ${formatBytes(availableInternalBytes)}"
            )
            appendLine(
                "Internal storage total: ${formatBytes(totalInternalBytes)}"
            )
            appendLine(
                "Diagnostic log size: ${
                    formatBytes(
                        if (diagnosticFile.exists()) {
                            diagnosticFile.length()
                        } else {
                            0L
                        }
                    )
                }"
            )
            appendLine()

            appendLine("[Audio]")
            appendLine(
                "Music volume: ${
                    audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                }/${
                    audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                }"
            )
            appendLine(
                "Music stream muted: ${
                    audioManager.isStreamMute(AudioManager.STREAM_MUSIC)
                }"
            )
            appendLine()

            appendLine("[Game and Runtime State]")

            val snapshot = diagnosticState
                .toSortedMap()

            if (snapshot.isEmpty()) {
                appendLine("(No game-specific state was published)")
            } else {
                snapshot.forEach { (key, value) ->
                    appendLine("$key: ${normalizeAliasRedirects(value)}")
                }
            }
        }
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes < 1024L) {
            return "$bytes B"
        }

        val units = arrayOf("KB", "MB", "GB", "TB")
        var value = bytes.toDouble()
        var unitIndex = -1

        while (value >= 1024.0 && unitIndex < units.lastIndex) {
            value /= 1024.0
            unitIndex++
        }

        return String.format(
            Locale.US,
            "%.1f %s",
            value,
            units[unitIndex]
        )
    }

    private fun formatDuration(milliseconds: Long): String {
        val totalSeconds = milliseconds / 1000L
        val hours = totalSeconds / 3600L
        val minutes = (totalSeconds % 3600L) / 60L
        val seconds = totalSeconds % 60L

        return "%02d:%02d:%02d".format(
            Locale.US,
            hours,
            minutes,
            seconds
        )
    }

    private fun formatUtc(timeMs: Long): String {
        return SimpleDateFormat(
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            Locale.US
        ).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(timeMs))
    }

    fun shareReport(activity: Activity) {
        val reportId = createReportId()
        val report = buildReport(activity)
        val zipFile = createDiagnosticZip(
            activity = activity,
            reportId = reportId,
            report = report
        )

        val reportUri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.fileprovider",
            zipFile
        )

        val subject =
            "OpenPigeon Diagnostic $reportId - " +
                    "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

        val body = """
        OpenPigeon diagnostic report attached.

        Report ID: $reportId
        App version: ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})
        Android: ${Build.VERSION.RELEASE} / API ${Build.VERSION.SDK_INT}
        Device: ${Build.MANUFACTURER} ${Build.MODEL}

        Please describe what happened:




        The attached diagnostic report was sanitized on the device before it was shared.
    """.trimIndent()

        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"

            putExtra(
                Intent.EXTRA_EMAIL,
                arrayOf(DIAGNOSTIC_EMAIL)
            )

            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, body)
            putExtra(Intent.EXTRA_STREAM, reportUri)

            clipData = ClipData.newUri(
                activity.contentResolver,
                "OpenPigeon diagnostic report",
                reportUri
            )

            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        activity.startActivity(
            Intent.createChooser(
                sendIntent,
                "Send diagnostic report"
            )
        )
    }

    private fun createDiagnosticZip(
        activity: Activity,
        reportId: String,
        report: String
    ): File {
        val reportDirectory = File(
            activity.cacheDir,
            REPORT_DIRECTORY
        ).apply {
            mkdirs()
        }

        deleteExpiredReports(reportDirectory)

        val zipFile = File(
            reportDirectory,
            "openpigeon-diagnostic-$reportId.zip"
        )

        ZipOutputStream(
            BufferedOutputStream(
                FileOutputStream(zipFile)
            )
        ).use { zip ->
            writeZipEntry(
                zip = zip,
                filename = "report.txt",
                text = report
            )

            writeZipEntry(
                zip = zip,
                filename = "state.txt",
                text = buildStateSnapshot(activity)
            )

            writeZipEntry(
                zip = zip,
                filename = "privacy.txt",
                text = """
            OpenPigeon Diagnostic Report

            This report was created only after the user selected
            Send Diagnostic Report.

            Identifiers are replaced with stable aliases that apply only
            within this diagnostic report. Examples include p1uid, p2uid,
            myuid, uid1, session1, and room1.

            Emails, URLs, IP addresses, credentials, avatar data, contact
            names, and user-message fields are removed before sharing.
        """.trimIndent()
            )
        }

        return zipFile
    }


    private fun writeZipEntry(
        zip: ZipOutputStream,
        filename: String,
        text: String
    ) {
        zip.putNextEntry(ZipEntry(filename))
        zip.write(text.toByteArray(Charsets.UTF_8))
        zip.closeEntry()
    }


    private fun deleteExpiredReports(directory: File) {
        val cutoff = System.currentTimeMillis() - REPORT_RETENTION_MS

        directory.listFiles()
            ?.filter { it.isFile && it.lastModified() < cutoff }
            ?.forEach { file ->
                runCatching {
                    file.delete()
                }
            }
    }


    private fun createReportId(): String {
        val timestamp = SimpleDateFormat(
            "yyyyMMdd-HHmmss",
            Locale.US
        ).format(Date())

        val suffix = java.util.UUID.randomUUID()
            .toString()
            .replace("-", "")
            .take(6)
            .uppercase(Locale.US)

        return "OP-$timestamp-$suffix"
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

                    normalizeAliasRedirects(
                        line.substring(separator + 1)
                    )
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

    @Synchronized
    private fun sanitize(input: String): String {
        if (input.isBlank()) return input

        discoverSemanticIdentifiers(input)

        uuidRegex.findAll(input).forEach { match ->
            registerIdentifier(
                original = match.value,
                preferredAlias = "uid${nextGenericUid}",
                allowSemanticUpgrade = false
            )

            if (identifierAliases[match.value] == "uid${nextGenericUid}") {
                nextGenericUid++
            }
        }

        var output = replaceKnownIdentifiers(input)
        output = normalizeAliasRedirects(output)

        output = output.replace(
            Regex("""[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"""),
            "[email]"
        )

        output = output.replace(
            Regex("""\b(?:\d{1,3}\.){3}\d{1,3}\b"""),
            "[ip]"
        )

        output = output.replace(
            Regex("""(?i)\bhttps?://[^\s"'<>]+"""),
            "[url]"
        )

        output = output.replace(
            Regex(
                """(?i)\b(token|auth|authorization|secret|password|passwd|api[_-]?key|access[_-]?token|refresh[_-]?token)\s*[:=]\s*["']?[^,\s|&}\]]+"""
            ),
            "$1=[redacted]"
        )

        output = output.replace(
            Regex(
                """(?i)(["']?avatar[12]?["']?\s*[:=]\s*)(\[\s*)?["']?[^}\]\n]+"""
            ),
            "$1[avatar-redacted]"
        )

        output = output.replace(
            Regex(
                """(?i)\b(name|displayName|chatName|contactName)\s*[:=]\s*[^,\n}]+"""
            ),
            "$1=[redacted]"
        )

        output = output.replace(
            Regex(
                """(?i)\b(userMessage|chatMessage|messageText|bodyText)\s*[:=]\s*[^,\n}]+"""
            ),
            "$1=[redacted]"
        )

        return output
    }


    @Synchronized
    private fun discoverSemanticIdentifiers(input: String) {
        discoverFieldValues(
            input = input,
            fieldNames = listOf(
                "player1",
                "player1Id",
                "player_1",
                "uuid1"
            ),
            alias = "p1uid"
        )

        discoverFieldValues(
            input = input,
            fieldNames = listOf(
                "player2",
                "player2Id",
                "player_2",
                "uuid2"
            ),
            alias = "p2uid"
        )

        discoverFieldValues(
            input = input,
            fieldNames = listOf(
                "myPlayerId",
                "my_uuid",
                "localPlayerId",
                "local_player_id",
                "myUUID"
            ),
            alias = "myuid"
        )

        discoverFieldValues(
            input = input,
            fieldNames = listOf(
                "sender",
                "senderId",
                "sender_uuid"
            ),
            alias = "senderuid"
        )

        discoverNumberedFieldValues(
            input = input,
            fieldNames = listOf(
                "session",
                "sessionId",
                "session_id"
            ),
            prefix = "session",
            nextNumber = {
                nextSession++
            }
        )

        discoverNumberedFieldValues(
            input = input,
            fieldNames = listOf(
                "room",
                "roomId",
                "room_id",
                "chatGuid",
                "chatId"
            ),
            prefix = "room",
            nextNumber = {
                nextRoom++
            }
        )
    }


    private fun discoverFieldValues(
        input: String,
        fieldNames: List<String>,
        alias: String
    ) {
        fieldNames.forEach { field ->
            fieldValuePatterns(field).forEach { pattern ->
                pattern.findAll(input).forEach { match ->
                    val value = match.groupValues
                        .getOrNull(1)
                        ?.trim()
                        .orEmpty()

                    registerIdentifier(
                        original = value,
                        preferredAlias = alias,
                        allowSemanticUpgrade = true
                    )
                }
            }
        }
    }


    private fun discoverNumberedFieldValues(
        input: String,
        fieldNames: List<String>,
        prefix: String,
        nextNumber: () -> Int
    ) {
        fieldNames.forEach { field ->
            fieldValuePatterns(field).forEach { pattern ->
                pattern.findAll(input).forEach { match ->
                    val value = match.groupValues
                        .getOrNull(1)
                        ?.trim()
                        .orEmpty()

                    if (!isUsefulIdentifier(value)) {
                        return@forEach
                    }

                    if (!identifierAliases.containsKey(value)) {
                        registerIdentifier(
                            original = value,
                            preferredAlias = "$prefix${nextNumber()}",
                            allowSemanticUpgrade = false
                        )
                    }
                }
            }
        }
    }


    private fun fieldValuePatterns(field: String): List<Regex> {
        val escaped = Regex.escape(field)

        return listOf(
            Regex(
                """(?i)["']?$escaped["']?\s*[:=]\s*["']([^"',}\]\s]+)["']?"""
            ),

            Regex(
                """(?i)["']?$escaped["']?\s*:\s*\[\s*["']([^"']+)["']"""
            )
        )
    }


    @Synchronized
    private fun registerIdentifier(
        original: String,
        preferredAlias: String,
        allowSemanticUpgrade: Boolean
    ) {
        val cleaned = original.trim()

        if (!isUsefulIdentifier(cleaned)) {
            return
        }

        val existing = identifierAliases[cleaned]

        if (existing == null) {
            identifierAliases[cleaned] = preferredAlias
            return
        }

        if (
            allowSemanticUpgrade &&
            existing.startsWith("uid") &&
            existing != preferredAlias
        ) {
            identifierAliases[cleaned] = preferredAlias
            aliasRedirects[existing] = preferredAlias
        }
    }


    private fun isUsefulIdentifier(value: String): Boolean {
        if (value.length < 6) return false

        return when (value.lowercase(Locale.US)) {
            "null",
            "none",
            "unknown",
            "undefined",
            "[redacted]" -> false

            else -> true
        }
    }


    @Synchronized
    private fun replaceKnownIdentifiers(input: String): String {
        var output = input

        identifierAliases.entries
            .sortedByDescending { it.key.length }
            .forEach { (original, alias) ->
                output = output.replace(original, alias)
            }

        return output
    }


    @Synchronized
    private fun normalizeAliasRedirects(input: String): String {
        var output = input

        aliasRedirects.forEach { (oldAlias, newAlias) ->
            output = output.replace(
                Regex("""\b${Regex.escape(oldAlias)}\b"""),
                newAlias
            )
        }

        return output
    }
}