package com.example.edge_shop

import android.content.Context
import android.os.IBinder
import android.os.Parcel
import android.util.Log

/**
 * Wrapper around the Telit UART HAL via direct binder transactions.
 *
 * RS-232 is mapped to device "/dev/ttyHS1" on the SE250B4 module.
 * Default config: 9600 baud, 8 data bits, no parity, 1 stop bit, no flow control.
 *
 * Uses raw binder transactions to the TelitManagerService, bypassing the
 * TelitManager proxy to avoid reflection-related blocking issues.
 */
class UartService(context: Context) {

    companion object {
        private const val TAG = "UartService"
        private const val DEV_NAME = "/dev/ttyHS1"
        private const val SERVICE_NAME = "telitmanagerservice"
        private const val INTERFACE_DESCRIPTOR = "android.app.telit.ITelitManager"

        // UartBaudRate enum values from Telit AIDL
        private const val UART_BAUD_RATE_9600 = 3
        private const val UART_PARITY_NONE = 0
        private const val UART_STOP_BIT_1 = 0
        private const val UART_FLOW_CTRL_DISABLE = 0

        // AIDL transaction codes (FIRST_CALL_TRANSACTION = 1, methods in ITelitManager order)
        private const val TRANSACTION_uartOpen  = 8
        private const val TRANSACTION_uartClose = 9
        private const val TRANSACTION_uartWrite = 10
        private const val TRANSACTION_uartRead  = 11
    }

    private var telitBinder: IBinder? = null
    private var isOpen = false

    init {
        try {
            val smClass = Class.forName("android.os.ServiceManager")
            val getService = smClass.getMethod("getService", String::class.java)
            val binder = getService.invoke(null, SERVICE_NAME) as? IBinder

            if (binder != null) {
                telitBinder = binder
                Log.d(TAG, "Binder obtained for $SERVICE_NAME (descriptor: ${binder.interfaceDescriptor})")
            } else {
                Log.e(TAG, "ServiceManager.getService(\"$SERVICE_NAME\") returned null")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get binder: ${e.message}", e)
        }

        Log.d(TAG, "UartService init complete — binder available: ${telitBinder != null}")
    }

    fun open(): Map<String, Any> {
        Log.d(TAG, "open() called — device=$DEV_NAME")

        if (telitBinder == null) {
            val msg = "TelitManager binder not available"
            Log.e(TAG, msg)
            return mapOf("success" to false, "message" to msg)
        }

        if (isOpen) {
            val msg = "Port $DEV_NAME is already open"
            Log.w(TAG, msg)
            return mapOf("success" to true, "message" to msg)
        }

        return try {
            val data = Parcel.obtain()
            val reply = Parcel.obtain()
            try {
                data.writeInterfaceToken(INTERFACE_DESCRIPTOR)
                data.writeString(DEV_NAME)
                // UartDevConfig Parcelable: non-null marker + 4 config ints
                data.writeInt(1)
                data.writeInt(UART_BAUD_RATE_9600)
                data.writeInt(UART_PARITY_NONE)
                data.writeInt(UART_STOP_BIT_1)
                data.writeInt(UART_FLOW_CTRL_DISABLE)

                Log.d(TAG, "Sending uartOpen transaction (9600/8N1)...")
                telitBinder!!.transact(TRANSACTION_uartOpen, data, reply, 0)
                reply.readException()
                val result = reply.readInt()

                if (result == 0) {
                    isOpen = true
                    val msg = "Port $DEV_NAME opened successfully (9600/8N1)"
                    Log.d(TAG, msg)
                    mapOf("success" to true, "message" to msg)
                } else {
                    val msg = "uartOpen returned error code: $result"
                    Log.e(TAG, msg)
                    mapOf("success" to false, "message" to msg)
                }
            } finally {
                data.recycle()
                reply.recycle()
            }
        } catch (e: Exception) {
            val msg = "Exception during uartOpen: ${e.message}"
            Log.e(TAG, msg, e)
            mapOf("success" to false, "message" to msg)
        }
    }

    fun close(): Map<String, Any> {
        Log.d(TAG, "close() called — device=$DEV_NAME")

        if (telitBinder == null) {
            val msg = "TelitManager binder not available"
            Log.e(TAG, msg)
            return mapOf("success" to false, "message" to msg)
        }

        if (!isOpen) {
            val msg = "Port $DEV_NAME is not open"
            Log.w(TAG, msg)
            return mapOf("success" to true, "message" to msg)
        }

        return try {
            val data = Parcel.obtain()
            val reply = Parcel.obtain()
            try {
                data.writeInterfaceToken(INTERFACE_DESCRIPTOR)
                data.writeString(DEV_NAME)
                telitBinder!!.transact(TRANSACTION_uartClose, data, reply, 0)
                reply.readException()
                val result = reply.readInt()

                if (result == 0) {
                    isOpen = false
                    val msg = "Port $DEV_NAME closed successfully"
                    Log.d(TAG, msg)
                    mapOf("success" to true, "message" to msg)
                } else {
                    val msg = "uartClose returned error code: $result"
                    Log.e(TAG, msg)
                    mapOf("success" to false, "message" to msg)
                }
            } finally {
                data.recycle()
                reply.recycle()
            }
        } catch (e: Exception) {
            val msg = "Exception during uartClose: ${e.message}"
            Log.e(TAG, msg, e)
            mapOf("success" to false, "message" to msg)
        }
    }

    fun write(text: String): Map<String, Any> {
        Log.d(TAG, "write() called — data=\"$text\" (${text.length} chars)")

        if (telitBinder == null) {
            val msg = "TelitManager binder not available"
            Log.e(TAG, msg)
            return mapOf("success" to false, "message" to msg, "bytesWritten" to 0)
        }

        if (!isOpen) {
            val msg = "Port $DEV_NAME is not open — call open() first"
            Log.e(TAG, msg)
            return mapOf("success" to false, "message" to msg, "bytesWritten" to 0)
        }

        return try {
            val wrChars = text.toCharArray()
            val wrLen = wrChars.size
            val data = Parcel.obtain()
            val reply = Parcel.obtain()
            try {
                data.writeInterfaceToken(INTERFACE_DESCRIPTOR)
                data.writeString(DEV_NAME)
                data.writeCharArray(wrChars)
                data.writeInt(wrLen)
                telitBinder!!.transact(TRANSACTION_uartWrite, data, reply, 0)
                reply.readException()
                val result = reply.readInt()

                if (result >= 0) {
                    val msg = "Wrote $result/$wrLen bytes to $DEV_NAME: \"$text\""
                    Log.d(TAG, msg)
                    Log.d(TAG, "  Hex: ${text.toByteArray().joinToString(" ") { "%02X".format(it) }}")
                    mapOf("success" to true, "message" to msg, "bytesWritten" to result)
                } else {
                    val msg = "uartWrite failed with error code: $result"
                    Log.e(TAG, msg)
                    mapOf("success" to false, "message" to msg, "bytesWritten" to 0)
                }
            } finally {
                data.recycle()
                reply.recycle()
            }
        } catch (e: Exception) {
            val msg = "Exception during uartWrite: ${e.message}"
            Log.e(TAG, msg, e)
            mapOf("success" to false, "message" to msg, "bytesWritten" to 0)
        }
    }

    fun read(maxLen: Int): Map<String, Any> {
        Log.d(TAG, "read() called — maxLen=$maxLen")

        if (telitBinder == null) {
            val msg = "TelitManager binder not available"
            Log.e(TAG, msg)
            return mapOf("success" to false, "message" to msg, "data" to "", "bytesRead" to 0)
        }

        if (!isOpen) {
            val msg = "Port $DEV_NAME is not open — call open() first"
            Log.e(TAG, msg)
            return mapOf("success" to false, "message" to msg, "data" to "", "bytesRead" to 0)
        }

        return try {
            val data = Parcel.obtain()
            val reply = Parcel.obtain()
            try {
                data.writeInterfaceToken(INTERFACE_DESCRIPTOR)
                data.writeString(DEV_NAME)
                data.writeInt(maxLen)
                telitBinder!!.transact(TRANSACTION_uartRead, data, reply, 0)
                reply.readException()
                val result = reply.readInt()
                val replyChars = reply.createCharArray()
                val received = if (replyChars != null) String(replyChars).trimEnd('\u0000') else ""

                if (result >= 0) {
                    val msg = "Read ${received.length} bytes from $DEV_NAME: \"$received\""
                    Log.d(TAG, msg)
                    if (received.isNotEmpty()) {
                        Log.d(TAG, "  Hex: ${received.toByteArray().joinToString(" ") { "%02X".format(it) }}")
                    }
                    mapOf("success" to true, "message" to msg, "data" to received, "bytesRead" to received.length)
                } else {
                    val msg = "uartRead failed with error code: $result"
                    Log.e(TAG, msg)
                    mapOf("success" to false, "message" to msg, "data" to "", "bytesRead" to 0)
                }
            } finally {
                data.recycle()
                reply.recycle()
            }
        } catch (e: Exception) {
            val msg = "Exception during uartRead: ${e.message}"
            Log.e(TAG, msg, e)
            mapOf("success" to false, "message" to msg, "data" to "", "bytesRead" to 0)
        }
    }

    fun isPortOpen(): Boolean = isOpen
}
