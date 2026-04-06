package android.app.telit.uart;

@Backing(type="int")
enum UartFlowCtrl {
    UART_FLOW_CTRL_DISABLE = 0,
    UART_FLOW_CTRL_RTSCTS,
}
