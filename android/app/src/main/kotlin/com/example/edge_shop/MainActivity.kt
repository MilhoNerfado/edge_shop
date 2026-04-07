package com.example.edge_shop

import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.edge_shop/uart"
    }

    private var uartService: UartService? = null
    private val workerThread = HandlerThread("uart-worker").apply { start() }
    private val workerHandler = Handler(workerThread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var previousUncaughtHandler: Thread.UncaughtExceptionHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        uartService = UartService(this)
        Log.d(TAG, "UartService initialized")

        // Catch crashes so the UART port is released even on unhandled exceptions
        previousUncaughtHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e(TAG, "Uncaught exception — emergency UART close", throwable)
            try { uartService?.close() } catch (_: Exception) {}
            previousUncaughtHandler?.uncaughtException(thread, throwable)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "MethodChannel call: ${call.method}")

                when (call.method) {
                    "uartOpen" -> {
                        workerHandler.post {
                            val response = uartService!!.open()
                            mainHandler.post { result.success(response) }
                        }
                    }
                    "uartClose" -> {
                        workerHandler.post {
                            val response = uartService!!.close()
                            mainHandler.post { result.success(response) }
                        }
                    }
                    "uartWrite" -> {
                        val data = call.argument<String>("data")
                        if (data == null) {
                            result.error("INVALID_ARG", "Missing 'data' argument", null)
                            return@setMethodCallHandler
                        }
                        workerHandler.post {
                            val response = uartService!!.write(data)
                            mainHandler.post { result.success(response) }
                        }
                    }
                    "uartRead" -> {
                        val maxLen = call.argument<Int>("maxLen") ?: 256
                        workerHandler.post {
                            val response = uartService!!.read(maxLen)
                            mainHandler.post { result.success(response) }
                        }
                    }
                    else -> {
                        Log.w(TAG, "Unknown method: ${call.method}")
                        result.notImplemented()
                    }
                }
            }
    }

    override fun onStop() {
        Log.d(TAG, "onStop — closing UART as a precaution")
        try { uartService?.close() } catch (e: Exception) {
            Log.w(TAG, "UART close in onStop failed: ${e.message}")
        }
        super.onStop()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy — cleaning up UART")
        try {
            // Close UART synchronously on the worker thread before shutting it down
            val latch = java.util.concurrent.CountDownLatch(1)
            workerHandler.post {
                try {
                    val resp = uartService?.close()
                    Log.d(TAG, "Auto-close UART on destroy: $resp")
                } catch (e: Exception) {
                    Log.w(TAG, "Auto-close UART failed: ${e.message}")
                } finally {
                    latch.countDown()
                }
            }
            // Wait up to 2s for the close to complete
            if (!latch.await(2, java.util.concurrent.TimeUnit.SECONDS)) {
                Log.w(TAG, "UART close timed out on destroy")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error during UART cleanup: ${e.message}")
        }
        workerThread.quitSafely()
        super.onDestroy()
    }
}
