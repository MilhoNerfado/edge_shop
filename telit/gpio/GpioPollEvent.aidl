package android.app.telit.gpio;

/*
 * GPIO Pin Poll events as defined in GPIO AIDL
 */
@Backing(type="int")
enum GpioPollEvent {
    GPIO_POLL_EVENT_NONE         = 0,
    GPIO_POLL_EVENT_RISING_EDGE  = 1,
    GPIO_POLL_EVENT_FALLING_EDGE = 2,
    GPIO_POLL_EVENT_BOTH_EDGES   = 3,
}

