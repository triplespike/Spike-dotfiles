#!/usr/bin/env python3
"""
Parallelogram Ribbon Theme Switcher for Niri / Wayland.
Inspired by skwd-wall's skewed 16:9 hero carousel:
- Native Wayland layer-shell overlay (transparent backdrop + exclusive keyboard)
- 60fps Cairo animation: center preset smoothly expands to 16:9, neighbors compress to slices
- Infinite wrap-around ribbon so both sides stay balanced even at index 1 or N
- Dynamic system colors + preview theme accent border and skewed palette swatches
- Keyboard, scroll, click, live search typing, and type filtering (All / Video / Scenes)
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

# Prefer GL renderer on NVIDIA Wayland to avoid Vulkan swapchain issues in GTK4
if "GSK_RENDERER" not in os.environ and os.path.exists("/dev/nvidia0"):
    os.environ["GSK_RENDERER"] = "gl"

if "GDK_BACKEND" not in os.environ and os.environ.get("WAYLAND_DISPLAY"):
    os.environ["GDK_BACKEND"] = "wayland"

if "GI_TYPELIB_PATH" not in os.environ:
    current_user = os.environ.get("USER", "")
    fallback_paths = [
        f"/etc/profiles/per-user/{current_user}/lib/girepository-1.0" if current_user else "",
        "/run/current-system/sw/lib/girepository-1.0",
        os.path.expanduser("~/.local/state/nix/profiles/home-manager/home-path/lib/girepository-1.0"),
        "/usr/lib/girepository-1.0",
    ]
    existing = [p for p in fallback_paths if p and os.path.isdir(p)]
    if existing:
        os.environ["GI_TYPELIB_PATH"] = ":".join(existing)

import cairo
import gi
from PIL import Image, ImageOps

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo  # noqa: E402

try:
    gi.require_version("Gtk4LayerShell", "1.0")
    from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402
except Exception:
    LayerShell = None


PRESETS_FILE = Path.home() / ".config/theme-manager/presets.json"
STATE_FILE = Path.home() / ".local/state/theme-manager/current"
CACHE_ROOT = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "theme-manager"


def hex_rgb(val: str, fallback: str = "#678FE4") -> tuple[float, float, float]:
    raw = (val or fallback).strip().lstrip("#")
    if len(raw) < 6:
        raw = fallback.lstrip("#")
    try:
        return (
            int(raw[0:2], 16) / 255.0,
            int(raw[2:4], 16) / 255.0,
            int(raw[4:6], 16) / 255.0,
        )
    except ValueError:
        return hex_rgb(fallback, "#678FE4")


def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def smoothstep(t: float) -> float:
    t = clamp(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


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
        if c and isinstance(c, str) and len(swatches) < 6:
            norm = "#" + c.strip().lstrip("#")[:6].upper()
            if norm not in swatches:
                swatches.append(norm)
    while len(swatches) < 6:
        swatches.append(swatches[-1] if swatches else "#678FE4")
    return swatches[:6]


def resolve_system_colors(presets: list[dict], current_id: str) -> dict[str, str]:
    active = next((p for p in presets if p.get("id") == current_id), None)
    if active is None and presets:
        active = presets[0]
    if active is None:
        return {
            "bg": "#0D1017",
            "surface": "#161B26",
            "fg": "#EDF1F8",
            "fg_muted": "#92A0B8",
            "primary": "#678FE4",
            "accent": "#AB66CC",
        }
    gh = active.get("ghostty") or {}
    ring = (active.get("niri") or {}).get("focus_ring") or {}
    return {
        "bg": "#" + (gh.get("background") or "0D1017").lstrip("#")[:6],
        "surface": "#" + (gh.get("selection_background") or "1A2130").lstrip("#")[:6],
        "fg": "#" + (gh.get("foreground") or "EDF1F8").lstrip("#")[:6],
        "fg_muted": "#9CA8BD",
        "primary": ring.get("from") or "#678FE4",
        "accent": ring.get("to") or ring.get("from") or "#AB66CC",
    }


def resolve_source_image(preset: dict, store_wp_dir: Path | None) -> Path | None:
    wp = preset.get("wallpaper") or {}
    for key in ("fallback_image", "path"):
        raw = (wp.get(key) or "").strip()
        if not raw:
            continue
        p = Path(os.path.expanduser(raw))
        if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}:
            return p
        if store_wp_dir is not None:
            cand = store_wp_dir / p.name
            if cand.is_file() and cand.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}:
                return cand
    return None


def load_card_surface(preset: dict, store_wp_dir: Path | None) -> tuple[cairo.ImageSurface, bytearray] | None:
    pid = preset.get("id", "")
    card_path = CACHE_ROOT / "cards" / f"{pid}.jpg"
    src_path: Path | None = card_path if card_path.is_file() else None
    need_cache = False

    if src_path is None:
        src_path = resolve_source_image(preset, store_wp_dir)
        need_cache = src_path is not None
    if src_path is None:
        return None

    try:
        with Image.open(src_path) as im:
            if need_cache:
                centering = (0.90, 0.55) if pid == "tame-impala" else (0.5, 0.5)
                im = ImageOps.fit(im.convert("RGB"), (960, 540), method=Image.Resampling.LANCZOS, centering=centering)
                try:
                    card_path.parent.mkdir(parents=True, exist_ok=True)
                    tmp = card_path.with_name(f".{card_path.name}.tmp")
                    im.save(tmp, format="JPEG", quality=92)
                    tmp.replace(card_path)
                except OSError:
                    pass
            rgba = im.convert("RGBA")
            w, h = rgba.size
            bgra = bytearray(rgba.tobytes("raw", "BGRA"))
            stride = cairo.ImageSurface.format_stride_for_width(cairo.FORMAT_ARGB32, w)
            surf = cairo.ImageSurface.create_for_data(bgra, cairo.FORMAT_ARGB32, w, h, stride)
            return surf, bgra
    except Exception:
        return None


def rounded_rect_path(ctx: cairo.Context, x: float, y: float, w: float, h: float, r: float) -> None:
    r = min(r, w / 2.0, h / 2.0)
    ctx.new_sub_path()
    ctx.arc(x + w - r, y + r, r, -math.pi / 2.0, 0.0)
    ctx.arc(x + w - r, y + h - r, r, 0.0, math.pi / 2.0)
    ctx.arc(x + r, y + h - r, r, math.pi / 2.0, math.pi)
    ctx.arc(x + r, y + r, r, math.pi, 3.0 * math.pi / 2.0)
    ctx.close_path()


def parallelogram_path(ctx: cairo.Context, x: float, y: float, w: float, h: float, skew: float) -> None:
    ctx.new_path()
    ctx.move_to(x + skew, y)
    ctx.line_to(x + skew + w, y)
    ctx.line_to(x + w, y + h)
    ctx.line_to(x, y + h)
    ctx.close_path()


def draw_pango_text(
    ctx: cairo.Context,
    text: str,
    x: float,
    y: float,
    font_desc: str,
    color_rgba: tuple[float, float, float, float],
    align: str = "left",
    max_width: int = -1,
) -> tuple[float, float]:
    layout = PangoCairo.create_layout(ctx)
    layout.set_font_description(Pango.FontDescription.from_string(font_desc))
    layout.set_text(text, -1)
    if max_width > 0:
        layout.set_width(max_width * Pango.SCALE)
        layout.set_ellipsize(Pango.EllipsizeMode.END)
    w, h = layout.get_pixel_size()
    draw_x = x
    if align == "center":
        draw_x = x - w / 2.0
    elif align == "right":
        draw_x = x - w
    ctx.save()
    ctx.set_source_rgba(*color_rgba)
    ctx.move_to(draw_x, y)
    PangoCairo.show_layout(ctx, layout)
    ctx.restore()
    return float(w), float(h)


def measure_pango_text(ctx: cairo.Context, text: str, font_desc: str) -> tuple[float, float]:
    layout = PangoCairo.create_layout(ctx)
    layout.set_font_description(Pango.FontDescription.from_string(font_desc))
    layout.set_text(text, -1)
    w, h = layout.get_pixel_size()
    return float(w), float(h)


def draw_filter_icon(ctx: cairo.Context, kind: str, cx: float, cy: float, size: float, rgba: tuple[float, float, float, float]) -> None:
    ctx.save()
    ctx.set_source_rgba(*rgba)
    ctx.set_line_width(1.6)
    s = size * 0.5
    if kind == "all":
        box = s * 0.78
        gap = s * 0.22
        for dx in (-gap - box, gap):
            for dy in (-gap - box, gap):
                rounded_rect_path(ctx, cx + dx, cy + dy, box, box, 1.5)
                ctx.fill()
    elif kind == "video":
        rounded_rect_path(ctx, cx - s, cy - s * 0.78, s * 2.0, s * 1.56, 3.0)
        ctx.stroke()
        ctx.move_to(cx - s * 0.28, cy - s * 0.42)
        ctx.line_to(cx + s * 0.45, cy)
        ctx.line_to(cx - s * 0.28, cy + s * 0.42)
        ctx.close_path()
        ctx.fill()
    else:  # scene / we
        ctx.move_to(cx, cy - s)
        ctx.line_to(cx + s * 0.9, cy)
        ctx.line_to(cx, cy + s)
        ctx.line_to(cx - s * 0.9, cy)
        ctx.close_path()
        ctx.stroke()
        ctx.arc(cx, cy, s * 0.28, 0.0, 2.0 * math.pi)
        ctx.fill()
    ctx.restore()


class ParallelogramCanvas:
    """State, infinite carousel geometry, animation, and Cairo renderer."""

    FILTERS = [
        ("all", "Все"),
        ("video", "Видео"),
        ("scene", "Сцены"),
    ]

    def __init__(self, presets: list[dict], current_id: str, store_wp_dir: Path | None) -> None:
        self.all_presets = presets
        self.current_id = current_id
        self.store_wp_dir = store_wp_dir
        self.sys_colors = resolve_system_colors(presets, current_id)

        self.filter_mode = "all"
        self.search_query = ""
        self.filtered: list[dict] = list(presets)

        start_idx = next((i for i, p in enumerate(self.filtered) if p.get("id") == current_id), 0)
        self.target_slot = start_idx
        self.anim_pos = float(start_idx)
        self.anim_alpha = 0.0
        self.last_tick_us: int | None = None

        self.surfaces: dict[str, cairo.ImageSurface] = {}
        self._buffers: list[bytearray] = []
        for p in presets:
            pid = p.get("id")
            if not pid:
                continue
            loaded = load_card_surface(p, store_wp_dir)
            if loaded is not None:
                surf, buf = loaded
                self.surfaces[pid] = surf
                self._buffers.append(buf)

        # (preset_idx, x, y, w, h, skew) in draw order
        self.card_hit_polys: list[tuple[int, int, float, float, float, float, float]] = []
        self.filter_hit_rects: list[tuple[str, float, float, float, float]] = []
        self.capsule_rect: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)
        self.hover_filter: str | None = None

    @property
    def selected_idx(self) -> int:
        n = len(self.filtered)
        return (self.target_slot % n) if n > 0 else 0

    def apply_filter(self, keep_id: str | None = None) -> None:
        q = self.search_query.strip().lower()
        result: list[dict] = []
        for p in self.all_presets:
            wtype = (p.get("wallpaper") or {}).get("type", "image").lower()
            if self.filter_mode == "video" and wtype != "video":
                continue
            if self.filter_mode == "scene" and wtype == "video":
                continue
            if q:
                hay = f"{p.get('id', '')} {p.get('name', '')}".lower()
                if q not in hay:
                    continue
            result.append(p)

        self.filtered = result
        if not result:
            self.target_slot = 0
            self.anim_pos = 0.0
            return

        target = keep_id or self.current_id
        new_idx = next((i for i, p in enumerate(result) if p.get("id") == target), 0)
        self.target_slot = new_idx
        self.anim_pos = float(new_idx)

    def move_selection(self, delta: int) -> None:
        if not self.filtered:
            return
        self.target_slot += delta

    def step_animation(self, dt: float) -> bool:
        dt = clamp(dt, 0.001, 0.05)
        moving = False

        if self.anim_alpha < 0.999:
            self.anim_alpha = min(1.0, self.anim_alpha + dt * 7.5)
            moving = True

        diff = float(self.target_slot) - self.anim_pos
        if abs(diff) > 0.002:
            factor = 1.0 - math.exp(-dt * 15.0)
            self.anim_pos += diff * factor
            moving = True
        else:
            self.anim_pos = float(self.target_slot)
        return moving

    def draw(self, ctx: cairo.Context, width: int, height: int) -> None:
        self.card_hit_polys.clear()
        self.filter_hit_rects.clear()

        fade = smoothstep(self.anim_alpha)
        bg_r, bg_g, bg_b = hex_rgb(self.sys_colors["bg"])
        surf_r, surf_g, surf_b = hex_rgb(self.sys_colors["surface"])
        fg_r, fg_g, fg_b = hex_rgb(self.sys_colors["fg"])
        muted_r, muted_g, muted_b = hex_rgb(self.sys_colors["fg_muted"])
        pri_r, pri_g, pri_b = hex_rgb(self.sys_colors["primary"])
        acc_r, acc_g, acc_b = hex_rgb(self.sys_colors["accent"])

        # Subtle vignette so cards pop over bright or busy wallpapers while edges stay visible
        ctx.save()
        vignette = cairo.RadialGradient(
            width * 0.5, height * 0.5, min(width, height) * 0.12,
            width * 0.5, height * 0.5, max(width, height) * 0.72,
        )
        vignette.add_color_stop_rgba(0.0, bg_r * 0.45, bg_g * 0.45, bg_b * 0.45, 0.46 * fade)
        vignette.add_color_stop_rgba(1.0, 0.02, 0.03, 0.05, 0.62 * fade)
        ctx.set_source(vignette)
        ctx.paint()
        ctx.restore()

        card_h = clamp(height * 0.40, 300.0, 460.0)
        hero_w = min(card_h * (16.0 / 9.0), width * 0.54)
        slice_w = clamp(card_h * 0.145, 48.0, 68.0)
        skew = round(card_h * 0.068)
        gap = 10.0

        ribbon_y = (height - card_h) * 0.52

        n = len(self.filtered)
        active_preset = self.filtered[self.selected_idx] if n > 0 else None

        # 1. Compact floating capsule bar above ribbon
        self._draw_top_capsule(
            ctx, width, ribbon_y, active_preset, fade,
            (bg_r, bg_g, bg_b), (surf_r, surf_g, surf_b),
            (fg_r, fg_g, fg_b), (muted_r, muted_g, muted_b),
            (pri_r, pri_g, pri_b),
        )

        # 2. Empty state when search/filter matches nothing
        if n == 0:
            msg = f"Нет тем по запросу «{self.search_query}»" if self.search_query else "В этом фильтре нет тем"
            draw_pango_text(
                ctx, msg, width * 0.5, ribbon_y + card_h * 0.46,
                "Sans SemiBold 14", (fg_r, fg_g, fg_b, 0.85 * fade), align="center",
            )
            return

        # 3. Infinite cyclic ribbon (or single card if n == 1):
        # 5 balanced slices per side in rest state, plus 6th fading in/out smoothly during motion
        anchor_slot = int(round(self.anim_pos))
        slots = [0] if n == 1 else list(range(anchor_slot - 6, anchor_slot + 7))

        widths: list[float] = []
        weights: list[float] = []
        edge_fades: list[float] = []
        for s in slots:
            dist = abs(float(s) - self.anim_pos)
            w_focus = smoothstep(1.0 - min(1.0, dist))
            weights.append(w_focus)
            widths.append(slice_w + (hero_w - slice_w) * w_focus)
            ef = 1.0 if n == 1 else clamp(1.0 - max(0.0, dist - 4.9) / 0.85, 0.0, 1.0)
            edge_fades.append(ef)

        lefts: list[float] = []
        cursor = 0.0
        for w in widths:
            lefts.append(cursor)
            cursor += w + gap

        if n == 1:
            focal_center = lefts[0] + widths[0] * 0.5
        else:
            lo_s = int(math.floor(self.anim_pos))
            hi_s = lo_s + 1
            lo_idx = slots.index(lo_s)
            hi_idx = slots.index(hi_s)
            frac = self.anim_pos - lo_s
            center_lo = lefts[lo_idx] + widths[lo_idx] * 0.5
            center_hi = lefts[hi_idx] + widths[hi_idx] * 0.5
            focal_center = center_lo + (center_hi - center_lo) * frac

        x_shift = (width * 0.5) - focal_center - skew * 0.5

        # Draw side slices first, hero card last so glow/border draws on top
        draw_order = sorted(range(len(slots)), key=lambda i: weights[i])
        for i in draw_order:
            if edge_fades[i] <= 0.01:
                continue
            s = slots[i]
            x = lefts[i] + x_shift
            w = widths[i]
            if x + w + skew < -40 or x > width + 40:
                continue
            preset_idx = s % n
            self._draw_card(
                ctx, s, preset_idx, self.filtered[preset_idx],
                x, ribbon_y, w, card_h, hero_w, skew,
                weights[i], fade * edge_fades[i], (bg_r, bg_g, bg_b), (fg_r, fg_g, fg_b),
            )

        # 4. Crisp bottom helper pill under ribbon
        hint = "← → или колесо: листать   •   Enter: применить   •   Печать: поиск   •   Esc: закрыть"
        hw, hh = measure_pango_text(ctx, hint, "Sans 9.5")
        hy = ribbon_y + card_h + 18.0
        ctx.save()
        rounded_rect_path(ctx, width * 0.5 - hw * 0.5 - 14.0, hy - 4.0, hw + 28.0, hh + 8.0, (hh + 8.0) * 0.5)
        ctx.set_source_rgba(bg_r * 0.7, bg_g * 0.7, bg_b * 0.7, 0.65 * fade)
        ctx.fill()
        ctx.restore()
        draw_pango_text(
            ctx, hint, width * 0.5, hy,
            "Sans 9.5", (muted_r, muted_g, muted_b, 0.88 * fade), align="center",
        )

    def _draw_top_capsule(
        self,
        ctx: cairo.Context,
        screen_w: int,
        ribbon_y: float,
        active_preset: dict | None,
        fade: float,
        bg_rgb: tuple[float, float, float],
        surf_rgb: tuple[float, float, float],
        fg_rgb: tuple[float, float, float],
        muted_rgb: tuple[float, float, float],
        pri_rgb: tuple[float, float, float],
    ) -> None:
        cap_h = 40.0
        pad_x = 12.0
        btn_h = 28.0
        btn_w = 28.0
        btn_gap = 6.0

        swatches = extract_swatches(active_preset) if active_preset else ["#678FE4"] * 6
        swatch_w = 15.0
        swatch_h = 15.0
        swatch_skew = 5.0
        swatch_gap = 5.0
        swatches_total_w = len(swatches) * swatch_w + (len(swatches) - 1) * swatch_gap + swatch_skew

        if self.search_query:
            right_txt = f"⌕ {self.search_query}"
        elif self.filtered:
            right_txt = f"{self.selected_idx + 1}/{len(self.filtered)}"
        else:
            right_txt = "0/0"
        right_w, right_h = measure_pango_text(ctx, right_txt, "JetBrains Mono SemiBold 10")
        right_box_w = max(46.0, right_w + 16.0)

        filters_w = len(self.FILTERS) * btn_w + (len(self.FILTERS) - 1) * btn_gap
        cap_w = pad_x + filters_w + 14.0 + 1.0 + 14.0 + swatches_total_w + 14.0 + 1.0 + 12.0 + right_box_w + pad_x
        cap_x = (screen_w - cap_w) * 0.5
        cap_y = ribbon_y - cap_h - 18.0

        self.capsule_rect = (cap_x, cap_y, cap_w, cap_h)

        # Capsule body
        ctx.save()
        rounded_rect_path(ctx, cap_x, cap_y, cap_w, cap_h, cap_h * 0.5)
        ctx.set_source_rgba(bg_rgb[0] * 0.85, bg_rgb[1] * 0.85, bg_rgb[2] * 0.85, 0.90 * fade)
        ctx.fill_preserve()
        ctx.set_line_width(1.2)
        ctx.set_source_rgba(pri_rgb[0], pri_rgb[1], pri_rgb[2], 0.45 * fade)
        ctx.stroke()
        ctx.restore()

        # Filter icon buttons
        cur_x = cap_x + pad_x
        btn_y = cap_y + (cap_h - btn_h) * 0.5
        for key, _label in self.FILTERS:
            is_active = self.filter_mode == key
            is_hover = self.hover_filter == key
            self.filter_hit_rects.append((key, cur_x, btn_y, btn_w, btn_h))

            ctx.save()
            rounded_rect_path(ctx, cur_x, btn_y, btn_w, btn_h, btn_h * 0.5)
            if is_active:
                ctx.set_source_rgba(pri_rgb[0], pri_rgb[1], pri_rgb[2], 0.92 * fade)
                ctx.fill()
                icon_col = (bg_rgb[0], bg_rgb[1], bg_rgb[2], 0.98 * fade)
            elif is_hover:
                ctx.set_source_rgba(surf_rgb[0], surf_rgb[1], surf_rgb[2], 0.85 * fade)
                ctx.fill()
                icon_col = (*fg_rgb, 0.95 * fade)
            else:
                ctx.set_source_rgba(surf_rgb[0], surf_rgb[1], surf_rgb[2], 0.45 * fade)
                ctx.fill()
                icon_col = (*muted_rgb, 0.90 * fade)
            ctx.restore()

            draw_filter_icon(ctx, key, cur_x + btn_w * 0.5, btn_y + btn_h * 0.5, 13.0, icon_col)
            cur_x += btn_w + btn_gap

        # Divider 1
        div1_x = cur_x - btn_gap + 12.0
        ctx.save()
        ctx.set_source_rgba(*muted_rgb, 0.25 * fade)
        ctx.set_line_width(1.0)
        ctx.move_to(div1_x, cap_y + 10.0)
        ctx.line_to(div1_x, cap_y + cap_h - 10.0)
        ctx.stroke()
        ctx.restore()

        # Skewed theme color swatches (parallelograms)
        sx = div1_x + 14.0
        sy = cap_y + (cap_h - swatch_h) * 0.5
        for hex_c in swatches:
            sr, sg, sb = hex_rgb(hex_c)
            ctx.save()
            parallelogram_path(ctx, sx, sy, swatch_w, swatch_h, swatch_skew)
            ctx.set_source_rgba(sr, sg, sb, 0.96 * fade)
            ctx.fill_preserve()
            ctx.set_line_width(0.9)
            ctx.set_source_rgba(1.0, 1.0, 1.0, 0.28 * fade)
            ctx.stroke()
            ctx.restore()
            sx += swatch_w + swatch_gap

        # Divider 2
        div2_x = sx - swatch_gap + swatch_skew + 12.0
        ctx.save()
        ctx.set_source_rgba(*muted_rgb, 0.25 * fade)
        ctx.set_line_width(1.0)
        ctx.move_to(div2_x, cap_y + 10.0)
        ctx.line_to(div2_x, cap_y + cap_h - 10.0)
        ctx.stroke()
        ctx.restore()

        # Counter / Search query text
        txt_col = (*pri_rgb, 0.98 * fade) if self.search_query else (*fg_rgb, 0.88 * fade)
        draw_pango_text(
            ctx,
            right_txt,
            cap_x + cap_w - pad_x - 4.0,
            cap_y + (cap_h - right_h) * 0.5,
            "JetBrains Mono SemiBold 10",
            txt_col,
            align="right",
        )

    def _draw_card(
        self,
        ctx: cairo.Context,
        slot: int,
        preset_idx: int,
        preset: dict,
        x: float,
        y: float,
        w: float,
        h: float,
        hero_w: float,
        skew: float,
        w_focus: float,
        fade: float,
        bg_rgb: tuple[float, float, float],
        fg_rgb: tuple[float, float, float],
    ) -> None:
        self.card_hit_polys.append((slot, preset_idx, x, y, w, h, skew))

        pid = preset.get("id", "")
        name = preset.get("name", pid)
        wtype = (preset.get("wallpaper") or {}).get("type", "image").lower()
        is_current = pid == self.current_id

        ring = ((preset.get("niri") or {}).get("focus_ring") or {})
        c_from = hex_rgb(ring.get("from") or self.sys_colors["primary"])
        c_to = hex_rgb(ring.get("to") or ring.get("from") or self.sys_colors["accent"])

        # Hero outer glow
        if w_focus > 0.25:
            ctx.save()
            parallelogram_path(ctx, x - 2.0, y - 2.0, w + 4.0, h + 4.0, skew)
            ctx.set_line_width(6.0)
            ctx.set_source_rgba(c_from[0], c_from[1], c_from[2], 0.24 * w_focus * fade)
            ctx.stroke()
            ctx.restore()

        # Clip to parallelogram & draw wallpaper centered relative to the card's middle
        ctx.save()
        parallelogram_path(ctx, x, y, w, h, skew)
        ctx.clip()

        surf = self.surfaces.get(pid)
        if surf is not None:
            iw = surf.get_width()
            ih = surf.get_height()
            span_w = hero_w + skew
            scale = max(span_w / iw, h / ih)
            draw_w = iw * scale
            draw_h = ih * scale
            card_cx = x + (w + skew) * 0.5
            card_cy = y + h * 0.5
            ctx.save()
            ctx.translate(card_cx - draw_w * 0.5, card_cy - draw_h * 0.5)
            ctx.scale(scale, scale)
            ctx.set_source_surface(surf, 0, 0)
            ctx.get_source().set_filter(cairo.FILTER_BILINEAR)
            ctx.paint_with_alpha(fade)
            ctx.restore()
        else:
            grad = cairo.LinearGradient(x, y, x + w + skew, y + h)
            grad.add_color_stop_rgba(0.0, c_from[0] * 0.35, c_from[1] * 0.35, c_from[2] * 0.35, fade)
            grad.add_color_stop_rgba(1.0, bg_rgb[0], bg_rgb[1], bg_rgb[2], fade)
            ctx.set_source(grad)
            ctx.paint()

        # Dim non-focused slices so the expanded 16:9 card stands out clearly
        if w_focus < 0.95:
            dim_alpha = (1.0 - w_focus) * 0.34 * fade
            ctx.set_source_rgba(0.03, 0.04, 0.07, dim_alpha)
            ctx.paint()

        # Subtle top-right circular play/type glyph on collapsed slices
        if w_focus < 0.45 and w >= 38.0:
            bx = x + skew + w - 16.0
            by = y + 16.0
            ctx.save()
            ctx.arc(bx, by, 8.5, 0.0, 2.0 * math.pi)
            ctx.set_source_rgba(0.05, 0.07, 0.11, 0.72 * (1.0 - w_focus) * fade)
            ctx.fill()
            ctx.set_line_width(1.0)
            ctx.set_source_rgba(1.0, 1.0, 1.0, 0.40 * (1.0 - w_focus) * fade)
            ctx.arc(bx, by, 8.5, 0.0, 2.0 * math.pi)
            ctx.stroke()
            ctx.set_source_rgba(1.0, 1.0, 1.0, 0.85 * (1.0 - w_focus) * fade)
            if wtype == "video":
                ctx.move_to(bx - 2.3, by - 3.4)
                ctx.line_to(bx + 3.6, by)
                ctx.line_to(bx - 2.3, by + 3.4)
                ctx.close_path()
                ctx.fill()
            else:
                ctx.arc(bx, by, 2.5, 0.0, 2.0 * math.pi)
                ctx.fill()
            ctx.restore()

        # Bottom mini type tag (VID / WE)
        tag = "VID" if wtype == "video" else "WE"
        if is_current and w_focus < 0.55:
            tag = "✦"
        tag_alpha = fade * (0.90 if w_focus > 0.6 else 0.78)
        tag_w, tag_h = measure_pango_text(ctx, tag, "JetBrains Mono Bold 7.5")
        tx = x + w - tag_w - 14.0
        ty = y + h - tag_h - 10.0
        ctx.save()
        rounded_rect_path(ctx, tx - 4.5, ty - 2.0, tag_w + 9.0, tag_h + 4.0, 4.0)
        ctx.set_source_rgba(0.04, 0.05, 0.08, 0.86 * tag_alpha)
        ctx.fill_preserve()
        ctx.set_line_width(0.8)
        ctx.set_source_rgba(1.0, 1.0, 1.0, 0.18 * tag_alpha)
        ctx.stroke()
        ctx.restore()
        draw_pango_text(
            ctx, tag, tx, ty, "JetBrains Mono Bold 7.5",
            (c_from[0], c_from[1], c_from[2], tag_alpha) if is_current else (0.90, 0.93, 0.98, tag_alpha),
        )

        # Hero center title pill at bottom
        if w_focus > 0.55:
            pill_alpha = clamp((w_focus - 0.55) / 0.45, 0.0, 1.0) * fade
            label_text = f"✦  {name}" if is_current else name
            tw, th = measure_pango_text(ctx, label_text, "Sans Bold 10.5")
            pill_w = min(w - 60.0, tw + 28.0)
            pill_h = th + 12.0
            pill_x = x + w * 0.5 - pill_w * 0.5
            pill_y = y + h - pill_h - 14.0

            ctx.save()
            rounded_rect_path(ctx, pill_x, pill_y, pill_w, pill_h, pill_h * 0.5)
            ctx.set_source_rgba(0.05, 0.06, 0.10, 0.86 * pill_alpha)
            ctx.fill_preserve()
            ctx.set_line_width(1.1)
            ctx.set_source_rgba(c_from[0], c_from[1], c_from[2], 0.72 * pill_alpha)
            ctx.stroke()
            ctx.restore()

            draw_pango_text(
                ctx, label_text, pill_x + pill_w * 0.5, pill_y + (pill_h - th) * 0.5,
                "Sans Bold 10.5", (*fg_rgb, 0.98 * pill_alpha),
                align="center", max_width=int(pill_w - 16),
            )

        ctx.restore()  # remove parallelogram clip

        # Crisp card border
        ctx.save()
        parallelogram_path(ctx, x, y, w, h, skew)
        if w_focus > 0.45:
            border_grad = cairo.LinearGradient(x, y, x + w + skew, y + h)
            border_grad.add_color_stop_rgba(0.0, c_from[0], c_from[1], c_from[2], 0.96 * w_focus * fade)
            border_grad.add_color_stop_rgba(1.0, c_to[0], c_to[1], c_to[2], 0.96 * w_focus * fade)
            ctx.set_source(border_grad)
            ctx.set_line_width(1.2 + 1.2 * w_focus)
        else:
            if is_current:
                ctx.set_source_rgba(c_from[0], c_from[1], c_from[2], 0.72 * fade)
                ctx.set_line_width(1.4)
            else:
                ctx.set_source_rgba(1.0, 1.0, 1.0, 0.18 * fade)
                ctx.set_line_width(1.0)
        ctx.stroke()
        ctx.restore()

    def hit_test_filter(self, px: float, py: float) -> str | None:
        for key, rx, ry, rw, rh in self.filter_hit_rects:
            if rx <= px <= rx + rw and ry <= py <= ry + rh:
                return key
        return None

    def point_in_capsule(self, px: float, py: float) -> bool:
        cx, cy, cw, ch = self.capsule_rect
        return cx <= px <= cx + cw and cy <= py <= cy + ch

    def hit_test_card(self, px: float, py: float) -> int | None:
        # Iterate reversed draw order so the expanded hero card catches overlaps first
        for slot, _preset_idx, x, y, w, h, skew in reversed(self.card_hit_polys):
            if py < y or py > y + h:
                continue
            t = (y + h - py) / h  # 0 at bottom, 1 at top
            left_edge = x + skew * t
            right_edge = left_edge + w
            if left_edge <= px <= right_edge:
                return slot
        return None


def load_data() -> tuple[list[dict], str, Path | None]:
    presets: list[dict] = []
    if PRESETS_FILE.is_file():
        try:
            presets = json.loads(PRESETS_FILE.read_text(encoding="utf-8")).get("presets", [])
        except Exception:
            presets = []
    current_id = ""
    if STATE_FILE.is_file():
        current_id = STATE_FILE.read_text(encoding="utf-8").strip()
    store_env = os.environ.get("STORE_WP_DIR", "").strip()
    store_wp_dir = Path(store_env) if store_env else (Path.home() / "Spike-dotfiles/assets/wallpapers")
    if not store_wp_dir.is_dir():
        store_wp_dir = None
    return presets, current_id, store_wp_dir


def apply_theme(preset_id: str) -> None:
    if not preset_id:
        return
    clean_env = {k: v for k, v in os.environ.items() if k != "LD_PRELOAD"}
    subprocess.Popen(
        ["theme-apply", preset_id],
        env=clean_env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


class ParallelogramWindow(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application, canvas: ParallelogramCanvas) -> None:
        super().__init__(application=app, title="Theme Parallelogram Switcher")
        self.canvas = canvas

        self.set_decorated(False)
        self.add_css_class("parallelogram-overlay")

        if LayerShell is not None and LayerShell.is_supported():
            LayerShell.init_for_window(self)
            LayerShell.set_namespace(self, "theme-parallelogram")
            LayerShell.set_layer(self, LayerShell.Layer.OVERLAY)
            LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.EXCLUSIVE)
            for edge in (
                LayerShell.Edge.TOP,
                LayerShell.Edge.BOTTOM,
                LayerShell.Edge.LEFT,
                LayerShell.Edge.RIGHT,
            ):
                LayerShell.set_anchor(self, edge, True)
            LayerShell.set_exclusive_zone(self, -1)
        else:
            self.set_default_size(1440, 720)

        self.area = Gtk.DrawingArea()
        self.area.set_hexpand(True)
        self.area.set_vexpand(True)
        self.area.set_focusable(True)
        self.area.set_draw_func(self._on_draw)
        self.set_child(self.area)

        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        key_ctrl.connect("key-pressed", self._on_key_pressed)
        self.add_controller(key_ctrl)

        scroll_ctrl = Gtk.EventControllerScroll.new(
            Gtk.EventControllerScrollFlags.BOTH_AXES | Gtk.EventControllerScrollFlags.DISCRETE
        )
        scroll_ctrl.connect("scroll", self._on_scroll)
        self.area.add_controller(scroll_ctrl)

        motion_ctrl = Gtk.EventControllerMotion()
        motion_ctrl.connect("motion", self._on_motion)
        self.area.add_controller(motion_ctrl)

        click_ctrl = Gtk.GestureClick.new()
        click_ctrl.connect("pressed", self._on_click)
        self.area.add_controller(click_ctrl)

        self.area.add_tick_callback(self._on_tick)

    def _on_tick(self, widget: Gtk.Widget, frame_clock: Gdk.FrameClock) -> bool:
        now_us = frame_clock.get_frame_time()
        dt = 0.016 if self.canvas.last_tick_us is None else (now_us - self.canvas.last_tick_us) / 1_000_000.0
        self.canvas.last_tick_us = now_us
        if self.canvas.step_animation(dt):
            widget.queue_draw()
        return GLib.SOURCE_CONTINUE

    def _on_draw(self, _area: Gtk.DrawingArea, ctx: cairo.Context, width: int, height: int) -> None:
        self.canvas.draw(ctx, width, height)

    def _commit_selected(self) -> None:
        if 0 <= self.canvas.selected_idx < len(self.canvas.filtered):
            pid = self.canvas.filtered[self.canvas.selected_idx].get("id", "")
            self.close()
            apply_theme(pid)

    def _on_key_pressed(
        self, _ctrl: Gtk.EventControllerKey, keyval: int, _keycode: int, state: Gdk.ModifierType
    ) -> bool:
        if keyval == Gdk.KEY_Escape:
            if self.canvas.search_query:
                self.canvas.search_query = ""
                self.canvas.apply_filter()
                self.area.queue_draw()
                return True
            self.close()
            return True

        if keyval in (Gdk.KEY_Left, Gdk.KEY_Up):
            self.canvas.move_selection(-1)
            self.area.queue_draw()
            return True

        if keyval in (Gdk.KEY_Right, Gdk.KEY_Down):
            self.canvas.move_selection(1)
            self.area.queue_draw()
            return True

        if keyval == Gdk.KEY_Tab:
            keys = [k for k, _ in self.canvas.FILTERS]
            cur_i = keys.index(self.canvas.filter_mode)
            cur_id = (
                self.canvas.filtered[self.canvas.selected_idx].get("id")
                if self.canvas.filtered
                else None
            )
            self.canvas.filter_mode = keys[(cur_i + 1) % len(keys)]
            self.canvas.apply_filter(keep_id=cur_id)
            self.area.queue_draw()
            return True

        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self._commit_selected()
            return True

        if keyval == Gdk.KEY_Home and self.canvas.filtered:
            self.canvas.target_slot = 0
            self.area.queue_draw()
            return True

        if keyval == Gdk.KEY_End and self.canvas.filtered:
            self.canvas.target_slot = len(self.canvas.filtered) - 1
            self.area.queue_draw()
            return True

        if keyval == Gdk.KEY_BackSpace:
            if self.canvas.search_query:
                self.canvas.search_query = self.canvas.search_query[:-1]
                self.canvas.apply_filter()
                self.area.queue_draw()
            return True

        if not self.canvas.search_query and not (state & Gdk.ModifierType.CONTROL_MASK):
            if keyval in (Gdk.KEY_h, Gdk.KEY_H):
                self.canvas.move_selection(-1)
                self.area.queue_draw()
                return True
            if keyval in (Gdk.KEY_l, Gdk.KEY_L):
                self.canvas.move_selection(1)
                self.area.queue_draw()
                return True

        uni = Gdk.keyval_to_unicode(keyval)
        if uni and uni >= 32 and not (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)):
            ch = chr(uni)
            if ch.isalnum() or ch in (" ", "-", "_"):
                self.canvas.search_query += ch
                self.canvas.apply_filter()
                self.area.queue_draw()
                return True

        return False

    def _on_scroll(self, _ctrl: Gtk.EventControllerScroll, dx: float, dy: float) -> bool:
        delta = dy if abs(dy) >= abs(dx) else dx
        if delta > 0:
            self.canvas.move_selection(1)
            self.area.queue_draw()
        elif delta < 0:
            self.canvas.move_selection(-1)
            self.area.queue_draw()
        return True

    def _on_motion(self, _ctrl: Gtk.EventControllerMotion, x: float, y: float) -> None:
        hovered = self.canvas.hit_test_filter(x, y)
        if hovered != self.canvas.hover_filter:
            self.canvas.hover_filter = hovered
            self.area.queue_draw()

    def _on_click(self, _gesture: Gtk.GestureClick, _n_press: int, x: float, y: float) -> None:
        fkey = self.canvas.hit_test_filter(x, y)
        if fkey is not None:
            cur_id = (
                self.canvas.filtered[self.canvas.selected_idx].get("id")
                if self.canvas.filtered
                else None
            )
            self.canvas.filter_mode = fkey
            self.canvas.apply_filter(keep_id=cur_id)
            self.area.queue_draw()
            return

        if self.canvas.point_in_capsule(x, y):
            return

        hit_slot = self.canvas.hit_test_card(x, y)
        if hit_slot is not None:
            if hit_slot == self.canvas.target_slot:
                self._commit_selected()
            else:
                self.canvas.target_slot = hit_slot
                self.area.queue_draw()
            return

        self.close()


def render_preview_png(out_path: str, width: int = 1920, height: int = 1080) -> int:
    """Render an offscreen PNG snapshot of the parallelogram overlay for verification."""
    presets, current_id, store_wp_dir = load_data()
    if not presets:
        print("No presets found", file=sys.stderr)
        return 1
    canvas = ParallelogramCanvas(presets, current_id, store_wp_dir)
    canvas.anim_alpha = 1.0
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    ctx = cairo.Context(surface)
    active_surf = canvas.surfaces.get(current_id)
    if active_surf is not None:
        iw, ih = active_surf.get_width(), active_surf.get_height()
        sc = max(width / iw, height / ih)
        ctx.save()
        ctx.translate((width - iw * sc) * 0.5, (height - ih * sc) * 0.5)
        ctx.scale(sc, sc)
        ctx.set_source_surface(active_surf, 0, 0)
        ctx.paint()
        ctx.restore()
    else:
        ctx.set_source_rgb(0.06, 0.08, 0.12)
        ctx.paint()
    canvas.draw(ctx, width, height)
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    surface.write_to_png(out_path)
    return 0


def main() -> int:
    if len(sys.argv) >= 3 and sys.argv[1] == "--render-preview":
        w = int(sys.argv[3]) if len(sys.argv) > 3 else 1920
        h = int(sys.argv[4]) if len(sys.argv) > 4 else 1080
        return render_preview_png(sys.argv[2], w, h)

    presets, current_id, store_wp_dir = load_data()
    if not presets:
        print(f"Файл пресетов не найден или пуст: {PRESETS_FILE}", file=sys.stderr)
        return 1

    canvas = ParallelogramCanvas(presets, current_id, store_wp_dir)

    css_provider = Gtk.CssProvider()
    css_provider.load_from_data(b"""
        window.parallelogram-overlay {
            background-color: transparent;
            box-shadow: none;
        }
    """)
    display = Gdk.Display.get_default()
    if display is not None:
        Gtk.StyleContext.add_provider_for_display(
            display, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    app = Gtk.Application(application_id="dev.spike.ThemeParallelogram")

    def on_activate(gtk_app: Gtk.Application) -> None:
        win = ParallelogramWindow(gtk_app, canvas)
        win.present()

    app.connect("activate", on_activate)
    return app.run(None)


if __name__ == "__main__":
    raise SystemExit(main())
