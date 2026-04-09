# Copilot Instructions — Edge Shop

## Commands

```bash
flutter run                          # Run on connected Android device
flutter build apk --release          # Build release APK
flutter analyze                      # Lint Dart code
flutter test                         # Run all tests
flutter test test/some_test.dart     # Run a single test file
```

> The app targets **Android only** (Telit SE250B4 hardware). Do not attempt to run or build for iOS, web, or desktop.

## Architecture

Edge Shop is a Flutter kiosk app for a physical vending machine. It runs fullscreen immersive mode (no status bar/navigation) and auto-launches on boot.

### Two-layer hardware stack

```
Flutter (Dart)
  └─ UartChannelService          lib/services/uart_service.dart
       └─ MethodChannel          "com.example.edge_shop/uart"
            └─ UartService.kt    android/app/src/main/.../UartService.kt
                 └─ raw Parcel binder → telitmanagerservice (system service)
                      └─ /dev/ttyHS1 (RS-232, 9600/8N1)
                           └─ Arduino UNO (edge_shop.ino)
                                └─ 4 GPIO relay channels (pins 2–5)
```

- **UART/GPIO**: All binder calls use hard-coded AIDL transaction codes (`uartOpen=8`, `uartClose=9`, `uartWrite=10`, `uartRead=11`) against the `telitmanagerservice` system binder. There is no AIDL file — the codes are maintained manually.
- **GPIO state** is sent as a single ASCII hex string `"0xHH\n"` where bits 0–3 of the lower nibble map to GPIO channels 0–3 (Arduino pins 2–5). The Arduino replies `"ACK\n"`. Always send the full state bitmask — do not send partial updates.
- **NFC** uses the `nfc_manager` package for payment confirmation. Any scanned NFC tag is accepted as valid payment (no tag validation).

### Flutter app state machine

`VendingMachinePage` (`lib/pages/vending_machine_page.dart`) owns the main flow:

```
idle → waitingPayment → done → idle (auto after 5 s)
```

- **idle**: Product grid shown; UART port open; GPIO all LOW.
- **waitingPayment**: NFC session active; pulsing animation shown.
- **done**: NFC session stopped; GPIO channel pulsed HIGH for 1 second; 5-second countdown to auto-reset.

### Key files

| File | Role |
|---|---|
| `lib/main.dart` | Entry point; kiosk mode; routes (`/` → VendingMachinePage, `/debug` → DebugToolsPage) |
| `lib/pages/vending_machine_page.dart` | Primary UI and vending state machine |
| `lib/models/vending_item.dart` | `VendingItem` data class + `vendingItems` list (4 items, slots A1/A2/B1/B2) |
| `lib/app_strings.dart` | i18n strings (English/Portuguese/German); resolved from device locale at runtime |
| `lib/services/uart_service.dart` | Dart MethodChannel client for UART |
| `android/.../UartService.kt` | Kotlin binder implementation for UART HAL |
| `android/.../MainActivity.kt` | Registers MethodChannel; dispatches UART calls on `HandlerThread("uart-worker")` |
| `android/.../BootReceiver.kt` | Auto-launch on `BOOT_COMPLETED` |
| `android/.../AdminReceiver.kt` | `DeviceAdminReceiver` for Device Owner / lock task mode |
| `edge_shop.ino` | Arduino sketch: parses `"0xHH\n"` commands, drives relay pins |

## Key conventions

### UART lifecycle
- UART port is closed on `AppLifecycleState.paused/detached`, `onStop`, and `onDestroy` to avoid leaving `/dev/ttyHS1` locked.
- On `open()`, if the HAL returns `-16` (EBUSY), `UartService.kt` force-closes and retries once automatically.
- After opening, a `"\r\n"` flush is sent to clear the Arduino's RX buffer.

### GPIO state management
- `_stateBits` (in `VendingMachinePage`) tracks the current full bitmask. `_openGpio(channel)` ORs the bit; `_closeGpio(channel)` ANDs the complement. Always call `_pushState()` to write the full state — never send partial commands.

### NFC debounce
- `_lastNfcScan` timestamp guards against double-firing within 1 second.
- The NFC session is started once in `initState` and kept running for the lifetime of `VendingMachinePage`. The `onDiscovered` callback state-gates behaviour (`waitingPayment` only).
- **Never call `stopSession()` from within an `onDiscovered` callback** — Android holds an internal lock during `onTagDiscovered`; calling `disableReaderMode` from inside causes a deadlock/timeout. Session is only stopped on app pause, `dispose`, or when entering the debug menu.
- Before navigating to `/debug`, the session is stopped (so the debug NFC reader can take over); it is restarted when the user returns.
- Immersive mode is re-entered on `AppLifecycleState.resumed` to recover after NFC system dialogs.

### Logging
- Use `dart:developer` `log()` with `name: 'EdgeShop.NFC'` or `name: 'EdgeShop.GPIO'` for vending flow events (filterable in logcat).

### i18n
- Add new strings to all three locales in `AppStrings` (`_english`, `_portuguese`, `_german`).
- `AppStrings.of(locale.languageCode)` is called in `didChangeDependencies`, not `initState`, so locale is available.

### Kiosk / Device Owner
- `startLockTask()` is only called when the app is the Device Owner (checked via `DevicePolicyManager`). Without Device Owner, the system overlay would freeze Flutter's first frame — skip it.
- A `PARTIAL_WAKE_LOCK` (`"EdgeShop::KioskWakeLock"`) is acquired in `onCreate` and released in `onDestroy` to prevent the CPU from deep-sleeping while the app is running. The `WAKE_LOCK` permission is declared in the manifest.

### Platform channel return shape
All UART MethodChannel methods return `Map<String, dynamic>` with at minimum `{'success': bool, 'message': String}`. `uartWrite` adds `'bytesWritten'`; `uartRead` adds `'data'` and `'bytesRead'`.
