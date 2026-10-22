package com.gettubeapp.gettube

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Platform channel "gettube/storage":
 *  - saveFile       : moves a finished file into public storage (phone or SD).
 *      * Android 10+ : MediaStore.Downloads on the requested volume
 *      * Android 9-  : direct write (needs WRITE_EXTERNAL_STORAGE)
 *  - saveFileToTree : copies a finished file into a user-picked SAF folder
 *                     (any folder the user chose, incl. SD card).
 *  - getStorageInfo : available storage volumes (phone / SD).
 *  - pickFolder     : SAF directory picker (persisted grant) -> {uri, name}.
 *  - createFolder   : creates a subfolder inside a picked tree -> {uri, name}.
 *  - openFile       : ACTION_VIEW on a content uri.
 *  - shareFile      : ACTION_SEND on a content uri.
 *  - openFolder     : opens the containing folder in the system Files app.
 *  - networkInfo    : {metered, wifi} for the "download over mobile data" gate.
 *  - deleteSaved    : removes a previously saved file (content uri or path).
 */
class MainActivity : FlutterActivity() {

    private val channelName = "gettube/storage"
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "saveFile" -> {
                            val src = call.argument<String>("src")!!
                            val subDir = call.argument<String>("subDir")!!
                            val name = call.argument<String>("name")!!
                            val mime = call.argument<String>("mime")!!
                            val volume = call.argument<String?>("volume")
                            result.success(saveFile(src, subDir, name, mime, volume))
                        }
                        "saveFileToTree" -> {
                            val src = call.argument<String>("src")!!
                            val tree = call.argument<String>("tree")!!
                            val name = call.argument<String>("name")!!
                            val mime = call.argument<String>("mime")!!
                            result.success(saveFileToTree(src, tree, name, mime))
                        }
                        "getStorageInfo" -> result.success(storageVolumes())
                        "pickFolder" -> pickFolder(result)
                        "createFolder" -> {
                            val tree = call.argument<String>("tree")!!
                            val name = call.argument<String>("name")!!
                            result.success(createFolder(tree, name))
                        }
                        "openFile" -> result.success(
                            openTarget(
                                call.argument<String>("target")!!,
                                call.argument<String>("mime") ?: ""
                            )
                        )
                        "shareFile" -> result.success(
                            shareTarget(
                                call.argument<String>("target")!!,
                                call.argument<String>("mime") ?: "",
                                call.argument<String>("title") ?: "GetTube"
                            )
                        )
                        "openFolder" -> result.success(openFolder(call.argument<String>("target")!!))
                        "networkInfo" -> result.success(networkInfo())
                        "deleteSaved" -> result.success(deleteSaved(call.argument<String>("target")!!))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("CHANNEL_ERROR", e.message, null)
                }
            }
    }

    // ---------------- public storage (MediaStore / direct) ----------------

    private fun saveFile(
        src: String,
        subDir: String,
        name: String,
        mime: String,
        volume: String?
    ): Map<String, String> {
        val inFile = File(src)

        if (Build.VERSION.SDK_INT >= 29) {
            val vol = volume ?: MediaStore.VOLUME_EXTERNAL_PRIMARY
            val collection = MediaStore.Downloads.getContentUri(vol)
            val relPath = "${Environment.DIRECTORY_DOWNLOADS}/GetTube/$subDir"

            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relPath)
            }
            val uri = contentResolver.insert(collection, values)
                ?: throw Exception("MediaStore insert failed")

            contentResolver.openOutputStream(uri)!!.use { out ->
                inFile.inputStream().use { it.copyTo(out) }
            }
            val dataPath = queryDataPath(uri)
            if (inFile.exists()) inFile.delete()
            return mapOf("uri" to uri.toString(), "path" to (dataPath ?: ""))
        } else {
            val base = if (volume == null || volume == "primary") {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            } else {
                File(volume, Environment.DIRECTORY_DOWNLOADS)
            }
            val dir = File(base, "GetTube/$subDir")
            if (!dir.exists()) dir.mkdirs()

            val dot = name.lastIndexOf('.')
            val baseName = if (dot > 0) name.substring(0, dot) else name
            val ext = if (dot > 0) name.substring(dot) else ""

            var out = File(dir, name)
            var i = 1
            while (out.exists()) {
                out = File(dir, "$baseName ($i)$ext")
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

    private fun storageVolumes(): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        if (Build.VERSION.SDK_INT >= 29) {
            for (v in MediaStore.getExternalVolumeNames(applicationContext)) {
                out.add(
                    mapOf(
                        "id" to v,
                        "removable" to (v != MediaStore.VOLUME_EXTERNAL_PRIMARY),
                        "root" to ""
                    )
                )
            }
        } else {
            val primary = Environment.getExternalStorageDirectory().absolutePath
            out.add(mapOf("id" to "primary", "removable" to false, "root" to primary))
            for (f in applicationContext.getExternalFilesDirs(null)) {
                if (f == null) continue
                val p = f.absolutePath
                val idx = p.indexOf("/Android/data")
                if (idx <= 0) continue
                val root = p.substring(0, idx)
                if (root != primary) {
                    out.add(mapOf("id" to root, "removable" to true, "root" to root))
                }
            }
        }
        return out
    }

    // ---------------- SAF custom folder ----------------

    private fun saveFileToTree(src: String, treeUri: String, name: String, mime: String): Map<String, String> {
        val root = DocumentFile.fromTreeUri(applicationContext, Uri.parse(treeUri))
            ?: throw Exception("Invalid folder")
        val inFile = File(src)

        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""

        var finalName = name
        var i = 1
        while (root.findFile(finalName) != null) {
            finalName = "$base ($i)$ext"
            i++
        }
        val created = root.createFile(mime, finalName) ?: throw Exception("Create file failed")
        contentResolver.openOutputStream(created.uri)!!.use { out ->
            inFile.inputStream().use { it.copyTo(out) }
        }
        if (inFile.exists()) inFile.delete()
        return mapOf(
            "uri" to created.uri.toString(),
            "path" to "",
            "name" to finalName,
            "folder" to treeDisplayName(treeUri)
        )
    }

    private fun pickFolder(result: MethodChannel.Result) {
        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        try {
            startActivityForResult(intent, REQ_PICK_FOLDER)
        } catch (e: Exception) {
            pendingFolderResult = null
            result.error("PICK_FAILED", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_PICK_FOLDER) {
            val pending = pendingFolderResult
            pendingFolderResult = null
            if (pending == null) return
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                pending.success(null)
                return
            }
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    data!!.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                )
            } catch (_: Exception) {
            }
            pending.success(mapOf("uri" to uri.toString(), "name" to treeDisplayName(uri)))
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun createFolder(treeUri: String, name: String): Map<String, String> {
        val root = DocumentFile.fromTreeUri(applicationContext, Uri.parse(treeUri))
            ?: throw Exception("Invalid folder")
        val created = root.createDirectory(name) ?: throw Exception("Create folder failed")
        val docId = DocumentsContract.getDocumentId(created.uri)
        val childTree = DocumentsContract.buildTreeDocumentUri(created.uri.authority, docId)
        try {
            contentResolver.takePersistableUriPermission(
                childTree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: Exception) {
        }
        return mapOf("uri" to childTree.toString(), "name" to name)
    }

    private fun treeDisplayName(uri: Uri): String {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(uri)
            val path = if (docId.contains(':')) docId.substringAfter(':') else docId
            path.ifBlank { "GetTube" }
        } catch (e: Exception) {
            "GetTube"
        }
    }

    // ---------------- open / share / open-folder ----------------

    private fun openTarget(target: String, mime: String): Boolean {
        if (!target.startsWith("content://")) return false
        val i = Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse(target), mime.ifBlank { "*/*" })
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            startActivity(i)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun shareTarget(target: String, mime: String, title: String): Boolean {
        if (!target.startsWith("content://")) return false
        val i = Intent(Intent.ACTION_SEND)
        i.type = mime.ifBlank { "*/*" }
        i.putExtra(Intent.EXTRA_STREAM, Uri.parse(target))
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            startActivity(Intent.createChooser(i, title))
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun openFolder(target: String): Boolean {
        return try {
            val uri: Uri = if (target.startsWith("content://")) {
                val u = Uri.parse(target)
                if (target.contains("/tree/")) {
                    DocumentsContract.buildDocumentUriUsingTree(u, DocumentsContract.getTreeDocumentId(u))
                } else {
                    val docId = DocumentsContract.getDocumentId(u)
                    val parent = docId.substringBeforeLast('/')
                    DocumentsContract.buildDocumentUri(u.authority, parent)
                }
            } else {
                val folder = target.substringBeforeLast('/')
                val vol = folder.removePrefix("/storage/").substringBefore('/')
                val docId = if (vol == "emulated") {
                    "primary:" + folder.removePrefix("/storage/emulated/0/")
                } else {
                    "$vol:" + folder.removePrefix("/storage/$vol/")
                }
                DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", docId)
            }
            val i = Intent(Intent.ACTION_VIEW)
            i.setDataAndType(uri, DocumentsContract.Document.MIME_TYPE_DIR)
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(i)
            true
        } catch (e: Exception) {
            false
        }
    }

    // ---------------- network ----------------

    @Suppress("DEPRECATION")
    private fun networkInfo(): Map<String, Any> {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val metered = cm.isActiveNetworkMetered
        var wifi = false
        try {
            val net = cm.activeNetwork
            val caps = net?.let { cm.getNetworkCapabilities(it) }
            wifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        } catch (_: Exception) {
        }
        return mapOf("metered" to metered, "wifi" to wifi)
    }

    // ---------------- delete ----------------

    private fun deleteSaved(target: String): Boolean {
        return try {
            if (target.startsWith("content://")) {
                val uri = Uri.parse(target)
                if (target.contains("/tree/")) {
                    try {
                        DocumentsContract.deleteDocument(contentResolver, uri)
                    } catch (e: Exception) {
                        contentResolver.delete(uri, null, null) > 0
                    }
                } else {
                    contentResolver.delete(uri, null, null) > 0
                }
            } else {
                val f = File(target)
                if (f.exists()) f.delete() else true
            }
        } catch (e: Exception) {
            false
        }
    }

    companion object {
        private const val REQ_PICK_FOLDER = 9021
    }
}
