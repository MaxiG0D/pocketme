#!/usr/bin/env python3
"""Package approved ImageGen masters using macOS's built-in PNG resizer."""
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MASTERS = ROOT / "Design/AppIcon"
CATALOG = ROOT / "App/Resources/Icons.xcassets"
OUTPUT = CATALOG / "AppIcon.appiconset"
OUTPUT.mkdir(parents=True, exist_ok=True)


def export(master, filename, pixels):
    subprocess.run([
        "sips", "-s", "format", "png", "-z", str(pixels), str(pixels),
        str(MASTERS / master), "--out", str(OUTPUT / filename),
    ], check=True, stdout=subprocess.DEVNULL)


images = []
for appearance in ("light", "dark", "tinted"):
    filename = f"ios-{appearance}-1024.png"
    export(f"{appearance}.png", filename, 1024)
    entry = {
        "filename": filename, "idiom": "universal", "platform": "ios",
        "size": "1024x1024",
    }
    if appearance != "light":
        entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
    images.append(entry)

for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        filename = f"mac-{points}@{scale}x.png"
        export("mac.png", filename, points * scale)
        images.append({
            "filename": filename, "idiom": "mac", "scale": f"{scale}x",
            "size": f"{points}x{points}",
        })

info = {"author": "xcode", "version": 1}
(CATALOG / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
(OUTPUT / "Contents.json").write_text(json.dumps({"images": images, "info": info}, indent=2) + "\n")
shutil.copy2(OUTPUT / "mac-512@2x.png", ROOT / "Release/Resources/release-icon-1024.png")
print(f"Exported {len(images)} app icon assets to {OUTPUT}")
