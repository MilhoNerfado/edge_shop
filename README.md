# edge_shop

A new Flutter project.

## ADB item setup import

The debug **Items** tab can import item names, descriptions, and images from the app's external files directory.

1. Push a setup bundle from your PC into:
   `/sdcard/Android/data/com.example.edge_shop/files/item_setup_import/`
2. Put a `config.json` file there, plus any referenced image files.
3. The app auto-imports the bundle on startup whenever `config.json` or the referenced images change.
4. You can also open **Debug Tools -> Items** and tap **Import from ADB** to force the import immediately.

Example:

```bash
adb shell mkdir -p /sdcard/Android/data/com.example.edge_shop/files/item_setup_import
adb push ./edge-shop-setup/. /sdcard/Android/data/com.example.edge_shop/files/item_setup_import/
```

Example `config.json`:

```json
{
  "items": [
    {
      "giftIndex": 1,
      "name": "Coffee Mug",
      "description": "Ceramic mug with logo",
      "image": "item_1.png"
    },
    {
      "giftIndex": 2,
      "name": "Notebook",
      "description": "A5 hard cover notebook"
    }
  ]
}
```

If an item omits `image`, the current image/icon is kept. If `image` is present but empty, the item visual is reset to the default icon.

## PC helper script

To create and upload the bundle from your PC with image selection support:

```bash
python3 scripts/import_items_via_adb.py
```

The script:

1. Prompts for each item's name and description
2. Lets you choose an image from your PC for each item
3. Builds `config.json`
4. Pushes the full bundle to the device with `adb`

If Tk file dialogs are unavailable on your PC, paste the image file path instead when prompted.

## Handy commands

Install the current release APK on the connected device:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Install the release APK on a specific device:

```bash
adb -s C2318000000430000752 install -r build/app/outputs/flutter-apk/app-release.apk
```

If there is a signature or version conflict:

```bash
adb -s C2318000000430000752 uninstall com.example.edge_shop
adb -s C2318000000430000752 install build/app/outputs/flutter-apk/app-release.apk
```

Push the already prepared import bundle again without prompts:

```bash
adb shell mkdir -p /sdcard/Android/data/com.example.edge_shop/files/item_setup_import && adb push /home/milho/.copilot/session-state/171ae147-6e66-434a-9a4e-e3c867b701ba/files/item_setup_import/. /sdcard/Android/data/com.example.edge_shop/files/item_setup_import/
```
