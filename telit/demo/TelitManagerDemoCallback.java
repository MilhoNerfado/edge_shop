package android.app.telit.demo;

/**
 * Callback provided by the client application while invoking registerCallback {@link TelitManagerDemoService demo_registerCallback}
 * to receive asynchronous operation results, updates and error notifications.
 */
public abstract class TelitManagerDemoCallback {
    public void onTelitManagerCallback(int callback_input_integer) {}
}

