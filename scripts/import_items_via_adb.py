#!/usr/bin/env python3
"""Create and upload an Edge Shop item setup bundle via ADB."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PACKAGE_NAME = "com.example.edge_shop"
DEVICE_IMPORT_DIR = (
    f"/sdcard/Android/data/{PACKAGE_NAME}/files/item_setup_import"
)
IMAGE_EXTENSIONS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".gif",
    ".bmp",
}


def prompt_text(label: str) -> str:
    return input(f"{label}: ").strip()


def try_pick_file_dialog(title: str) -> Path | None:
    try:
        import tkinter as tk
        from tkinter import filedialog
    except Exception:
        return None

    root = tk.Tk()
    root.withdraw()
    root.update()
    selected = filedialog.askopenfilename(
        title=title,
        filetypes=[
            ("Image files", "*.png *.jpg *.jpeg *.webp *.gif *.bmp"),
            ("All files", "*.*"),
        ],
    )
    root.destroy()
    return Path(selected) if selected else None


def prompt_image(item_number: int) -> Path | None:
    print(f"\nItem {item_number} image")
    print("Press Enter to open a file picker, type a file path, or type '-' to skip.")
    response = input("> ").strip()
    if response == "-":
      return None
    if response:
        path = Path(response).expanduser()
        if not path.is_file():
            raise FileNotFoundError(f"Image file not found: {path}")
        return path

    selected = try_pick_file_dialog(f"Select image for item {item_number}")
    return selected


def ensure_adb() -> None:
    try:
        subprocess.run(
            ["adb", "version"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise RuntimeError("adb is not available on PATH.") from exc


def run_adb(*args: str) -> None:
    subprocess.run(["adb", *args], check=True)


def build_bundle(staging_dir: Path) -> list[dict[str, object]]:
    items: list[dict[str, object]] = []

    for gift_index in range(1, 4):
        print(f"\n--- Item {gift_index} ---")
        item: dict[str, object] = {"giftIndex": gift_index}

        name = prompt_text("Name (leave empty to keep current/default)")
        if name:
            item["name"] = name

        description = prompt_text("Description (leave empty to keep current/default)")
        if description:
            item["description"] = description

        image_path = prompt_image(gift_index)
        if image_path is not None:
            extension = image_path.suffix.lower()
            if extension not in IMAGE_EXTENSIONS:
                raise ValueError(
                    f"Unsupported image type for item {gift_index}: {image_path.name}"
                )

            destination_name = f"item_{gift_index}{extension}"
            shutil.copy2(image_path, staging_dir / destination_name)
            item["image"] = destination_name

        items.append(item)

    return items


def write_config(staging_dir: Path, items: list[dict[str, object]]) -> Path:
    config_path = staging_dir / "config.json"
    config_path.write_text(
        json.dumps({"items": items}, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    return config_path


def push_bundle(staging_dir: Path) -> None:
    run_adb("shell", "mkdir", "-p", DEVICE_IMPORT_DIR)
    run_adb("push", f"{staging_dir}/.", f"{DEVICE_IMPORT_DIR}/")


def main() -> int:
    print("Edge Shop ADB item importer")
    print(f"Device bundle folder: {DEVICE_IMPORT_DIR}")

    try:
        ensure_adb()
        with tempfile.TemporaryDirectory(prefix="edge-shop-item-setup-") as temp_dir:
            staging_dir = Path(temp_dir)
            items = build_bundle(staging_dir)
            config_path = write_config(staging_dir, items)

            print(f"\nGenerated bundle at: {staging_dir}")
            print(f"Config file: {config_path}")
            print(json.dumps({"items": items}, indent=2, ensure_ascii=True))

            confirm = input("\nPush this bundle to the device with adb? [Y/n] ").strip()
            if confirm.lower() not in {"", "y", "yes"}:
                print("Cancelled before upload.")
                return 0

            push_bundle(staging_dir)
    except KeyboardInterrupt:
        print("\nCancelled.")
        return 130
    except Exception as exc:
        print(f"\nError: {exc}", file=sys.stderr)
        return 1

    print("\nUpload complete.")
    print("On the device, open Debug Tools -> Items and tap Import from ADB.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
