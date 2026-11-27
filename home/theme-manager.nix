{ pkgs, lib, ... }:

let
  livewall = pkgs.callPackage ../pkgs/livewall.nix {};

  themeInjectApps = pkgs.writeShellScriptBin "theme-inject-apps" ''
    exec ${pkgs.python3}/bin/python3 ${../scripts/theme-inject-apps.py} "$@"
  '';

  themeApply = pkgs.writeShellScriptBin "theme-apply" ''
    set -euo pipefail

    TARGET_ID="''${1:-}"
    PRESETS_FILE="$HOME/.config/theme-manager/presets.json"
    STATE_DIR="$HOME/.local/state/theme-manager"
    NIRI_DIR="$HOME/.config/niri"
    GHOSTTY_DIR="$HOME/.config/ghostty"

    mkdir -p "$STATE_DIR" "$NIRI_DIR" "$GHOSTTY_DIR"

    if [ ! -f "$PRESETS_FILE" ]; then
      echo "Файл пресетов не найден: $PRESETS_FILE" >&2
      exit 1
    fi

    if [ -z "$TARGET_ID" ]; then
      if [ -f "$STATE_DIR/current" ]; then
        TARGET_ID="$(cat "$STATE_DIR/current")"
      else
        TARGET_ID="nullscapes"
      fi
    fi

    PRESET="$(${pkgs.jq}/bin/jq -c --arg id "$TARGET_ID" '.presets[] | select(.id == $id)' "$PRESETS_FILE" | head -n1)"
    if [ -z "$PRESET" ]; then
      echo "Пресет '$TARGET_ID' не найден в $PRESETS_FILE" >&2
      exit 1
    fi

    NAME="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.name')"
    ICON="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.icon')"

    # 1. Обои (видео через ryoku-livewall / mpvpaper / Workshop ID)
    WP_TYPE="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.type // "video"')"
    SCREEN="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.screen // "HDMI-A-1"')"
    STORE_WP_DIR="${../assets/wallpapers}"

    resolve_wp_path() {
      local raw="$1"
      [ -n "$raw" ] || return 0
      raw="''${raw/#\~/$HOME}"
      if [ -f "$raw" ]; then
        printf '%s' "$raw"
        return 0
      fi
      local base
      base="$(${pkgs.coreutils}/bin/basename "$raw")"
      if [ -f "$STORE_WP_DIR/$base" ]; then
        printf '%s' "$STORE_WP_DIR/$base"
      else
        printf '%s' "$raw"
      fi
    }

    if command -v niri >/dev/null 2>&1; then
      ACTIVE_OUT="$(niri msg -j outputs 2>/dev/null | ${pkgs.jq}/bin/jq -r --arg s "$SCREEN" 'if .[$s] then $s else (keys[0] // "") end' || true)"
      [ -n "$ACTIVE_OUT" ] && SCREEN="$ACTIVE_OUT"
    fi

    stop_wallpapers() {
      ${pkgs.procps}/bin/pkill -CONT -f '(^|/)\.?linux-wallpaperengine([[:space:]]|$)' >/dev/null 2>&1 || true
      ${pkgs.procps}/bin/pkill -CONT -f '(^|/)\.?ryoku-livewall([[:space:]]|$)' >/dev/null 2>&1 || true
      ${pkgs.procps}/bin/pkill -CONT -f '(^|/)\.?mpvpaper(-wrapped)?([[:space:]]|$)' >/dev/null 2>&1 || true
      systemctl --user stop theme-wallpaper-video.service theme-wallpaper-engine.service >/dev/null 2>&1 || true
      systemctl --user reset-failed theme-wallpaper-video.service theme-wallpaper-engine.service >/dev/null 2>&1 || true
      ${pkgs.procps}/bin/pkill -9 -f '(^|/)\.?linux-wallpaperengine([[:space:]]|$)' >/dev/null 2>&1 || true
      ${pkgs.procps}/bin/pkill -9 -f '(^|/)\.?ryoku-livewall([[:space:]]|$)' >/dev/null 2>&1 || true
      ${pkgs.procps}/bin/pkill -9 -f '(^|/)\.?mpvpaper(-wrapped)?([[:space:]]|$)' >/dev/null 2>&1 || true
      local tries=0
      while (${pkgs.procps}/bin/pgrep -f '(^|/)\.?linux-wallpaperengine([[:space:]]|$)' >/dev/null 2>&1 || ${pkgs.procps}/bin/pgrep -f '(^|/)\.?ryoku-livewall([[:space:]]|$)' >/dev/null 2>&1 || ${pkgs.procps}/bin/pgrep -f '(^|/)\.?mpvpaper(-wrapped)?([[:space:]]|$)' >/dev/null 2>&1) && [ "$tries" -lt 40 ]; do
        ${pkgs.coreutils}/bin/sleep 0.05
        tries=$((tries + 1))
      done
      ${pkgs.coreutils}/bin/sleep 0.1
    }

    start_video_bg() {
      local vid="$1"
      [ -n "$vid" ] && [ -f "$vid" ] || return 1
      systemd-run --user --collect --unit=theme-wallpaper-video \
        ${livewall}/bin/ryoku-livewall "$vid" 1920 fill "$SCREEN" >/dev/null || true
      ${pkgs.coreutils}/bin/sleep 0.4
      if ! systemctl --user is-active --quiet theme-wallpaper-video.service; then
        systemd-run --user --collect --unit=theme-wallpaper-video \
          ${pkgs.mpvpaper}/bin/mpvpaper -p -l background -o "no-audio loop hwdec=auto-safe" "$SCREEN" "$vid" >/dev/null || true
        ${pkgs.coreutils}/bin/sleep 0.4
        if ! systemctl --user is-active --quiet theme-wallpaper-video.service; then
          echo "Не удалось запустить видеообои: $vid (оставлен fallback_image)" >&2
          return 1
        fi
      fi
      return 0
    }

    WALLPAPER_STARTED=1
    if [ "$WP_TYPE" = "video" ]; then
      WP_PATH="$(resolve_wp_path "$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.path // ""')")"
      FALLBACK="$(resolve_wp_path "$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.fallback_image // ""')")"
      FALLBACK_VIDEO="$(resolve_wp_path "$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r --arg id "$TARGET_ID" '.wallpaper.fallback_video // ("~/Spike-dotfiles/assets/wallpapers/" + $id + ".mp4")')")"

      stop_wallpapers
      if [ -n "$FALLBACK" ] && [ -f "$FALLBACK" ]; then
        noctalia msg wallpaper-set "$FALLBACK" >/dev/null 2>&1 || true
      fi
      if [ -n "$WP_PATH" ] && [ -f "$WP_PATH" ]; then
        start_video_bg "$WP_PATH" || true
      elif [ -n "$FALLBACK_VIDEO" ] && [ -f "$FALLBACK_VIDEO" ]; then
        start_video_bg "$FALLBACK_VIDEO" || true
      elif [ -z "$FALLBACK" ] || [ ! -f "$FALLBACK" ]; then
        echo "Не найден файл обоев для пресета '$TARGET_ID': $WP_PATH" >&2
        WALLPAPER_STARTED=0
      fi
    elif [ "$WP_TYPE" = "wallpaperengine" ]; then
      WE_ID="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.id // .wallpaper.workshop_id // ""')"
      FALLBACK="$(resolve_wp_path "$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.fallback_image // ""')")"
      FALLBACK_VIDEO="$(resolve_wp_path "$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r --arg id "$TARGET_ID" '.wallpaper.fallback_video // ("~/Spike-dotfiles/assets/wallpapers/" + $id + ".mp4")')")"

      WE_TARGET=""
      if [ -n "$WE_ID" ]; then
        if [ -d "$HOME/.local/share/Steam/steamapps/workshop/content/431960/$WE_ID" ]; then
          WE_TARGET="$WE_ID"
        fi
      fi

      stop_wallpapers
      if [ -n "$FALLBACK" ] && [ -f "$FALLBACK" ]; then
        noctalia msg wallpaper-set "$FALLBACK" >/dev/null 2>&1 || true
      fi

      if [ -n "$WE_TARGET" ]; then
        EXTRA_WE_ARGS=()
        CLAMP_MODE="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.clamp // "clamp"')"
        EXTRA_WE_ARGS+=(--clamp "$CLAMP_MODE")

        skip_clamp_value=0
        while IFS= read -r arg; do
          if [ "$skip_clamp_value" -eq 1 ]; then
            skip_clamp_value=0
            continue
          fi
          if [ "$arg" = "--clamp" ]; then
            skip_clamp_value=1
          elif [ -n "$arg" ]; then
            EXTRA_WE_ARGS+=("$arg")
          fi
        done < <(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.args[]? // empty' 2>/dev/null || true)

        while IFS="=" read -r prop_key prop_val; do
          if [ -n "$prop_key" ]; then
            EXTRA_WE_ARGS+=("--set-property" "$prop_key=$prop_val")
          fi
        done < <(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.properties | to_entries[]? | "\(.key)=\(.value)"' 2>/dev/null || true)

        systemd-run --user --collect --unit=theme-wallpaper-engine \
          --setenv=SDL_AUDIODRIVER=dummy --setenv=PIPEWIRE_AUTOCONNECT=false \
          linux-wallpaperengine --fps 60 --layer background --screen-root "$SCREEN" --bg "$WE_TARGET" --volume 0 --silent --no-audio-processing --noautomute "''${EXTRA_WE_ARGS[@]}" >/dev/null || true
        ${pkgs.coreutils}/bin/sleep 0.6
        if ! systemctl --user is-active --quiet theme-wallpaper-engine.service; then
          echo "Wallpaper Engine не запустился для '$TARGET_ID', пробую fallback." >&2
          [ -f "$FALLBACK_VIDEO" ] && start_video_bg "$FALLBACK_VIDEO" || true
        fi
      elif [ -n "$FALLBACK_VIDEO" ] && [ -f "$FALLBACK_VIDEO" ]; then
        start_video_bg "$FALLBACK_VIDEO" || true
      elif [ -z "$FALLBACK" ] || [ ! -f "$FALLBACK" ]; then
        echo "Сцена Wallpaper Engine '$WE_ID' и fallback_image не найдены для '$TARGET_ID'" >&2
        WALLPAPER_STARTED=0
      fi
    elif [ "$WP_TYPE" = "image" ] || [ "$WP_TYPE" = "static" ]; then
      WP_PATH="$(resolve_wp_path "$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.wallpaper.path // .wallpaper.fallback_image // ""')")"
      stop_wallpapers
      if [ -n "$WP_PATH" ] && [ -f "$WP_PATH" ]; then
        noctalia msg wallpaper-set "$WP_PATH" >/dev/null 2>&1 || true
      else
        echo "Файл обоев не найден: $WP_PATH" >&2
        WALLPAPER_STARTED=0
      fi
    fi

    if [ "$WALLPAPER_STARTED" -ne 1 ]; then
      exit 1
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

    # 5. Цвета Cava и Lavat
    LAVAT_COLOR="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.lavat.color // ""')"
    LAVAT_RIM="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.lavat.rim // ""')"
    if [ -z "$LAVAT_COLOR" ]; then
      LAVAT_COLOR="''${RING_FROM#\#}"
    fi
    if [ -z "$LAVAT_RIM" ]; then
      LAVAT_RIM="''${RING_TO#\#}"
    fi

    cat << EOF > "$STATE_DIR/lavat.conf.tmp"
COLOR="$LAVAT_COLOR"
RIM="$LAVAT_RIM"
EOF
    mv "$STATE_DIR/lavat.conf.tmp" "$STATE_DIR/lavat.conf"

    CAVA_1="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.cava.gradient[0] // ""')"
    CAVA_2="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.cava.gradient[1] // ""')"
    CAVA_3="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.cava.gradient[2] // ""')"
    CAVA_4="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.cava.gradient[3] // ""')"
    CAVA_5="$(echo "$PRESET" | ${pkgs.jq}/bin/jq -r '.cava.gradient[4] // ""')"

    if [ -z "$CAVA_1" ]; then
      CAVA_1="$RING_FROM"
      CAVA_2="$RING_FROM"
      CAVA_3="$RING_TO"
      CAVA_4="$RING_TO"
      CAVA_5="$RING_TO"
    fi

    CAVA_DIR="$HOME/.config/cava"
    mkdir -p "$CAVA_DIR"
    if [ -f "$CAVA_DIR/config" ]; then
      if ! grep -q "^live-config" "$CAVA_DIR/config"; then
        sed -i 's/\[general\]/\[general\]\nlive-config = 1/' "$CAVA_DIR/config"
      fi
      sed -i \
        -e "s|^gradient_color_1 = .*|gradient_color_1 = '$CAVA_1'|" \
        -e "s|^gradient_color_2 = .*|gradient_color_2 = '$CAVA_2'|" \
        -e "s|^gradient_color_3 = .*|gradient_color_3 = '$CAVA_3'|" \
        -e "s|^gradient_color_4 = .*|gradient_color_4 = '$CAVA_4'|" \
        -e "s|^gradient_color_5 = .*|gradient_color_5 = '$CAVA_5'|" \
        "$CAVA_DIR/config"
      ${pkgs.procps}/bin/pkill -USR1 cava >/dev/null 2>&1 || true
    fi

    # 6. Цвета btop
    BTOP_DIR="$HOME/.config/btop"
    mkdir -p "$BTOP_DIR/themes"

    BTOP_TITLE="$RING_FROM"
    BTOP_HI="$RING_TO"
    BTOP_BOX_CPU="$RING_FROM"
    BTOP_BOX_MEM="$RING_TO"
    BTOP_BOX_NET="$RING_FROM"
    BTOP_BOX_PROC="$RING_TO"

    cat << EOF > "$BTOP_DIR/themes/$TARGET_ID.theme.tmp"
# Dynamically generated by Theme Manager for preset: $TARGET_ID
theme[main_bg]=""
theme[main_fg]="#$GH_FG"
theme[title]="$BTOP_TITLE"
theme[hi_fg]="$BTOP_HI"
theme[selected_bg]="$GH_SEL_BG"
theme[selected_fg]="$GH_SEL_FG"
theme[inactive_fg]="#616771"
theme[graph_text]="$BTOP_TITLE"
theme[meter_bg]="$GH_SEL_BG"
theme[proc_misc]="$BTOP_HI"
theme[cpu_box]="$BTOP_BOX_CPU"
theme[mem_box]="$BTOP_BOX_MEM"
theme[net_box]="$BTOP_BOX_NET"
theme[proc_box]="$BTOP_BOX_PROC"
theme[div_line]="$GH_SEL_BG"
theme[temp_start]="$CAVA_1"
theme[temp_mid]="$CAVA_3"
theme[temp_end]="$CAVA_5"
theme[cpu_start]="$CAVA_1"
theme[cpu_mid]="$CAVA_3"
theme[cpu_end]="$CAVA_4"
theme[free_start]="$CAVA_4"
theme[free_mid]="$CAVA_2"
theme[free_end]="$CAVA_1"
theme[cached_start]="$CAVA_1"
theme[cached_mid]="$CAVA_2"
theme[cached_end]="$CAVA_3"
theme[available_start]="$CAVA_4"
theme[available_mid]="$CAVA_2"
theme[available_end]="$CAVA_1"
theme[used_start]="$CAVA_1"
theme[used_mid]="$CAVA_3"
theme[used_end]="$CAVA_4"
theme[download_start]="$CAVA_1"
theme[download_mid]="$CAVA_2"
theme[download_end]="$CAVA_4"
theme[upload_start]="$CAVA_4"
theme[upload_mid]="$CAVA_3"
theme[upload_end]="$CAVA_1"
theme[process_start]="$CAVA_1"
theme[process_mid]="$CAVA_3"
theme[process_end]="$CAVA_4"
EOF
    mv "$BTOP_DIR/themes/$TARGET_ID.theme.tmp" "$BTOP_DIR/themes/$TARGET_ID.theme"
    cp -f "$BTOP_DIR/themes/$TARGET_ID.theme" "$BTOP_DIR/themes/theme-current.theme"

    if [ -f "$BTOP_DIR/btop.conf" ]; then
      sed -i 's/^color_theme = .*/color_theme = "'"$TARGET_ID"'"/' "$BTOP_DIR/btop.conf"
    fi
    ${pkgs.procps}/bin/pkill -SIGUSR2 btop >/dev/null 2>&1 || true

    # 7. Мгновенная перезагрузка работающих экземпляров лавалампы
    ${pkgs.procps}/bin/pkill -USR1 -f "/.*bin/lava" >/dev/null 2>&1 || true

    # 8. Стилизация Antigravity 2.0 (Agy 2)
    if [ -x "$HOME/.local/bin/theme-inject-antigravity" ]; then
      "$HOME/.local/bin/theme-inject-antigravity" "$TARGET_ID" >/dev/null 2>&1 || true
    fi

    # 9. Стилизация Riff Music Player
    if [ -x "$HOME/.local/bin/theme-inject-riff" ]; then
      "$HOME/.local/bin/theme-inject-riff" "$TARGET_ID" >/dev/null 2>&1 || true
    fi

    # 10. Стилизация Zen Browser (userChrome/userContent + custom newtab + live SSE)
    ZEN_NEWTAB_TEMPLATE="${../zen-newtab/index.html}" ${pkgs.python3}/bin/python3 ${../scripts/theme-inject-zen.py} "$TARGET_ID" >/dev/null 2>&1 || true
    ${pkgs.procps}/bin/pkill -USR1 -f "theme-zen-bridge" >/dev/null 2>&1 || true

    # 11. Стилизация Vesktop, VSCode и Firefox
    ${pkgs.python3}/bin/python3 ${../scripts/theme-inject-apps.py} "$TARGET_ID" >/dev/null 2>&1 || true

    # 12. Сохранение состояния
    echo "$TARGET_ID" > "$STATE_DIR/current"

    # 13. Уведомление
    ${pkgs.libnotify}/bin/notify-send -a "Theme Manager" -i preferences-desktop-theme "Тема применена" "$ICON $NAME" >/dev/null 2>&1 || true
  '';

  themePython = pkgs.python3.withPackages (ps: with ps; [
    pygobject3
    pycairo
    pillow
  ]);

  themeTypelibPath = pkgs.lib.makeSearchPath "lib/girepository-1.0" [
    pkgs.libadwaita
    pkgs.gtk4
    pkgs.gtk4-layer-shell
    pkgs.pango.out
    pkgs.graphene
    pkgs.harfbuzz
    pkgs.gdk-pixbuf
    pkgs.glib.out
    pkgs.gobject-introspection
  ];

  themeThumbnails = pkgs.writeShellScriptBin "theme-thumbnails" ''
    export STORE_WP_DIR="''${STORE_WP_DIR:-${../assets/wallpapers}}"
    exec ${themePython}/bin/python3 ${../scripts/theme-thumbnails.py} "$@"
  '';

  themeMenu = pkgs.writeShellScriptBin "theme-menu" ''
    set -euo pipefail
    export PATH="${themeApply}/bin:${themeThumbnails}/bin:${pkgs.rofi}/bin:${pkgs.jq}/bin:$PATH"

    PRESETS_FILE="$HOME/.config/theme-manager/presets.json"
    if [ ! -f "$PRESETS_FILE" ]; then
      theme-restore --init-only || true
    fi

    if [ ! -f "$PRESETS_FILE" ]; then
      echo "Файл пресетов не найден: $PRESETS_FILE" >&2
      exit 1
    fi

    # --gui / --adw: классическое окно Libadwaita
    if [ "''${1:-}" = "--gui" ] || [ "''${1:-}" = "--adw" ]; then
      export GSK_RENDERER="gl"
      export GI_TYPELIB_PATH="${themeTypelibPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
      GUI_SCRIPT="$HOME/Spike-dotfiles/scripts/theme-menu-gui.py"
      [ -f "$GUI_SCRIPT" ] || GUI_SCRIPT="${../scripts/theme-menu-gui.py}"
      if [ -f "$GUI_SCRIPT" ] && [ -n "''${WAYLAND_DISPLAY:-}" ]; then
        exec ${themePython}/bin/python3 "$GUI_SCRIPT"
      fi
    fi

    # По умолчанию: наклонная лента параллелограммов на GTK4 + Layer-Shell + Cairo
    if [ "''${1:-}" != "--rofi" ] && [ -n "''${WAYLAND_DISPLAY:-}" ]; then
      PARA_SCRIPT="$HOME/Spike-dotfiles/scripts/theme-menu-parallelogram.py"
      [ -f "$PARA_SCRIPT" ] || PARA_SCRIPT="${../scripts/theme-menu-parallelogram.py}"
      if [ -f "$PARA_SCRIPT" ]; then
        STORE_WP_DIR="''${STORE_WP_DIR:-${../assets/wallpapers}}"
        STORE_WP_DIR="$STORE_WP_DIR" theme-thumbnails >/dev/null 2>&1 || true
        if ${pkgs.coreutils}/bin/env \
          GDK_BACKEND=wayland \
          GSK_RENDERER=gl \
          GI_TYPELIB_PATH="${themeTypelibPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}" \
          LD_PRELOAD="${pkgs.gtk4-layer-shell}/lib/libgtk4-layer-shell.so''${LD_PRELOAD:+:$LD_PRELOAD}" \
          STORE_WP_DIR="$STORE_WP_DIR" \
          ${themePython}/bin/python3 "$PARA_SCRIPT"; then
          exit 0
        fi
      fi
    fi

    STATE_FILE="$HOME/.local/state/theme-manager/current"
    CURRENT_ID=""
    if [ -f "$STATE_FILE" ]; then
      CURRENT_ID="$(${pkgs.coreutils}/bin/cat "$STATE_FILE" 2>/dev/null | tr -d ' \r\n' || true)"
    fi

    CACHE_DIR="$HOME/.cache/theme-manager/thumbnails"
    mkdir -p "$CACHE_DIR"
    STORE_WP_DIR="${../assets/wallpapers}"
    STORE_WP_DIR="$STORE_WP_DIR" theme-thumbnails >/dev/null 2>&1 || true

    if [ ! -f "$HOME/.config/rofi/theme-colors.rasi" ]; then
      ${themeInjectApps}/bin/theme-inject-apps "$CURRENT_ID" >/dev/null 2>&1 || true
    fi

    THEME_RASI="$HOME/.config/rofi/theme-selector.rasi"
    if [ ! -f "$THEME_RASI" ]; then
      THEME_RASI="${../theme-selector.rasi}"
    fi

    declare -a IDS
    ACTIVE_INDEX=-1
    INDEX=0

    while read -r id; do
      IDS+=("$id")
      if [ "$id" = "$CURRENT_ID" ]; then
        ACTIVE_INDEX=$INDEX
      fi
      INDEX=$((INDEX + 1))
    done < <(${pkgs.jq}/bin/jq -r '.presets[].id' "$PRESETS_FILE")

    ROFI_ARGS=(
      -dmenu
      -i
      -show-icons
      -format "i"
      -p "󰏘  Темы"
      -mesg "← → листать  •  Enter применить  •  Esc закрыть"
      -theme "$THEME_RASI"
    )

    if [ "$ACTIVE_INDEX" -ge 0 ]; then
      ROFI_ARGS+=(-selected-row "$ACTIVE_INDEX" -a "$ACTIVE_INDEX")
    fi

    CHOSEN_INDEX="$(
      while IFS=$'\t' read -r id name icon fallback; do
        fallback="''${fallback/#\~/$HOME}"
        thumb="$CACHE_DIR/''${id}.png"
        if [ ! -f "$thumb" ]; then
          if [ -n "$fallback" ] && [ -f "$fallback" ]; then
            thumb="$fallback"
          elif [ -n "$fallback" ]; then
            base="$(${pkgs.coreutils}/bin/basename "$fallback")"
            [ -f "$STORE_WP_DIR/$base" ] && thumb="$STORE_WP_DIR/$base"
          fi
        fi
        label="$name"
        [ "$id" = "$CURRENT_ID" ] && label="$name  ✦"
        printf '%s\0icon\x1f%s\n' "$label" "$thumb"
      done < <(${pkgs.jq}/bin/jq -r '.presets[] | [ .id, .name, .icon, (.wallpaper.fallback_image // .wallpaper.path // "") ] | @tsv' "$PRESETS_FILE") | ${pkgs.rofi}/bin/rofi "''${ROFI_ARGS[@]}" || true
    )"

    if [ -z "$CHOSEN_INDEX" ]; then
      exit 0
    fi

    TARGET_ID="''${IDS[$CHOSEN_INDEX]:-}"
    if [ -n "$TARGET_ID" ]; then
      theme-apply "$TARGET_ID"
    fi
  '';

  themeRestore = pkgs.writeShellScriptBin "theme-restore" ''
    set -euo pipefail
    export PATH="${themeApply}/bin:$PATH"

    STATE_DIR="$HOME/.local/state/theme-manager"
    CONFIG_DIR="$HOME/.config/theme-manager"

    mkdir -p "$STATE_DIR" "$CONFIG_DIR"
    if [ ! -f "$CONFIG_DIR/presets.json" ]; then
      ${pkgs.coreutils}/bin/cp -f ${../config/theme-manager/presets.json} "$CONFIG_DIR/presets.json"
      ${pkgs.coreutils}/bin/chmod 0644 "$CONFIG_DIR/presets.json"
    fi

    if [ "''${1:-}" = "--init-only" ]; then
      exit 0
    fi

    SCREEN="HDMI-A-1"
    if command -v niri >/dev/null 2>&1; then
      OUT="$(niri msg -j outputs 2>/dev/null | ${pkgs.jq}/bin/jq -r 'keys[0] // ""' || true)"
      [ -n "$OUT" ] && SCREEN="$OUT"
    fi

    attempt=0
    until noctalia msg wallpaper-get "$SCREEN" >/dev/null 2>&1 || [ "$attempt" -ge 80 ]; do
      ${pkgs.coreutils}/bin/sleep 0.25
      attempt=$((attempt + 1))
    done
    ${pkgs.coreutils}/bin/sleep 0.5

    CURRENT="nullscapes"
    if [ -f "$STATE_DIR/current" ]; then
      CURRENT="$(cat "$STATE_DIR/current")"
    fi

    theme-apply "$CURRENT" || true
  '';

  themeLava = pkgs.writeShellScriptBin "lava" ''
    set -u
    STATE_DIR="$HOME/.local/state/theme-manager"
    CONF="$STATE_DIR/lavat.conf"

    CHILD=""
    WATCHER_PID=""
    RELOAD=0

    cleanup() {
      if [ -n "$WATCHER_PID" ]; then
        kill -TERM "$WATCHER_PID" 2>/dev/null || true
      fi
      if [ -n "$CHILD" ]; then
        kill -TERM "$CHILD" 2>/dev/null || true
      fi
      exit 0
    }
    trap cleanup INT TERM HUP EXIT

    do_reload() {
      RELOAD=1
      if [ -n "$CHILD" ]; then
        kill -TERM "$CHILD" 2>/dev/null || true
      fi
    }
    trap do_reload USR1

    # Фоновый наблюдатель за обновлением конфигурации темы
    (
      LAST_M="$(stat -c %Y "$CONF" 2>/dev/null || echo 0)"
      while true; do
        sleep 0.25
        M="$(stat -c %Y "$CONF" 2>/dev/null || echo 0)"
        if [ "$M" != "$LAST_M" ]; then
          LAST_M="$M"
          kill -USR1 $$ 2>/dev/null || exit 0
        fi
      done
    ) &
    WATCHER_PID=$!

    while true; do
      COLOR="678FE4"
      RIM="AB66CC"
      if [ -f "$CONF" ]; then
        # shellcheck disable=SC1090
        source "$CONF"
      fi

      RELOAD=0

      # Проверяем, задал ли пользователь цвет вручную
      HAS_CUSTOM_COLOR=0
      for arg in "$@"; do
        if [ "$arg" = "-c" ] || [ "$arg" = "-k" ]; then
          HAS_CUSTOM_COLOR=1
          break
        fi
      done

      if [ "$HAS_CUSTOM_COLOR" -eq 1 ]; then
        ${pkgs.lavat}/bin/lavat "$@" &
      else
        ${pkgs.lavat}/bin/lavat -g -c "$COLOR" -k "$RIM" -C -G "$@" &
      fi

      CHILD=$!
      wait "$CHILD" 2>/dev/null || true
      CHILD=""

      if [ "$RELOAD" -eq 1 ]; then
        continue
      fi
      break
    done
  '';
in {
  home.packages = with pkgs; [
    libnotify
    themeApply
    themeMenu
    themeRestore
    themeLava
    themeThumbnails
    themeInjectApps
    lavat
  ];

  # Инициализируем стартовые файлы на чистой системе (не перезаписывая существующие)
  # + обновляем динамические цвета Vesktop, VSCode, Firefox, Rofi и Zen при активации
  home.activation.initAppThemeColors = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.coreutils}/bin/mkdir -p \
      "$HOME/.config/niri" \
      "$HOME/.config/rofi" \
      "$HOME/.config/theme-manager" \
      "$HOME/.config/ghostty" \
      "$HOME/.config/fastfetch" \
      "$HOME/.local/state/noctalia/community-palettes"

    if [ ! -e "$HOME/.config/niri/theme.kdl" ]; then
      run ${pkgs.coreutils}/bin/install -m 0644 ${../theme.kdl} "$HOME/.config/niri/theme.kdl"
    fi
    if [ ! -e "$HOME/.config/theme-manager/presets.json" ]; then
      run ${pkgs.coreutils}/bin/install -m 0644 ${../config/theme-manager/presets.json} "$HOME/.config/theme-manager/presets.json"
    fi
    if [ ! -e "$HOME/.config/fastfetch/logo.png" ]; then
      run ${pkgs.coreutils}/bin/install -m 0644 ${../assets/fastfetch/logo.png} "$HOME/.config/fastfetch/logo.png"
    fi
    if [ ! -e "$HOME/.config/kdeglobals" ]; then
      run ${pkgs.coreutils}/bin/install -m 0644 ${../arch/config/kdeglobals} "$HOME/.config/kdeglobals"
    fi
    for pal in ${../arch/config/noctalia/community-palettes}/*.json; do
      base="$(${pkgs.coreutils}/bin/basename "$pal")"
      if [ ! -e "$HOME/.local/state/noctalia/community-palettes/$base" ]; then
        run ${pkgs.coreutils}/bin/install -m 0644 "$pal" "$HOME/.local/state/noctalia/community-palettes/$base"
      fi
    done

    run ${themeInjectApps}/bin/theme-inject-apps || true
    run ${themeThumbnails}/bin/theme-thumbnails || true
    run ${pkgs.coreutils}/bin/env ZEN_NEWTAB_TEMPLATE="${../zen-newtab/index.html}" ${pkgs.python3}/bin/python3 ${../scripts/theme-inject-zen.py} || true
  '';

  xdg.configFile."rofi/theme-selector.rasi" = {
    source = ../theme-selector.rasi;
    force = lib.mkForce true;
  };
}
