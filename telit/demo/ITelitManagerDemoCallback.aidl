package android.app.telit.demo;

/**
 * Telit System-Service Manager Callback interface to Applications
 *
 * {@hide}
 */
oneway interface ITelitManagerDemoCallback {
    void onDemoTestCallback(in int callback_input_integer);
}
