/**
 * edge_shop.ino — Arduino UNO GPIO Controller via UART
 *
 * Listens on Serial (9600 8N1) for hex-string commands of the form "0xHH\n".
 * Only the lower nibble (bits 0-3) drives 4 GPIOs; upper bits are ignored.
 * Acknowledged: the Arduino replies "ACK\n" after applying a valid command.
 *
 * This string-based protocol filters out boot garbage from the Android device,
 * since random bytes will never match the "0x" + two hex digits + '\n' pattern.
 *
 * Byte layout (only lower nibble used):
 *   bit 0 → pin 2
 *   bit 1 → pin 3
 *   bit 2 → pin 4
 *   bit 3 → pin 5
 *
 * Example: "0x05\n" → pin 2 HIGH, pin 3 LOW, pin 4 HIGH, pin 5 LOW
 */

#define NUM_PINS 4
const uint8_t gpioPins[NUM_PINS] = {13, 3, 4, 5};
const uint8_t PIN_MASK = 0x0F;

#define BUF_SIZE 8
char rxBuf[BUF_SIZE];
uint8_t rxIdx = 0;

void applyState(uint8_t state) {
  state &= PIN_MASK;
  for (uint8_t i = 0; i < NUM_PINS; i++) {
    digitalWrite(gpioPins[i], (state >> i) & 1 ? LOW : HIGH);
  }
}

int8_t hexCharToNibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return -1;
}

void setup() {
  Serial.begin(9600);
  Serial.println("Arduino GPIO Controller Ready");

  for (uint8_t i = 0; i < NUM_PINS; i++) {
    pinMode(gpioPins[i], OUTPUT);
  }

  delay(1);

  applyState(0x00);
}

void loop() {
  while (Serial.available()) {
    char c = Serial.read();

    if (c == '\n' || c == '\r') {
      if (rxIdx == 4 && rxBuf[0] == '0' && (rxBuf[1] == 'x' || rxBuf[1] == 'X')) {
        int8_t hi = hexCharToNibble(rxBuf[2]);
        int8_t lo = hexCharToNibble(rxBuf[3]);
        if (hi >= 0 && lo >= 0) {
          applyState(((uint8_t)hi << 4) | (uint8_t)lo);
          Serial.println("ACK");
        }
      }
      rxIdx = 0;
    } else {
      if (rxIdx < BUF_SIZE - 1) {
        rxBuf[rxIdx++] = c;
      } else {
        rxIdx = BUF_SIZE;
      }
    }
  }
}
