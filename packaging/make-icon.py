#!/usr/bin/env python3
"""Draw the installer's icon -- our own artwork, nothing traced from the game.

Writes o2jam.png (512x512, for Linux / the AppImage) and o2jam.ico (all sizes,
for the Windows build) next to this script.

    python3 packaging/make-icon.py
"""

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.stderr.write("needs Pillow:  python3 -m pip install pillow\n")
    raise SystemExit(1)

DARK = (18, 20, 26, 255)          # window-ish charcoal
BLUE = (53, 194, 240, 255)        # the project's accent
WHITE = (240, 248, 255, 255)
ICO_SIZES = [256, 128, 64, 48, 32, 16]

FONT_CANDIDATES = (
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/liberation/LiberationSans-Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "C:/Windows/Fonts/segoeuib.ttf",
)


def load_font(size: int):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def draw(size: int) -> "Image.Image":
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    d.rounded_rectangle([0, 0, size - 1, size - 1],
                        radius=int(size * 0.22), fill=DARK)

    ring_w = max(2, int(size * 0.055))
    m = int(size * 0.13)
    d.ellipse([m, m, size - 1 - m, size - 1 - m], outline=BLUE, width=ring_w)
    d.ellipse([m + ring_w, m + ring_w, size - 1 - m - ring_w, size - 1 - m - ring_w],
              outline=(53, 194, 240, 90), width=max(1, ring_w // 3))

    txt = "O2"
    font = load_font(int(size * 0.36))
    box = d.textbbox((0, 0), txt, font=font)
    d.text(((size - (box[2] - box[0])) / 2 - box[0],
            (size - (box[3] - box[1])) / 2 - box[1]), txt, font=font, fill=WHITE)
    return img


def main() -> int:
    png = HERE / "o2jam.png"
    ico = HERE / "o2jam.ico"
    big = draw(512)
    big.save(png)
    print(f"  wrote {png}  ({png.stat().st_size} bytes, {big.width}x{big.height})")

    frames = [draw(s) for s in ICO_SIZES]
    frames[0].save(ico, format="ICO", sizes=[(s, s) for s in ICO_SIZES])
    print(f"  wrote {ico}  ({ico.stat().st_size} bytes, sizes {ICO_SIZES})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
