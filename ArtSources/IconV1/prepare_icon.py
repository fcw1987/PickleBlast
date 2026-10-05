#!/usr/bin/env python3
"""Technical conversion of the approved original icon; preserve design and pin solid ink to sRGB black."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from import_art import convert_png, png_pixels, write_png
root = Path(__file__).resolve().parent
convert_png(root / "generated-master.png", root / "app_icon_1024.png", [1024, 1024], opaque=True)
width, height, channels, pixels = png_pixels(root / "app_icon_1024.png")
# Only near-black solid ink becomes exact #000000. Green and blended edges stay intact.
for offset in range(0, len(pixels), channels):
    if max(pixels[offset:offset + 3]) <= 32:
        pixels[offset:offset + 3] = b"\0\0\0"
write_png(root / "app_icon_1024.png", width, height, channels, pixels)

