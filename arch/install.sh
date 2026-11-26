#!/usr/bin/env bash
# Установщик Spike-dotfiles для Arch Linux / CachyOS / EndeavourOS
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_DIR="$REPO_DIR/arch"
BACKUP_DIR="$HOME/.config-backup-spike-$(date +%Y%m%d-%H%M%S)"
INSTALL_PKGS=1
NONINTERACTIVE=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --no-packages) INSTALL_PKGS=0 ;;
    --yes|-y) NONINTERACTIVE=1 ;;
    --force) FORCE=1 ;;
    -h|--help)
      cat <<EOF
Использование: $0 [--no-packages] [--yes] [--force]
  --no-packages   Не ставить пакеты через pacman/AUR, только разложить конфиги и скрипты
  --yes, -y       Передать --noconfirm в pacman/AUR
  --force         Разрешить запуск даже на NixOS
EOF
      exit 0
      ;;
    *) echo "Неизвестный флаг: $arg" >&2; exit 2 ;;
  esac
done

if [ -f /etc/NIXOS ] && [ "$FORCE" -ne 1 ]; then
  echo "Этот установщик предназначен для Arch-подобных дистрибутивов, не для NixOS (передайте --force, если точно уверены)." >&2
  exit 1
fi

log()  { printf '\033[1;34m[spike-arch]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }

PACMAN_PKGS=(
  niri ghostty fish starship fastfetch jq rofi
  noctalia adw-gtk-theme papirus-icon-theme
  dolphin firefox playerctl wireplumber
  grim slurp wl-clipboard cliphist swaybg hyprpicker
  tesseract tesseract-data-eng tesseract-data-rus zbar ffmpeg libnotify
  btop cava bat eza zoxide fzf yazi satty
  python python-gobject gtk4 libadwaita xdg-utils
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
  base-devel pkgconf wayland wayland-protocols
)

AUR_PKGS=(
  zen-browser-bin
  catppuccin-cursors-mocha
  wl-clip-persist
  mpvpaper
  songrec
  xwayland-satellite
)

if [ "$INSTALL_PKGS" -eq 1 ]; then
  if command -v pacman >/dev/null 2>&1; then
    PAC_FLAGS=(--needed)
    [ "$NONINTERACTIVE" -eq 1 ] && PAC_FLAGS+=(--noconfirm)
    log "Устанавливаю пакеты (Niri, Noctalia, темы, утилиты) через pacman..."
    sudo pacman -S "${PAC_FLAGS[@]}" "${PACMAN_PKGS[@]}"
  else
    warn "pacman не найден — пропускаю установку системных пакетов."
  fi

  AUR_HELPER=""
  for h in paru yay; do
    command -v "$h" >/dev/null 2>&1 && { AUR_HELPER="$h"; break; }
  done

  if [ -n "$AUR_HELPER" ]; then
    AUR_FLAGS=(--needed)
    [ "$NONINTERACTIVE" -eq 1 ] && AUR_FLAGS+=(--noconfirm)
    log "Устанавливаю пакеты из AUR (Zen Browser, курсор, mpvpaper, songrec...) через $AUR_HELPER..."
    "$AUR_HELPER" -S "${AUR_FLAGS[@]}" "${AUR_PKGS[@]}" || warn "Некоторые AUR-пакеты не установились — продолжим с тем, что есть."
  else
    warn "paru/yay не найдены. При желании поставьте из AUR: ${AUR_PKGS[*]}"
  fi
fi

backup_if_exists() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    mkdir -p "$BACKUP_DIR"
    local rel="${target#"$HOME/"}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$target" "$BACKUP_DIR/$rel" 2>/dev/null || true
  fi
}

install_file() {
  local src="$1" dst="$2" mode="${3:-0644}"
  backup_if_exists "$dst"
  mkdir -p "$(dirname "$dst")"
  install -m "$mode" "$src" "$dst"
}

log "Раскладываю конфиги в ~/.config (бэкап при наличии: $BACKUP_DIR)..."
install_file "$ARCH_DIR/config/niri/config.kdl"             "$HOME/.config/niri/config.kdl" 0644
install_file "$REPO_DIR/theme.kdl"                          "$HOME/.config/niri/theme.kdl" 0644
install_file "$ARCH_DIR/config/niri/autostart.sh"           "$HOME/.config/niri/autostart.sh" 0755
install_file "$ARCH_DIR/config/ghostty/config"              "$HOME/.config/ghostty/config" 0644
install_file "$ARCH_DIR/config/fish/config.fish"            "$HOME/.config/fish/config.fish" 0644
install_file "$ARCH_DIR/config/starship.toml"               "$HOME/.config/starship.toml" 0644
install_file "$ARCH_DIR/config/fastfetch/config.jsonc"      "$HOME/.config/fastfetch/config.jsonc" 0644
install_file "$REPO_DIR/assets/fastfetch/Easy.png"          "$HOME/.config/fastfetch/logo.png" 0644
install_file "$REPO_DIR/theme-selector.rasi"                "$HOME/.config/rofi/theme-selector.rasi" 0644
install_file "$ARCH_DIR/config/rofi/config.rasi"            "$HOME/.config/rofi/config.rasi" 0644
install_file "$ARCH_DIR/config/gtk-3.0/settings.ini"        "$HOME/.config/gtk-3.0/settings.ini" 0644
install_file "$ARCH_DIR/config/gtk-4.0/settings.ini"        "$HOME/.config/gtk-4.0/settings.ini" 0644
install_file "$ARCH_DIR/config/icons/default/index.theme"   "$HOME/.local/share/icons/default/index.theme" 0644
install_file "$ARCH_DIR/config/noctalia/palettes/Nullscapes.json" "$HOME/.config/noctalia/palettes/Nullscapes.json" 0644

backup_if_exists "$HOME/.config/noctalia/config.toml"
mkdir -p "$HOME/.config/noctalia" "$HOME/Pictures/Screenshots"
sed "s|__HOME__|$HOME|g" "$ARCH_DIR/config/noctalia/config.toml" > "$HOME/.config/noctalia/config.toml"

mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/90-spike-local-bin.conf" <<'EOF'
PATH=$HOME/.local/bin:$PATH
EOF

# Прописываем реальный путь к репозиторию в presets.json
backup_if_exists "$HOME/.config/theme-manager/presets.json"
mkdir -p "$HOME/.config/theme-manager"
sed "s|~/Spike-dotfiles|$REPO_DIR|g" "$ARCH_DIR/config/theme-manager/presets.json" > "$HOME/.config/theme-manager/presets.json"

log "Устанавливаю скрипты в ~/.local/bin..."
mkdir -p "$HOME/.local/bin"
for f in theme-apply theme-menu theme-restore lava; do
  install -m 0755 "$ARCH_DIR/bin/$f" "$HOME/.local/bin/$f"
done
for f in color-pick discord-compress ocr-grab qr-scan songrec-grab obs-control; do
  install -m 0755 "$REPO_DIR/scripts/$f" "$HOME/.local/bin/$f"
done
install -m 0755 "$REPO_DIR/scripts/theme-menu-gui.py"      "$HOME/.local/bin/theme-menu-gui"
install -m 0755 "$REPO_DIR/scripts/theme-inject-zen.py"    "$HOME/.local/bin/theme-inject-zen"
install -m 0755 "$REPO_DIR/scripts/theme-inject-apps.py"   "$HOME/.local/bin/theme-inject-apps"
install -m 0755 "$REPO_DIR/scripts/theme-zen-bridge.py"    "$HOME/.local/bin/theme-zen-bridge"
install -m 0755 "$REPO_DIR/scripts/wallpaper-autopause.py" "$HOME/.local/bin/wallpaper-autopause"

log "Настраиваю профили Zen Browser и Firefox..."
ensure_zen_root() {
  local root="$1"
  local has_profile=0
  if [ -d "$root" ]; then
    for d in "$root"/*; do
      [ -d "$d" ] && { [ -f "$d/prefs.js" ] || [ -d "$d/chrome" ]; } && { has_profile=1; break; }
    done
  fi
  if [ "$has_profile" -eq 0 ]; then
    mkdir -p "$root/default-spike/chrome"
    cat > "$root/profiles.ini" <<'EOF'
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=default-spike
IsRelative=1
Path=default-spike
Default=1
EOF
  fi
  for d in "$root"/*; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in
      newtab|"Crash Reports"|"Pending Pings") continue ;;
    esac
    { [ -f "$d/prefs.js" ] || [ -d "$d/chrome" ]; } || continue
    mkdir -p "$d/chrome" "$d/extensions"
    sed "s|__HOME__|$HOME|g" "$ARCH_DIR/config/zen/user.js" > "$d/user.js"
    install -m 0644 "$ARCH_DIR/config/zen/chrome/userChrome.css" "$d/chrome/userChrome.css"
    install -m 0644 "$ARCH_DIR/config/zen/chrome/userContent.css" "$d/chrome/userContent.css"
    install -m 0644 "$REPO_DIR/vendor/ryoku/zen/ryoku-zen-palette-1.0.3.xpi" "$d/extensions/ryoku-zen-palette@local.xpi"
  done
}

ensure_zen_root "$HOME/.zen"
ensure_zen_root "$HOME/.config/zen"

for ff_base in "$HOME/.mozilla/firefox" "$HOME/.config/mozilla/firefox"; do
  [ -d "$ff_base" ] || continue
  for d in "$ff_base"/*; do
    [ -d "$d" ] || continue
    { [ -f "$d/prefs.js" ] || [ -d "$d/chrome" ]; } || continue
    mkdir -p "$d/chrome"
    install -m 0644 "$ARCH_DIR/config/firefox/user.js" "$d/user.js"
    install -m 0644 "$ARCH_DIR/config/firefox/chrome/userChrome.css" "$d/chrome/userChrome.css"
  done
done

# Инициализируем динамические цвета Zen / Firefox / Vesktop / VSCode
export PATH="$HOME/.local/bin:$PATH"
ZEN_NEWTAB_TEMPLATE="$REPO_DIR/zen-newtab/index.html" theme-inject-zen >/dev/null 2>&1 || true
theme-inject-apps >/dev/null 2>&1 || true

# Собираем лёгкий нативный видео-плеер обоев ryoku-livewall
if command -v gcc >/dev/null 2>&1 && command -v wayland-scanner >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1; then
  log "Собираю ryoku-livewall в ~/.local/bin/ryoku-livewall..."
  if bash "$REPO_DIR/vendor/ryoku/livewall/build.sh" "$HOME/.local/bin/ryoku-livewall"; then
    chmod 0755 "$HOME/.local/bin/ryoku-livewall"
  else
    warn "Не удалось собрать ryoku-livewall — theme-apply автоматически использует mpvpaper/swaybg."
  fi
else
  warn "Не хватает gcc/wayland-scanner/pkg-config для сборки ryoku-livewall — будет использоваться mpvpaper/swaybg."
fi

log "Устанавливаю systemd --user юниты..."
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/theme-zen-bridge.service" <<EOF
[Unit]
Description=Theme Manager Zen Browser live SSE palette bridge
After=default.target

[Service]
Environment="ZEN_NEWTAB_TEMPLATE=$REPO_DIR/zen-newtab/index.html"
ExecStart=$HOME/.local/bin/theme-zen-bridge
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target default.target
EOF
install -m 0644 "$ARCH_DIR/systemd/wallpaper-autopause.service" "$HOME/.config/systemd/user/wallpaper-autopause.service"

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now theme-zen-bridge.service >/dev/null 2>&1 || true
  systemctl --user enable wallpaper-autopause.service >/dev/null 2>&1 || true
fi

if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface cursor-theme 'catppuccin-mocha-dark-cursors' >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface cursor-size 20 >/dev/null 2>&1 || true
fi

if command -v niri >/dev/null 2>&1; then
  log "Проверяю конфиг Niri..."
  niri validate || warn "niri validate сообщил замечания — проверьте ~/.config/niri/config.kdl"
fi

# Если установка запущена внутри живой Wayland/Niri сессии — применяем всё на лету
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
  log "Применяю конфиг Niri, панель Noctalia и тему прямо сейчас..."
  niri msg action load-config-file >/dev/null 2>&1 || true
  if command -v noctalia >/dev/null 2>&1; then
    pgrep -x noctalia >/dev/null || nohup noctalia >/dev/null 2>&1 &
    sleep 1
  fi
  systemctl --user enable --now wallpaper-autopause.service >/dev/null 2>&1 || true
  theme-apply >/dev/null 2>&1 || true
fi

log "Готово!"
cat <<EOF

Дальнейшие шаги:
  1. Для применения всех переменных окружения (курсор, GTK, ~/.local/bin) перезайдите в сессию Niri.
  2. Нажмите Mod+Shift+T для выбора темы или Mod+D для лаунчера Noctalia.
  3. Zen Browser (Mod+B) уже настроен со стеклом, новой вкладкой и автосинхронизацией тем через 127.0.0.1:47616.
EOF
