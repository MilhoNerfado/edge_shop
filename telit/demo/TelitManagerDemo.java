package android.app.telit.demo;

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

import android.app.telit.demo.ITelitManagerDemo;
import android.app.telit.demo.ITelitManagerDemoCallback;
import android.app.telit.demo.TelitManagerDemoCallback;

@SystemService(Context.TELIT_MANAGER_DEMO_SERVICE)
public class TelitManagerDemo {
    private static final String TAG="TelitManagerDemo";

    private static Context mContext;
    private static Handler mHandler;
    private static ITelitManagerDemo mTelitManagerDemoService;
    private static ITelitManagerDemoCallback mITelitManagerDemoCallback;
    private static TelitManagerDemoCallback mAppCallback;
    private static int mResult;

    /**
     * create TelitManagerDemo class instance and bind TelitManagerDemoService.
     * @hide
     */
    public TelitManagerDemo(Context context) throws ServiceNotFoundException {
	Log.d(TAG, "TelitManagerDemo Intance Created");
	mContext = context;
        
	IBinder binder = ServiceManager.getServiceOrThrow(Context.TELIT_MANAGER_DEMO_SERVICE);
        mTelitManagerDemoService = ITelitManagerDemo.Stub.asInterface(binder);
    }

    public @NonNull int initialize(@NonNull int aidl) {
	try {
            mResult = mTelitManagerDemoService.initialize(aidl);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: initialize: Check whether AIDL service is running");
            e.printStackTrace();
        }
	return mResult;
    }

    public @NonNull int demo_testInputPassing(@NonNull int input_integer, @NonNull String input_string) {
        try {
            mResult = mTelitManagerDemoService.demo_testInputPassing(input_integer, input_string);
        } catch (Exception e) {
            Log.e(TAG, "ERROR: demo_testInputPassing: Call TelitManagerDemo.initialize before reattempt");
            e.printStackTrace();
        }
	return mResult;
    }

    @SuppressLint("ExecutorRegistration")
    public @NonNull int demo_registerCallback(@NonNull TelitManagerDemoCallback callback) {
        mAppCallback = callback;
        mHandler = new Handler(Looper.getMainLooper());

        mITelitManagerDemoCallback = new ITelitManagerDemoCallback.Stub() {
            @Override
            public void onDemoTestCallback(int callback_input_integer) {
                Log.d(TAG, "ITelitManagerDemoCallback.onDemoTestCallback invoked with input = " + callback_input_integer);
		mHandler.post(() -> mAppCallback.onTelitManagerCallback(callback_input_integer));
            }
        };

	try {
	    mResult = mTelitManagerDemoService.demo_registerCallback(mITelitManagerDemoCallback);
	} catch (Exception e) {
            Log.e(TAG, "ERROR: demo_registerCallback: Call TelitManagerDemo.initialize before reattempt");
	    e.printStackTrace();
	}
	return mResult;
    }

    public @NonNull int demo_testCallback(@NonNull int callback_input_integer) {
	try {
	    mResult = mTelitManagerDemoService.demo_testCallback(callback_input_integer);
	} catch (Exception e) {
            Log.e(TAG, "ERROR: demo_testCallback: Call TelitManagerDemo.initialize before reattempt");
	    e.printStackTrace();
	}
	return mResult;
    }
}
