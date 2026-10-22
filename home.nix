{ config, pkgs, lib, inputs, ... }:

let
  esc = builtins.fromJSON ''"\u001b"'';

  satellitePkgs = import inputs.nixpkgs-satellite {
    inherit (pkgs.stdenv.hostPlatform) system;
  };

  forceArdorHeadsetProfile = pkgs.writeShellScript "force-ardor-headset-profile" ''
    ${pkgs.coreutils}/bin/sleep 3

    card="alsa_card.usb-XiiSound_Technology_Corporation_Temple_Pro_Black-00"
    pactl="${pkgs.pulseaudio}/bin/pactl"
    amixer="${pkgs.alsa-utils}/bin/amixer"

    # Принудительно выставляем рабочий аналоговый стерео-профиль с микрофоном
    "$pactl" set-card-profile "$card" output:analog-stereo+input:mono-fallback 2>/dev/null || true

    # Разблокируем оба аппаратных стерео-канала на 100%, чтобы чип не глушил второе ухо
    "$amixer" -c Black sset 'PCM',0 100% unmute 2>/dev/null || true
    "$amixer" -c Black sset 'PCM',1 100% unmute 2>/dev/null || true

    sink="$($pactl list sinks short | ${pkgs.gawk}/bin/awk 'tolower($0) ~ /temple/ { print $2; exit }')"
    if [ -n "$sink" ]; then
      "$pactl" set-default-sink "$sink"
    fi
  '';

  niriAutostart = pkgs.writeShellScript "niri-autostart" ''

    # 1. Глушим 25-секундный таймаут доступности D-Bus
    export NO_AT_BRIDGE=1

    # Переменные курсора (размер 20 под Catppuccin)
    export XCURSOR_THEME="catppuccin-mocha-dark-cursors"
    export XCURSOR_SIZE=20

    # 2. Проброс переменных Wayland и курсора в D-Bus и systemd
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=niri DISPLAY XCURSOR_THEME XCURSOR_SIZE
    systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP DISPLAY XCURSOR_THEME XCURSOR_SIZE

    # 3. Фоновые демоны, DMS и обои
    pgrep -x wl-clip-persist >/dev/null || wl-clip-persist --clipboard regular &
    pgrep -x xwayland-satellite >/dev/null || xwayland-satellite &
    pgrep -x noctalia >/dev/null || noctalia &

    # 4. Восстановление активной темы оформления (Theme Manager)
    ${themeRestore}/bin/theme-restore &
  '';

  themeApply = pkgs.writeShellScriptBin "theme-apply" ''
    set -euo pipefail

    TARGET_ID="''${1:-}"
    if [ -z "$TARGET_ID" ]; then
      echo "Использование: theme-apply <preset_id>" >&2
      exit 1
    fi

    PRESETS_FILE="$HOME/.config/theme-manager/presets.json"
    STATE_DIR="$HOME/.local/state/theme-manager"
    CONFIG_DIR="$HOME/.config/theme-manager"
    NIRI_DIR="$HOME/.config/niri"
    GHOSTTY_DIR="$HOME/.config/ghostty"

    mkdir -p "$STATE_DIR" "$CONFIG_DIR" "$NIRI_DIR" "$GHOSTTY_DIR"

    if [ ! -f "$PRESETS_FILE" ]; then
      echo "Файл пресетов не найден: $PRESETS_FILE" >&2
      exit 1
    fi

    PRESET="$(${pkgs.jq}/bin/jq -e --arg id "$TARGET_ID" '.presets[] | select(.id == $id)' "$PRESETS_FILE" 2>/dev/null || true)"
    if [ -z "$PRESET" ]; then
      echo "Пресет '$TARGET_ID' не найден в $PRESETS_FILE" >&2
      exit 1
    fi

    NAME="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.name')"
    ICON="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.icon // "🎨"')"

    stop_wallpapers() {
      systemctl --user stop theme-wallpaper-video.service >/dev/null 2>&1 || true
      systemctl --user stop theme-wallpaper-engine.service >/dev/null 2>&1 || true
      ${pkgs.procps}/bin/pkill -9 -x linux-wallpaper >/dev/null 2>&1 || true
      ${pkgs.procps}/bin/pkill -9 -x .mpvpaper-wrapp >/dev/null 2>&1 || true
      while ${pkgs.procps}/bin/pgrep -x linux-wallpaper >/dev/null 2>&1 || ${pkgs.procps}/bin/pgrep -x .mpvpaper-wrapp >/dev/null 2>&1; do
        ${pkgs.coreutils}/bin/sleep 0.05
      done
    }

    # 1. Управление обоями
    WP_TYPE="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.type // "image"')"
    SCREEN="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.screen // "HDMI-A-1"')"
    FALLBACK="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.fallback_image // ""')"

    if [ "$WP_TYPE" = "video" ]; then
      VIDEO_PATH="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.path // ""')"
      stop_wallpapers
      if [ -n "$FALLBACK" ] && [ -f "$FALLBACK" ]; then
        noctalia msg wallpaper-set "$FALLBACK" >/dev/null 2>&1 || true
      fi
      if [ -n "$VIDEO_PATH" ] && [ -f "$VIDEO_PATH" ]; then
        systemd-run --user --unit=theme-wallpaper-video \
          ${pkgs.mpvpaper}/bin/mpvpaper -p -l background -o "no-audio loop hwdec=nvdec" "$SCREEN" "$VIDEO_PATH" >/dev/null 2>&1
      fi
    elif [ "$WP_TYPE" = "wallpaperengine" ]; then
      WE_ID="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.id')"
      stop_wallpapers
      if [ -n "$FALLBACK" ] && [ -f "$FALLBACK" ]; then
        noctalia msg wallpaper-set "$FALLBACK" >/dev/null 2>&1 || true
      fi
      systemd-run --user --unit=theme-wallpaper-engine \
        linux-wallpaperengine --fps 60 --layer background --screen-root "$SCREEN" --bg "$WE_ID" --clamp repeat --volume 0 --silent --no-audio-processing >/dev/null 2>&1
    elif [ "$WP_TYPE" = "image" ] || [ "$WP_TYPE" = "static" ]; then
      WP_PATH="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.path // ""')"
      stop_wallpapers
      if [ -n "$WP_PATH" ] && [ -f "$WP_PATH" ]; then
        noctalia msg wallpaper-set "$WP_PATH" >/dev/null 2>&1 || true
      fi
    fi

    # 2. Палитра Noctalia
    NOCTALIA_SRC="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.noctalia.source // "custom"')"
    NOCTALIA_PAL="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.noctalia.palette // "Nullscapes"')"
    noctalia msg color-scheme-set "$NOCTALIA_SRC" "$NOCTALIA_PAL" >/dev/null 2>&1 || true

    # 3. Цвета Niri (focus-ring, tab-indicator, shadow, overview)
    RING_FROM="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.niri.focus_ring.from // "#678FE4"')"
    RING_TO="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.niri.focus_ring.to // "#AB66CC"')"
    RING_ANGLE="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.niri.focus_ring.angle // 135')"

    TAB_FROM="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.niri.tab_indicator.from // "#678FE4"')"
    TAB_TO="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.niri.tab_indicator.to // "#AB66CC"')"
    TAB_ANGLE="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.niri.tab_indicator.angle // 90')"
    TAB_INACTIVE="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.niri.tab_indicator.inactive // "#1B243788"')"

    SHADOW_COL="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.niri.shadow // "#050711cc"')"
    OVERVIEW_BG="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.niri.overview_backdrop // "#080B16dd"')"

    cat << EOF > "$NIRI_DIR/theme.kdl.tmp"
layout {
    focus-ring {
        width 2.5
        active-gradient from="$RING_FROM" to="$RING_TO" angle=$RING_ANGLE relative-to="workspace-view"
        inactive-color "transparent"
    }

    tab-indicator {
        hide-when-single-tab
        place-within-column
        gap 6
        width 4
        length total-proportion=0.85
        position "top"
        active-gradient from="$TAB_FROM" to="$TAB_TO" angle=$TAB_ANGLE
        inactive-color "$TAB_INACTIVE"
        corner-radius 6
    }

    shadow {
        on
        softness 42
        spread 5
        offset x=0 y=10
        color "$SHADOW_COL"
    }
}

overview {
    backdrop-color "$OVERVIEW_BG"
}
EOF
    mv "$NIRI_DIR/theme.kdl.tmp" "$NIRI_DIR/theme.kdl"
    niri msg action load-config-file >/dev/null 2>&1 || true

    # 4. Цвета Ghostty
    GH_BG="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.ghostty.background // "080B16"')"
    GH_FG="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.ghostty.foreground // "E8EDFF"')"
    GH_CUR="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.ghostty.cursor_color // "#A8B7FF"')"
    GH_SEL_BG="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.ghostty.selection_background // "#344879"')"
    GH_SEL_FG="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.ghostty.selection_foreground // "#FFFFFF"')"

    cat << EOF > "$GHOSTTY_DIR/theme.conf.tmp"
background = $GH_BG
foreground = $GH_FG
cursor-color = $GH_CUR
selection-background = $GH_SEL_BG
selection-foreground = $GH_SEL_FG
EOF

    echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.ghostty.palette[]?' 2>/dev/null | while read -r p_line; do
      if [ -n "$p_line" ]; then
        echo "palette = $p_line" >> "$GHOSTTY_DIR/theme.conf.tmp"
      fi
    done

    mv "$GHOSTTY_DIR/theme.conf.tmp" "$GHOSTTY_DIR/theme.conf"

    # Мгновенная перезагрузка палитры во всех запущенных окнах Ghostty через D-Bus
    for bus_name in $(busctl --user list 2>/dev/null | awk '/ghostty/ {print $1}'); do
      busctl --user call "$bus_name" /com/mitchellh/ghostty org.gtk.Actions Activate sava{sv} "reload-config" 0 0 >/dev/null 2>&1 || true
    done

    # 5. Сохранение состояния
    echo "$TARGET_ID" > "$STATE_DIR/current"

    # 6. Уведомление
    ${pkgs.libnotify}/bin/notify-send -a "Theme Manager" -i preferences-desktop-theme "Тема применена" "$ICON $NAME" >/dev/null 2>&1 || true
  '';

  themeMenu = pkgs.writeShellScriptBin "theme-menu" ''
    set -euo pipefail

    PRESETS_FILE="$HOME/.config/theme-manager/presets.json"
    if [ ! -f "$PRESETS_FILE" ]; then
      theme-restore --init-only || true
    fi

    CHOICES="$(${pkgs.jq}/bin/jq -r '.presets[] | "\(.icon) \(.name)\t\(.id)"' "$PRESETS_FILE")"
    CHOICES="$CHOICES"$'\n'"🎲 Случайный сетап (Random)\trandom"

    SELECTED="$(printf '%s\n' "$CHOICES" | cut -f1 | noctalia dmenu -p "Выберите тему оформления:" | tr -d '\r\n' || true)"
    if [ -z "$SELECTED" ]; then
      exit 0
    fi

    TARGET_ID="$(printf '%s\n' "$CHOICES" | grep -F "$SELECTED" | cut -f2 | tr -d '\r\n' | head -n 1)"

    if [ "$TARGET_ID" = "random" ]; then
      theme-random
    elif [ -n "$TARGET_ID" ]; then
      theme-apply "$TARGET_ID"
    fi
  '';

  themeRandom = pkgs.writeShellScriptBin "theme-random" ''
    set -euo pipefail

    PRESETS_FILE="$HOME/.config/theme-manager/presets.json"
    STATE_DIR="$HOME/.local/state/theme-manager"

    CURRENT=""
    if [ -f "$STATE_DIR/current" ]; then
      CURRENT="$(cat "$STATE_DIR/current")"
    fi

    IDS="$(${pkgs.jq}/bin/jq -r '.presets[].id' "$PRESETS_FILE")"
    FILTERED="$(printf '%s\n' "$IDS" | grep -v "^''${CURRENT}$" || printf '%s\n' "$IDS")"
    RANDOM_ID="$(printf '%s\n' "$FILTERED" | ${pkgs.coreutils}/bin/shuf -n 1)"

    if [ -n "$RANDOM_ID" ]; then
      theme-apply "$RANDOM_ID"
    fi
  '';

  themeRestore = pkgs.writeShellScriptBin "theme-restore" ''
    set -euo pipefail

    STATE_DIR="$HOME/.local/state/theme-manager"
    CONFIG_DIR="$HOME/.config/theme-manager"

    mkdir -p "$STATE_DIR" "$CONFIG_DIR"

    if [ "''${1:-}" = "--init-only" ]; then
      exit 0
    fi

    ${pkgs.coreutils}/bin/sleep 1.2

    CURRENT="nullscapes"
    if [ -f "$STATE_DIR/current" ]; then
      CURRENT="$(cat "$STATE_DIR/current")"
    fi

    theme-apply "$CURRENT" || true
  '';
in
{
  imports = [
    inputs.noctalia.homeModules.default
    inputs.spicetify-nix.homeManagerModules.default
  ];

  home = {
    username = "spike";
    homeDirectory = "/home/spike";
    stateVersion = "26.05";
    sessionPath = [
      "$HOME/.local/bin"
      "$HOME/.npm-global/bin"
    ];

    packages = with pkgs; [
      # Терминальные утилиты и инструменты разработки
      aider-chat
      btop
      cava
      cbonsai
      antigravity-cli
      codex
      ffmpeg
      jq
      nodejs_22
      opencode
      peaclock
      pipes-rs
      libsecret
      psmisc
      gcc
      mpvpaper
      socat
      (python3.withPackages (ps: with ps; [
        numpy
        onnxruntime
        pillow
      ]))
      wget
      wf-recorder

      # Пользовательские приложения
      inputs.zen-browser.packages."${pkgs.stdenv.hostPlatform.system}".default
      bottles
      file-roller
      gnome-text-editor
      libreoffice
      gpu-screen-recorder-gtk
      kdePackages.dolphin
      kdePackages.kate
      kdePackages.kio-extras
      kdePackages.partitionmanager
      linux-wallpaperengine
      loupe
      nautilus
      prismlauncher
      protonup-qt
      swaybg
      telegram-desktop
      vesktop

      # Инструменты сессии Niri/Wayland
      grim
      matugen
      slurp
      wl-clip-persist
      wl-clipboard
      wtype
      satellitePkgs.xwayland-satellite

      # Управление темами и уведомлениями (Theme Manager)
      libnotify
      themeApply
      themeMenu
      themeRandom
      themeRestore
    ];

    pointerCursor = {
      enable = true;
      gtk.enable = true;
      x11.enable = true;
      package = pkgs.catppuccin-cursors.mochaDark;
      name = "catppuccin-mocha-dark-cursors";
      size = 20;
    };

    sessionVariables = {
      XCURSOR_THEME = "catppuccin-mocha-dark-cursors";
      XCURSOR_SIZE = "20";
      MOZ_ENABLE_WAYLAND = "1";
      DEFAULT_BROWSER = "zen-beta";
      BROWSER = "zen-beta";
      NH_FLAKE = "/etc/nixos";
    };

    file = {
      ".gitconfig" = {
        force = lib.mkForce true;
        text = ''
          [safe]
            directory = /etc/nixos
          [user]
            name = Spike
            email = spike@nixos.local
        '';
      };
      "/home/spike/.gtkrc-2.0".force = lib.mkForce true;
      ".icons/default/index.theme".force = lib.mkForce true;

      ".config/mozilla/firefox/mrf4l2sq.default/user.js" = {
        force = lib.mkForce true;
        text = ''
          user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
          user_pref("layers.acceleration.force-enabled", true);
          user_pref("browser.tabs.firefox-view", false);
        '';
      };

      ".config/mozilla/firefox/mrf4l2sq.default/chrome/userChrome.css" = {
        force = lib.mkForce true;
        text = ''
          /* Nullscapes Minimal Glass Theme */
          :root {
            --toolbar-bgcolor: rgba(8, 11, 22, 0.75) !important;
            --tab-selected-bgcolor: rgba(27, 36, 55, 0.85) !important;
            --lwt-accent-color: #080B16 !important;
            --lwt-text-color: #E8EDFF !important;
            --arrowpanel-background: #141B29 !important;
            --arrowpanel-color: #E8EDFF !important;
            --arrowpanel-border-color: #616771 !important;
          }

          #navigator-toolbox {
            background-color: rgba(8, 11, 22, 0.75) !important;
            backdrop-filter: blur(16px) !important;
            border-bottom: 1px solid rgba(97, 103, 113, 0.25) !important;
          }

          /* Скругление вкладок под стиль капсул */
          .tabbrowser-tab .tab-background {
            border-radius: 10px !important;
            margin-block: 4px !important;
          }

          .tabbrowser-tab[selected="true"] .tab-background {
            background: #1B2437 !important;
            border: 1px solid #678FE4 !important;
          }

          /* Аккуратная адресная строка */
          #urlbar-background {
            border-radius: 12px !important;
            background-color: rgba(20, 27, 41, 0.8) !important;
            border: 1px solid rgba(97, 103, 113, 0.3) !important;
          }

          #urlbar[focused="true"] > #urlbar-background {
            border-color: #678FE4 !important;
            box-shadow: 0 0 0 1px #678FE4 !important;
          }

          /* Стилизация скроллбаров под Nullscapes */
          * {
            scrollbar-color: #678FE4 #080B16 !important;
            scrollbar-width: thin !important;
          }
        '';
      };

      ".config/zen/qn0dspde.Default Profile/user.js" = {
        force = lib.mkForce true;
        text = ''
          user_pref("browser.shell.checkDefaultBrowser", false);
          user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
          user_pref("zen.widget.linux.transparency", true);
          user_pref("zen.theme.acrylic-sidebar", true);
          user_pref("zen.theme.acrylic-urlbar", true);
          user_pref("zen.theme.accent-color", "#678FE4");
          user_pref("zen.theme.border-radius", 14);
          user_pref("zen.theme.content-element-separation", 4);
          user_pref("zen.theme.gradient.show-custom-colors", true);
          user_pref("layers.acceleration.force-enabled", true);
          user_pref("svg.context-properties.content.enabled", true);
          user_pref("layout.css.color-mix.enabled", true);
        '';
      };

      ".config/zen/qn0dspde.Default Profile/chrome/userChrome.css" = {
        force = lib.mkForce true;
        text = ''
          /* Zen Browser — Nullscapes Rice Theme */
          :root {
            --zen-primary-color: #678FE4 !important;
            --zen-colors-primary: #678FE4 !important;
            --zen-colors-primary-foreground: #FFFFFF !important;
            --zen-colors-secondary: #1B2437 !important;
            --zen-colors-tertiary: #141B29 !important;
            --zen-colors-hover-bg: rgba(40, 54, 83, 0.75) !important;
            --zen-colors-border: rgba(103, 143, 228, 0.22) !important;
            --zen-colors-border-contrast: rgba(171, 102, 204, 0.4) !important;
            --zen-colors-input-bg: #141B29 !important;

            --zen-branding-dark: #080B16 !important;
            --zen-branding-bg: #080B16 !important;
            --zen-main-browser-background: #080B16 !important;
            --zen-main-browser-background-toolbar: #080B16 !important;
            --zen-dialog-background: #141B29 !important;
            --zen-urlbar-background: rgba(20, 27, 41, 0.85) !important;
            --zen-border-radius: 14px !important;

            --toolbar-bgcolor: rgba(8, 11, 22, 0.78) !important;
            --tab-selected-bgcolor: #1B2437 !important;
            --lwt-accent-color: #080B16 !important;
            --lwt-text-color: #E8EDFF !important;
            --arrowpanel-background: #141B29 !important;
            --arrowpanel-color: #E8EDFF !important;
            --arrowpanel-border-color: rgba(103, 143, 228, 0.3) !important;
            --toolbar-field-color: #E8EDFF !important;
            --toolbar-field-focus-color: #FFFFFF !important;
          }

          #main-window,
          #zen-main-app-wrapper,
          #navigator-toolbox {
            background-color: var(--zen-main-browser-background) !important;
          }

          #zen-sidebar,
          #navigator-toolbox[zen-floating="true"],
          #TabsToolbar {
            background-color: rgba(14, 20, 33, 0.82) !important;
            backdrop-filter: blur(20px) saturate(135%) !important;
            border-right: 1px solid var(--zen-colors-border) !important;
          }

          .tabbrowser-tab {
            margin-block: 2px !important;
          }

          .tabbrowser-tab .tab-background {
            border-radius: 10px !important;
            transition: all 0.15s ease-in-out !important;
          }

          .tabbrowser-tab:hover .tab-background {
            background-color: var(--zen-colors-hover-bg) !important;
          }

          .tabbrowser-tab[selected="true"] .tab-background,
          .tabbrowser-tab[zen-active="true"] .tab-background {
            background: linear-gradient(135deg, #1B2437 0%, #222F47 100%) !important;
            border: 1px solid rgba(103, 143, 228, 0.55) !important;
            box-shadow: 0 2px 10px rgba(103, 143, 228, 0.22), inset 0 0 8px rgba(103, 143, 228, 0.1) !important;
          }

          .tabbrowser-tab[selected="true"] .tab-label {
            font-weight: 600 !important;
            color: #FFFFFF !important;
          }

          #urlbar,
          .urlbar-background {
            border-radius: 12px !important;
            background-color: var(--zen-urlbar-background) !important;
            border: 1px solid rgba(97, 103, 113, 0.32) !important;
            transition: border-color 0.18s ease, box-shadow 0.18s ease !important;
          }

          #urlbar[focused="true"] .urlbar-background {
            border-color: #678FE4 !important;
            box-shadow: 0 0 0 2px rgba(103, 143, 228, 0.3), 0 4px 18px rgba(0, 0, 0, 0.45) !important;
          }

          #appcontent browser,
          .browserSidebarContainer {
            border-radius: 12px !important;
            overflow: hidden !important;
          }

          menupopup,
          panel[type="arrow"],
          .panel-arrowcontent {
            --panel-background: #141B29 !important;
            --panel-color: #E8EDFF !important;
            --panel-border-color: rgba(103, 143, 228, 0.25) !important;
            border-radius: 12px !important;
          }

          menuitem:hover,
          menu:hover {
            background-color: var(--zen-colors-hover-bg) !important;
            color: #FFFFFF !important;
            border-radius: 6px !important;
          }

          * {
            scrollbar-color: #678FE4 #080B16 !important;
            scrollbar-width: thin !important;
          }
        '';
      };
    };

    activation.prepareCursorDataDir = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      cursor_dir="${config.xdg.dataHome}/icons/default"
      if [ -L "$cursor_dir" ]; then
        run rm "$cursor_dir"
      fi
      run mkdir -p "$cursor_dir"
    '';
  };

  gtk = {
    enable = true;
    font = {
      name = "Noto Sans";
      size = 10;
      package = pkgs.noto-fonts;
    };
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.catppuccin-papirus-folders.override {
        flavor = "mocha";
        accent = "lavender";
      };
    };
    gtk2.extraConfig = ''
      gtk-enable-animations=1
      gtk-primary-button-warps-slider=1
      gtk-toolbar-style=3
      gtk-menu-images=1
      gtk-button-images=1
      gtk-cursor-blink-time=1000
      gtk-cursor-blink=1
      gtk-sound-theme-name="ocean"
    '';
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-button-images = true;
      gtk-cursor-blink = true;
      gtk-cursor-blink-time = 1000;
      gtk-decoration-layout = "icon:minimize,maximize,close";
      gtk-enable-animations = true;
      gtk-menu-images = true;
      gtk-modules = "colorreload-gtk-module";
      gtk-primary-button-warps-slider = true;
      gtk-sound-theme-name = "ocean";
      gtk-toolbar-style = 3;
      gtk-xft-dpi = 98304;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-cursor-blink = true;
      gtk-cursor-blink-time = 1000;
      gtk-decoration-layout = "icon:minimize,maximize,close";
      gtk-enable-animations = true;
      gtk-primary-button-warps-slider = true;
      gtk-sound-theme-name = "ocean";
      gtk-xft-dpi = 98304;
    };
  };

  programs = {
    bash = {
      enable = true;
      initExtra = ''
        fastfetch
      '';
    };

    fastfetch = {
      enable = true;
      settings = {
        logo = {
          type = "kitty-direct";
          source = "/home/spike/.config/fastfetch/Easy.png";
          width = 26;
          height = 13;
          padding = {
            top = 1;
            left = 2;
            right = 4;
          };
        };
        display = {
          separator = " 󰅂 ";
          color.separator = "bright_black";
        };
        modules = [
          { type = "custom"; format = "${esc}[38;2;103;143;228m╭─   Система ──────────────────────────────────────${esc}[0m"; }
          { type = "os"; key = "│   Дистрибутив"; keyColor = "bright_blue"; }
          { type = "kernel"; key = "│ 󰌢  Ядро       "; keyColor = "bright_blue"; }
          { type = "uptime"; key = "│ 󱫐  Аптайм     "; keyColor = "bright_blue"; }
          {
            type = "command";
            key = "│ 󰔠  Возраст ОС ";
            keyColor = "bright_blue";
            text = "echo $(( ($(date +%s) - $(cat ~/.config/fastfetch/install-date 2>/dev/null || stat -c %Y /nix/store 2>/dev/null || stat -c %Y /etc/nixos)) / 86400 )) дней";
          }
          { type = "custom"; format = "${esc}[38;2;103;143;228m╰───────────────────────────────────────────────────${esc}[0m"; }
          { type = "custom"; format = "${esc}[38;2;171;102;204m╭─ 󱂬  Десктоп ──────────────────────────────────────${esc}[0m"; }
          { type = "wm"; key = "│ 󰧨  Композитор "; keyColor = "bright_magenta"; }
          { type = "terminal"; key = "│   Терминал   "; keyColor = "bright_magenta"; }
          { type = "shell"; key = "│ 󰞷  Оболочка   "; keyColor = "bright_magenta"; }
          { type = "display"; key = "│ 󰍹  Монитор    "; keyColor = "bright_magenta"; }
          { type = "custom"; format = "${esc}[38;2;171;102;204m╰───────────────────────────────────────────────────${esc}[0m"; }
          { type = "custom"; format = "${esc}[38;2;125;207;255m╭─   Аппаратная часть ─────────────────────────────${esc}[0m"; }
          { type = "cpu"; key = "│   Процессор  "; keyColor = "bright_cyan"; }
          { type = "gpu"; key = "│ 󰢮  Видеокарта "; keyColor = "bright_cyan"; format = "{1} {2}"; }
          { type = "memory"; key = "│ 󰘚  Память ОЗУ "; keyColor = "bright_cyan"; }
          { type = "disk"; key = "│ 󰋊  NVMe (Root)"; folders = "/"; keyColor = "bright_cyan"; }
          { type = "disk"; key = "│ 󰋊  HDD (Игры) "; folders = "/mnt/storage"; keyColor = "bright_cyan"; }
          { type = "disk"; key = "│ 󰋊  SSD игровой"; folders = "/mnt/ssd"; keyColor = "bright_cyan"; }
          { type = "custom"; format = "${esc}[38;2;125;207;255m╰───────────────────────────────────────────────────${esc}[0m"; }
          { type = "colors"; symbol = "circle"; paddingLeft = 2; }
        ];
      };
    };

    bat = {
      enable = true;
      config = {
        theme = "base16-256";
        pager = "less -FR";
      };
    };

    eza = {
      enable = true;
      enableFishIntegration = true;
      icons = "auto";
      git = true;
      extraOptions = [
        "--group-directories-first"
        "--header"
      ];
    };

    firefox.enable = true;

    fish = {
      enable = true;
      shellAliases = {
        pls = "sudo";
        cat = "bat --paging=never";
        zen = "zen-beta";
        agy-switch = "agy-accounts switch";
        agy-whoami = "agy-accounts status";
        agy-acc1 = "agy-accounts acc1";
        agy-acc2 = "agy-accounts acc2";
      };
      shellAbbrs.upp = "nh os switch";
      plugins = [
        {
          name = "done";
          src = pkgs.fishPlugins.done.src;
        }
        {
          name = "sponge";
          src = pkgs.fishPlugins.sponge.src;
        }
      ];
      interactiveShellInit = ''
        set -g fish_greeting ""

        # Адаптивная подсветка синтаксиса Fish под активную тему терминала
        set -g fish_color_normal normal
        set -g fish_color_command blue --bold
        set -g fish_color_keyword magenta --bold
        set -g fish_color_quote cyan
        set -g fish_color_redirection normal
        set -g fish_color_end magenta
        set -g fish_color_error red --bold
        set -g fish_color_param normal
        set -g fish_color_comment brblack
        set -g fish_color_selection --background=brblack
        set -g fish_color_search_match --background=brblack
        set -g fish_color_operator magenta
        set -g fish_color_escape cyan
        set -g fish_color_autosuggestion brblack
        set -g fish_color_cwd blue
        set -g fish_color_user blue
        set -g fish_color_host magenta
        set -g fish_color_cancel red

        fastfetch
      '';
    };

    satty = {
      enable = true;
      settings = {
        general = {
          fullscreen = true;
          early-exit = true;
          copy-command = "wl-copy";
          corner-roundness = 16;
          initial-tool = "arrow";
        };
        font = {
          family = "JetBrainsMono Nerd Font";
          style = "bold";
        };
      };
    };

    fzf = {
      enable = true;
      enableFishIntegration = true;
    };

    ghostty = {
      enable = true;
      settings = {
        config-file = "?theme.conf";
        font-family = "JetBrainsMono Nerd Font";
        window-width = 96;
        window-height = 25;
        window-save-state = "never";
        window-padding-x = 14;
        window-padding-y = 12;
        window-padding-balance = true;
        cursor-style = "bar";
        cursor-style-blink = true;
        mouse-hide-while-typing = true;
        window-decoration = false;
        background = "080B16";
        foreground = "E8EDFF";
        background-opacity = 0.76;
        background-blur-radius = 20;
        palette = [
          "0=#080B16" "1=#FD4663" "2=#678FE4" "3=#E0AF68"
          "4=#678FE4" "5=#AB66CC" "6=#82B8E8" "7=#E8EDFF"
          "8=#46516F" "9=#FF6B8B" "10=#7DCFFF" "11=#F1F3FF"
          "12=#829AFF" "13=#C77DFF" "14=#AED8FF" "15=#FFFFFF"
        ];
        cursor-color = "#A8B7FF";
        selection-background = "#344879";
        selection-foreground = "#FFFFFF";
        command = "fish";
        keybind = [
          "shift+insert=paste_from_clipboard"
          "ctrl+v=paste_from_clipboard"
          "ctrl+,=unbind"
        ];
        clipboard-read = "allow";
        clipboard-paste-protection = false;
      };
    };

    git.enable = true;

    noctalia = {
      enable = true;
      package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
        src = pkgs.applyPatches {
          src = old.src;
          patches = [ ./patches/noctalia-bar-capsule-blur.patch ];
        };
      });
      settings = {
        backdrop.enabled = false;
        theme = {
          mode = "dark";
          source = "custom";
          custom_palette = "Nullscapes";
        };
        shell = {
          corner_radius_scale = 0.88;
          font_family = "JetBrainsMono Nerd Font";
          panel = {
            transparency_mode = "soft";
            borders = true;
            shadow = true;
          };
          screenshot = {
            freeze_screen = true;
            pipe_to_command = true;
            pipe_command = "${pkgs.satty}/bin/satty --filename - --fullscreen --output-filename /home/spike/Pictures/Screenshots/Screenshot-%Y-%m-%d_%H-%M-%S.png";
            save_to_file = false;
            copy_to_clipboard = false;
          };
        };
        bar.main = {
          thickness = 40;
          background_opacity = 0.0;
          shadow = false;
          contact_shadow = false;
          margin_ends = 18;
          margin_edge = 10;
          padding = 6;
          widget_spacing = 8;
          capsule = false;
          start = [ "group:lunar" ];
          center = [ "group:pulse" ];
          end = [ "group:signal" ];
          capsule_group = [
            {
              id = "lunar";
              members = [ "launcher" "wallpaper" "workspaces" "clock" ];
              fill = "surface_variant";
              border = "outline";
              foreground = "on_surface";
              padding = 10;
              radius = 16;
              opacity = 0.58;
              widget_spacing = 8;
            }
            {
              id = "pulse";
              members = [ "audio_visualizer" "media" "audio_visualizer" ];
              fill = "surface_variant";
              border = "outline";
              foreground = "on_surface";
              padding = 12;
              radius = 16;
              opacity = 0.64;
              widget_spacing = 8;
            }
            {
              id = "signal";
              members = [ "tray" "notifications" "clipboard" "network" "bluetooth" "volume" "brightness" "battery" "control-center" "session" ];
              fill = "surface_variant";
              border = "outline";
              foreground = "on_surface";
              padding = 10;
              radius = 16;
              opacity = 0.58;
              widget_spacing = 8;
            }
          ];
        };
        widget.audio_visualizer = {
          width = 56;
          bands = 20;
          mirrored = true;
          reversed = false;
          centered = true;
          show_when_idle = false;
          color_1 = "#678FE4";
          color_2 = "#AB66CC";
        };
        osd = {
          position = "top_center";
          orientation = "horizontal";
          scale = 1.0;
          background_opacity = 0.85;
          offset_y = 14;
          kinds = {
            volume = true;
            volume_output = true;
            volume_input = true;
            brightness = true;
            wifi = true;
            bluetooth = true;
          };
        };
      };
      customPalettes.Nullscapes.dark = {
        mPrimary = "#678FE4";
        mOnPrimary = "#181C25";
        mSecondary = "#715CD6";
        mOnSecondary = "#EEF4FF";
        mTertiary = "#AB66CC";
        mOnTertiary = "#181B24";
        mError = "#FD4663";
        mOnError = "#181C25";
        mSurface = "#141B29";
        mOnSurface = "#F2F2F3";
        mSurfaceVariant = "#1B2437";
        mOnSurfaceVariant = "#AFB1B6";
        mOutline = "#616771";
        mShadow = "#141B29";
        mHover = "#283653";
        mOnHover = "#F2F2F3";
        terminal = {
          background = "#080B16";
          foreground = "#E8EDFF";
          cursor = "#A8B7FF";
          cursorText = "#090C18";
          selectionBg = "#344879";
          selectionFg = "#FFFFFF";
          normal = {
            black = "#080B16";
            red = "#FD4663";
            green = "#678FE4";
            yellow = "#E0AF68";
            blue = "#678FE4";
            magenta = "#AB66CC";
            cyan = "#82B8E8";
            white = "#E8EDFF";
          };
          bright = {
            black = "#46516F";
            red = "#FF6B8B";
            green = "#7DCFFF";
            yellow = "#F1F3FF";
            blue = "#829AFF";
            magenta = "#C77DFF";
            cyan = "#AED8FF";
            white = "#FFFFFF";
          };
        };
      };
    };

    spicetify =
      let
        spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
      in
      {
        enable = true;
        theme = spicePkgs.themes.sleek;
        colorScheme = "Catppuccin";

        # Кастомные приложения внутри Spotify
        enabledCustomApps = with spicePkgs.apps; [
          marketplace       # Встроенный каталог тем и расширений прямо в приложении
          lyricsPlus        # Альтернативный просмотр текстов
          historyInSidebar  # История треков в боковом меню
          newReleases       # Свежие релизы любимых артистов
        ];

        # Расширения
        enabledExtensions = with spicePkgs.extensions; [
          adblock           # Блокировка рекламы
          shuffle           # Улучшенный Shuffle+
          beautifulLyrics   # Анимированное караоке в стиле Apple Music
          fullAppDisplay    # Полноэкранный плеер с размытой обложкой
          coverAmbience     # Подсветка интерфейса цветом текущего альбома
          songStats         # Показ BPM и тональности трека
          loopyLoop         # Зацикливание любого отрезка трека
          bookmark          # Закладки на интересные моменты
        ];
      };

    starship = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      settings = {
        add_newline = true;
        format = "[](fg:#678FE4)[   ](fg:#080B16 bg:#678FE4)[](fg:#678FE4 bg:#1B2437)$directory$git_branch$git_status$nix_shell$cmd_duration$line_break[╰─](fg:#678FE4) $character";
        character = {
          success_symbol = "[❯](bold #678FE4)[❯](bold #AB66CC)";
          error_symbol = "[❯](bold #FD4663)[❯](bold #FD4663)";
        };
        directory = {
          truncation_length = 3;
          truncation_symbol = "…/";
          truncate_to_repo = false;
          style = "fg:#E8EDFF bg:#1B2437 bold";
          format = "[ $path ]($style)[](fg:#1B2437) ";
        };
        git_branch = {
          style = "fg:#EEF4FF bg:#715CD6 bold";
          format = "[](fg:#715CD6)[ 󰘬 $branch ]($style)";
        };
        git_status = {
          style = "fg:#EEF4FF bg:#715CD6";
          format = "[$all_status$ahead_behind ]($style)[](fg:#715CD6) ";
        };
        nix_shell = {
          style = "fg:#181B24 bg:#AB66CC bold";
          format = "[](fg:#AB66CC)[ 󱄅 nix ]($style)[](fg:#AB66CC) ";
        };
        cmd_duration = {
          min_time = 2000;
          style = "fg:#AFB1B6 bg:#141B29";
          format = "[](fg:#141B29)[ 󱫐 $duration ]($style)[](fg:#141B29) ";
        };
      };
    };

    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };

    mpv = {
      enable = true;
      scripts = with pkgs.mpvScripts; [
        uosc
        thumbfast
        mpris
      ];
      config = {
        osc = false;
        osd-bar = false;
        border = false;
        hwdec = "auto-safe";
        vo = "gpu-next";
        gpu-context = "wayland";
        save-position-on-quit = true;
        sub-auto = "fuzzy";
        sub-font = "JetBrainsMono Nerd Font";
        sub-font-size = 36;
        sub-color = "#E8EDFF";
        sub-border-color = "#080B16";
        sub-border-size = 2.5;
        "autofit-larger" = "80%x85%";
      };
      scriptOpts = {
        uosc = {
          timeline_style = "bar";
          timeline_line_width = 3;
          timeline_size = 32;
          progress = "always";
          progress_size = 3;
          controls = "menu,subtitles<has_many_subtitles>,audio<has_many_audio>,video<has_many_video>,gap,prev,play-pause,next,gap,fullscreen";
          color = "foreground=678fe4,foreground_text=e8edff,background=080b16,background_text=e8edff,curtain=080b16,success=7dcfff,error=fd4663";
          opacity = "timeline=0.85,controls=0.85,timeline_persisted=0.6";
        };
      };
    };

    yazi = {
      enable = true;
      enableFishIntegration = true;
      enableBashIntegration = true;
      settings = {
        mgr = {
          show_hidden = true;
          sort_by = "natural";
          sort_dir_first = true;
          linemode = "size";
        };
        preview = {
          image_filter = "lanczos3";
          max_width = 1200;
          max_height = 1200;
        };
      };
      theme = {
        manager = {
          cwd = { fg = "#7DCFFF"; italic = true; };
          hovered = { fg = "#E8EDFF"; bg = "#1B2437"; bold = true; };
          preview_hovered = { underline = true; };
          find_keyword = { fg = "#FD4663"; bold = true; };
          find_position = { fg = "#AB66CC"; normal = true; };
          marker_selected = { fg = "#AB66CC"; bg = "#AB66CC"; };
          marker_copied = { fg = "#7DCFFF"; bg = "#7DCFFF"; };
          marker_cut = { fg = "#FD4663"; bg = "#FD4663"; };
          tab_active = { fg = "#E8EDFF"; bg = "#1B2437"; bold = true; };
          tab_inactive = { fg = "#AFB1B6"; bg = "#080B16"; };
          border_style = { fg = "#616771"; };
        };
        status = {
          separator_open = "";
          separator_close = "";
          separator_style = { fg = "#1B2437"; bg = "#1B2437"; };
          mode_normal = { fg = "#080B16"; bg = "#678FE4"; bold = true; };
          mode_select = { fg = "#080B16"; bg = "#AB66CC"; bold = true; };
          mode_unset = { fg = "#080B16"; bg = "#FD4663"; bold = true; };
          progress_label = { fg = "#E8EDFF"; bold = true; };
          progress_normal = { fg = "#678FE4"; bg = "#1B2437"; };
          progress_error = { fg = "#FD4663"; bg = "#1B2437"; };
          permissions_t = { fg = "#678FE4"; };
          permissions_r = { fg = "#C8CBE6"; };
          permissions_w = { fg = "#FD4663"; };
          permissions_x = { fg = "#7DCFFF"; };
          permissions_s = { fg = "#AFB1B6"; };
        };
        filetype = {
          rules = [
            { mime = "image/*"; fg = "#7DCFFF"; }
            { mime = "video/*"; fg = "#AB66CC"; }
            { mime = "audio/*"; fg = "#678FE4"; }
            { mime = "application/zip"; fg = "#FD4663"; }
            { mime = "application/tar"; fg = "#FD4663"; }
            { mime = "application/bzip2"; fg = "#FD4663"; }
            { mime = "application/gzip"; fg = "#FD4663"; }
            { mime = "application/x-tar"; fg = "#FD4663"; }
            { mime = "application/x-7z-compressed"; fg = "#FD4663"; }
            { mime = "application/x-rar"; fg = "#FD4663"; }
            { url = "*/"; fg = "#678FE4"; bold = true; }
            { url = "*"; fg = "#E8EDFF"; }
          ];
        };
      };
    };
  };

  wayland.windowManager.niri = {
    enable = true;
    package = null;
    systemd.enable = false;
    xwaylandSatellitePackage = null;
    portalPackage = null;
    checkConfig = false;
    extraConfig = builtins.readFile ./niri.kdl;
  };

  services.swayidle = {
    enable = true;
    systemdTargets = [ "graphical-session.target" ];
    timeouts = [
      {
        timeout = 900; # 15 минут простоя: гашение экранов по DPMS
        command = "${pkgs.niri}/bin/niri msg action power-off-monitors";
        resumeCommand = "${pkgs.niri}/bin/niri msg action power-on-monitors";
      }
    ];
  };

  systemd.user.services.force-ardor-headset = {
    Unit = {
      Description = "Sequential profile toggle for Spooky's Ardor Headset";
      After = [ "pipewire.service" "pipewire-pulse.service" "wireplumber.service" ];
      Wants = [ "pipewire.service" "pipewire-pulse.service" "wireplumber.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = forceArdorHeadsetProfile;
    };
    Install.WantedBy = [ "default.target" ];
  };

  xdg = {
    enable = true;

    dataFile."icons/default/index.theme".force = lib.mkForce true;

    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/xhtml+xml" = "zen-beta.desktop";
        "image/avif" = "org.gnome.Loupe.desktop";
        "image/bmp" = "org.gnome.Loupe.desktop";
        "image/gif" = "org.gnome.Loupe.desktop";
        "image/jpeg" = "org.gnome.Loupe.desktop";
        "image/png" = "org.gnome.Loupe.desktop";
        "image/svg+xml" = "org.gnome.Loupe.desktop";
        "image/webp" = "org.gnome.Loupe.desktop";
        "inode/directory" = "org.kde.dolphin.desktop";
        "text/html" = "zen-beta.desktop";
        "x-scheme-handler/about" = "zen-beta.desktop";
        "x-scheme-handler/discord" = "vesktop.desktop";
        "x-scheme-handler/file" = "org.kde.dolphin.desktop";
        "x-scheme-handler/http" = "zen-beta.desktop";
        "x-scheme-handler/https" = "zen-beta.desktop";
        "x-scheme-handler/sftp" = "org.kde.dolphin.desktop";
        "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
        "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
        "x-scheme-handler/unknown" = "zen-beta.desktop";
      };
    };

    userDirs = {
      enable = true;
      createDirectories = true;
      desktop = "${config.home.homeDirectory}/Desktop";
      documents = "${config.home.homeDirectory}/Documents";
      download = "${config.home.homeDirectory}/Downloads";
      music = "${config.home.homeDirectory}/Music";
      pictures = "${config.home.homeDirectory}/Pictures";
      projects = "${config.home.homeDirectory}/projects";
      publicShare = null;
      templates = null;
      videos = "${config.home.homeDirectory}/Videos";
    };

    configFile = {
      "fastfetch/config.jsonc".force = lib.mkForce true;
      "fish/config.fish".force = lib.mkForce true;
      "ghostty/config".force = lib.mkForce true;
      "gtk-3.0/settings.ini".force = lib.mkForce true;
      "gtk-4.0/settings.ini".force = lib.mkForce true;
      "mimeapps.list".force = lib.mkForce true;
      "niri/autostart.sh" = {
        source = niriAutostart;
        force = lib.mkForce true;
      };
      "niri/config.kdl".force = lib.mkForce true;
      "noctalia/config.toml".force = lib.mkForce true;
      "user-dirs.dirs".force = lib.mkForce true;
      "vesktop/settings/quickCss.css" = {
        force = lib.mkForce true;
        text = ''
          /**
           * @name Nullscapes Cosmic Theme
           * @description Deep dark cyber/cosmic palette matching system rice
           */

          :root {
            /* Backgrounds */
            --background-primary: #080B16 !important;
            --background-secondary: #0D1222 !important;
            --background-secondary-alt: #10162A !important;
            --background-tertiary: #141B29 !important;
            --background-floating: #182033 !important;
            --background-accent: #1B2437 !important;
            --channeltextarea-background: #141B29 !important;
            --activity-card-background: #141B29 !important;

            /* Accents */
            --brand-experiment: #678FE4 !important;
            --brand-experiment-500: #678FE4 !important;
            --brand-experiment-560: #577CCE !important;
            --brand-experiment-600: #496AB8 !important;
            --accent-color: #678FE4 !important;
            --button-accent: #678FE4 !important;

            /* Text & Interactive */
            --text-normal: #E8EDFF !important;
            --text-muted: #AFB1B6 !important;
            --header-primary: #FFFFFF !important;
            --header-secondary: #C8CBE6 !important;
            --interactive-normal: #C8CBE6 !important;
            --interactive-hover: #E8EDFF !important;
            --interactive-active: #FFFFFF !important;
            --interactive-muted: #616771 !important;

            /* Status & Highlights */
            --status-danger: #FD4663 !important;
            --status-positive: #7DCFFF !important;
            --status-warning: #C8CBE6 !important;
            --mention-foreground: #678FE4 !important;
            --mention-background: rgba(103, 143, 228, 0.15) !important;
          }

          /* Rounded corners under system capsule style */
          .visual-refresh [class*="channel_"],
          [class*="member_"],
          [class*="listItem_"] {
            border-radius: 10px !important;
          }

          /* Nullscapes Scrollbars */
          ::-webkit-scrollbar {
            width: 8px !important;
            height: 8px !important;
          }
          ::-webkit-scrollbar-track {
            background: #080B16 !important;
          }
          ::-webkit-scrollbar-thumb {
            background: #1B2437 !important;
            border-radius: 8px !important;
            border: 2px solid #080B16 !important;
          }
          ::-webkit-scrollbar-thumb:hover {
            background: #678FE4 !important;
          }
        '';
      };
    };
  };
}
