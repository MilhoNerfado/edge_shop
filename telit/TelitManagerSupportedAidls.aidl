package android.app.telit;

/*
 * List of AIDL services suppoted by TelitManager
 * 
 */
@Backing(type="int")
enum TelitManagerSupportedAidls {
    TELIT_AIDL_GPIO = 1,
    TELIT_AIDL_I2C,
    TELIT_AIDL_UART,
}

