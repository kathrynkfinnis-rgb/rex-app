#!/usr/bin/env python3
"""Regenerate every Rex brand file from the masters in brand/source.

AGENTS.md used to say the dino existed as eleven files and that nothing kept
them in step. This is the thing that keeps them in step. Change a master, run
this, commit everything it touches — that is the whole procedure.

    python3 brand/regenerate.py

Needs Pillow:  python3 -m pip install --user Pillow

The delivered dino is flat green on flat cream with no alpha channel, so
transparency is recovered by reading where each pixel sits on the cream->green
ramp. That turns the cream dots in the crown and the eye into real holes, which
is what a transparent mark should do, and leaves anti-aliased edges with no
pale halo around them.
"""
import pathlib
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is missing — python3 -m pip install --user Pillow")

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "brand" / "source"

# Sampled from the November 2026 delivery. ic_launcher_background in
# android/app/src/main/res/values/colors.xml must match CREAM, or the masked
# Android icon shows a seam where the foreground's own cream meets it.
CREAM = (249, 250, 234)   # #F9FAEA
GREEN = (112, 163, 97)    # #70A361


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def dino_rgba():
    """The dino alone, cream knocked out, cropped tight to its own ink."""
    src = Image.open(SRC / "dino.jpg").convert("RGB")
    w, h = src.size
    lo, hi = lum(GREEN), lum(CREAM)
    out = Image.new("RGBA", (w, h), GREEN + (0,))
    sp, op = src.load(), out.load()
    for y in range(h):
        for x in range(w):
            a = (hi - lum(sp[x, y])) / (hi - lo)
            op[x, y] = GREEN + (0 if a <= 0 else 255 if a >= 1 else int(a * 255),)
    return out.crop(out.getbbox())


def flat(img, size, bg=CREAM):
    """Square and opaque on the mark's own cream — every launcher icon."""
    canvas = Image.new("RGB", (size, size), bg)
    r = img.convert("RGBA").resize((size, size), Image.LANCZOS)
    canvas.paste(r, (0, 0), r)
    return canvas


def centred(mark, size, fraction):
    """Transparent square holding the mark at `fraction` of the canvas."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    box = int(size * fraction)
    s = min(box / mark.size[0], box / mark.size[1])
    m = mark.resize((max(1, round(mark.size[0] * s)),
                     max(1, round(mark.size[1] * s))), Image.LANCZOS)
    canvas.paste(m, ((size - m.size[0]) // 2, (size - m.size[1]) // 2), m)
    return canvas


def main():
    icon = Image.open(SRC / "dino.jpg").convert("RGB")
    lock = Image.open(SRC / "lockup.jpg").convert("RGB")
    word = Image.open(SRC / "wordmark-green.png").convert("RGBA")
    mark = dino_rgba()

    written = []

    def put(path, img):
        img.save(ROOT / path)
        written.append((path, img.size, img.mode))

    # iOS — Apple wants 1024 square and opaque, and the designer's own margins
    # are the right ones to keep, so this is a straight resize.
    put("ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png",
        icon.resize((1024, 1024), Image.LANCZOS))

    # Android — 432 is 108dp at xxhdpi. The launcher masks the outer ring away
    # and guarantees only the inner 66 of those 108dp, so the dino is held to
    # 61% of the canvas or a circular mask eats its tail and feet.
    put("android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png",
        centred(mark, 432, 66 / 108))

    # Website
    put("web/og-default.png", flat(lock, 1200))   # link previews: mark + name
    put("web/icon-512.png", flat(icon, 512))
    put("web/icon-192.png", flat(icon, 192))
    put("web/icon-180.png", flat(icon, 180))
    put("web/apple-touch-icon.png", flat(icon, 180))
    put("web/favicon.png", flat(icon, 64))
    put("web/wordmark.png",
        word.resize((496, round(word.size[1] * 496 / word.size[0])), Image.LANCZOS))
    put("web/dinologo.png",
        mark.resize((506, round(mark.size[1] * 506 / mark.size[0])), Image.LANCZOS))

    for path, size, mode in written:
        print(f"  {size[0]:>5}x{size[1]:<5} {mode:<5} {path}")
    print(f"\n{len(written)} files written")


if __name__ == "__main__":
    main()
