#!/usr/bin/env python3
"""
Visual Theme Switcher GUI for Niri / Wayland
Modern Libadwaita / GTK4 interface displaying cards with wallpaper thumbnails,
palette previews, keyboard and mouse navigation.
"""

import os
import sys

# Force OpenGL renderer for GTK4 on NVIDIA Wayland (avoids Vulkan swapchain out of date bug)
os.environ["GSK_RENDERER"] = "gl"

# Fallback GI_TYPELIB_PATH if not set by wrapper
if "GI_TYPELIB_PATH" not in os.environ:
    fallback_paths = [
        "/etc/profiles/per-user/spike/lib/girepository-1.0",
        "/run/current-system/sw/lib/girepository-1.0",
        os.path.expanduser("~/.local/state/nix/profiles/home-manager/home-path/lib/girepository-1.0"),
    ]
    os.environ["GI_TYPELIB_PATH"] = ":".join(p for p in fallback_paths if os.path.isdir(p))

import json
import subprocess
import gi

gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, Gdk, GLib, Gio


PRESETS_FILE = os.path.expanduser("~/.config/theme-manager/presets.json")
STATE_FILE = os.path.expanduser("~/.local/state/theme-manager/current")


CUSTOM_CSS = """
window.theme-switcher-window {
    background-color: #0d1016;
}

headerbar.theme-header {
    background-color: #11151d;
    border-bottom: 1px solid #252c39;
}

.theme-search {
    min-width: 190px;
}

.theme-card {
    background-color: #151a23;
    border: 1px solid #252d3b;
    border-radius: 12px;
    padding: 9px;
    margin: 5px;
    transition: all 150ms ease-in-out;
}

.theme-card:hover {
    background-color: #1b2230;
    border-color: #7186ad;
}

.theme-card:focus, .theme-card:focus-visible {
    border-color: #8aa7e8;
    background-color: #202a3a;
    box-shadow: 0 0 0 2px rgba(138, 167, 232, 0.18);
}

.theme-card.active-theme {
    border-color: #ff8a3d;
    box-shadow: 0 0 0 1px rgba(255, 138, 61, 0.22);
}

.card-title {
    font-size: 13px;
    font-weight: 700;
    color: #edf1f8;
    margin-top: 5px;
    margin-bottom: 2px;
}

.card-meta {
    font-size: 10.5px;
    color: #8995aa;
}

.badge-active {
    background-color: #3a2114;
    color: #ffb078;
    border: 1px solid #8d4d2a;
    border-radius: 999px;
    padding: 2px 7px;
    font-size: 10px;
    font-weight: 700;
}

.badge-index {
    background-color: #252d3b;
    color: #9aa8bf;
    border-radius: 5px;
    padding: 1px 6px;
    font-size: 10px;
    font-weight: 600;
}

.color-dot {
    border-radius: 999px;
    min-width: 12px;
    min-height: 12px;
    border: 1px solid rgba(255, 255, 255, 0.18);
}

.thumb-frame {
    border-radius: 9px;
    background-color: #090c12;
}

.menu-footer {
    color: #7f8ba0;
    font-size: 11px;
    padding: 0 18px 12px;
}
"""


def load_presets():
    if not os.path.exists(PRESETS_FILE):
        return []
    try:
        with open(PRESETS_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
            return data.get("presets", [])
    except Exception as e:
        print(f"Error loading presets: {e}", file=sys.stderr)
        return []


def get_current_theme():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, 'r', encoding='utf-8') as f:
                return f.read().strip()
        except Exception:
            pass
    return ""


def apply_theme(preset_id, app):
    try:
        result = subprocess.run(["theme-apply", preset_id], check=False)
        if result.returncode != 0:
            if app.footer_label:
                app.footer_label.set_text("Не удалось применить тему · проверь журнал theme-apply")
            return False
    except Exception as e:
        print(f"Error executing theme-apply {preset_id}: {e}", file=sys.stderr)
        if app.footer_label:
            app.footer_label.set_text(f"Ошибка запуска: {e}")
        return False
    app.quit()
    return True


class ThemeMenuApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.spike.theme_menu_gui", flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.presets = []
        self.current_theme = ""
        self.card_buttons = []
        self.presets_by_id = {}
        self.flow = None
        self.search_entry = None
        self.footer_label = None

    def do_activate(self):
        self.presets = load_presets()
        self.current_theme = get_current_theme()

        # Force dark mode
        style_manager = Adw.StyleManager.get_default()
        style_manager.set_color_scheme(Adw.ColorScheme.FORCE_DARK)

        # Apply Global CSS
        display = Gdk.Display.get_default()
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(CUSTOM_CSS.encode('utf-8'))
        Gtk.StyleContext.add_provider_for_display(
            display,
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        # Build dynamic CSS for dot colors
        dynamic_css = []
        for preset in self.presets:
            for col in self.extract_palette_colors(preset):
                clean_col = col.replace('#', '')
                dynamic_css.append(f".dot-{clean_col} {{ background-color: {col}; }}")

        if dynamic_css:
            dots_provider = Gtk.CssProvider()
            dots_provider.load_from_data("\n".join(dynamic_css).encode('utf-8'))
            Gtk.StyleContext.add_provider_for_display(
                display,
                dots_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

        win = Adw.ApplicationWindow.new(self)
        win.add_css_class("theme-switcher-window")
        win.set_title("Темы оформления")
        win.set_default_size(900, 660)
        win.set_size_request(520, 420)

        root_box = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0)
        win.set_content(root_box)

        header = Adw.HeaderBar.new()
        header.add_css_class("theme-header")
        header.set_show_end_title_buttons(True)
        title_widget = Adw.WindowTitle.new("Темы", "Выбери сетап")
        header.set_title_widget(title_widget)

        self.search_entry = Gtk.SearchEntry.new()
        self.search_entry.set_placeholder_text("Найти тему")
        self.search_entry.add_css_class("theme-search")
        self.search_entry.set_hexpand(True)
        header.pack_start(self.search_entry)
        root_box.append(header)

        scroller = Gtk.ScrolledWindow.new()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        root_box.append(scroller)

        self.flow = Gtk.FlowBox.new()
        self.flow.set_valign(Gtk.Align.START)
        self.flow.set_halign(Gtk.Align.FILL)
        self.flow.set_max_children_per_line(4)
        self.flow.set_min_children_per_line(2)
        self.flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.flow.set_homogeneous(True)
        self.flow.set_row_spacing(6)
        self.flow.set_column_spacing(6)
        self.flow.set_margin_top(10)
        self.flow.set_margin_bottom(10)
        self.flow.set_margin_start(12)
        self.flow.set_margin_end(12)
        self.flow.set_filter_func(self.filter_theme_card)
        scroller.set_child(self.flow)

        for idx, preset in enumerate(self.presets):
            self.presets_by_id[preset.get("id", "")] = preset
            card_btn = self.create_theme_card(preset, idx + 1)
            self.flow.append(card_btn)
            self.card_buttons.append((preset.get("id"), card_btn))

        self.search_entry.connect("search-changed", self.on_search_changed)

        self.footer_label = Gtk.Label.new()
        self.footer_label.add_css_class("menu-footer")
        self.footer_label.set_halign(Gtk.Align.START)
        root_box.append(self.footer_label)
        self.update_footer()

        key_ctrl = Gtk.EventControllerKey.new()
        key_ctrl.connect("key-pressed", self.on_key_pressed)
        win.add_controller(key_ctrl)

        win.present()
        self.search_entry.grab_focus()

    def create_theme_card(self, preset, index):
        p_id = preset.get("id", "")
        p_name = preset.get("name", p_id)
        p_icon = preset.get("icon", "🎨")
        is_active = (p_id == self.current_theme)

        btn = Gtk.Button.new()
        btn.set_name(p_id)
        btn.add_css_class("theme-card")
        if is_active:
            btn.add_css_class("active-theme")

        card_vbox = Gtk.Box.new(Gtk.Orientation.VERTICAL, 6)
        btn.set_child(card_vbox)

        # Thumbnail frame
        thumb_frame = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0)
        thumb_frame.add_css_class("thumb-frame")
        thumb_frame.set_size_request(210, 118)

        fallback_img = preset.get("wallpaper", {}).get("fallback_image", "")
        thumb_path = None
        if fallback_img and os.path.exists(fallback_img):
            cache_dir = os.path.expanduser("~/.cache/theme-manager/thumbnails")
            os.makedirs(cache_dir, exist_ok=True)
            thumb_path = os.path.join(cache_dir, f"{p_id}.jpg")
            if not os.path.exists(thumb_path) or os.path.getmtime(fallback_img) > os.path.getmtime(thumb_path):
                try:
                    from PIL import Image
                    with Image.open(fallback_img) as image:
                        image.thumbnail((420, 236), Image.Resampling.LANCZOS)
                        image.convert("RGB").save(thumb_path, "JPEG", quality=82)
                except Exception as e:
                    print(f"Error creating thumbnail for {fallback_img}: {e}", file=sys.stderr)
            if not os.path.exists(thumb_path):
                thumb_path = fallback_img

        if thumb_path:
            pic = Gtk.Picture.new_for_filename(thumb_path)
            pic.set_content_fit(Gtk.ContentFit.COVER)
            pic.set_size_request(210, 118)
            thumb_frame.append(pic)
        else:
            placeholder = Gtk.Label.new(p_icon)
            placeholder.set_valign(Gtk.Align.CENTER)
            placeholder.set_vexpand(True)
            thumb_frame.append(placeholder)

        card_vbox.append(thumb_frame)

        title_row = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6)
        card_vbox.append(title_row)

        idx_label = Gtk.Label.new(str(index))
        idx_label.add_css_class("badge-index")
        title_row.append(idx_label)

        title_lbl = Gtk.Label.new(f"{p_icon} {p_name.split(' (')[0]}")
        title_lbl.add_css_class("card-title")
        title_lbl.set_halign(Gtk.Align.START)
        title_lbl.set_hexpand(True)
        title_lbl.set_ellipsize(3)
        title_row.append(title_lbl)

        if is_active:
            active_badge = Gtk.Label.new("●")
            active_badge.set_tooltip_text("Активная тема")
            active_badge.add_css_class("badge-active")
            title_row.append(active_badge)

        wallpaper_type = preset.get("wallpaper", {}).get("type", "image")
        if wallpaper_type == "wallpaperengine":
            source_label = "Wallpaper Engine"
        elif wallpaper_type == "video":
            source_label = "Видео"
        else:
            source_label = "Статичные обои"
        meta = Gtk.Label.new(source_label)
        meta.add_css_class("card-meta")
        meta.set_halign(Gtk.Align.START)
        card_vbox.append(meta)

        dots_row = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 5)
        dots_row.set_halign(Gtk.Align.START)
        dots_row.set_margin_top(2)
        dots_row.set_margin_bottom(2)
        card_vbox.append(dots_row)

        colors = self.extract_palette_colors(preset)
        for col in colors:
            dot = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 0)
            dot.add_css_class("color-dot")
            clean_col = col.replace('#', '')
            dot.add_css_class(f"dot-{clean_col}")
            dots_row.append(dot)

        # Connect click action
        btn.connect("clicked", lambda b: apply_theme(p_id, self))

        return btn

    def extract_palette_colors(self, preset):
        colors = []
        niri = preset.get("niri", {})
        ring_from = niri.get("focus_ring", {}).get("from")
        ring_to = niri.get("focus_ring", {}).get("to")
        if ring_from:
            colors.append(ring_from)
        if ring_to and ring_to != ring_from:
            colors.append(ring_to)

        ghostty = preset.get("ghostty", {})
        cursor = ghostty.get("cursor_color")
        if cursor and cursor not in colors:
            colors.append(cursor)

        fg = ghostty.get("foreground")
        if fg:
            if not fg.startswith("#"):
                fg = f"#{fg}"
            if fg not in colors and len(colors) < 5:
                colors.append(fg)

        bg = ghostty.get("background")
        if bg:
            if not bg.startswith("#"):
                bg = f"#{bg}"
            if bg not in colors and len(colors) < 5:
                colors.append(bg)

        return colors[:5]

    def filter_theme_card(self, child):
        if not self.search_entry:
            return True
        query = self.search_entry.get_text().strip().casefold()
        if not query:
            return True
        preset = self.presets_by_id.get(child.get_child().get_name(), {})
        searchable = " ".join((preset.get("name", ""), preset.get("id", ""))).casefold()
        return query in searchable

    def on_search_changed(self, entry):
        self.flow.invalidate_filter()
        self.update_footer()

    def update_footer(self):
        visible = sum(1 for _, button in self.card_buttons if button.get_parent().get_child_visible())
        total = len(self.card_buttons)
        if self.footer_label:
            self.footer_label.set_text(f"Темы: {visible}/{total}  ·  Enter применить первую  ·  Esc закрыть")

    def on_key_pressed(self, controller, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.quit()
            return True

        # Number shortcuts 1..9
        if Gdk.KEY_1 <= keyval <= Gdk.KEY_9:
            win = self.get_active_window()
            if win and win.get_focus() == self.search_entry:
                return False
            num = keyval - Gdk.KEY_1
            if 0 <= num < len(self.presets):
                apply_theme(self.presets[num].get("id"), self)
                return True

        # Enter / Space on focused card
        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_space):
            win = self.get_active_window()
            if win:
                focused = win.get_focus()
                if focused == self.search_entry:
                    for preset_id, button in self.card_buttons:
                        if button.get_parent().get_child_visible():
                            apply_theme(preset_id, self)
                            return True
                    if self.footer_label:
                        self.footer_label.set_text("Совпадений нет")
                    return True
                for p_id, btn in self.card_buttons:
                    if focused == btn or (focused and btn.is_ancestor(focused)):
                        apply_theme(p_id, self)
                        return True

        return False


def main():
    app = ThemeMenuApp()
    return app.run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
