{ config, pkgs, lib, inputs, ... }:

let
  esc = builtins.fromJSON ''"\u001b"'';

  satellitePkgs = import inputs.nixpkgs-satellite {
    inherit (pkgs.stdenv.hostPlatform) system;
  };


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

    packages = with pkgs; [
      # Терминальные утилиты и инструменты разработки
      btop
      cava
      cbonsai
      ffmpeg
      jq
      peaclock
      pipes-rs
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
      file-roller
      gnome-text-editor
      gpu-screen-recorder-gtk
      kdePackages.dolphin
      kdePackages.kate
      kdePackages.kio-extras
      kdePackages.partitionmanager
      linux-wallpaperengine
      loupe
      nautilus
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
    };

    file = {
      ".gitconfig" = {
        force = lib.mkForce true;
        text = ''
          [safe]
            directory = /etc/nixos
          [user]
            name = triplespike
            email = vladikzolota12@gmail.com
        '';
      };
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
          source = "${./assets/fastfetch/Easy.png}";
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
          { type = "custom"; format = "${esc}[38;2;121;185;181m╭─   Аппаратная часть ─────────────────────────────${esc}[0m"; }
          { type = "cpu"; key = "│   Процессор  "; keyColor = "bright_cyan"; }
          { type = "gpu"; key = "│ 󰢮  Видеокарта "; keyColor = "bright_cyan"; format = "{1} {2}"; }
          { type = "memory"; key = "│ 󰘚  Память ОЗУ "; keyColor = "bright_cyan"; }
          { type = "disk"; key = "│ 󰋊  Диск (Root)"; folders = "/"; keyColor = "bright_cyan"; }          { type = "custom"; format = "${esc}[38;2;121;185;181m╰───────────────────────────────────────────────────${esc}[0m"; }
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
      };
      shellAbbrs.upp = "pls nixos-rebuild switch --flake /etc/nixos#nixos";
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
          "0=#080B16" "1=#E8758D" "2=#79B9B5" "3=#C8CBE6"
          "4=#6480D7" "5=#8A91E8" "6=#82B8E8" "7=#E8EDFF"
          "8=#46516F" "9=#FF91A5" "10=#A0D8CF" "11=#F1F3FF"
          "12=#829AFF" "13=#B2BBFF" "14=#AED8FF" "15=#FFFFFF"
        ];
        cursor-color = "#A8B7FF";
        selection-background = "#344879";
        selection-foreground = "#FFFFFF";
        command = "fish";
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
            pipe_command = "${pkgs.satty}/bin/satty --filename - --fullscreen --output-filename ${config.home.homeDirectory}/Pictures/Screenshots/Screenshot-%Y-%m-%d_%H-%M-%S.png";
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
            red = "#E8758D";
            green = "#79B9B5";
            yellow = "#C8CBE6";
            blue = "#6480D7";
            magenta = "#8A91E8";
            cyan = "#82B8E8";
            white = "#E8EDFF";
          };
          bright = {
            black = "#46516F";
            red = "#FF91A5";
            green = "#A0D8CF";
            yellow = "#F1F3FF";
            blue = "#829AFF";
            magenta = "#B2BBFF";
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
        theme = spicePkgs.themes.catppuccin;
        colorScheme = "custom";
        customColorScheme = {
          text               = "E8EDFF";
          subtext            = "AFB1B6";
          main               = "080B16";
          main-elevated      = "141B29";
          highlight          = "1B2437";
          highlight-elevated = "283653";
          sidebar            = "080B16";
          player             = "080B16";
          card               = "141B29";
          shadow             = "050711";
          selected-row       = "678FE4";
          button             = "678FE4";
          button-active      = "AB66CC";
          button-disabled    = "46516F";
          tab-active         = "1B2437";
          notification       = "1B2437";
          notification-error = "FD4663";
          equalizer          = "678FE4";
          misc               = "715CD6";

          crust              = "050711";
          mantle             = "080B16";
          base               = "080B16";
          surface0           = "141B29";
          surface1           = "1B2437";
          surface2           = "283653";
          overlay0           = "46516F";
          overlay1           = "616771";
          overlay2           = "AFB1B6";
          blue               = "678FE4";
          mauve              = "AB66CC";
          lavender           = "A8B7FF";
          red                = "FD4663";
          green              = "79B9B5";
          yellow             = "C8CBE6";
        };
        enabledExtensions = with spicePkgs.extensions; [
          adblock
          shuffle
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
      };
      scriptOpts = {
        uosc = {
          timeline_style = "bar";
          timeline_line_width = 3;
          timeline_size = 32;
          progress = "always";
          progress_size = 3;
          controls = "menu,subtitles<has_many_subtitles>,audio<has_many_audio>,video<has_many_video>,gap,prev,play-pause,next,gap,fullscreen";
          color = "foreground=678fe4,foreground_text=e8edff,background=080b16,background_text=e8edff,curtain=080b16,success=79b9b5,error=fd4663";
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
          cwd = { fg = "#79B9B5"; italic = true; };
          hovered = { fg = "#E8EDFF"; bg = "#1B2437"; bold = true; };
          preview_hovered = { underline = true; };
          find_keyword = { fg = "#FD4663"; bold = true; };
          find_position = { fg = "#AB66CC"; normal = true; };
          marker_selected = { fg = "#AB66CC"; bg = "#AB66CC"; };
          marker_copied = { fg = "#79B9B5"; bg = "#79B9B5"; };
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
          permissions_x = { fg = "#79B9B5"; };
          permissions_s = { fg = "#AFB1B6"; };
        };
        filetype = {
          rules = [
            { mime = "image/*"; fg = "#79B9B5"; }
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
    extraConfig = ''
      // Запуск единого скрипта автозапуска
      spawn-at-startup "~/.config/niri/autostart.sh"

      // ==========================================================
      //                   Настройки монитора
      // ==========================================================

      output "HDMI-A-1" {
          mode "1920x1080@75.000"
          scale 1.0
      }

      hotkey-overlay {
          skip-at-startup
      }

      screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"

      // Мягкий, умеренный блюр (меньше радиус и число проходов)
      blur {
          passes 2
          offset 1.5
      }

      // ==========================================================
      //                     Ввод и клавиатура
      // ==========================================================

      input {
          keyboard {
              xkb {
                  layout "us,ru"
                  options "grp:win_space_toggle"
              }
              repeat-delay 300
              repeat-rate 50
          }
      }

      // ==========================================================
      //                   Внешний вид и анимации
      // ==========================================================

      layout {
          gaps 16
          center-focused-column "never"

          // Прозрачный фон столов (чтобы живые обои оставались неподвижными)
          background-color "transparent"

          preset-column-widths {
              proportion 0.25
              proportion 0.5
              proportion 0.75
              proportion 1.0
          }

          // Космический киберпанк-градиент Nullscapes (Blue -> Purple)
          focus-ring {
              width 2.5
              active-gradient from="#678FE4" to="#AB66CC" angle=135 relative-to="workspace-view"
              inactive-color "transparent"
          }

          // Индикатор табов в колонке: неоновая капсула
          tab-indicator {
              hide-when-single-tab
              place-within-column
              gap 6
              width 4
              length total-proportion=0.85
              position "top"
              active-gradient from="#678FE4" to="#AB66CC" angle=90
              inactive-color "#1B243788"
              corner-radius 6
          }

          // Глубокая полупрозрачная тень
          shadow {
              on
              softness 42
              spread 5
              offset x=0 y=10
              color "#050711cc"
          }

          // Внутренние отступы от краёв экрана до ленты
          struts {
              left 10
              right 10
              top 8
              bottom 10
          }
      }

      overview {
          backdrop-color "#080B16dd"
          workspace-shadow {
              on
          }
      }

      animations {
          horizontal-view-movement {
              spring damping-ratio=0.84 stiffness=820 epsilon=0.0001
          }
          window-movement {
              spring damping-ratio=0.82 stiffness=800 epsilon=0.0001
          }
          window-resize {
              spring damping-ratio=0.80 stiffness=900 epsilon=0.0001
          }
          workspace-switch {
              spring damping-ratio=0.85 stiffness=850 epsilon=0.0001
          }
          overview-open-close {
              spring damping-ratio=0.85 stiffness=800 epsilon=0.0001
          }
          screenshot-ui-open {
              duration-ms 200
              curve "ease-out-expo"
          }

          // Плавные анимации открытия и закрытия окон
          window-open {
              duration-ms 200
              curve "ease-out-expo"
          }
          window-close {
              duration-ms 150
              curve "ease-out-quad"
          }
      }

      environment {
          XCURSOR_THEME "catppuccin-mocha-dark-cursors"
          XCURSOR_SIZE "20"
          QT_QPA_PLATFORMTHEME "kde"
      }

      cursor {
          xcursor-theme "catppuccin-mocha-dark-cursors"
          xcursor-size 20
      }

      prefer-no-csd

      // ==========================================================
      //                     Правила для окон
      // ==========================================================

      // Отключаем рентген статики для элементов Noctalia
      layer-rule {
          match namespace="^noctalia-(bar|notification|dock|panel|attached-panel|osd).*"
          background-effect {
              xray false
          }
      }

      // Запрещаем мылить фон за пределами меню
      layer-rule {
          match namespace="^noctalia-backdrop.*"
          background-effect {
              blur false
          }
      }

      // Исключаем размытие и рентген для оверлея скриншотов Noctalia
      layer-rule {
          match namespace="^noctalia-(screenshot-region|annotate).*"
          background-effect {
              blur false
              xray false
          }
      }

      // Закругление углов для всех окон (16px под стиль капсул)
      // draw-border-with-background false предотвращает отрисовку рамки/градиента сплошной плашкой позади полупрозрачных окон
      window-rule {
          geometry-corner-radius 16
          clip-to-geometry true
          draw-border-with-background false
      }

      // Geometry Dash и игры Steam: Direct Scanout, нулевой инпут-лаг, без скруглений и теней
      window-rule {
          match app-id=r#"(?i).*(steam_app_|geometrydash).*"#
          open-fullscreen true
          geometry-corner-radius 0
          clip-to-geometry false
          shadow {
              off
          }
      }

      // Ghostty: ровно 50% экрана (0.5), чтобы идеально вставать рядом с браузером без скролла
      window-rule {
          match app-id="(?i).*ghostty.*"
          default-column-width { proportion 0.5; }
      }

      // Scratchpad терминал Ghostty по центру экрана
      window-rule {
          match app-id="(?i).*ghostty-scratch.*"
          open-floating true
          default-column-width { proportion 0.62; }
          default-window-height { proportion 0.62; }
          geometry-corner-radius 16
          clip-to-geometry true
      }

      // Telegram Desktop: 42% экрана
      window-rule {
          match app-id="(?i).*telegram.*"
          default-column-width { proportion 0.42; }
      }

      // Spotify: умеренная прозрачность к живым обоям стола и легкий блюр (xray false)
      window-rule {
          match app-id="(?i).*spotify.*"
          opacity 0.88
          background-effect {
              blur true
              xray false
          }
      }

      // Vesktop: нативное прозрачное стекло через Electron transparent с аппаратным блюром (иконки 100% плотные)
      window-rule {
          match app-id="(?i).*vesktop.*"
          background-effect {
              blur true
              xray false
          }
      }

      // MPV: аккуратное центрированное плавающее окно матового стекла
      window-rule {
          match app-id="(?i).*mpv.*"
          open-floating true
          default-column-width { proportion 0.65; }
          geometry-corner-radius 16
          clip-to-geometry true
      }

      // Firefox всегда открывается строго на 1-м воркспейсе с шириной 50%
      window-rule {
          match app-id="(?i).*firefox.*"
          open-on-workspace "1"
          default-column-width { proportion 0.5; }
          background-effect {
              blur true
              xray false
          }
      }

      // Плавающее окно Picture-in-Picture (PiP) в углу с закруглениями
      window-rule {
          match app-id="(?i).*firefox.*" title="(?i).*(picture-in-picture|картинка в картинке).*"
          open-floating true
          default-column-width { fixed 520; }
          default-window-height { fixed 292; }
          default-floating-position x=24 y=24 relative-to="bottom-right"
          geometry-corner-radius 14
          clip-to-geometry true
      }

      // Автоматические плавающие окна для системных утилит и медиа
      window-rule {
          match app-id="(?i).*(pavucontrol|satty|blueman-manager|gpu-screen-recorder|org.gnome.Loupe|nm-connection-editor).*"
          open-floating true
      }

      // Автоматические плавающие окна для диалогов и выбора файлов
      window-rule {
          match title="(?i).*(выбор файла|open file|save file|сохранить файл|подтверждение|dialog).*"
          open-floating true
      }

      // ==========================================================
      //                     Горячие клавиши
      // ==========================================================

      binds {
          // Всплывающая интерактивная подсказка всех клавиш (Mod+Shift+?)
          Mod+Shift+Slash { show-hotkey-overlay; }

          // ------------------------------------------------------
          //                   Запуск приложений
          // ------------------------------------------------------
          // Терминал Ghostty
          Mod+Return { spawn "ghostty"; }
          Ctrl+Alt+T { spawn "ghostty"; }

          // Scratchpad плавающий терминал
          Mod+T { spawn "ghostty" "--class=ghostty-scratch" "--title=Scratchpad"; }

          // Файловый менеджер Dolphin
          Mod+E { spawn "dolphin"; }

          // Браузер Firefox
          Mod+B { spawn "firefox"; }

          // Музыкальный плеер Spotify
          Mod+M { spawn "spotify"; }

          // Лаунчер приложений Noctalia (поиск)
          Mod+D { spawn "noctalia" "msg" "panel-toggle" "launcher"; }

          // Центр управления (шторка быстрых настроек)
          Mod+Shift+C { spawn "noctalia" "msg" "panel-toggle" "control-center"; }
          Mod+N { spawn "noctalia" "msg" "settings-toggle"; }
          Mod+P { spawn "noctalia" "msg" "settings-toggle"; }

          // Быстрые панели Noctalia
          Mod+Tab { spawn "noctalia" "msg" "window-switcher"; }
          Mod+X { spawn "noctalia" "msg" "panel-toggle" "session"; }

          // ------------------------------------------------------
          //                   Управление окнами
          // ------------------------------------------------------
          Alt+F4 { close-window; }
          Mod+Q  { close-window; }
          Mod+V  { toggle-window-floating; }
          Mod+Shift+V { switch-focus-between-floating-and-tiling; }
          Mod+W  { toggle-column-tabbed-display; }
          Mod+O  { toggle-overview; }

          // Сшить / расцепить окна в колонке
          Mod+BracketLeft  { consume-or-expel-window-left; }
          Mod+BracketRight { consume-or-expel-window-right; }
          Mod+Comma        { consume-window-into-column; }
          Mod+Period       { expel-window-from-column; }

          // Навигация по ленте (влево / вправо)
          Mod+Left  { focus-column-left; }
          Mod+Right { focus-column-right; }
          Mod+H     { focus-column-left; }
          Mod+L     { focus-column-right; }

          // Перемещение колонок внутри воркспейса (влево / вправо)
          Mod+Shift+Left  { move-column-left; }
          Mod+Shift+Right { move-column-right; }
          Mod+Shift+H     { move-column-left; }
          Mod+Shift+L     { move-column-right; }

          // Навигация по окнам/вкладкам в колонке (вверх / вниз)
          Mod+Page_Down { focus-window-down; }
          Mod+Page_Up   { focus-window-up; }
          Mod+J         { focus-window-down; }
          Mod+K         { focus-window-up; }

          // Перемещение окон внутри колонки (вверх / вниз)
          Mod+Shift+Page_Down { move-window-down; }
          Mod+Shift+Page_Up   { move-window-up; }
          Mod+Shift+J         { move-window-down; }
          Mod+Shift+K         { move-window-up; }

          // Размеры и полный экран (привычная моторика)
          Mod+Up      { maximize-column; }
          Mod+Down    { switch-preset-column-width; }
          Mod+F       { maximize-column; }
          Mod+Ctrl+F  { fullscreen-window; }
          Mod+Shift+F { fullscreen-window; }

          // Выход из сессии Niri в SDDM
          Mod+Shift+E { quit; }

          // ------------------------------------------------------
          //                 Навигация по воркспейсам
          // ------------------------------------------------------

          Mod+1 { focus-workspace 1; }
          Mod+2 { focus-workspace 2; }
          Mod+3 { focus-workspace 3; }
          Mod+4 { focus-workspace 4; }
          Mod+5 { focus-workspace 5; }
          Mod+6 { focus-workspace 6; }
          Mod+7 { focus-workspace 7; }
          Mod+8 { focus-workspace 8; }
          Mod+9 { focus-workspace 9; }

          // Перенос активной колонки на нужный воркспейс
          Mod+Shift+1 { move-column-to-workspace 1; }
          Mod+Shift+2 { move-column-to-workspace 2; }
          Mod+Shift+3 { move-column-to-workspace 3; }
          Mod+Shift+4 { move-column-to-workspace 4; }
          Mod+Shift+5 { move-column-to-workspace 5; }
          Mod+Shift+6 { move-column-to-workspace 6; }
          Mod+Shift+7 { move-column-to-workspace 7; }
          Mod+Shift+8 { move-column-to-workspace 8; }
          Mod+Shift+9 { move-column-to-workspace 9; }

          // Прыжок на предыдущий активный воркспейс
          Mod+Shift+Tab { focus-workspace-previous; }

          // Листание воркспейсов клавишами
          Mod+U         { focus-workspace-down; }
          Mod+I         { focus-workspace-up; }

          // Перемещение текущей колонки на воркспейс выше/ниже
          Mod+Shift+U         { move-column-to-workspace-down; }
          Mod+Shift+I         { move-column-to-workspace-up; }

          // Плавное листание воркспейсов колесиком мыши с зажатым Mod
          Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }
          Mod+WheelScrollUp   cooldown-ms=150 { focus-workspace-up; }

          // ------------------------------------------------------
          //       Мультимедиа и громкость (Noctalia IPC OSD)
          // ------------------------------------------------------

          XF86AudioRaiseVolume allow-when-locked=true { spawn "noctalia" "msg" "volume-up"; }
          XF86AudioLowerVolume allow-when-locked=true { spawn "noctalia" "msg" "volume-down"; }
          XF86AudioMute        allow-when-locked=true { spawn "noctalia" "msg" "volume-mute"; }

          XF86MonBrightnessUp   allow-when-locked=true { spawn "noctalia" "msg" "brightness-up"; }
          XF86MonBrightnessDown allow-when-locked=true { spawn "noctalia" "msg" "brightness-down"; }

          XF86AudioPlay        allow-when-locked=true { spawn "playerctl" "play-pause"; }
          XF86AudioNext        allow-when-locked=true { spawn "playerctl" "next"; }
          XF86AudioPrev        allow-when-locked=true { spawn "playerctl" "previous"; }

          // ------------------------------------------------------
          //                      Скриншоты
          // ------------------------------------------------------
          Print       { spawn "noctalia" "msg" "screenshot-region"; }
          Mod+Shift+S { spawn "noctalia" "msg" "screenshot-region"; }
          Ctrl+Print  { screenshot-screen; }
          Alt+Print   { screenshot-window; }
      }

    '';
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


  xdg = {
    enable = true;

    dataFile."icons/default/index.theme".force = lib.mkForce true;

    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/xhtml+xml" = "firefox.desktop";
        "image/avif" = "org.gnome.Loupe.desktop";
        "image/bmp" = "org.gnome.Loupe.desktop";
        "image/gif" = "org.gnome.Loupe.desktop";
        "image/jpeg" = "org.gnome.Loupe.desktop";
        "image/png" = "org.gnome.Loupe.desktop";
        "image/svg+xml" = "org.gnome.Loupe.desktop";
        "image/webp" = "org.gnome.Loupe.desktop";
        "inode/directory" = "org.kde.dolphin.desktop";
        "text/html" = "firefox.desktop";
        "x-scheme-handler/discord" = "vesktop.desktop";
        "x-scheme-handler/file" = "org.kde.dolphin.desktop";
        "x-scheme-handler/http" = "firefox.desktop";
        "x-scheme-handler/https" = "firefox.desktop";
        "x-scheme-handler/sftp" = "org.kde.dolphin.desktop";
        "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
        "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
      };
    };

    userDirs = {
      enable = true;
      createDirectories = true;
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
            --status-positive: #79B9B5 !important;
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
