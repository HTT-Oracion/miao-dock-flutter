package com.miaodock.miao_dock_flutter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "miao_dock/folder_picker"
    private val folderRequestCode = 9201
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "appDataPath") {
                result.success(File(filesDir, "mobile-manga").absolutePath)
                return@setMethodCallHandler
            }
            if (call.method != "pickImageFolder") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingFolderResult != null) {
                result.error("PICKER_BUSY", "folder picker is already open", null)
                return@setMethodCallHandler
            }
            pendingFolderResult = result
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }
            startActivityForResult(intent, folderRequestCode)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != folderRequestCode) return
        val result = pendingFolderResult ?: return
        pendingFolderResult = null
        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            result.success(emptyList<String>())
            return
        }
        try {
            contentResolver.takePersistableUriPermission(treeUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: SecurityException) {
            // 部分文档提供器不支持持久授权，本次读取仍可继续。
        }
        Thread {
            try {
                val output = File(filesDir, "mobile-manga/imports").apply { mkdirs() }
                val paths = mutableListOf<String>()
                collectImages(treeUri, DocumentsContract.getTreeDocumentId(treeUri), output, paths)
                runOnUiThread { result.success(paths) }
            } catch (error: Exception) {
                runOnUiThread { result.error("FOLDER_READ_FAILED", error.message, null) }
            }
        }.start()
    }

    private fun collectImages(treeUri: Uri, parentId: String, output: File, paths: MutableList<String>) {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        contentResolver.query(children, projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext()) {
                val id = cursor.getString(idIndex)
                val name = cursor.getString(nameIndex) ?: "image"
                val mime = cursor.getString(mimeIndex) ?: ""
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    collectImages(treeUri, id, output, paths)
                    continue
                }
                val lower = name.lowercase()
                if (!mime.startsWith("image/") && !listOf(".png", ".jpg", ".jpeg", ".webp").any(lower::endsWith)) {
                    continue
                }
                val source = DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
                val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
                val target = File(output, "${System.nanoTime()}_$safeName")
                contentResolver.openInputStream(source)?.use { input ->
                    target.outputStream().use(input::copyTo)
                    paths.add(target.absolutePath)
                }
            }
        }
    }
}
