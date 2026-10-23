#!/usr/bin/env python3
"""
Visual Theme Switcher GUI for Niri / Wayland
Modern Libadwaita / GTK4 interface displaying cards with wallpaper thumbnails,
palette previews, keyboard and mouse navigation.
"""

import os
import sys
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
    background-color: #0f1218;
}

.theme-card {
    background-color: #161a23;
    border: 1px solid #242b3b;
    border-radius: 14px;
    padding: 10px;
    margin: 6px;
    transition: all 150ms ease-in-out;
}

.theme-card:hover {
    background-color: #1f2533;
    border-color: #5d78b6;
}

.theme-card:focus, .theme-card:focus-visible {
    border-color: #7aa2f7;
    background-color: #222938;
    box-shadow: 0 0 12px rgba(122, 162, 247, 0.45);
}

.theme-card.active-theme {
    border-color: #48bb78;
    box-shadow: 0 0 10px rgba(72, 187, 120, 0.35);
}

.card-title {
    font-size: 13.5px;
    font-weight: 700;
    color: #e5eaf5;
    margin-top: 6px;
    margin-bottom: 4px;
}

.badge-active {
    background-color: #143521;
    color: #48bb78;
    border: 1px solid #2f7347;
    border-radius: 999px;
    padding: 2px 8px;
    font-size: 10.5px;
    font-weight: 700;
}

.badge-index {
    background-color: #222938;
    color: #8c9cb8;
    border-radius: 6px;
    padding: 1px 6px;
    font-size: 10.5px;
    font-weight: 600;
}

.color-dot {
    border-radius: 999px;
    min-width: 14px;
    min-height: 14px;
    border: 1px solid rgba(255, 255, 255, 0.18);
}

.thumb-frame {
    border-radius: 10px;
    background-color: #0b0d13;
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
        subprocess.Popen(["theme-apply", preset_id])
    except Exception as e:
        print(f"Error executing theme-apply {preset_id}: {e}", file=sys.stderr)
    app.quit()


class ThemeMenuApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.spike.theme_menu_gui", flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.presets = []
        self.current_theme = ""
        self.card_buttons = []
        self.flow = None

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
        win.set_default_size(960, 620)

        # Root box
        root_box = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0)
        win.set_content(root_box)

        # Header bar
        header = Adw.HeaderBar.new()
        header.set_show_end_title_buttons(True)
        title_widget = Adw.WindowTitle.new(
            "Темы оформления",
            "Enter / клик для применения • Esc для отмены • 1–7 быстрый выбор"
        )
        header.set_title_widget(title_widget)
        root_box.append(header)

        # Scrolled container
        scroller = Gtk.ScrolledWindow.new()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        root_box.append(scroller)

        # FlowBox for responsive cards
        self.flow = Gtk.FlowBox.new()
        self.flow.set_valign(Gtk.Align.START)
        self.flow.set_halign(Gtk.Align.CENTER)
        self.flow.set_max_children_per_line(4)
        self.flow.set_min_children_per_line(3)
        self.flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.flow.set_homogeneous(True)
        self.flow.set_row_spacing(10)
        self.flow.set_column_spacing(10)
        self.flow.set_margin_top(16)
        self.flow.set_margin_bottom(16)
        self.flow.set_margin_start(16)
        self.flow.set_margin_end(16)
        scroller.set_child(self.flow)

        initial_child = None

        for idx, preset in enumerate(self.presets):
            card_btn = self.create_theme_card(preset, idx + 1)
            self.flow.append(card_btn)
            self.card_buttons.append((preset.get("id"), card_btn))

            if preset.get("id") == self.current_theme:
                initial_child = card_btn

        # Keyboard shortcuts controller
        key_ctrl = Gtk.EventControllerKey.new()
        key_ctrl.connect("key-pressed", self.on_key_pressed)
        win.add_controller(key_ctrl)

        win.present()

        # Focus active theme card
        if initial_child:
            GLib.idle_add(lambda: initial_child.grab_focus())
        elif self.card_buttons:
            GLib.idle_add(lambda: self.card_buttons[0][1].grab_focus())

    def create_theme_card(self, preset, index):
        p_id = preset.get("id", "")
        p_name = preset.get("name", p_id)
        p_icon = preset.get("icon", "🎨")
        is_active = (p_id == self.current_theme)

        btn = Gtk.Button.new()
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
        if fallback_img and os.path.exists(fallback_img):
            pic = Gtk.Picture.new_for_filename(fallback_img)
            pic.set_content_fit(Gtk.ContentFit.COVER)
            pic.set_size_request(210, 118)
            thumb_frame.append(pic)
        else:
            placeholder = Gtk.Label.new(p_icon)
            placeholder.set_valign(Gtk.Align.CENTER)
            placeholder.set_vexpand(True)
            thumb_frame.append(placeholder)

        card_vbox.append(thumb_frame)

        # Title & badge row
        title_row = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6)
        card_vbox.append(title_row)

        idx_label = Gtk.Label.new(str(index))
        idx_label.add_css_class("badge-index")
        title_row.append(idx_label)

        title_lbl = Gtk.Label.new(f"{p_icon} {p_name.split(' (')[0]}")
        title_lbl.add_css_class("card-title")
        title_lbl.set_halign(Gtk.Align.START)
        title_lbl.set_hexpand(True)
        title_lbl.set_ellipsize(3) # PANGO_ELLIPSIZE_END
        title_row.append(title_lbl)

        if is_active:
            active_badge = Gtk.Label.new("✓ Активна")
            active_badge.add_css_class("badge-active")
            title_row.append(active_badge)

        # Color dots row
        dots_row = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 5)
        dots_row.set_halign(Gtk.Align.START)
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

    def on_key_pressed(self, controller, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.quit()
            return True

        # Number shortcuts 1..9
        if Gdk.KEY_1 <= keyval <= Gdk.KEY_9:
            num = keyval - Gdk.KEY_1
            if 0 <= num < len(self.presets):
                apply_theme(self.presets[num].get("id"), self)
                return True

        # Enter / Space on focused card
        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_space):
            focused = self.get_active_window().get_focus()
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
