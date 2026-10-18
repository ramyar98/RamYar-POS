# -*- coding: utf-8 -*-
"""
RAMYAR POS - App icon generator.

Takes a single 1024x1024 source icon (assets/icon/app_icon.png) and produces
every platform icon variant the project needs:

  Android   -> legacy mipmaps + adaptive foreground/monochrome + anydpi-v26 XML
  iOS       -> AppIcon.appiconset (all sizes, opaque, incl. 1024 marketing)
  macOS     -> AppIcon.appiconset (16..1024, opaque)
  Windows   -> runner/resources/app_icon.ico (16..256 multi-size)
  Web/PWA   -> icons/Icon-{192,512}.png, maskable variants, favicon,
               apple-touch-icon
  Linux     -> embedded GResource icon PNG (flat, opaque)

The source logo is a centered dark-navy/orange mark with its own transparent
padding. For "opaque" formats (iOS/macOS/Windows/PWA) the mark is composited
onto a subtle vertical navy gradient so the finished icon looks intentionally
designed instead of showing a hard clipped edge. Android adaptive / web theme
colors use a flat brand navy derived from the same palette.

Usage:  python tools/generate_app_icons.py
"""

import os
import struct

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "assets", "icon", "app_icon.png")

# ---- Brand palette (sampled from the source mark's rim / body colors) ------
GRAD_TOP = (27, 46, 74)      # #1B2E4A subtle lighter navy (top)
GRAD_BOTTOM = (11, 16, 26)   # #0B101A deeper navy (bottom)
BRAND = (17, 26, 41)         # #111A29 flat navy (adaptive bg / web theme)

# Isolated safety zones (fraction of the canvas that icon content may fill)
ADAPTIVE_SAFE = 0.62   # Android adaptive: centre circle => bbox <= 62%
MASKABLE_SAFE = 0.78   # PWA maskable: safe zone is inner 80% square

APPICON_DIR_IOS = os.path.join(
    ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
APPICON_DIR_MACOS = os.path.join(
    ROOT, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
MIPMAP_DIR = os.path.join(ROOT, "android", "app", "src", "main", "res")
WEB_DIR = os.path.join(ROOT, "web", "icons")
WIN_ICO = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
LINUX_RES = os.path.join(ROOT, "linux", "runner", "resources")


def gradient(size, top=GRAD_TOP, bottom=GRAD_BOTTOM):
    """Build a vertical navy gradient image."""
    w, h = size
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1) if h > 1 else 0.0
        r = round(top[0] + (bottom[0] - top[0]) * t)
        g = round(top[1] + (bottom[1] - top[1]) * t)
        b = round(top[2] + (bottom[2] - top[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    return img


def flat_icon(size, background, content):
    """Composite content onto a background image (content keeps its alpha)."""
    canvas = background.convert("RGBA")
    canvas.alpha_composite(content)
    return canvas


def scaled_content(src, target_size, safe_fraction):
    """Return src resized so its visible bbox fills `safe_fraction` of target."""
    alpha = src.getchannel("A")
    bbox = alpha.point(lambda a: 255 if a > 16 else 0).getbbox()
    src_size = max(bbox[2] - bbox[0], bbox[3] - bbox[1])
    scale = (target_size * safe_fraction) / src_size
    nw = round(src.width * scale)
    nh = round(src.height * scale)
    return src.resize((nw, nh), Image.LANCZOS), scale


def place_centered(canvas, content, background=None):
    """Paste `content` centered on `canvas` (transparent or flat bg)."""
    canvas = canvas.convert("RGBA")
    if background is not None:
        bg = background.convert("RGBA")
        bg.alpha_composite(canvas)
        canvas = bg
    x = (canvas.width - content.width) // 2
    y = (canvas.height - content.height) // 2
    canvas.alpha_composite(content, (x, y))
    return canvas


def save_png(img, path, opaque=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Apple rejects app icons that carry an alpha channel, etc. Fully-opaque
    # variants are saved as true RGB PNGs.
    out = img.convert("RGB" if opaque else "RGBA")
    out.save(path, "PNG", optimize=True)
    print("wrote", os.path.relpath(path, ROOT))


def main():
    if not os.path.exists(SRC):
        raise SystemExit("Source icon not found: %s" % SRC)

    src = Image.open(SRC).convert("RGBA")
    if src.size != (1024, 1024):
        raise SystemExit("Expected a 1024x1024 source, got %s" % (src.size,))

    # ------------------------------------------------------------------
    # Master "flat" icon: gradient background + mark (opaque, 1024x1024)
    # ------------------------------------------------------------------
    bg_1024 = gradient((1024, 1024))
    flat = flat_icon((1024, 1024), bg_1024, src)

    # ------------------------------------------------------------------
    # Android
    # ------------------------------------------------------------------
    densities = {
        "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
    }
    adaptive_canvas = {
        "mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432,
    }

    # Adaptive foreground + monochrome sized once per density
    content_cache = {}
    for d in densities:
        size = densities[d]
        legacy = flat.resize((size, size), Image.LANCZOS)
        save_png(legacy, os.path.join(
            MIPMAP_DIR, "mipmap-%s" % d, "ic_launcher.png"), opaque=True)
        save_png(legacy, os.path.join(
            MIPMAP_DIR, "mipmap-%s" % d, "ic_launcher_round.png"), opaque=True)

        ac = adaptive_canvas[d]
        # Foreground: logo sized to 62% of the adaptive canvas, centered,
        # keeping its own transparency so the launcher background shows around.
        fg, _ = scaled_content(src, ac, ADAPTIVE_SAFE)
        fg_canvas = Image.new("RGBA", (ac, ac), (0, 0, 0, 0))
        fg_canvas = place_centered(fg_canvas, fg)
        save_png(fg_canvas, os.path.join(
            MIPMAP_DIR, "mipmap-%s" % d, "ic_launcher_foreground.png"))

        # Monochrome: the mark's silhouette in white (Android 13 themed icons)
        mono_sil = Image.new("RGBA", src.size, (255, 255, 255, 0))
        mono_sil.putalpha(src.getchannel("A"))
        mono, _ = scaled_content(mono_sil, ac, ADAPTIVE_SAFE)
        mono_canvas = Image.new("RGBA", (ac, ac), (0, 0, 0, 0))
        mono_canvas = place_centered(mono_canvas, mono)
        save_png(mono_canvas, os.path.join(
            MIPMAP_DIR, "mipmap-%s" % d, "ic_launcher_monochrome.png"))

    # ------------------------------------------------------------------
    # iOS (all sizes from Contents.json; opaque, no alpha channel)
    # ------------------------------------------------------------------
    ios_sizes = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, size in ios_sizes.items():
        save_png(flat.resize((size, size), Image.LANCZOS),
                 os.path.join(APPICON_DIR_IOS, name), opaque=True)

    # ------------------------------------------------------------------
    # macOS
    # ------------------------------------------------------------------
    mac_sizes = {
        "app_icon_16.png": 16, "app_icon_32.png": 32, "app_icon_64.png": 64,
        "app_icon_128.png": 128, "app_icon_256.png": 256,
        "app_icon_512.png": 512, "app_icon_1024.png": 1024,
    }
    for name, size in mac_sizes.items():
        save_png(flat.resize((size, size), Image.LANCZOS),
                 os.path.join(APPICON_DIR_MACOS, name), opaque=True)

    # ------------------------------------------------------------------
    # Windows multi-size .ico
    # ------------------------------------------------------------------
    ico_sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32),
                 (24, 24), (16, 16)]
    os.makedirs(os.path.dirname(WIN_ICO), exist_ok=True)
    with open(WIN_ICO, "wb") as f:
        flat_rgb = flat.convert("RGBA").resize((256, 256), Image.LANCZOS)
        ico_bytes = flat_rgb.save(f, format="ICO", sizes=ico_sizes)
    print("wrote", os.path.relpath(WIN_ICO, ROOT))

    # ------------------------------------------------------------------
    # Web / PWA
    # ------------------------------------------------------------------
    save_png(flat.resize((192, 192), Image.LANCZOS),
             os.path.join(WEB_DIR, "Icon-192.png"), opaque=True)
    save_png(flat.resize((512, 512), Image.LANCZOS),
             os.path.join(WEB_DIR, "Icon-512.png"), opaque=True)

    # Maskable: full-bleed gradient + mark kept well inside the safe zone.
    for size in (192, 512):
        bg = gradient((size, size))
        mask_content, _ = scaled_content(src, size, MASKABLE_SAFE)
        mask_icon = place_centered(
            Image.new("RGBA", (size, size), (0, 0, 0, 0)),
            mask_content, background=bg)
        save_png(mask_icon, os.path.join(
            WEB_DIR, "Icon-maskable-%d.png" % size), opaque=True)

    save_png(flat.resize((32, 32), Image.LANCZOS),
             os.path.join(ROOT, "web", "favicon.png"), opaque=True)
    save_png(flat.resize((180, 180), Image.LANCZOS),
             os.path.join(ROOT, "web", "apple-touch-icon.png"), opaque=True)

    # ------------------------------------------------------------------
    # Linux (embedded GResource icon - flat, opaque)
    # ------------------------------------------------------------------
    save_png(flat.resize((512, 512), Image.LANCZOS),
             os.path.join(LINUX_RES, "my_application_icon.png"), opaque=True)

    print("\nAll platform icons regenerated from", os.path.relpath(SRC, ROOT))


if __name__ == "__main__":
    main()