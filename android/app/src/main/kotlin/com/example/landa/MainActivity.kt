package com.example.landa

import android.Manifest
import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "landa/network"
        private const val LOCK_TAG = "landa_multicast_lock"
        private const val DOWNLOAD_CHANNEL_ID = "landa_downloads"
        private const val DOWNLOAD_CHANNEL_NAME = "Landa downloads"
        private const val DOWNLOAD_CHANNEL_DESCRIPTION = "File transfer progress and completion"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1401
    }

    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureDownloadNotificationChannel()
        requestNotificationPermissionIfNeeded()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    acquireMulticastLock()
                    result.success(null)
                }
                "releaseMulticastLock" -> {
                    releaseMulticastLock()
                    result.success(null)
                }
                "getPublicDownloadsPath" -> {
                    val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                    result.success(downloads?.absolutePath)
                }
                "copyFileToDownloads" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val relativePath = call.argument<String>("relativePath")
                    val appFolderName = call.argument<String>("appFolderName") ?: "Landa"
                    if (sourcePath.isNullOrBlank() || relativePath.isNullOrBlank()) {
                        result.error("invalid_args", "sourcePath/relativePath are required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val destination = copyFileToDownloads(
                            sourcePath = sourcePath,
                            relativePath = relativePath,
                            appFolderName = appFolderName,
                        )
                        result.success(destination)
                    } catch (t: Throwable) {
                        result.error("copy_failed", t.message, null)
                    }
                }
                "showDownloadProgressNotification" -> {
                    val requestId = call.argument<String>("requestId")
                    val senderName = call.argument<String>("senderName") ?: "Device"
                    val receivedBytes = call.argument<Number>("receivedBytes")?.toLong() ?: 0L
                    val totalBytes = call.argument<Number>("totalBytes")?.toLong() ?: 0L
                    if (requestId.isNullOrBlank()) {
                        result.error("invalid_args", "requestId is required", null)
                        return@setMethodCallHandler
                    }
                    showDownloadProgressNotification(
                        requestId = requestId,
                        senderName = senderName,
                        receivedBytes = receivedBytes,
                        totalBytes = totalBytes,
                    )
                    result.success(null)
                }
                "showDownloadCompletedNotification" -> {
                    val requestId = call.argument<String>("requestId")
                    val savedPaths = (call.argument<List<String>>("savedPaths") ?: emptyList())
                        .map { it.trim() }
                        .filter { it.isNotEmpty() }
                    val directoryPath = call.argument<String>("directoryPath")?.trim()
                    if (requestId.isNullOrBlank()) {
                        result.error("invalid_args", "requestId is required", null)
                        return@setMethodCallHandler
                    }
                    showDownloadCompletedNotification(
                        requestId = requestId,
                        savedPaths = savedPaths,
                        directoryPath = directoryPath,
                    )
                    result.success(null)
                }
                "showDownloadFailedNotification" -> {
                    val requestId = call.argument<String>("requestId")
                    val message = call.argument<String>("message") ?: "Download failed"
                    if (requestId.isNullOrBlank()) {
                        result.error("invalid_args", "requestId is required", null)
                        return@setMethodCallHandler
                    }
                    showDownloadFailedNotification(
                        requestId = requestId,
                        message = message,
                    )
                    result.success(null)
                }
                "showDownloadAttemptNotification" -> {
                    val requesterName = call.argument<String>("requesterName") ?: "Unknown device"
                    val shareLabel = call.argument<String>("shareLabel") ?: "Shared files"
                    val requestedFilesCount =
                        call.argument<Number>("requestedFilesCount")?.toInt() ?: 0
                    showDownloadAttemptNotification(
                        requesterName = requesterName,
                        shareLabel = shareLabel,
                        requestedFilesCount = requestedFilesCount,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }

    private fun acquireMulticastLock() {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return

        if (multicastLock == null) {
            multicastLock = wifiManager.createMulticastLock(LOCK_TAG).apply {
                setReferenceCounted(true)
            }
        }

        if (multicastLock?.isHeld != true) {
            multicastLock?.acquire()
        }
    }

    private fun releaseMulticastLock() {
        if (multicastLock?.isHeld == true) {
            multicastLock?.release()
        }
    }

    private fun copyFileToDownloads(
        sourcePath: String,
        relativePath: String,
        appFolderName: String,
    ): String {
        val sourceFile = File(sourcePath)
        require(sourceFile.exists()) { "Source file does not exist: $sourcePath" }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return copyFileToDownloadsScoped(
                sourceFile = sourceFile,
                relativePath = relativePath,
                appFolderName = appFolderName,
            )
        }

        val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val baseTarget = File(downloads, "$appFolderName/$relativePath")
        val target = nextAvailableFile(baseTarget)
        target.parentFile?.mkdirs()
        sourceFile.copyTo(target, overwrite = false)
        return target.absolutePath
    }

    private fun copyFileToDownloadsScoped(
        sourceFile: File,
        relativePath: String,
        appFolderName: String,
    ): String {
        val resolver = applicationContext.contentResolver
        val normalized = relativePath.replace('\\', '/').trim('/')
        val displayName = normalized.substringAfterLast('/')
        val subPath = normalized.substringBeforeLast('/', "")

        val baseRelative = if (subPath.isBlank()) {
            "Download/$appFolderName/"
        } else {
            "Download/$appFolderName/$subPath/"
        }

        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.RELATIVE_PATH, baseRelative)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val itemUri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Failed to create MediaStore item")

        resolver.openOutputStream(itemUri)?.use { output ->
            FileInputStream(sourceFile).use { input ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Failed to open output stream")

        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(itemUri, values, null, null)

        val destination = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "$appFolderName/$normalized",
        )
        return destination.absolutePath
    }

    private fun nextAvailableFile(base: File): File {
        if (!base.exists()) {
            return base
        }

        val parent = base.parentFile ?: return base
        val name = base.nameWithoutExtension
        val ext = if (base.extension.isBlank()) "" else ".${base.extension}"
        var counter = 1
        while (true) {
            val candidate = File(parent, "$name ($counter)$ext")
            if (!candidate.exists()) {
                return candidate
            }
            counter += 1
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun ensureDownloadNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java) ?: return
        val existing = manager.getNotificationChannel(DOWNLOAD_CHANNEL_ID)
        if (existing != null) {
            return
        }

        val channel = NotificationChannel(
            DOWNLOAD_CHANNEL_ID,
            DOWNLOAD_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = DOWNLOAD_CHANNEL_DESCRIPTION
        }
        manager.createNotificationChannel(channel)
    }

    private fun canPostNotifications(): Boolean {
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) {
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun showDownloadProgressNotification(
        requestId: String,
        senderName: String,
        receivedBytes: Long,
        totalBytes: Long,
    ) {
        if (!canPostNotifications()) {
            return
        }

        val notificationId = notificationIdForRequest(requestId)
        val boundedTotal = totalBytes.coerceAtLeast(0L)
        val boundedReceived = receivedBytes.coerceAtLeast(0L)
        val indeterminate = boundedTotal <= 0L
        val progress = if (indeterminate) {
            0
        } else {
            ((boundedReceived.coerceAtMost(boundedTotal) * 100L) / boundedTotal).toInt()
        }
        val text = if (indeterminate) {
            "Preparing transfer..."
        } else {
            "Received $progress%"
        }

        val notification = NotificationCompat.Builder(this, DOWNLOAD_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Downloading from $senderName")
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setProgress(100, progress, indeterminate)
            .build()

        NotificationManagerCompat.from(this).notify(notificationId, notification)
    }

    private fun showDownloadCompletedNotification(
        requestId: String,
        savedPaths: List<String>,
        directoryPath: String?,
    ) {
        if (!canPostNotifications()) {
            return
        }

        val notificationId = notificationIdForRequest(requestId)
        val targetIntent = buildOpenTargetIntent(savedPaths, directoryPath)
        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            targetIntent,
            pendingIntentFlags(),
        )

        val text = if (savedPaths.size <= 1) {
            "Tap to open downloaded file"
        } else {
            "Tap to open download folder"
        }

        val notification = NotificationCompat.Builder(this, DOWNLOAD_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Download completed")
            .setContentText(text)
            .setAutoCancel(true)
            .setOngoing(false)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .build()

        NotificationManagerCompat.from(this).notify(notificationId, notification)
    }

    private fun showDownloadFailedNotification(
        requestId: String,
        message: String,
    ) {
        if (!canPostNotifications()) {
            return
        }

        val notificationId = notificationIdForRequest(requestId)
        val fallbackIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            fallbackIntent,
            pendingIntentFlags(),
        )

        val notification = NotificationCompat.Builder(this, DOWNLOAD_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle("Download failed")
            .setContentText(message)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .build()

        NotificationManagerCompat.from(this).notify(notificationId, notification)
    }

    private fun showDownloadAttemptNotification(
        requesterName: String,
        shareLabel: String,
        requestedFilesCount: Int,
    ) {
        if (!canPostNotifications()) {
            return
        }

        val text = if (requestedFilesCount > 0) {
            "$requesterName requests $requestedFilesCount file(s) from \"$shareLabel\"."
        } else {
            "$requesterName requests all files from \"$shareLabel\"."
        }

        val notification = NotificationCompat.Builder(this, DOWNLOAD_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
            .setContentTitle("Download attempt detected")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        NotificationManagerCompat.from(this).notify(
            abs(("attempt|$requesterName|$shareLabel|${System.currentTimeMillis()}").hashCode()),
            notification,
        )
    }

    private fun notificationIdForRequest(requestId: String): Int {
        val hash = requestId.hashCode()
        return if (hash == Int.MIN_VALUE) {
            1
        } else {
            abs(hash)
        }
    }

    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }

    private fun buildOpenTargetIntent(savedPaths: List<String>, directoryPath: String?): Intent {
        val intent = if (savedPaths.size == 1) {
            buildOpenFileIntent(savedPaths.first())
        } else {
            buildOpenDirectoryIntent(directoryPath)
        }

        if (intent.resolveActivity(packageManager) != null) {
            return intent
        }

        return Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
    }

    private fun buildOpenFileIntent(path: String): Intent {
        val file = File(path)
        if (!file.exists()) {
            return buildOpenDirectoryIntent(file.parent)
        }

        val uri = fileUri(file)
        val mime = contentResolver.getType(uri) ?: "*/*"
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    private fun buildOpenDirectoryIntent(directoryPath: String?): Intent {
        val directory = directoryPath?.let(::File)
        if (directory != null && directory.exists()) {
            val uri = fileUri(directory)
            val folderIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, DocumentsContract.Document.MIME_TYPE_DIR)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            if (folderIntent.resolveActivity(packageManager) != null) {
                return folderIntent
            }
        }

        return Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
    }

    private fun fileUri(file: File): Uri {
        return try {
            FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file,
            )
        } catch (_: Throwable) {
            Uri.fromFile(file)
        }
    }
}
