package com.example.edge_shop

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class AdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        Log.d("AdminReceiver", "Device admin enabled")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        Log.d("AdminReceiver", "Device admin disabled")
    }
}
