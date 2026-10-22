package com.gettubeapp.gettube

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Platform channel "gettube/storage":
 *  - saveFile: moves a finished file into the public Downloads folder.
 *      * Android 10+ : MediaStore.Downloads (no storage permission required)
 *      * Android 9-  : direct write into /storage/emulated/0/Download/GetTube/...
 *  - deleteSaved: removes a previously saved file (by content uri or path).
 */
class MainActivity : FlutterActivity() {

    private val channelName = "gettube/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveFile" -> {
                        try {
                            val src = call.argument<String>("src")!!
                            val subDir = call.argument<String>("subDir")!!
                            val name = call.argument<String>("name")!!
                            val mime = call.argument<String>("mime")!!
                            result.success(saveFile(src, subDir, name, mime))
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    "deleteSaved" -> {
                        try {
                            val target = call.argument<String>("target")!!
                            result.success(deleteSaved(target))
                        } catch (e: Exception) {
                            result.error("DELETE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveFile(src: String, subDir: String, name: String, mime: String): Map<String, String> {
        val inFile = File(src)

        if (Build.VERSION.SDK_INT >= 29) {
            val resolver = applicationContext.contentResolver
            val relPath = "${Environment.DIRECTORY_DOWNLOADS}/GetTube/$subDir"

            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relPath)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("MediaStore insert failed")

            resolver.openOutputStream(uri)!!.use { out ->
                inFile.inputStream().use { it.copyTo(out) }
            }
            val dataPath = queryDataPath(uri)
            if (inFile.exists()) inFile.delete()
            return mapOf("uri" to uri.toString(), "path" to (dataPath ?: ""))
        } else {
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "GetTube/$subDir"
            )
            if (!dir.exists()) dir.mkdirs()

            var out = File(dir, name)
            var i = 1
            while (out.exists()) {
                val dot = name.lastIndexOf('.')
                val base = if (dot > 0) name.substring(0, dot) else name
                val ext = if (dot > 0) name.substring(dot) else ""
                out = File(dir, "$base ($i)$ext")
                i++
            }
            inFile.copyTo(out, overwrite = true)
            inFile.delete()
            return mapOf("uri" to "", "path" to out.absolutePath)
        }
    }

    private fun queryDataPath(uri: Uri): String? {
        return try {
            val cursor = contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)
            cursor?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun deleteSaved(target: String): Boolean {
        return try {
            if (target.startsWith("content://")) {
                contentResolver.delete(Uri.parse(target), null, null) > 0
            } else {
                val f = File(target)
                if (f.exists()) f.delete() else true
            }
        } catch (e: Exception) {
            false
        }
    }
}
