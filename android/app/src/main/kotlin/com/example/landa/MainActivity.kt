package com.example.landa

import android.content.Context
import android.content.ContentValues
import android.net.wifi.WifiManager
import android.os.Environment
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "landa/network"
        private const val LOCK_TAG = "landa_multicast_lock"
    }

    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                            appFolderName = appFolderName
                        )
                        result.success(destination)
                    } catch (t: Throwable) {
                        result.error("copy_failed", t.message, null)
                    }
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
        appFolderName: String
    ): String {
        val sourceFile = File(sourcePath)
        require(sourceFile.exists()) { "Source file does not exist: $sourcePath" }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return copyFileToDownloadsScoped(
                sourceFile = sourceFile,
                relativePath = relativePath,
                appFolderName = appFolderName
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
        appFolderName: String
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
            "$appFolderName/$normalized"
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
}


