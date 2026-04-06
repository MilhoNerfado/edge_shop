package android.app.telit.gpio;

/*
 * GPIO State Values as defined in GPIO AIDL
 */
@Backing(type="int")
enum GpioState {
    GPIO_STATE_LOW = 0,
    GPIO_STATE_HIGH = 1,
    GPIO_STATE_UNKNOWN,
}

