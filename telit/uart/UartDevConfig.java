package android.app.telit.uart;

import android.os.Parcel;
import android.os.Parcelable;
import android.annotation.NonNull;
import android.annotation.Nullable;

import android.app.telit.uart.UartBaudRate;
import android.app.telit.uart.UartParity;
import android.app.telit.uart.UartStopBit;
import android.app.telit.uart.UartFlowCtrl;

/**
 * Support for parcelable and aidl operations.
 */
public final class UartDevConfig implements Parcelable {
    private @UartBaudRate int mBaudRate;
    private @UartParity int mParity;
    private @UartStopBit int mStopBit;
    private @UartFlowCtrl int mFlowCtrl;

    public UartDevConfig(@UartBaudRate int baudRate, @UartParity int parity,
                        @UartStopBit int stopBit, @UartFlowCtrl int flowCtrl) {
        this.mBaudRate = baudRate;
        this.mParity = parity;
        this.mStopBit = stopBit;
        this.mFlowCtrl = flowCtrl;
    }

    public static final @NonNull Parcelable.Creator<UartDevConfig> CREATOR
        = new Parcelable.Creator<UartDevConfig>() {

            public UartDevConfig createFromParcel(Parcel in) {
                return new UartDevConfig(in);
            }

            public UartDevConfig[] newArray(int size) {
                return new UartDevConfig[size];
            }
    };

    public void writeToParcel(@NonNull Parcel dest, int flags) {
        dest.writeInt(mBaudRate);
        dest.writeInt(mParity);
        dest.writeInt(mStopBit);
        dest.writeInt(mFlowCtrl);
    }

    public void readFromParcel(@NonNull Parcel in) {
        mBaudRate = in.readInt();
        mParity = in.readInt();
        mStopBit = in.readInt();
        mFlowCtrl = in.readInt();
    }

    UartDevConfig(@NonNull Parcel in) {
        readFromParcel(in);
    }

    public int describeContents() {
        return 0;
    }

    public int getBaudRate() {
        return mBaudRate;
    }

    public int getParity() {
        return mParity;
    }

    public int getStopBit() {
        return mStopBit;
    }
     
    public int getFlowCtrl() {
        return mFlowCtrl;
    }

    public void setBaudRate(@UartBaudRate int baudRate) {
        this.mBaudRate = baudRate;
    }

    public void setParity(@UartParity int parity) {
        this.mParity = parity;
    }

    public void setStopBit(@UartStopBit int stopBit) {
        this.mStopBit = stopBit;
    }

    public void setFlowCtrl(@UartFlowCtrl int flowCtrl) {
        this.mFlowCtrl = flowCtrl;
    }
}

