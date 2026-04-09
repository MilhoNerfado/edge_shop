## Project: Edge Shop

Edge Shop is a Flutter (Dart) kiosk app for a physical vending machine running on a **Telit SE250B4** Android module. It runs permanently in fullscreen immersive/lock-task kiosk mode, auto-launches on boot, and is deployed as a Device Owner app.

### Hardware

| Interface | Details |
|-----------|---------|
| RS-232 / UART | `/dev/ttyHS1`, 9600/8N1. Accessed via raw Parcel transactions to the `telitmanagerservice` system binder (AIDL transaction codes: open=8, close=9, write=10, read=11). No public SDK. |
| GPIO | 4-channel relay via an Arduino on the RS-232 line. State sent as a hex byte `"0xHH\n"` where bits 0–3 map to channels 0–3 (Arduino pins 2–5). |
| NFC reader | Device built-in; uses the `nfc_manager` Flutter package for tag discovery and NDEF parsing. NFC triggers payment confirmation in the vending flow. |

### Flutter/Dart app structure

- `lib/main.dart` — entry point; immersive kiosk mode setup; lifecycle observer to re-enter immersive after NFC dialogs. Routes: `/` → `VendingMachinePage`, `/debug` → `DebugToolsPage`.
- `lib/pages/vending_machine_page.dart` — primary UI. State machine: `idle → waitingPayment → dispensing → done → idle`.
- `lib/services/uart_service.dart` — `UartChannelService`: Dart MethodChannel client for UART ops (open/close/write/read).
- `lib/models/vending_item.dart` — `VendingItem` data class; 4 items (slots A1/A2/B1/B2, GPIO channels 0–3).
- `lib/app_strings.dart` — inline i18n: English (default), Portuguese, German.
- `lib/pages/gpio_control_page.dart`, `rs232_echo_page.dart`, `nfc_reader_page.dart` — debug tools.

### Android (Kotlin) layer

- `MainActivity.kt` — registers MethodChannel `com.example.edge_shop/uart`; dispatches all UART calls to a `HandlerThread` ("uart-worker"); calls `startLockTask()` when device owner.
- `UartService.kt` — raw binder client for `telitmanagerservice`; handles EBUSY (-16) with force-close + retry.
- `AdminReceiver.kt` — `DeviceAdminReceiver` required for Device Owner.
- `BootReceiver.kt` — `BOOT_COMPLETED` receiver that re-launches the app.

### Key behaviours to keep in mind

- UART port is force-closed on `onStop`/`onDestroy`/`paused` lifecycle events.
- NFC events are debounced with a 1-second guard (`_lastNfcScan`).
- App re-enters immersive mode on `AppLifecycleState.resumed` to recover after NFC system dialogs.
- Logcat filter names: `EdgeShop.NFC`, `EdgeShop.GPIO`.

### Flutter dependencies

- `nfc_manager: ^3.3.0`
- `flutter_svg: ^2.0.10+1`

---

### How to use this project

Describe what you need and Claude will adapt its mode:

- **Searching the codebase** — mention a file name, class, or behaviour and ask where/how it works.
- **Research** — ask "how does X work", "what's the Android API for Y", "what are the options for Z" and Claude will research Flutter patterns, Android kiosk/Device Owner APIs, AIDL internals, or NFC protocols.
- **Brainstorming** — say "I'm thinking about adding X" or "help me design Y" and Claude will explore trade-offs and approaches before touching code.
- **Implementation** — say "implement X" or "fix Y" and Claude will write code following the patterns above.

Always assume the target device is the Telit SE250B4 (Android, no Play Services, Device Owner).
