package com.daonsystem.daon_crm

import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.charset.Charset

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.daonsystem.daon_crm/overlay"
    private val REQUEST_CALL_SCREENING_ROLE = 2001
    private val REQUEST_PICK_CSV = 2002
    private val REQUEST_SAVE_CSV = 2003

    private var pendingCsvResult: MethodChannel.Result? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingCsvBytes: ByteArray? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startMonitorService()
    }

    private fun startMonitorService() {
        try {
            val startIntent = Intent(this, OverlayService::class.java).apply {
                action = "ACTION_START_MONITOR"
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(startIntent)
            } else {
                startService(startIntent)
            }
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startMonitorService" -> {
                    startMonitorService()
                    result.success(true)
                }
                "testPopup" -> {
                    val phone = call.argument<String>("phone") ?: "010-1234-5678"
                    OverlayService.triggerIncomingFromAnyWhere(applicationContext, phone, true)
                    result.success(true)
                }
                "requestCallerIdRole" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
                        if (roleManager.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) &&
                            !roleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) {
                            val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING)
                            startActivityForResult(intent, REQUEST_CALL_SCREENING_ROLE)
                        }
                    }
                    result.success(true)
                }
                "saveCsvFile" -> {
                    val fileName = call.argument<String>("fileName") ?: "daon_crm_backup.csv"
                    val csvText = call.argument<String>("csvText") ?: ""
                    val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
                    pendingCsvBytes = bom + csvText.toByteArray(Charsets.UTF_8)
                    pendingSaveResult = result

                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "text/csv"
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                    startActivityForResult(intent, REQUEST_SAVE_CSV)
                }
                "shareCsvFile" -> {
                    try {
                        val fileName = call.argument<String>("fileName") ?: "daon_crm_backup.csv"
                        val csvText = call.argument<String>("csvText") ?: ""
                        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
                        val bytes = bom + csvText.toByteArray(Charsets.UTF_8)

                        val outFile = File(cacheDir, fileName)
                        outFile.writeBytes(bytes)

                        val uri = FileProvider.getUriForFile(
                            this,
                            "${applicationContext.packageName}.fileprovider",
                            outFile
                        )
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/csv"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            putExtra(Intent.EXTRA_SUBJECT, fileName)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(shareIntent, "엑셀(CSV) 파일 보내기"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_ERR", e.message, null)
                    }
                }
                "pickCsvContent" -> {
                    pendingCsvResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(intent, REQUEST_PICK_CSV)
                }
                "openAppSettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.fromParts("package", packageName, null)
                    }
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK_CSV) {
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                try {
                    val uri = data.data!!
                    val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    if (bytes != null) {
                        val text = try {
                            String(bytes, Charsets.UTF_8)
                        } catch (e: Exception) {
                            String(bytes, Charset.forName("EUC-KR"))
                        }
                        pendingCsvResult?.success(text)
                    } else {
                        pendingCsvResult?.success(null)
                    }
                } catch (e: Exception) {
                    pendingCsvResult?.error("READ_ERR", e.message, null)
                }
            } else {
                pendingCsvResult?.success(null)
            }
            pendingCsvResult = null
        } else if (requestCode == REQUEST_SAVE_CSV) {
            if (resultCode == Activity.RESULT_OK && data?.data != null && pendingCsvBytes != null) {
                try {
                    val uri = data.data!!
                    contentResolver.openOutputStream(uri)?.use { it.write(pendingCsvBytes!!) }
                    pendingSaveResult?.success(true)
                } catch (e: Exception) {
                    pendingSaveResult?.error("SAVE_ERR", e.message, null)
                }
            } else {
                pendingSaveResult?.success(false)
            }
            pendingSaveResult = null
            pendingCsvBytes = null
        }
    }
}