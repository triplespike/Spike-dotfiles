{ config, pkgs, lib, inputs, ... }:

let
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

    # 3. Фоновые демоны, Noctalia и обои
    pgrep -x wl-clip-persist >/dev/null || wl-clip-persist --clipboard regular &
    pgrep -x xwayland-satellite >/dev/null || xwayland-satellite &
    pgrep -x noctalia >/dev/null || noctalia &

    # 4. Демон живой стилизации Antigravity 2.0
    if [ -x "$HOME/.local/bin/theme-daemon-antigravity" ]; then
      pgrep -f theme-daemon-antigravity >/dev/null || "$HOME/.local/bin/theme-daemon-antigravity" &
    fi

    # 5. Восстановление активной темы оформления (Theme Manager)
    theme-restore &
  '';

  # Скрипт уведомлений для платы ESP8266 (моргание синим диодом)
  espNotify = pkgs.writeScriptBin "esp-notify" ''
    #!${pkgs.python3}/bin/python3
    import os
    import glob
    import time

    def notify():
        ports = glob.glob('/dev/ttyUSB*') + glob.glob('/dev/ttyACM*')
        if not ports:
            return
        try:
            with open(ports[0], 'wb') as f:
                f.write(b'1')
                f.flush()
            time.sleep(0.05)
        except Exception:
            pass

    if __name__ == "__main__":
        notify()
  '';

  wrapScript = name: path: bins: pkgs.writeShellScriptBin name ''
    export PATH="${pkgs.lib.makeBinPath bins}:$PATH"
    exec ${path} "$@"
  '';

  wrapPyScript = name: path: bins: pkgs.writeShellScriptBin name ''
    export PATH="${pkgs.lib.makeBinPath bins}:$PATH"
    exec ${pkgs.python3}/bin/python3 ${path} "$@"
  '';

  ocrGrab = wrapScript "ocr-grab" ../scripts/ocr-grab [ pkgs.grim pkgs.slurp pkgs.tesseract pkgs.wl-clipboard pkgs.libnotify pkgs.coreutils ];
  qrScan = wrapScript "qr-scan" ../scripts/qr-scan [ pkgs.grim pkgs.slurp pkgs.zbar pkgs.wl-clipboard pkgs.libnotify pkgs.xdg-utils pkgs.coreutils ];
  colorPick = wrapScript "color-pick" ../scripts/color-pick [ pkgs.hyprpicker pkgs.wl-clipboard pkgs.libnotify ];
  songrecGrab = wrapScript "songrec-grab" ../scripts/songrec-grab [ pkgs.songrec pkgs.wl-clipboard pkgs.libnotify ];
  discordCompress = wrapPyScript "discord-compress" ../scripts/discord-compress [ pkgs.ffmpeg pkgs.coreutils ];

  themeZenBridgeBin = pkgs.writeShellScriptBin "theme-zen-bridge" ''
    export ZEN_NEWTAB_TEMPLATE="${../zen-newtab/index.html}"
    export THEME_ZEN_INJECTOR="${pkgs.python3}/bin/python3 ${../scripts/theme-inject-zen.py}"
    exec ${pkgs.python3}/bin/python3 ${../scripts/theme-zen-bridge.py} "$@"
  '';

  wallpaperAutopauseBin = pkgs.writeShellScriptBin "wallpaper-autopause" ''
    export PATH="${pkgs.lib.makeBinPath [ pkgs.niri pkgs.coreutils ]}:$PATH"
    exec ${pkgs.python3}/bin/python3 ${../scripts/wallpaper-autopause.py} "$@"
  '';
in {
  home = {
    packages = [
      espNotify
      ocrGrab
      qrScan
      colorPick
      songrecGrab
      discordCompress
    ];

    pointerCursor = {
      enable = true;
      gtk.enable = true;
      x11.enable = true;
      package = pkgs.catppuccin-cursors.mochaDark;
      name = "catppuccin-mocha-dark-cursors";
      size = 20;
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

  programs.noctalia = {
    enable = true;
    package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      src = pkgs.applyPatches {
        src = old.src;
        patches = [
          ../patches/noctalia-bar-capsule-blur.patch
          ../patches/noctalia-launcher-tab-navigation.patch
          ../patches/noctalia-wpa-supplicant-sdbus-error.patch
        ];
      };
    });
    settings = let
      # Пресеты верхнего бара Noctalia:
      # "classic" — оригинальный проверенный бар Spike (воркспейсы и часы слева, медиа в центре)
      # "island"  — новый парящий симметричный бар (воркспейсы и часы в центре, медиа слева)
      barPresets = {
        classic = {
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

        island = {
          thickness = 40;
          background_opacity = 0.0;
          shadow = false;
          contact_shadow = false;
          margin_ends = 18;
          margin_edge = 10;
          padding = 6;
          widget_spacing = 8;
          capsule = false;
          start = [ "group:quick" ];
          center = [ "group:island" ];
          end = [ "group:signal" ];
          capsule_group = [
            {
              id = "quick";
              members = [ "launcher" "wallpaper" "media" "audio_visualizer" ];
              fill = "surface_variant";
              border = "outline";
              foreground = "on_surface";
              padding = 10;
              radius = 16;
              opacity = 0.60;
              widget_spacing = 8;
            }
            {
              id = "island";
              members = [ "workspaces" "clock" ];
              fill = "surface_variant";
              border = "outline";
              foreground = "on_surface";
              padding = 10;
              radius = 16;
              opacity = 0.68;
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
      };

      # Активный пресет: "island" для тестирования нового или "classic" для возврата к прежнему
      activeBar = "classic";
    in {
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
          pipe_command = "${pkgs.satty}/bin/satty --filename - --fullscreen --output-filename ${config.home.homeDirectory}/Pictures/Screenshots/Screenshot-%Y-%m-%d_%H-%M-%S.png";
          save_to_file = false;
          copy_to_clipboard = false;
        };
      };
      bar.main = barPresets.${activeBar};
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

  wayland.windowManager.niri = {
    enable = true;
    package = null;
    systemd.enable = false;
    xwaylandSatellitePackage = null;
    portalPackage = null;
    checkConfig = false;
    extraConfig = builtins.readFile ../niri.kdl;
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

  systemd.user.services = {
    force-ardor-headset = {
      Unit = {
        Description = "Sequential profile toggle for Ardor Headset";
        After = [ "pipewire.service" "pipewire-pulse.service" "wireplumber.service" ];
        Wants = [ "pipewire.service" "pipewire-pulse.service" "wireplumber.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = forceArdorHeadsetProfile;
      };
      Install.WantedBy = [ "default.target" ];
    };

    theme-zen-bridge = {
      Unit = {
        Description = "Theme Manager Zen Browser live SSE palette bridge";
        After = [ "default.target" ];
      };
      Service = {
        ExecStart = "${themeZenBridgeBin}/bin/theme-zen-bridge";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" "default.target" ];
    };

    wallpaper-autopause = {
      Unit = {
        Description = "Auto-pause live wallpapers when fullscreen window or game is active on Niri";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${wallpaperAutopauseBin}/bin/wallpaper-autopause";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };

  xdg = {
    dataFile."icons/default/index.theme".force = lib.mkForce true;
    configFile = {
      "gtk-3.0/settings.ini".force = lib.mkForce true;
      "gtk-4.0/settings.ini".force = lib.mkForce true;
      "niri/autostart.sh" = {
        source = niriAutostart;
        force = lib.mkForce true;
      };
      "niri/config.kdl".force = lib.mkForce true;
      "noctalia/config.toml".force = lib.mkForce true;
    };
  };
}
