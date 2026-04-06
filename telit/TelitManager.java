package android.app.telit;

import android.os.Handler;
import android.os.Looper;
import android.os.IBinder;
import android.os.ServiceManager;
import android.os.ServiceManager.ServiceNotFoundException;
import android.os.RemoteException;
import android.content.Context;
import android.annotation.SystemService;
import android.annotation.SuppressLint;
import android.annotation.NonNull;
import android.util.Log;

import android.app.telit.ITelitManager;
import android.app.telit.TelitManagerSupportedAidls;
import android.app.telit.gpio.GpioNum;
import android.app.telit.gpio.GpioDirection;
import android.app.telit.gpio.GpioState;
import android.app.telit.gpio.GpioPollEvent;
import android.app.telit.i2c.I2cBus;
import android.app.telit.uart.UartDevConfig;

@SystemService(Context.TELIT_MANAGER_SERVICE)
public class TelitManager {
    private static final String TAG="TelitManager";

    private static Context mContext;
    private static Handler mHandler;
    private static ITelitManager mTelitManagerService;
    private static int mResult;

    /**
     * create TelitManager class instance and bind TelitManagerService.
     * @hide
     */
    public TelitManager(Context context) throws ServiceNotFoundException {
        Log.d(TAG, "TelitManager Instance Created");
        mContext = context;

        IBinder binder = ServiceManager.getServiceOrThrow(Context.TELIT_MANAGER_SERVICE);
        mTelitManagerService = ITelitManager.Stub.asInterface(binder);
    }

    public @NonNull int gpioGetDirection(@NonNull int gpioNum) {
        try {
            mResult = mTelitManagerService.gpioGetDirection(gpioNum);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: gpioGetDirection: Call TelitManager.initialize before reattempt");
            e.printStackTrace();
        }
        return mResult;
    }

    public @NonNull int gpioSetDirection(@NonNull int gpioNum, @NonNull @GpioDirection int direction) {
        try {
            mResult = mTelitManagerService.gpioSetDirection(gpioNum, direction);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: gpioSetDirection: Call TelitManager.initialize before reattempt");
            e.printStackTrace();
        }
        return mResult;
    }

    public @NonNull int gpioRead(@NonNull int gpioNum) {
        try {
            mResult = mTelitManagerService.gpioRead(gpioNum);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: gpioRead: Call TelitManager.initialize before reattempt");
            e.printStackTrace();
        }
        return mResult;
    }

    public @NonNull int gpioWrite(@NonNull int gpioNum, @NonNull @GpioState int state) {
        try {
            mResult = mTelitManagerService.gpioWrite(gpioNum, state);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: gpioWrite: Call TelitManager.initialize before reattempt");
            e.printStackTrace();
        }
        return mResult;
    }

    public @NonNull int gpioPoll(@NonNull int gpioNum, @NonNull @GpioPollEvent int event, @NonNull int timeout) {
        try {
            mResult = mTelitManagerService.gpioPoll(gpioNum, event, timeout);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: gpioPoll: Call TelitManager.initialize before reattempt");
            e.printStackTrace();
        }
        return mResult;
    }

    public @NonNull int i2cReadByteData(@NonNull @I2cBus int bus, @NonNull int slave, @NonNull int cmd) {
        try {
            mResult = mTelitManagerService.i2cReadByte(bus, slave, cmd);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: i2cReadByteData: Call TelitManager.initialize before reattempt");
            e.printStackTrace();
        }
        return mResult;
    }

    public @NonNull int i2cWriteByteData(@NonNull @I2cBus int bus, @NonNull int slave, @NonNull int cmd, @NonNull int wrByte) {
        try {
            mResult = mTelitManagerService.i2cWriteByte(bus, slave, cmd, wrByte);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: i2cWriteByteData: Call TelitManager.initialize before reattempt");
            e.printStackTrace();
        }
        return mResult;
    }

    public @NonNull int uartOpen(@NonNull String devName, @NonNull UartDevConfig devConfig) {
        try {
            mResult = mTelitManagerService.uartOpen(devName, devConfig);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: uartOpen: Call TelitManager.initialize before reattempt");
            e.printStackTrace();
        }
        return mResult;
    }

    public @NonNull int uartClose(@NonNull String devName) {
        try {
            mResult = mTelitManagerService.uartClose(devName);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: uartClose: Call TelitManager.initialize before reattempt");
            e.printStackTrace();
        }
        return mResult;
    }

    public @NonNull int uartWrite(@NonNull String devName, @NonNull StringBuffer wrBuf, @NonNull int wrLen) {
        try {
            /* copy StringBuffer input into char[] array type */
            char[] wrChars = new char[wrLen];
            wrBuf.getChars(0, wrLen, wrChars, 0);

            mResult = mTelitManagerService.uartWrite(devName, wrChars, wrLen);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: uartWrite: Call TelitManager.initialize before reattempt");
            e.printStackTrace();
        }
        return mResult;
    }

    public @NonNull int uartRead(@NonNull String devName, @NonNull StringBuffer rdBuf, @NonNull int rdLen) {
        try {
            /* use char[] array to collect data from UART AIDL */
            char[] rdChars = new char[rdLen];

            mResult = mTelitManagerService.uartRead(devName, rdChars, rdLen);

            /* copy char[] ouput back to StringBuffer */
            rdBuf.insert(0, rdChars);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: uartRead: Call TelitManager.initialize before reattempt");
            e.printStackTrace();
        }
        return mResult;
    }

}

