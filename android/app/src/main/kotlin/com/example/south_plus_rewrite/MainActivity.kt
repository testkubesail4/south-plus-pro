package com.example.south_plus_rewrite

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val saveImageRequestCode = 4107
    private var pendingImageSave: PendingImageSave? = null
    private val saveAttachmentRequestCode = 4108
    private var pendingAttachmentSave: Pair<File, MethodChannel.Result>? = null

    private var incomingLinks = IncomingLinkState(0, false)
    private var incomingLinkChannel: MethodChannel? = null
    private var watchNotifications: WatchNotificationBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        incomingLinks = IncomingLinkState(
            savedInstanceState?.getLong("incoming_link_sequence") ?: 0,
            savedInstanceState?.getBoolean("incoming_link_consumed") ?: false
        )
        if (intent?.action == Intent.ACTION_VIEW) incomingLinks.restore(intent.dataString)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        watchNotifications?.receiveIntent(intent)
        if (intent.action != Intent.ACTION_VIEW) return
        setIntent(intent)
        incomingLinks.receive(intent.dataString)
        incomingLinkChannel?.invokeMethod("openLink", incomingLinks.pending())
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putLong("incoming_link_sequence", incomingLinks.sequence())
        outState.putBoolean("incoming_link_consumed", incomingLinks.consumed())
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        watchNotifications?.close()
        watchNotifications = null
        incomingLinkChannel?.setMethodCallHandler(null)
        incomingLinkChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        watchNotifications?.close()
        watchNotifications = WatchNotificationBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        incomingLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "south_plus_rewrite/incoming_links"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeInitialLink" -> result.success(incomingLinks.pending())
                    "acknowledgeLink" -> {
                        (call.arguments as? Number)?.toLong()?.let { incomingLinks.acknowledge(it) }
                        if (incomingLinks.consumed()) setIntent(Intent(intent).setData(null))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "south_plus_rewrite/network_state"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isOnWifi" -> result.success(isOnWifi())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "south_plus_rewrite/image_saver"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImage" -> handleSaveImage(call, result)
                "shareImage" -> handleShareImage(call, result)
                "shareText" -> handleShareText(call, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "south_plus_rewrite/attachment_saver"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveAttachment" -> handleSaveAttachment(call, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "south_plus_rewrite/link_opener"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> handleOpenLink(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleSaveAttachment(call: MethodCall, result: MethodChannel.Result) {
        if (pendingAttachmentSave != null) {
            result.error("save_in_progress", "已有附件正在保存", null)
            return
        }
        try {
            val path = call.argument<String>("path") ?: throw IllegalArgumentException("附件路径为空")
            val file = File(path).canonicalFile
            val cache = cacheDir.canonicalFile
            if (!file.path.startsWith(cache.path + File.separator) || !file.isFile || file.length() == 0L) {
                throw IllegalArgumentException("附件临时文件无效")
            }
            val fileName = call.argument<String>("fileName") ?: "attachment.bin"
            if (fileName.isBlank() || fileName.length > 180 || fileName == "." || fileName == ".." ||
                fileName.any { it == '/' || it == '\\' || it.code < 32 || it.code == 127 }) {
                throw IllegalArgumentException("附件文件名无效")
            }
            val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
            pendingAttachmentSave = Pair(file, result)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveAttachmentInDownloads(file, fileName, mimeType, result)
            } else {
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mimeType
                    putExtra(Intent.EXTRA_TITLE, fileName)
                }
                startActivityForResult(intent, saveAttachmentRequestCode)
            }
        } catch (error: Exception) {
            pendingAttachmentSave = null
            result.error("save_failed", error.localizedMessage ?: "无法保存附件", null)
        }
    }

    private fun saveAttachmentInDownloads(
        file: File,
        fileName: String,
        mimeType: String,
        result: MethodChannel.Result
    ) {
        Thread {
            val resolver = contentResolver
            var pendingUri: Uri? = null
            try {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, mimeType)
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/SouthPlus")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("无法创建下载文件")
                pendingUri = uri
                resolver.openOutputStream(uri, "w")?.use { output ->
                    file.inputStream().use { input -> input.copyTo(output) }
                } ?: throw IllegalStateException("无法写入下载文件")
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                check(resolver.update(uri, values, null, null) == 1) { "无法完成下载文件保存" }
                runOnUiThread {
                    pendingAttachmentSave = null
                    result.success(true)
                }
            } catch (error: Exception) {
                pendingUri?.let { uri ->
                    try { resolver.delete(uri, null, null) } catch (_: Exception) { }
                }
                runOnUiThread {
                    pendingAttachmentSave = null
                    result.error("save_failed", error.localizedMessage ?: "保存附件失败", null)
                }
            }
        }.start()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveAttachmentRequestCode) return
        val pending = pendingAttachmentSave ?: return
        if (resultCode != RESULT_OK) {
            pendingAttachmentSave = null
            pending.second.success(false)
            return
        }
        val uri = data?.data
        if (uri == null) {
            pendingAttachmentSave = null
            pending.second.error("save_failed", "没有选择保存位置", null)
            return
        }
        Thread {
            try {
                contentResolver.openOutputStream(uri, "w")?.use { output ->
                    pending.first.inputStream().use { input -> input.copyTo(output) }
                } ?: throw IllegalStateException("无法写入附件文件")
                runOnUiThread {
                    pendingAttachmentSave = null
                    pending.second.success(true)
                }
            } catch (error: Exception) {
                try { contentResolver.delete(uri, null, null) } catch (_: Exception) { }
                runOnUiThread {
                    pendingAttachmentSave = null
                    pending.second.error("save_failed", error.localizedMessage ?: "保存附件失败", null)
                }
            }
        }.start()
    }

    private fun isOnWifi(): Boolean {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = manager.activeNetwork ?: return false
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    private fun handleSaveImage(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val fileName = call.argument<String>("fileName") ?: defaultImageFileName()
        if (bytes == null || bytes.isEmpty()) {
            result.error("empty_image", "图片数据为空", null)
            return
        }
        if (pendingImageSave != null) {
            result.error("save_in_progress", "已有图片正在保存", null)
            return
        }

        if (requiresLegacyStoragePermission() &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingImageSave = PendingImageSave(bytes, fileName, result)
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                saveImageRequestCode
            )
            return
        }

        saveImageAsync(bytes, fileName, result)
    }

    // Only files inside the forum image cache are shared, through a read grant.
    private fun handleShareImage(call: MethodCall, result: MethodChannel.Result) {
        try {
            val path = call.argument<String>("path") ?: throw IllegalArgumentException("图片路径为空")
            val file = File(path).canonicalFile
            val images = File(cacheDir, "southPlusForumImages").canonicalFile
            if (!file.path.startsWith(images.path + File.separator) || !file.isFile || file.length() == 0L) {
                throw IllegalArgumentException("图片缓存文件无效")
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.images", file)
            val send = Intent(Intent.ACTION_SEND).apply {
                type = mimeTypeFor(file.name)
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri(null, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(send, null))
            result.success(true)
        } catch (error: Exception) {
            result.error("share_failed", error.localizedMessage ?: "分享失败", null)
        }
    }

    private fun handleShareText(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")?.trim()
        if (text.isNullOrEmpty()) {
            result.error("empty_text", "分享内容为空", null)
            return
        }
        try {
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            startActivity(Intent.createChooser(send, null))
            result.success(true)
        } catch (error: Exception) {
            result.error("share_failed", error.localizedMessage ?: "分享失败", null)
        }
    }

    private fun handleOpenLink(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim()
        if (url.isNullOrEmpty()) {
            result.error("empty_url", "链接为空", null)
            return
        }

        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            startActivity(intent)
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            result.error("no_activity", "没有找到可打开该链接的应用", null)
        } catch (error: Exception) {
            result.error("open_failed", error.localizedMessage ?: "打开链接失败", null)
        }
    }

    private fun saveImageAsync(
        bytes: ByteArray,
        fileName: String,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveImageWithMediaStore(bytes, fileName)
                } else {
                    saveImageLegacy(bytes, fileName)
                }
                runOnUiThread { result.success(uri) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("save_failed", error.localizedMessage ?: "保存图片失败", null)
                }
            }
        }.start()
    }

    private fun saveImageWithMediaStore(bytes: ByteArray, fileName: String): String {
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeTypeFor(fileName))
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + File.separator + "SouthPlus"
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("无法创建相册文件")
        try {
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
            } ?: throw IllegalStateException("无法写入相册文件")
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun saveImageLegacy(bytes: ByteArray, fileName: String): String {
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            "SouthPlus"
        )
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("无法创建相册目录")
        }
        val file = File(directory, fileName)
        FileOutputStream(file).use { stream ->
            stream.write(bytes)
        }
        MediaScannerConnection.scanFile(
            this,
            arrayOf(file.absolutePath),
            arrayOf(mimeTypeFor(fileName)),
            null
        )
        return file.toURI().toString()
    }

    private fun requiresLegacyStoragePermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
    }

    private fun mimeTypeFor(fileName: String): String {
        val lower = fileName.lowercase()
        return when {
            lower.endsWith(".png") -> "image/png"
            lower.endsWith(".gif") -> "image/gif"
            lower.endsWith(".webp") -> "image/webp"
            else -> "image/jpeg"
        }
    }

    private fun defaultImageFileName(): String {
        return "south_plus_${System.currentTimeMillis()}.jpg"
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (watchNotifications?.onRequestPermissionsResult(requestCode) == true) return
        if (requestCode != saveImageRequestCode) return

        val pending = pendingImageSave ?: return
        pendingImageSave = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            saveImageAsync(pending.bytes, pending.fileName, pending.result)
        } else {
            pending.result.error("permission_denied", "需要存储权限才能保存图片", null)
        }
    }

    private data class PendingImageSave(
        val bytes: ByteArray,
        val fileName: String,
        val result: MethodChannel.Result
    )
}
