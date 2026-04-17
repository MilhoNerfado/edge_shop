#include <SoftwareSerial.h>

#define UART_TX 8
#define UART_RX 9

SoftwareSerial Uart(UART_RX, UART_TX);

char buffer[6]; // "0xFF\n" + '\0'
uint8_t index = 0;

void setup() {
  Uart.begin(9600);

  pinMode(2, OUTPUT);
  pinMode(3, OUTPUT);
  pinMode(4, OUTPUT);

  digitalWrite(2, LOW);
  digitalWrite(3, LOW);
  digitalWrite(4, LOW);
}

void processCommand() {
  buffer[index] = '\0';

  if (strcmp(buffer, "0x00") == 0) {
    digitalWrite(2, LOW);
    digitalWrite(3, LOW);
    digitalWrite(4, LOW);
  }
  else if (strcmp(buffer, "0x01") == 0) {
    digitalWrite(2, HIGH);
    digitalWrite(3, LOW);
    digitalWrite(4, LOW);
    Uart.println("ACK");
  }
  else if (strcmp(buffer, "0x02") == 0) {
    digitalWrite(2, LOW);
    digitalWrite(3, HIGH);
    digitalWrite(4, LOW);
    Uart.println("ACK");
  }
  else if (strcmp(buffer, "0x04") == 0) {
    digitalWrite(2, LOW);
    digitalWrite(3, LOW);
    digitalWrite(4, HIGH);
    Uart.println("ACK");
  }
  else if (strcmp(buffer, "0x0f") == 0) {
    digitalWrite(2, HIGH);
    digitalWrite(3, HIGH);
    digitalWrite(4, HIGH);
    Uart.println("ACK");
  }
}

void loop() {
  while (Uart.available()) {
    char c = Uart.read();

    if (c == '\n') {
      processCommand();
      index = 0;
    } 
    else {
      if (index < sizeof(buffer) - 1) {
        buffer[index++] = c;
      } 
      else {
       // DESLOCA PARA ESQUERDA
        for (uint8_t i = 0; i < sizeof(buffer) - 2; i++) {
          buffer[i] = buffer[i + 1];
        }
        buffer[sizeof(buffer) - 2] = c;
        index = sizeof(buffer) - 1;
      }
    }
  }
}
