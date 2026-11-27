#!/usr/bin/env python3
"""
GPU-accelerated Parallelogram Ribbon Theme Switcher for Niri / Wayland.
Inspired by skwd-wall's skewed 16:9 hero carousel:
- Native Wayland layer-shell overlay (transparent backdrop + exclusive keyboard)
- 100% GPU-rendered GTK4 GSK Scene Graph (Gtk.Widget.do_snapshot + Gsk.Transform + Gdk.Texture)
- Exact critically-damped spring physics synced to monitor refresh rate (60–240 Hz)
- Cached micro-textures for HUD elements (0 Cairo/Pango work during ribbon motion)
- Dynamic system colors + preview theme accent border/glow & skewed palette swatches
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
import time
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
gi.require_version("Gsk", "4.0")
gi.require_version("Graphene", "1.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GLib, Graphene, Gsk, Gtk, Pango, PangoCairo  # noqa: E402

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


def make_rgba(r: float, g: float, b: float, a: float = 1.0) -> Gdk.RGBA:
    c = Gdk.RGBA()
    c.red = r
    c.green = g
    c.blue = b
    c.alpha = a
    return c


def make_rect(x: float, y: float, w: float, h: float) -> Graphene.Rect:
    r = Graphene.Rect()
    r.init(float(x), float(y), float(w), float(h))
    return r


def make_point(x: float, y: float) -> Graphene.Point:
    p = Graphene.Point()
    p.init(float(x), float(y))
    return p


def make_stop(offset: float, rgba: Gdk.RGBA) -> Gsk.ColorStop:
    s = Gsk.ColorStop()
    s.offset = float(offset)
    s.color = rgba
    return s


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
            "fg_muted": "#9CA8BD",
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


def load_gpu_card_texture(preset: dict, store_wp_dir: Path | None) -> Gdk.Texture | None:
    """Load 960x540 cached JPEG straight into a GPU Gdk.Texture (fast path)."""
    pid = preset.get("id", "")
    card_path = CACHE_ROOT / "cards" / f"{pid}.jpg"

    if not card_path.is_file():
        src_path = resolve_source_image(preset, store_wp_dir)
        if src_path is None:
            return None
        try:
            with Image.open(src_path) as im:
                centering = (0.90, 0.55) if pid == "tame-impala" else (0.5, 0.5)
                fitted = ImageOps.fit(
                    im.convert("RGB"), (960, 540), method=Image.Resampling.LANCZOS, centering=centering
                )
                card_path.parent.mkdir(parents=True, exist_ok=True)
                tmp = card_path.with_name(f".{card_path.name}.tmp")
                fitted.save(tmp, format="JPEG", quality=92)
                tmp.replace(card_path)
        except Exception:
            try:
                return Gdk.Texture.new_from_filename(str(src_path))
            except Exception:
                return None

    try:
        return Gdk.Texture.new_from_filename(str(card_path))
    except Exception:
        return None


def cairo_to_texture(surface: cairo.ImageSurface) -> Gdk.MemoryTexture:
    surface.flush()
    w = surface.get_width()
    h = surface.get_height()
    stride = surface.get_stride()
    gbytes = GLib.Bytes.new(bytes(surface.get_data()))
    return Gdk.MemoryTexture.new(w, h, Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED, gbytes, stride)


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


def measure_text(text: str, font_desc: str) -> tuple[int, int]:
    dummy = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)
    ctx = cairo.Context(dummy)
    layout = PangoCairo.create_layout(ctx)
    layout.set_font_description(Pango.FontDescription.from_string(font_desc))
    layout.set_text(text, -1)
    return layout.get_pixel_size()


def draw_text(
    ctx: cairo.Context,
    text: str,
    x: float,
    y: float,
    font_desc: str,
    rgba: tuple[float, float, float, float],
    align: str = "left",
    max_width: int = -1,
) -> tuple[int, int]:
    layout = PangoCairo.create_layout(ctx)
    layout.set_font_description(Pango.FontDescription.from_string(font_desc))
    layout.set_text(text, -1)
    if max_width > 0:
        layout.set_width(max_width * Pango.SCALE)
        layout.set_ellipsize(Pango.EllipsizeMode.END)
    w, h = layout.get_pixel_size()
    draw_x = x - w * 0.5 if align == "center" else (x - w if align == "right" else x)
    ctx.save()
    ctx.set_source_rgba(*rgba)
    ctx.move_to(draw_x, y)
    PangoCairo.show_layout(ctx, layout)
    ctx.restore()
    return w, h


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
    else:
        ctx.move_to(cx, cy - s)
        ctx.line_to(cx + s * 0.9, cy)
        ctx.line_to(cx, cy + s)
        ctx.line_to(cx - s * 0.9, cy)
        ctx.close_path()
        ctx.stroke()
        ctx.arc(cx, cy, s * 0.28, 0.0, 2.0 * math.pi)
        ctx.fill()
    ctx.restore()


def build_pill_texture(
    label: str,
    border_rgb: tuple[float, float, float],
    fg_rgb: tuple[float, float, float],
    max_w: int = 560,
) -> Gdk.MemoryTexture:
    tw, th = measure_text(label, "Sans Bold 10.5")
    w = min(max_w, tw + 30)
    h = th + 14
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w + 4, h + 4)
    ctx = cairo.Context(surf)
    rounded_rect_path(ctx, 2, 2, w, h, h * 0.5)
    ctx.set_source_rgba(0.05, 0.06, 0.10, 0.88)
    ctx.fill_preserve()
    ctx.set_line_width(1.2)
    ctx.set_source_rgba(border_rgb[0], border_rgb[1], border_rgb[2], 0.78)
    ctx.stroke()
    draw_text(ctx, label, 2 + w * 0.5, 2 + (h - th) * 0.5, "Sans Bold 10.5", (*fg_rgb, 0.98), align="center", max_width=w - 18)
    return cairo_to_texture(surf)


def build_tag_texture(tag: str, text_rgb: tuple[float, float, float]) -> Gdk.MemoryTexture:
    tw, th = measure_text(tag, "JetBrains Mono Bold 7.5")
    w = tw + 12
    h = th + 6
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w + 2, h + 2)
    ctx = cairo.Context(surf)
    rounded_rect_path(ctx, 1, 1, w, h, 4.0)
    ctx.set_source_rgba(0.04, 0.05, 0.08, 0.86)
    ctx.fill_preserve()
    ctx.set_line_width(0.8)
    ctx.set_source_rgba(1.0, 1.0, 1.0, 0.22)
    ctx.stroke()
    draw_text(ctx, tag, 1 + w * 0.5, 1 + (h - th) * 0.5, "JetBrains Mono Bold 7.5", (*text_rgb, 0.95), align="center")
    return cairo_to_texture(surf)


def build_glyph_texture(is_video: bool) -> Gdk.MemoryTexture:
    size = 22
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    ctx = cairo.Context(surf)
    cx = cy = size * 0.5
    ctx.arc(cx, cy, 8.5, 0.0, 2.0 * math.pi)
    ctx.set_source_rgba(0.05, 0.07, 0.11, 0.74)
    ctx.fill_preserve()
    ctx.set_line_width(1.0)
    ctx.set_source_rgba(1.0, 1.0, 1.0, 0.42)
    ctx.stroke()
    ctx.set_source_rgba(1.0, 1.0, 1.0, 0.88)
    if is_video:
        ctx.move_to(cx - 2.3, cy - 3.4)
        ctx.line_to(cx + 3.6, cy)
        ctx.line_to(cx - 2.3, cy + 3.4)
        ctx.close_path()
        ctx.fill()
    else:
        ctx.arc(cx, cy, 2.5, 0.0, 2.0 * math.pi)
        ctx.fill()
    return cairo_to_texture(surf)


def build_hint_texture(text: str, bg_rgb: tuple[float, float, float], muted_rgb: tuple[float, float, float]) -> Gdk.MemoryTexture:
    hw, hh = measure_text(text, "Sans 9.5")
    w = hw + 30
    h = hh + 10
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w + 2, h + 2)
    ctx = cairo.Context(surf)
    rounded_rect_path(ctx, 1, 1, w, h, h * 0.5)
    ctx.set_source_rgba(bg_rgb[0] * 0.7, bg_rgb[1] * 0.7, bg_rgb[2] * 0.7, 0.68)
    ctx.fill()
    draw_text(ctx, text, 1 + w * 0.5, 1 + (h - hh) * 0.5, "Sans 9.5", (*muted_rgb, 0.90), align="center")
    return cairo_to_texture(surf)


def build_empty_texture(text: str, fg_rgb: tuple[float, float, float]) -> Gdk.MemoryTexture:
    tw, th = measure_text(text, "Sans SemiBold 14")
    w = tw + 24
    h = th + 12
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    ctx = cairo.Context(surf)
    draw_text(ctx, text, w * 0.5, (h - th) * 0.5, "Sans SemiBold 14", (*fg_rgb, 0.88), align="center")
    return cairo_to_texture(surf)


class ParallelogramView(Gtk.Widget):
    """100% GPU-rendered GTK4 widget using Gsk.Transform shear + cached textures + spring physics."""

    FILTERS = [
        ("all", "Все"),
        ("video", "Видео"),
        ("scene", "Сцены"),
    ]

    def __init__(self, presets: list[dict], current_id: str, store_wp_dir: Path | None) -> None:
        super().__init__()
        self.set_hexpand(True)
        self.set_vexpand(True)
        self.set_focusable(True)

        self.all_presets = presets
        self.current_id = current_id
        self.store_wp_dir = store_wp_dir
        self.sys_colors = resolve_system_colors(presets, current_id)

        self.bg_rgb = hex_rgb(self.sys_colors["bg"])
        self.surf_rgb = hex_rgb(self.sys_colors["surface"])
        self.fg_rgb = hex_rgb(self.sys_colors["fg"])
        self.muted_rgb = hex_rgb(self.sys_colors["fg_muted"])
        self.pri_rgb = hex_rgb(self.sys_colors["primary"])
        self.acc_rgb = hex_rgb(self.sys_colors["accent"])

        self.filter_mode = "all"
        self.search_query = ""
        self.filtered: list[dict] = list(presets)

        start_idx = next((i for i, p in enumerate(self.filtered) if p.get("id") == current_id), 0)
        self.target_slot = start_idx
        self.anim_pos = float(start_idx)
        self.anim_vel = 0.0
        self.anim_alpha = 0.0
        self.last_tick_us: int | None = None
        self.hover_filter: str | None = None

        # Preload GPU card textures & tiny HUD label textures ONCE (0 allocations per frame!)
        self.card_textures: dict[str, Gdk.Texture] = {}
        self.pill_textures: dict[str, Gdk.MemoryTexture] = {}
        self.preset_colors: dict[str, tuple[tuple[float, float, float], tuple[float, float, float]]] = {}
        for p in presets:
            pid = p.get("id", "")
            if not pid:
                continue
            tex = load_gpu_card_texture(p, store_wp_dir)
            if tex is not None:
                self.card_textures[pid] = tex
            ring = (p.get("niri") or {}).get("focus_ring") or {}
            c_from = hex_rgb(ring.get("from") or self.sys_colors["primary"])
            c_to = hex_rgb(ring.get("to") or ring.get("from") or self.sys_colors["accent"])
            self.preset_colors[pid] = (c_from, c_to)
            name = p.get("name", pid)
            label = f"✦  {name}" if pid == current_id else name
            self.pill_textures[pid] = build_pill_texture(label, c_from, self.fg_rgb)

        self.tag_vid = build_tag_texture("VID", (0.90, 0.93, 0.98))
        self.tag_we = build_tag_texture("WE", (0.90, 0.93, 0.98))
        self.tag_cur = build_tag_texture("✦", self.pri_rgb)
        self.glyph_vid = build_glyph_texture(True)
        self.glyph_we = build_glyph_texture(False)
        self.hint_tex = build_hint_texture(
            "← → или колесо: листать   •   Enter: применить   •   Печать: поиск   •   Esc: закрыть",
            self.bg_rgb,
            self.muted_rgb,
        )

        # Cached top capsule texture + relative filter button hitboxes
        self._capsule_cache_key: tuple | None = None
        self._capsule_tex: Gdk.MemoryTexture | None = None
        self._capsule_rel_filters: list[tuple[str, float, float, float, float]] = []
        self._empty_cache_key: str | None = None
        self._empty_tex: Gdk.MemoryTexture | None = None

        # Per-frame hit test geometry
        self.card_hit_polys: list[tuple[int, float, float, float, float, float]] = []
        self.filter_hit_rects: list[tuple[str, float, float, float, float]] = []
        self.capsule_rect: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)

        self.add_tick_callback(self._on_tick)

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
            self.anim_vel = 0.0
            self.queue_draw()
            return

        target = keep_id or self.current_id
        new_idx = next((i for i, p in enumerate(result) if p.get("id") == target), 0)
        self.target_slot = new_idx
        self.anim_pos = float(new_idx)
        self.anim_vel = 0.0
        self.queue_draw()

    def move_selection(self, delta: int) -> None:
        if not self.filtered:
            return
        self.target_slot += delta
        self.queue_draw()

    def jump_to_slot(self, slot: int) -> None:
        self.target_slot = slot
        self.queue_draw()

    def step_animation(self, dt: float) -> bool:
        moving = False

        if self.anim_alpha < 0.999:
            self.anim_alpha = min(1.0, self.anim_alpha + dt * 8.0)
            moving = True

        x0 = self.anim_pos - float(self.target_slot)
        v0 = self.anim_vel
        if abs(x0) > 0.0008 or abs(v0) > 0.004:
            # Exact analytical critically-damped spring: buttery smooth at 60–240 Hz
            omega = 16.5
            exp_t = math.exp(-omega * dt)
            c2 = v0 + omega * x0
            self.anim_pos = float(self.target_slot) + (x0 + c2 * dt) * exp_t
            self.anim_vel = (v0 - omega * c2 * dt) * exp_t
            moving = True
        else:
            self.anim_pos = float(self.target_slot)
            self.anim_vel = 0.0

        return moving

    def _on_tick(self, _widget: Gtk.Widget, frame_clock: Gdk.FrameClock) -> bool:
        now_us = frame_clock.get_frame_time()
        if self.last_tick_us is None:
            dt = 1.0 / 120.0
        else:
            raw_dt = (now_us - self.last_tick_us) / 1_000_000.0
            # Guard against large first-frame delta after idle pause
            dt = (1.0 / 120.0) if (raw_dt <= 0.0 or raw_dt > 0.05) else raw_dt
        self.last_tick_us = now_us

        if self.step_animation(dt):
            self.queue_draw()
        return GLib.SOURCE_CONTINUE

    def _ensure_capsule_texture(self, active_preset: dict | None) -> Gdk.MemoryTexture:
        pid = active_preset.get("id", "") if active_preset else ""
        key = (self.filter_mode, self.selected_idx, len(self.filtered), self.search_query, self.hover_filter, pid)
        if key == self._capsule_cache_key and self._capsule_tex is not None:
            return self._capsule_tex

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
        right_w, right_h = measure_text(right_txt, "JetBrains Mono SemiBold 10")
        right_box_w = max(46.0, right_w + 16.0)

        filters_w = len(self.FILTERS) * btn_w + (len(self.FILTERS) - 1) * btn_gap
        cap_w = int(math.ceil(pad_x + filters_w + 14.0 + 1.0 + 14.0 + swatches_total_w + 14.0 + 1.0 + 12.0 + right_box_w + pad_x))
        tex_w = cap_w + 4
        tex_h = int(cap_h) + 4

        surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, tex_w, tex_h)
        ctx = cairo.Context(surf)

        ox, oy = 2.0, 2.0
        rounded_rect_path(ctx, ox, oy, cap_w, cap_h, cap_h * 0.5)
        ctx.set_source_rgba(self.bg_rgb[0] * 0.85, self.bg_rgb[1] * 0.85, self.bg_rgb[2] * 0.85, 0.90)
        ctx.fill_preserve()
        ctx.set_line_width(1.2)
        ctx.set_source_rgba(self.pri_rgb[0], self.pri_rgb[1], self.pri_rgb[2], 0.48)
        ctx.stroke()

        rel_filters: list[tuple[str, float, float, float, float]] = []
        cur_x = ox + pad_x
        btn_y = oy + (cap_h - btn_h) * 0.5
        for fkey, _label in self.FILTERS:
            is_active = self.filter_mode == fkey
            is_hover = self.hover_filter == fkey
            rel_filters.append((fkey, cur_x, btn_y, btn_w, btn_h))
            ctx.save()
            rounded_rect_path(ctx, cur_x, btn_y, btn_w, btn_h, btn_h * 0.5)
            if is_active:
                ctx.set_source_rgba(*self.pri_rgb, 0.94)
                ctx.fill()
                icon_col = (*self.bg_rgb, 0.98)
            elif is_hover:
                ctx.set_source_rgba(*self.surf_rgb, 0.88)
                ctx.fill()
                icon_col = (*self.fg_rgb, 0.95)
            else:
                ctx.set_source_rgba(*self.surf_rgb, 0.45)
                ctx.fill()
                icon_col = (*self.muted_rgb, 0.90)
            ctx.restore()
            draw_filter_icon(ctx, fkey, cur_x + btn_w * 0.5, btn_y + btn_h * 0.5, 13.0, icon_col)
            cur_x += btn_w + btn_gap

        div1_x = cur_x - btn_gap + 12.0
        ctx.set_source_rgba(*self.muted_rgb, 0.25)
        ctx.set_line_width(1.0)
        ctx.move_to(div1_x, oy + 10.0)
        ctx.line_to(div1_x, oy + cap_h - 10.0)
        ctx.stroke()

        sx = div1_x + 14.0
        sy = oy + (cap_h - swatch_h) * 0.5
        for hex_c in swatches:
            sr, sg, sb = hex_rgb(hex_c)
            parallelogram_path(ctx, sx, sy, swatch_w, swatch_h, swatch_skew)
            ctx.set_source_rgba(sr, sg, sb, 0.96)
            ctx.fill_preserve()
            ctx.set_line_width(0.9)
            ctx.set_source_rgba(1.0, 1.0, 1.0, 0.28)
            ctx.stroke()
            sx += swatch_w + swatch_gap

        div2_x = sx - swatch_gap + swatch_skew + 12.0
        ctx.set_source_rgba(*self.muted_rgb, 0.25)
        ctx.set_line_width(1.0)
        ctx.move_to(div2_x, oy + 10.0)
        ctx.line_to(div2_x, oy + cap_h - 10.0)
        ctx.stroke()

        txt_col = (*self.pri_rgb, 0.98) if self.search_query else (*self.fg_rgb, 0.90)
        draw_text(
            ctx,
            right_txt,
            ox + cap_w - pad_x - 4.0,
            oy + (cap_h - right_h) * 0.5,
            "JetBrains Mono SemiBold 10",
            txt_col,
            align="right",
        )

        self._capsule_cache_key = key
        self._capsule_tex = cairo_to_texture(surf)
        self._capsule_rel_filters = rel_filters
        return self._capsule_tex

    def render_snapshot(self, snapshot: Gtk.Snapshot, width: int, height: int) -> None:
        self.card_hit_polys.clear()
        self.filter_hit_rects.clear()

        if width <= 0 or height <= 0:
            return

        fade = smoothstep(self.anim_alpha)
        full_rect = make_rect(0.0, 0.0, width, height)

        # 1. Subtle GPU radial vignette backdrop
        stop_inner = make_stop(0.0, make_rgba(self.bg_rgb[0] * 0.45, self.bg_rgb[1] * 0.45, self.bg_rgb[2] * 0.45, 0.44 * fade))
        stop_outer = make_stop(1.0, make_rgba(0.02, 0.03, 0.05, 0.62 * fade))
        snapshot.append_radial_gradient(
            full_rect,
            make_point(width * 0.5, height * 0.5),
            width * 0.65,
            height * 0.65,
            0.12,
            1.0,
            [stop_inner, stop_outer],
        )

        card_h = clamp(height * 0.40, 300.0, 460.0)
        hero_w = min(card_h * (16.0 / 9.0), width * 0.54)
        slice_w = clamp(card_h * 0.145, 48.0, 68.0)
        skew = round(card_h * 0.068)
        gap = 10.0
        ribbon_y = (height - card_h) * 0.52

        n = len(self.filtered)
        active_preset = self.filtered[self.selected_idx] if n > 0 else None

        # 2. Cached top capsule GPU texture
        cap_tex = self._ensure_capsule_texture(active_preset)
        cw = float(cap_tex.get_width())
        ch = float(cap_tex.get_height())
        cap_x = (width - cw) * 0.5
        cap_y = ribbon_y - ch - 16.0
        self.capsule_rect = (cap_x, cap_y, cw, ch)
        for fkey, rx, ry, rw, rh in self._capsule_rel_filters:
            self.filter_hit_rects.append((fkey, cap_x + rx, cap_y + ry, rw, rh))

        if fade < 0.999:
            snapshot.push_opacity(fade)
        snapshot.append_texture(cap_tex, make_rect(cap_x, cap_y, cw, ch))
        if fade < 0.999:
            snapshot.pop()

        # 3. Empty state
        if n == 0:
            msg = f"Нет тем по запросу «{self.search_query}»" if self.search_query else "В этом фильтре нет тем"
            if msg != self._empty_cache_key or self._empty_tex is None:
                self._empty_cache_key = msg
                self._empty_tex = build_empty_texture(msg, self.fg_rgb)
            ew, eh = float(self._empty_tex.get_width()), float(self._empty_tex.get_height())
            snapshot.append_texture(self._empty_tex, make_rect((width - ew) * 0.5, ribbon_y + (card_h - eh) * 0.5, ew, eh))
            return

        # 4. Compute exact infinite cyclic ribbon layout
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

        draw_order = sorted(range(len(slots)), key=lambda i: weights[i])
        for i in draw_order:
            ef = edge_fades[i]
            if ef <= 0.01:
                continue
            s = slots[i]
            x = lefts[i] + x_shift
            w = widths[i]
            if x + w + skew < -40.0 or x > width + 40.0:
                continue

            preset_idx = s % n
            preset = self.filtered[preset_idx]
            pid = preset.get("id", "")
            wtype = (preset.get("wallpaper") or {}).get("type", "image").lower()
            is_current = pid == self.current_id
            w_focus = weights[i]
            card_alpha = fade * ef

            self.card_hit_polys.append((s, x, ribbon_y, w, card_h, float(skew)))

            c_from_rgb, c_to_rgb = self.preset_colors.get(pid, (self.pri_rgb, self.acc_rgb))
            bbox = make_rect(x - 6.0, ribbon_y - 6.0, w + skew + 12.0, card_h + 12.0)

            pb = Gsk.PathBuilder()
            pb.move_to(float(x + skew), float(ribbon_y))
            pb.line_to(float(x + skew + w), float(ribbon_y))
            pb.line_to(float(x + w), float(ribbon_y + card_h))
            pb.line_to(float(x), float(ribbon_y + card_h))
            pb.close()
            path = pb.to_path()

            pushed_alpha = card_alpha < 0.999
            if pushed_alpha:
                snapshot.push_opacity(card_alpha)

            # Soft outer glow around hero parallelogram
            if w_focus > 0.25:
                snapshot.append_stroke(
                    path,
                    Gsk.Stroke.new(7.0),
                    make_rgba(c_from_rgb[0], c_from_rgb[1], c_from_rgb[2], 0.26 * w_focus),
                )

            # Native GTK4 GPU path fill mask: upright wallpaper clipped to crisp anti-aliased parallelogram
            snapshot.push_fill(path, Gsk.FillRule.WINDING)

            tex = self.card_textures.get(pid)
            if tex is not None:
                iw = float(tex.get_width())
                ih = float(tex.get_height())
                span_w = hero_w + skew
                scale = max(span_w / iw, card_h / ih)
                draw_w = iw * scale
                draw_h = ih * scale
                card_cx = x + (w + skew) * 0.5
                card_cy = ribbon_y + card_h * 0.5
                snapshot.append_scaled_texture(
                    tex,
                    Gsk.ScalingFilter.LINEAR,
                    make_rect(card_cx - draw_w * 0.5, card_cy - draw_h * 0.5, draw_w, draw_h),
                )
            else:
                g1 = make_stop(0.0, make_rgba(c_from_rgb[0] * 0.35, c_from_rgb[1] * 0.35, c_from_rgb[2] * 0.35, 1.0))
                g2 = make_stop(1.0, make_rgba(*self.bg_rgb, 1.0))
                snapshot.append_linear_gradient(
                    bbox, make_point(x, ribbon_y), make_point(x + w + skew, ribbon_y + card_h), [g1, g2]
                )

            if w_focus < 0.96:
                snapshot.append_color(make_rgba(0.03, 0.04, 0.07, (1.0 - w_focus) * 0.34), bbox)

            snapshot.pop()  # end push_fill

            # Crisp GPU parallelogram border (linear accent gradient on hero, clean rim on slices)
            if w_focus > 0.45:
                bw = 1.3 + 1.2 * w_focus
                snapshot.push_stroke(path, Gsk.Stroke.new(bw))
                st1 = make_stop(0.0, make_rgba(*c_from_rgb, 0.96 * w_focus))
                st2 = make_stop(1.0, make_rgba(*c_to_rgb, 0.96 * w_focus))
                snapshot.append_linear_gradient(
                    bbox,
                    make_point(x, ribbon_y),
                    make_point(x + w + skew, ribbon_y + card_h),
                    [st1, st2],
                )
                snapshot.pop()
            else:
                if is_current:
                    snapshot.append_stroke(path, Gsk.Stroke.new(1.5), make_rgba(*c_from_rgb, 0.78))
                else:
                    snapshot.append_stroke(path, Gsk.Stroke.new(1.0), make_rgba(1.0, 1.0, 1.0, 0.20))

            # Upright cached micro-textures (zero text re-layout on scroll!)
            if w_focus < 0.45 and w >= 38.0:
                gtex = self.glyph_vid if wtype == "video" else self.glyph_we
                gw, gh = float(gtex.get_width()), float(gtex.get_height())
                snapshot.push_opacity(1.0 - w_focus)
                snapshot.append_texture(gtex, make_rect(x + skew + w - gw - 6.0, ribbon_y + 6.0, gw, gh))
                snapshot.pop()

            tag_tex = self.tag_cur if (is_current and w_focus < 0.55) else (self.tag_vid if wtype == "video" else self.tag_we)
            tw, th = float(tag_tex.get_width()), float(tag_tex.get_height())
            snapshot.append_texture(tag_tex, make_rect(x + w - tw - 10.0, ribbon_y + card_h - th - 8.0, tw, th))

            if w_focus > 0.55:
                pill_tex = self.pill_textures.get(pid)
                if pill_tex is not None:
                    pill_alpha = clamp((w_focus - 0.55) / 0.45, 0.0, 1.0)
                    pw, ph = float(pill_tex.get_width()), float(pill_tex.get_height())
                    px = x + w * 0.5 - pw * 0.5
                    py = ribbon_y + card_h - ph - 12.0
                    snapshot.push_opacity(pill_alpha)
                    snapshot.append_texture(pill_tex, make_rect(px, py, pw, ph))
                    snapshot.pop()

            if pushed_alpha:
                snapshot.pop()

        # 5. Cached bottom helper hint
        hw, hh = float(self.hint_tex.get_width()), float(self.hint_tex.get_height())
        if fade < 0.999:
            snapshot.push_opacity(fade)
        snapshot.append_texture(self.hint_tex, make_rect((width - hw) * 0.5, ribbon_y + card_h + 15.0, hw, hh))
        if fade < 0.999:
            snapshot.pop()

    def do_snapshot(self, snapshot: Gtk.Snapshot) -> None:
        self.render_snapshot(snapshot, self.get_width(), self.get_height())

    def hit_test_filter(self, px: float, py: float) -> str | None:
        for fkey, rx, ry, rw, rh in self.filter_hit_rects:
            if rx <= px <= rx + rw and ry <= py <= ry + rh:
                return fkey
        return None

    def point_in_capsule(self, px: float, py: float) -> bool:
        cx, cy, cw, ch = self.capsule_rect
        return cx <= px <= cx + cw and cy <= py <= cy + ch

    def hit_test_card(self, px: float, py: float) -> int | None:
        for slot, x, y, w, h, skew in reversed(self.card_hit_polys):
            if py < y or py > y + h:
                continue
            t = (y + h - py) / h
            left_edge = x + skew * t
            if left_edge <= px <= left_edge + w:
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
    def __init__(self, app: Gtk.Application, view: ParallelogramView) -> None:
        super().__init__(application=app, title="Theme Parallelogram Switcher")
        self.view = view

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

        self.set_child(self.view)

        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        key_ctrl.connect("key-pressed", self._on_key_pressed)
        self.add_controller(key_ctrl)

        scroll_ctrl = Gtk.EventControllerScroll.new(
            Gtk.EventControllerScrollFlags.BOTH_AXES | Gtk.EventControllerScrollFlags.DISCRETE
        )
        scroll_ctrl.connect("scroll", self._on_scroll)
        self.view.add_controller(scroll_ctrl)

        motion_ctrl = Gtk.EventControllerMotion()
        motion_ctrl.connect("motion", self._on_motion)
        self.view.add_controller(motion_ctrl)

        click_ctrl = Gtk.GestureClick.new()
        click_ctrl.connect("pressed", self._on_click)
        self.view.add_controller(click_ctrl)

    def _commit_selected(self) -> None:
        if 0 <= self.view.selected_idx < len(self.view.filtered):
            pid = self.view.filtered[self.view.selected_idx].get("id", "")
            self.close()
            apply_theme(pid)

    def _on_key_pressed(
        self, _ctrl: Gtk.EventControllerKey, keyval: int, _keycode: int, state: Gdk.ModifierType
    ) -> bool:
        if keyval == Gdk.KEY_Escape:
            if self.view.search_query:
                self.view.search_query = ""
                self.view.apply_filter()
                return True
            self.close()
            return True

        if keyval in (Gdk.KEY_Left, Gdk.KEY_Up):
            self.view.move_selection(-1)
            return True

        if keyval in (Gdk.KEY_Right, Gdk.KEY_Down):
            self.view.move_selection(1)
            return True

        if keyval == Gdk.KEY_Tab:
            keys = [k for k, _ in self.view.FILTERS]
            cur_i = keys.index(self.view.filter_mode)
            cur_id = self.view.filtered[self.view.selected_idx].get("id") if self.view.filtered else None
            self.view.filter_mode = keys[(cur_i + 1) % len(keys)]
            self.view.apply_filter(keep_id=cur_id)
            return True

        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self._commit_selected()
            return True

        if keyval == Gdk.KEY_Home and self.view.filtered:
            self.view.jump_to_slot(0)
            return True

        if keyval == Gdk.KEY_End and self.view.filtered:
            self.view.jump_to_slot(len(self.view.filtered) - 1)
            return True

        if keyval == Gdk.KEY_BackSpace:
            if self.view.search_query:
                self.view.search_query = self.view.search_query[:-1]
                self.view.apply_filter()
            return True

        if not self.view.search_query and not (state & Gdk.ModifierType.CONTROL_MASK):
            if keyval in (Gdk.KEY_h, Gdk.KEY_H):
                self.view.move_selection(-1)
                return True
            if keyval in (Gdk.KEY_l, Gdk.KEY_L):
                self.view.move_selection(1)
                return True

        uni = Gdk.keyval_to_unicode(keyval)
        if uni and uni >= 32 and not (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)):
            ch = chr(uni)
            if ch.isalnum() or ch in (" ", "-", "_"):
                self.view.search_query += ch
                self.view.apply_filter()
                return True

        return False

    def _on_scroll(self, _ctrl: Gtk.EventControllerScroll, dx: float, dy: float) -> bool:
        delta = dy if abs(dy) >= abs(dx) else dx
        if delta > 0:
            self.view.move_selection(1)
        elif delta < 0:
            self.view.move_selection(-1)
        return True

    def _on_motion(self, _ctrl: Gtk.EventControllerMotion, x: float, y: float) -> None:
        hovered = self.view.hit_test_filter(x, y)
        if hovered != self.view.hover_filter:
            self.view.hover_filter = hovered
            self.view.queue_draw()

    def _on_click(self, _gesture: Gtk.GestureClick, _n_press: int, x: float, y: float) -> None:
        fkey = self.view.hit_test_filter(x, y)
        if fkey is not None:
            cur_id = self.view.filtered[self.view.selected_idx].get("id") if self.view.filtered else None
            self.view.filter_mode = fkey
            self.view.apply_filter(keep_id=cur_id)
            return

        if self.view.point_in_capsule(x, y):
            return

        hit_slot = self.view.hit_test_card(x, y)
        if hit_slot is not None:
            if hit_slot == self.view.target_slot:
                self._commit_selected()
            else:
                self.view.jump_to_slot(hit_slot)
            return

        self.close()


def run_benchmark() -> int:
    Gtk.init()
    presets, current_id, store_wp_dir = load_data()
    if not presets:
        print("No presets found", file=sys.stderr)
        return 1
    t0 = time.perf_counter()
    view = ParallelogramView(presets, current_id, store_wp_dir)
    t_load = (time.perf_counter() - t0) * 1000.0

    view.anim_alpha = 1.0
    view.move_selection(3)

    frames = 240
    t1 = time.perf_counter()
    for _ in range(frames):
        view.step_animation(1.0 / 144.0)
        snap = Gtk.Snapshot()
        view.render_snapshot(snap, 1920, 1080)
        snap.to_node()
    elapsed_ms = (time.perf_counter() - t1) * 1000.0
    print(f"startup={t_load:.1f}ms, {frames} GPU scene-graph frames in {elapsed_ms:.1f}ms ({elapsed_ms/frames:.3f}ms/frame)")
    return 0


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "--benchmark":
        return run_benchmark()

    presets, current_id, store_wp_dir = load_data()
    if not presets:
        print(f"Файл пресетов не найден или пуст: {PRESETS_FILE}", file=sys.stderr)
        return 1

    app = Gtk.Application(application_id="dev.spike.ThemeParallelogram")

    def on_activate(gtk_app: Gtk.Application) -> None:
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
        view = ParallelogramView(presets, current_id, store_wp_dir)
        win = ParallelogramWindow(gtk_app, view)
        win.present()

    app.connect("activate", on_activate)
    return app.run(None)


if __name__ == "__main__":
    raise SystemExit(main())
