package android.app.telit.gpio;

/*
 * GPIO Pins available for user access
 */
@Backing(type="int")
enum GpioNum {
    GPIO_NUM_START = 0,
    GPIO_NUM_END   = 126,

    PM_GPIO_NUM_START = 200,
    PM_GPIO_NUM_END   = 209,
}

