{ config, pkgs, lib, inputs, ... }:

{
  home.file = {
    # Замените "default" на имя вашего профиля из ~/.config/mozilla/firefox/profiles.ini
    ".config/mozilla/firefox/default/user.js" = {
      force = lib.mkForce true;
      text = ''
        user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
        user_pref("layers.acceleration.force-enabled", true);
        user_pref("browser.tabs.firefox-view", false);
      '';
    };

    ".config/mozilla/firefox/default/chrome/userChrome.css" = {
      force = lib.mkForce true;
      text = ''
        @import url("theme-colors.css");

        /* Firefox Minimal Glass Theme (synced with Theme Manager) */
        :root {
          --toolbar-bgcolor: var(--ff-toolbar-bg, rgba(8, 11, 22, 0.75)) !important;
          --tab-selected-bgcolor: var(--ff-surface-alt, rgba(27, 36, 55, 0.85)) !important;
          --lwt-accent-color: var(--ff-bg, #080B16) !important;
          --lwt-text-color: var(--ff-fg, #E8EDFF) !important;
          --arrowpanel-background: var(--ff-surface, #141B29) !important;
          --arrowpanel-color: var(--ff-fg, #E8EDFF) !important;
          --arrowpanel-border-color: var(--ff-border, rgba(103, 143, 228, 0.28)) !important;
        }

        #navigator-toolbox {
          background-color: var(--ff-toolbar-bg, rgba(8, 11, 22, 0.75)) !important;
          backdrop-filter: blur(16px) !important;
          border-bottom: 1px solid var(--ff-border, rgba(97, 103, 113, 0.25)) !important;
        }

        /* Скругление вкладок под стиль капсул */
        .tabbrowser-tab .tab-background {
          border-radius: 10px !important;
          margin-block: 4px !important;
        }

        .tabbrowser-tab[selected="true"] .tab-background {
          background: var(--ff-surface-alt, #1B2437) !important;
          border: 1px solid var(--ff-primary, #678FE4) !important;
        }

        /* Аккуратная адресная строка */
        #urlbar-background {
          border-radius: 12px !important;
          background-color: var(--ff-urlbar-bg, rgba(20, 27, 41, 0.8)) !important;
          border: 1px solid var(--ff-border, rgba(97, 103, 113, 0.3)) !important;
        }

        #urlbar[focused="true"] > #urlbar-background {
          border-color: var(--ff-primary, #678FE4) !important;
          box-shadow: 0 0 0 1px var(--ff-primary, #678FE4) !important;
        }

        /* Стилизация скроллбаров под активную тему */
        * {
          scrollbar-color: var(--ff-primary, #678FE4) var(--ff-bg, #080B16) !important;
          scrollbar-width: thin !important;
        }
      '';
    };
  };

  programs = {
    firefox.enable = true;

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

    obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [
        wlrobs
        obs-vaapi
        obs-vkcapture
        obs-pipewire-audio-capture
      ];
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
  };

  xdg = {
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
      "mimeapps.list".force = lib.mkForce true;
      "user-dirs.dirs".force = lib.mkForce true;
    };
  };
}
