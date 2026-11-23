package com.daonsystem.daon_crm

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.CallLog
import android.provider.Settings
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat

class OverlayService : Service() {
    companion object {
        @Volatile
        var instance: OverlayService? = null

        fun triggerIncomingFromAnyWhere(context: Context, rawNumber: String, isTest: Boolean = false) {
            val running = instance
            if (running != null) {
                running.handleIncomingCall(rawNumber, isTest)
            } else {
                try {
                    val intent = Intent(context, OverlayService::class.java).apply {
                        action = "ACTION_INCOMING_CALL"
                        putExtra("PHONE_NUMBER", rawNumber)
                        putExtra("IS_TEST", isTest)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                } catch (_: Exception) {}
            }
        }

        fun hidePopupFromAnyWhere() {
            instance?.mainHandler?.post {
                instance?.removeOverlay()
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    val mainHandler = Handler(Looper.getMainLooper())
    private var telephonyManager: TelephonyManager? = null
    private var telephonyCallback: Any? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        startForegroundNotification()
        registerCallStateListener()
    }

    private fun registerCallStateListener() {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            return
        }
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val cb = @RequiresApi(Build.VERSION_CODES.S) object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    if (state == TelephonyManager.CALL_STATE_RINGING) {
                        handleIncomingCall("")
                    } else if (state == TelephonyManager.CALL_STATE_IDLE) {
                        mainHandler.post { removeOverlay() }
                    }
                }
            }
            telephonyCallback = cb
            telephonyManager?.registerTelephonyCallback(mainExecutor, cb)
        } else {
            @Suppress("DEPRECATION")
            val listener = object : PhoneStateListener() {
                @Deprecated("Deprecated in Java")
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    if (state == TelephonyManager.CALL_STATE_RINGING) {
                        handleIncomingCall(phoneNumber ?: "")
                    } else if (state == TelephonyManager.CALL_STATE_IDLE) {
                        mainHandler.post { removeOverlay() }
                    }
                }
            }
            @Suppress("DEPRECATION")
            telephonyManager?.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        instance = this
        startForegroundNotification()
        when (intent?.action) {
            "ACTION_HIDE_POPUP" -> {
                mainHandler.post { removeOverlay() }
            }
            "ACTION_INCOMING_CALL" -> {
                val rawNumber = intent.getStringExtra("PHONE_NUMBER") ?: ""
                val isTest = intent.getBooleanExtra("IS_TEST", false)
                handleIncomingCall(rawNumber, isTest)
            }
        }
        return START_STICKY
    }

    fun handleIncomingCall(rawNumber: String, isTest: Boolean = false) {
        if (isTest) {
            val cleanTest = normalizePhone(rawNumber)
            val found = if (cleanTest.isNotEmpty()) findCustomerByPhone(cleanTest) else null
            val info = found ?: mapOf(
                "name" to "테스트 고객 (다온시스템)",
                "address" to "서울 강남구 역삼동 테헤란로",
                "device" to "노트북 / PC",
                "symptom" to "발신자 팝업 정상 작동 테스트",
                "amount" to "100,000",
                "payment_status" to "입금완료",
                "memo" to "실제 등록된 고객 번호로 전화가 오면 해당 고객 정보가 뜹니다.",
                "visit_date" to "오늘"
            )
            mainHandler.post {
                showOverlay(info)
                showHeadsUpCustomerAlert(info)
            }
            return
        }

        val cleanNumber = normalizePhone(rawNumber)
        if (cleanNumber.isNotEmpty()) {
            val customerInfo = findCustomerByPhone(cleanNumber)
            if (customerInfo != null) {
                mainHandler.post {
                    showOverlay(customerInfo)
                    showHeadsUpCustomerAlert(customerInfo)
                }
                return
            }
        }

        listOf(300L, 900L).forEach { delayMs ->
            mainHandler.postDelayed({
                val latestNumber = getLatestIncomingNumberFromCallLog()
                val cleanLatest = normalizePhone(latestNumber)
                if (cleanLatest.isNotEmpty()) {
                    val customerInfo = findCustomerByPhone(cleanLatest)
                    if (customerInfo != null) {
                        showOverlay(customerInfo)
                        showHeadsUpCustomerAlert(customerInfo)
                    }
                }
            }, delayMs)
        }
    }

    private fun normalizePhone(raw: String): String {
        var clean = raw.replace("[^0-9]".toRegex(), "")
        if (clean.startsWith("82")) {
            clean = "0" + clean.substring(2)
        }
        return clean
    }

    private fun getLatestIncomingNumberFromCallLog(): String {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
            return ""
        }
        return try {
            val cursor = contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DATE),
                "${CallLog.Calls.TYPE} = ?",
                arrayOf(CallLog.Calls.INCOMING_TYPE.toString()),
                "${CallLog.Calls.DATE} DESC"
            )
            var num = ""
            if (cursor != null && cursor.moveToFirst()) {
                val callTime = cursor.getLong(2)
                if (System.currentTimeMillis() - callTime < 20000) {
                    num = cursor.getString(0) ?: ""
                }
            }
            cursor?.close()
            num
        } catch (e: Exception) {
            ""
        }
    }

    private fun findCustomerByPhone(cleanPhone: String): Map<String, String>? {
        val dbPath = getDatabasePath("daon_crm.db")
        if (!dbPath.exists()) return null

        return try {
            val db = SQLiteDatabase.openDatabase(dbPath.path, null, SQLiteDatabase.OPEN_READONLY)
            val cursor = db.rawQuery(
                "SELECT name, address, device, symptom, amount, payment_status, memo, visit_date FROM customers WHERE replace(replace(phone, '-', ''), ' ', '') = ? ORDER BY id DESC LIMIT 1",
                arrayOf(cleanPhone)
            )
            var result: Map<String, String>? = null
            if (cursor.moveToFirst()) {
                result = mapOf(
                    "name" to (cursor.getString(0) ?: ""),
                    "address" to (cursor.getString(1) ?: ""),
                    "device" to (cursor.getString(2) ?: ""),
                    "symptom" to (cursor.getString(3) ?: ""),
                    "amount" to (cursor.getString(4) ?: ""),
                    "payment_status" to (cursor.getString(5) ?: ""),
                    "memo" to (cursor.getString(6) ?: ""),
                    "visit_date" to (cursor.getString(7) ?: "")
                )
            }
            cursor.close()
            db.close()
            result
        } catch (e: Exception) {
            null
        }
    }

    private fun showHeadsUpCustomerAlert(info: Map<String, String>) {
        val channelId = "daon_crm_urgent_popup"
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "다온시스템 등록 고객 긴급 수신 알림",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                enableVibration(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)
        }

        val openIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val detailText = "📍 ${info["address"]}\n🛠 [${info["visit_date"]}] ${info["device"]} - ${info["symptom"]}\n💰 ${info["amount"]}원 (${info["payment_status"]}) | ${info["memo"]}"

        val alertNoti = NotificationCompat.Builder(this, channelId)
            .setContentTitle("📞 [다온시스템 고객] ${info["name"]}")
            .setContentText("📍 ${info["address"]} | ${info["symptom"]}")
            .setStyle(NotificationCompat.BigTextStyle().bigText(detailText))
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .build()

        manager.notify(2002, alertNoti)
    }

    private fun showOverlay(info: Map<String, String>) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            return
        }
        removeOverlay()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        overlayView = inflater.inflate(R.layout.overlay_customer_popup, null)

        overlayView?.findViewById<TextView>(R.id.tv_popup_name)?.text = info["name"]
        overlayView?.findViewById<TextView>(R.id.tv_popup_address)?.text = "📍 ${info["address"]}"
        overlayView?.findViewById<TextView>(R.id.tv_popup_history)?.text =
            "🛠 [${info["visit_date"]}] ${info["device"]} - ${info["symptom"]}"
        overlayView?.findViewById<TextView>(R.id.tv_popup_memo)?.text =
            "💰 ${info["amount"]}원 (${info["payment_status"]}) | 메모: ${info["memo"]}"

        overlayView?.findViewById<Button>(R.id.btn_close_popup)?.setOnClickListener {
            removeOverlay()
        }

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        @Suppress("DEPRECATION")
        val windowFlags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            windowFlags,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = 140
        }

        var initialY = 0
        var initialTouchY = 0f
        overlayView?.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialY = params.y
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.y = initialY + (event.rawY - initialTouchY).toInt()
                    windowManager?.updateViewLayout(overlayView, params)
                    true
                }
                else -> false
            }
        }

        try {
            windowManager?.addView(overlayView, params)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun removeOverlay() {
        try {
            if (overlayView != null && windowManager != null) {
                windowManager?.removeView(overlayView)
                overlayView = null
            }
        } catch (e: Exception) {
            overlayView = null
        }
    }

    private fun startForegroundNotification() {
        val channelId = "daon_crm_caller_id"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "다온시스템 발신자 표시 대기",
                NotificationManager.IMPORTANCE_MIN
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("다온시스템 고객 수신 감지 대기중")
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setOngoing(true)
            .build()
        startForeground(1001, notification)
    }

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
    }
}