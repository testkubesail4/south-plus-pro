package com.example.south_plus_rewrite

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val saveImageRequestCode = 4107
    private var pendingImageSave: PendingImageSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                else -> result.notImplemented()
            }
        }
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
