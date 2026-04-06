package android.app.telit.demo;

import android.app.telit.demo.ITelitManagerDemoCallback;

/**
 * Telit System-Service Manager APIs to interface Hardware AIDL APIs
 *
 * {@hide}
 */
interface ITelitManagerDemo {
    /* API to initialize TelitManagerDemo System-Service */
    int initialize(in int aidl);

    /* API to invoke Demo AIDL TestInputPassing functionality */
    int demo_testInputPassing(in int input_integer, in String input_string);

    /* API to invoke Demo AIDL RegisterCallback functionality */
    int demo_registerCallback(in ITelitManagerDemoCallback callback);

    /* API to invoke Demo AIDL testCallback functionality */
    int demo_testCallback(in int callback_input_integer);
}
