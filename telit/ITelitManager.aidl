package android.app.telit;

import android.app.telit.TelitManagerSupportedAidls;
import android.app.telit.gpio.GpioNum;
import android.app.telit.gpio.GpioDirection;
import android.app.telit.gpio.GpioState;
import android.app.telit.gpio.GpioPollEvent;
import android.app.telit.i2c.I2cBus;
import android.app.telit.uart.UartDevConfig;

/**
 * Telit System-Service Manager APIs to interface Hardware AIDL APIs
 *
 * {@hide}
 */
interface ITelitManager {
    /* API to invoke GPIO AIDL GetDirection for input GPIO */
    int gpioGetDirection(in int gpioNum);

    /* API to invoke GPIO AIDL SetDirection for input GPIO */
    int gpioSetDirection(in int gpioNum, in GpioDirection direction);

    /* API to invoke GPIO AIDL Read for input GPIO */
    int gpioRead(in int gpioNum);

    /* API to invoke GPIO AIDL write for input GPIO */
    int gpioWrite(in int gpioNum, in GpioState state);

    /* API to invoke GPIO AIDL Poll for input GPIO */
    int gpioPoll(in int gpioNum, in GpioPollEvent event, in int timeout);

    /* API to invoke I2C AIDL Read byte data */
    int i2cReadByte(in I2cBus bus, in int slave, in int cmd);

    /* API to invoke I2C AIDL write byte data */
    int i2cWriteByte(in I2cBus bus, in int slave, in int cmd, in int wrByte);

    /* API to invoke UART AIDL Open */
    int uartOpen(in String devName, in UartDevConfig devConfig);

    /* API to invoke UART AIDL close */
    int uartClose(in String devName);

    /* API to invoke UART AIDL Write data */
    int uartWrite(in String devName, in char[] wrBuf, in int wrLen);

    /* API to invoke UART AIDL Read data */
    int uartRead(in String devName, out char[] rdBuf, in int rdLen);
}

