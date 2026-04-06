package android.app.telit.gpio;

/* 
 * GPIO Direction Values as defined in GPIO AIDL 
 */
@Backing(type="int")
enum GpioDirection {
    GPIO_DIRECTION_UNKNOWN = 0,
    GPIO_DIRECTION_IN = 1,
    GPIO_DIRECTION_OUT = 2,
} 

