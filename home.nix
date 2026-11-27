{ pkgs, lib, inputs, userConfig ? import ./user-config.nix, ... }:

let
  satellitePkgs = import inputs.nixpkgs-satellite {
    inherit (pkgs.stdenv.hostPlatform) system;
  };
in {
  imports = [
    inputs.noctalia.homeModules.default
    inputs.spicetify-nix.homeManagerModules.default
    ./zen-browser.nix
    ./home/theme-manager.nix
    ./home/shell.nix
    ./home/apps.nix
    ./home/desktop.nix
  ];

  home = {
    username = lib.mkDefault userConfig.username;
    homeDirectory = lib.mkDefault "/home/${userConfig.username}";
    stateVersion = lib.mkDefault "26.05";

    sessionPath = [
      "$HOME/.local/bin"
      "$HOME/.npm-global/bin"
    ];

    sessionVariables = {
      XCURSOR_THEME = "catppuccin-mocha-dark-cursors";
      XCURSOR_SIZE = "20";
      MOZ_ENABLE_WAYLAND = "1";
      DEFAULT_BROWSER = "zen-beta";
      BROWSER = "zen-beta";
      NH_FLAKE = "/etc/nixos";
    };

    packages = with pkgs; [
      pulseaudio # Утилита pactl для управления нодами PipeWire и виртуального микрофона

      # Терминальные утилиты и инструменты разработки
      btop
      cava
      cbonsai
      ffmpeg
      jq
      nodejs_22
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
        pygobject3
      ]))
      libadwaita
      gtk4
      wget
      wf-recorder
      obs-cmd
      rofi

      # Шрифты
      jetbrains-mono
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
      noto-fonts
      noto-fonts-color-emoji
      twemoji-color-font

      # Инструменты и утилиты
      age
      alsa-utils
      bat
      cliphist
      coreutils
      eza
      fastfetch
      fd
      fzf
      git
      glib
      gsettings-desktop-schemas
      killall

      # Пользовательские приложения
      (pkgs.callPackage ./pkgs/riff.nix {})
      file-roller
      gnome-text-editor
      gpu-screen-recorder-gtk
      kdePackages.dolphin
      kdePackages.kate
      kdePackages.kio-extras
      kdePackages.ffmpegthumbs
      kdePackages.kdegraphics-thumbnailers
      kdePackages.kimageformats
      kdePackages.partitionmanager
      ffmpegthumbnailer
      linux-wallpaperengine
      loupe
      swaybg
      telegram-desktop
      vesktop

      # Инструменты сессии Niri/Wayland
      (pkgs.callPackage ./pkgs/livewall.nix {})
      grim
      hyprpicker
      inputs.lumine-capture.packages.${pkgs.stdenv.hostPlatform.system}.default
      matugen
      slurp
      songrec
      tesseract
      wl-clip-persist
      wl-clipboard
      wtype
      zbar
      satellitePkgs.xwayland-satellite
    ];
  };

  xdg.enable = true;
}
