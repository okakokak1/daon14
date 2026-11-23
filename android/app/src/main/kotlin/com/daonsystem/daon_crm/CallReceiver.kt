package com.daonsystem.daon_crm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.TelephonyManager

class CallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                try {
                    val startIntent = Intent(context, OverlayService::class.java).apply {
                        action = "ACTION_START_MONITOR"
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(startIntent)
                    } else {
                        context.startService(startIntent)
                    }
                } catch (_: Exception) {}
            }
            TelephonyManager.ACTION_PHONE_STATE_CHANGED -> {
                val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
                @Suppress("DEPRECATION")
                val incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""

                if (state == TelephonyManager.EXTRA_STATE_RINGING) {
                    OverlayService.triggerIncomingFromAnyWhere(context.applicationContext, incomingNumber)
                } else if (state == TelephonyManager.EXTRA_STATE_IDLE) {
                    OverlayService.hidePopupFromAnyWhere()
                }
            }
        }
    }
}