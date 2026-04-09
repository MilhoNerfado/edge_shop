# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run on connected Android device (primary target)
flutter run

# Build release APK
flutter build apk --release

# Analyze Dart code
flutter analyze

# Run Dart tests
flutter test

# Run a single test file
flutter test test/some_test.dart
```

The app targets Android only (Telit SE250B4 hardware). It does not run on iOS or desktop.

## Architecture

Edge Shop is a Flutter kiosk app for a physical vending machine. It runs in fullscreen immersive/kiosk mode (no status bar, no navigation) and auto-launches on boot.

### Hardware interface

The app controls hardware on a **Telit SE250B4** Android module via two channels:

1. **RS-232 / UART** (`/dev/ttyHS1`, 9600/8N1) — drives an Arduino that controls 4 physical GPIO relay channels (pins 2–5). GPIO state is sent as a single hex byte `"0xHH\n"` where bits 0–3 map to channels 0–3.

2. **NFC** — uses the `nfc_manager` package to read NFC tag UIDs for payment confirmation.

### Platform channel

`UartChannelService` (Dart, `lib/services/uart_service.dart`) talks to `UartService.kt` (Kotlin, `android/app/src/main/kotlin/com/example/edge_shop/`) via MethodChannel `com.example.edge_shop/uart`. All UART I/O is dispatched on a dedicated `HandlerThread` ("uart-worker") to avoid blocking the UI thread.

`UartService.kt` bypasses the TelitManager Java proxy and talks directly to the `telitmanagerservice` system binder using raw `Parcel` transactions. AIDL transaction codes: `uartOpen=8`, `uartClose=9`, `uartWrite=10`, `uartRead=11`.

### Flutter app structure

- `lib/main.dart` — entry point; sets up immersive kiosk mode, lifecycle observer to re-enter immersive mode after NFC dialogs. Routes: `/` → `VendingMachinePage`, `/debug` → `DebugToolsPage`.
- `lib/pages/vending_machine_page.dart` — primary user-facing UI. State machine: `idle → waitingPayment → dispensing → done → idle`. Selecting a product starts an NFC session; scanning a valid tag opens the corresponding GPIO channel; the user manually closes the slot.
- `lib/models/vending_item.dart` — `VendingItem` data class + `vendingItems` list (4 items, slots A1/A2/B1/B2, GPIO channels 0–3).
- `lib/app_strings.dart` — simple i18n: English (default), Portuguese, German. Selected by device locale at runtime.
- `lib/pages/gpio_control_page.dart` — debug tool: manually toggle GPIO channels over RS-232.
- `lib/pages/rs232_echo_page.dart` — debug tool: raw RS-232 send/receive.
- `lib/pages/nfc_reader_page.dart` — debug tool: scan and dump NFC tag data.

### Kiosk / device owner features

- `AdminReceiver.kt` — `DeviceAdminReceiver` required for Device Owner mode.
- `BootReceiver.kt` — auto-launches the app on `BOOT_COMPLETED`.
- `MainActivity.kt` — calls `startLockTask()` when the app is the device owner, enabling Android kiosk lock task mode silently (no system overlay).

### Key behavioural notes

- UART port is closed on `onStop`/`onDestroy`/`AppLifecycleState.paused` to avoid leaving `/dev/ttyHS1` locked. On open, if EBUSY (-16) is returned, `UartService` does a force-close and retries once.
- NFC events are debounced with a 1-second guard (`_lastNfcScan`) to prevent double-triggering.
- The app re-enters immersive mode on `AppLifecycleState.resumed` to recover after NFC system dialogs.
- Vending flow logs use `dart:developer` log with name `EdgeShop.NFC` / `EdgeShop.GPIO` for filtering in logcat.
