#!/usr/bin/env bash
set -uo pipefail

export PATH="$HOME/.local/bin:$PATH"
export NO_AT_BRIDGE=1
export XCURSOR_THEME="${XCURSOR_THEME:-catppuccin-mocha-dark-cursors}"
export XCURSOR_SIZE="${XCURSOR_SIZE:-20}"

# Проброс переменных Wayland/Niri в D-Bus и systemd --user
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=niri DISPLAY NIRI_SOCKET XCURSOR_THEME XCURSOR_SIZE 2>/dev/null || true
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP DISPLAY NIRI_SOCKET XCURSOR_THEME XCURSOR_SIZE 2>/dev/null || true

# Фоновые демоны
command -v wl-clip-persist >/dev/null 2>&1 && { pgrep -x wl-clip-persist >/dev/null || wl-clip-persist --clipboard regular & }
command -v xwayland-satellite >/dev/null 2>&1 && { pgrep -x xwayland-satellite >/dev/null || xwayland-satellite & }
command -v noctalia >/dev/null 2>&1 && { pgrep -x noctalia >/dev/null || noctalia & }

# Восстановление активной темы и обоев
command -v theme-restore >/dev/null 2>&1 && theme-restore &
