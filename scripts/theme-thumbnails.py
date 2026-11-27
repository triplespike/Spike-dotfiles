#!/usr/bin/env python3
"""Generate cached rounded wallpaper + palette-dot poster thumbnails for Rofi theme carousel."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


SIZE = 260
ART_W = 260
ART_H = 186
RADIUS = 16


def hex_rgba(val: str, fallback: str = "#678FE4", alpha: int = 255) -> tuple[int, int, int, int]:
    raw = (val or fallback).strip().lstrip("#")
    if len(raw) < 6:
        raw = fallback.lstrip("#")
    return int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16), alpha


def resolve_image(preset: dict, store_wp_dir: Path | None, home: Path) -> Path | None:
    wp = preset.get("wallpaper") or {}
    for key in ("fallback_image", "path"):
        raw = (wp.get(key) or "").strip()
        if not raw:
            continue
        p = Path(raw.replace("~", str(home), 1))
        if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}:
            return p
        if store_wp_dir is not None:
            cand = store_wp_dir / p.name
            if cand.is_file() and cand.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}:
                return cand
    return None


def extract_swatches(preset: dict) -> list[str]:
    niri = preset.get("niri") or {}
    ring = niri.get("focus_ring") or {}
    cava = (preset.get("cava") or {}).get("gradient") or []
    gh_pal = [
        entry.split("=", 1)[1]
        for entry in ((preset.get("ghostty") or {}).get("palette") or [])
        if isinstance(entry, str) and "=" in entry
    ]
    gh_accents = gh_pal[1:7] if len(gh_pal) >= 7 else gh_pal
    candidates = [ring.get("from"), ring.get("to"), *cava, *gh_accents]
    swatches: list[str] = []
    for c in candidates:
        if c and isinstance(c, str) and len(swatches) < 5:
            norm = "#" + c.strip().lstrip("#")[:6].upper()
            if norm not in swatches:
                swatches.append(norm)
    while len(swatches) < 5:
        swatches.append(swatches[-1] if swatches else "#678FE4")
    return swatches[:5]


def build_poster(src_img: Path, swatches: list[str], out_path: Path, centering: tuple[float, float] = (0.5, 0.5)) -> None:
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    with Image.open(src_img) as im:
        im = im.convert("RGBA")
        cover = ImageOps.fit(im, (ART_W, ART_H), method=Image.Resampling.LANCZOS, centering=centering)

    mask = Image.new("L", (ART_W, ART_H), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle((0, 0, ART_W - 1, ART_H - 1), radius=RADIUS, fill=255)
    cover.putalpha(mask)

    canvas.paste(cover, (0, 6), cover)

    draw = ImageDraw.Draw(canvas)
    # Subtle glass highlight border around artwork
    draw.rounded_rectangle(
        (0, 6, ART_W - 1, 6 + ART_H - 1),
        radius=RADIUS,
        outline=(255, 255, 255, 42),
        width=2,
    )

    # Bottom row of 5 palette swatches centered inside the square icon box
    dot_r = 10
    gap = 12
    total_w = 5 * (dot_r * 2) + 4 * gap
    start_x = (SIZE - total_w) // 2 + dot_r
    cy = 6 + ART_H + 30

    for i, hex_c in enumerate(swatches):
        cx = start_x + i * (dot_r * 2 + gap)
        draw.ellipse(
            (cx - dot_r - 2, cy - dot_r - 2, cx + dot_r + 2, cy + dot_r + 2),
            fill=(10, 12, 18, 175),
        )
        draw.ellipse(
            (cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r),
            fill=hex_rgba(hex_c),
            outline=(255, 255, 255, 90),
            width=1,
        )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_path.with_name(f".{out_path.name}.tmp")
    canvas.save(tmp, format="PNG")
    tmp.replace(out_path)


def main() -> int:
    home = Path(os.environ.get("HOME", Path.home()))
    presets_file = home / ".config/theme-manager/presets.json"
    if not presets_file.is_file():
        return 0

    store_env = os.environ.get("STORE_WP_DIR", "").strip()
    store_wp_dir = Path(store_env) if store_env else (home / "Spike-dotfiles/assets/wallpapers")
    if not store_wp_dir.is_dir():
        store_wp_dir = None

    cache_dir = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache")) / "theme-manager/thumbnails"
    cache_dir.mkdir(parents=True, exist_ok=True)

    presets_mtime = max(presets_file.stat().st_mtime, Path(__file__).stat().st_mtime)
    data = json.loads(presets_file.read_text(encoding="utf-8"))

    for preset in data.get("presets", []):
        pid = preset.get("id")
        if not pid:
            continue
        src = resolve_image(preset, store_wp_dir, home)
        if src is None:
            continue
        out = cache_dir / f"{pid}.png"
        need_build = not out.is_file()
        if not need_build:
            out_m = out.stat().st_mtime
            if out_m < presets_mtime or out_m < src.stat().st_mtime:
                need_build = True
        if need_build:
            centering = (0.90, 0.55) if pid == "tame-impala" else (0.5, 0.5)
            build_poster(src, extract_swatches(preset), out, centering=centering)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
