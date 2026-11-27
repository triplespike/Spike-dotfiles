# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, userConfig ? import ./user-config.nix, ... }:

let
  isNvidia = userConfig.gpu == "nvidia";
in {
  imports =
    lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix
    ++ [ ./performance.nix ];

  # ==========================================================
  #                        Boot / Bootloader
  # ==========================================================

  boot.loader.systemd-boot.enable = false;

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    useOSProber = false;

    theme =
      (pkgs.fetchFromGitHub {
        owner = "Coopydood";
        repo = "HyperFluent-GRUB-Theme";
        rev = "v1.0.1";
        sha256 = "sha256-zryQsvue+YKGV681Uy6GqnDMxGUAEfmSJEKCoIuu2z8=";
      }) + "/nixos";
  };

  boot.loader.efi.canTouchEfiVariables = true;

  # Разрешаем TRIM / discard для зашифрованного NVMe SSD (только если включено в user-config.nix)
  boot.initrd.luks.devices = lib.mkIf userConfig.luksCryptroot {
    "cryptroot".allowDiscards = true;
  };

  # Zen-ядро с низкими задержками для десктопа и игр
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # ==========================================================
  #                        Networking
  # ==========================================================

  networking.hostName = userConfig.hostName;
  networking.networkmanager.enable = true;

  # Разрешаем асимметричный трафик туннеля (критично для UDP в Discord)
  networking.firewall.checkReversePath = "loose";

  # Делаем виртуальные интерфейсы VPN доверенными (Throne)
  networking.firewall.trustedInterfaces = [ "throne-tun" "tun0" "singbox-tun" ];

  # Разрешаем локальный порт для Clipper Studio (Wi-Fi передача на телефон)
  networking.firewall.allowedTCPPorts = [ 8080 ];


  # Корректная работа DNS внутри туннеля
  services.resolved.enable = true;

  # ==========================================================
  #                        Locale / Time
  # ==========================================================

  time.timeZone = userConfig.timeZone;
  i18n.defaultLocale = userConfig.locale;

  i18n.extraLocaleSettings = {
    LC_ADDRESS = userConfig.locale;
    LC_IDENTIFICATION = userConfig.locale;
    LC_MEASUREMENT = userConfig.locale;
    LC_MONETARY = userConfig.locale;
    LC_NAME = userConfig.locale;
    LC_NUMERIC = userConfig.locale;
    LC_PAPER = userConfig.locale;
    LC_TELEPHONE = userConfig.locale;
    LC_TIME = userConfig.locale;
  };

  # ==========================================================
  #                        Desktop / Display
  # ==========================================================

  # X11 (нужен даже под Wayland-сессии для совместимости со старыми программами)
  services.xserver.enable = true;

  # Фантомная Plasma 6 отключена — используется чистый Niri.
  # Polkit-агент для графических запросов пароля (sudo/pkexec) в сессии Niri:
  systemd.user.services.polkit-kde-authentication-agent-1 = {
    description = "polkit-kde-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };

  # Правила Polkit: беспарольное управление службами и вызов systemctl для Gamer Mode (группа wheel)
  security.polkit = {
    enable = true;
    extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (subject.isInGroup("wheel")) {
          // 1. Управление юнитами systemd (через D-Bus)
          if (action.id === "org.freedesktop.systemd1.manage-units") {
            return polkit.Result.YES;
          }
          // 2. Вызовы pkexec systemctl (плагин Gamer Mode в Noctalia)
          if (action.id === "org.freedesktop.policykit.exec") {
            var prog = action.lookup("program");
            if (prog && (prog === "/run/current-system/sw/bin/systemctl" || prog.indexOf("/bin/systemctl") >= 0)) {
              return polkit.Result.YES;
            }
          }
          // 3. Беспарольное управление DNS и сброс кэша (Throne TUN / systemd-resolved)
          if (action.id.indexOf("org.freedesktop.resolve1.") === 0) {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };

  # Настройка SDDM под Qt6 и тему Astronaut
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "sddm-astronaut-theme";
    package = lib.mkForce pkgs.kdePackages.sddm;
    extraPackages = with pkgs.kdePackages; [
      qt5compat
      qtsvg
      qtmultimedia
      qtvirtualkeyboard
    ];
  };

  services.displayManager.defaultSession = lib.mkForce "niri";

  services.xserver.xkb = {
    layout = "us,ru";
    options = "grp:win_space_toggle";
    variant = "";
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  # Темизация Qt/KDE (Dolphin и др.) без фоновых демонов Plasma
  qt = {
    enable = true;
    platformTheme = "kde";
    style = "breeze";
  };

  # Бесконечный скролл-композитор Niri
  programs.niri.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gnome pkgs.xdg-desktop-portal-gtk ];
    config = {
      niri = {
        default = [ "gnome" "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
      };
    };
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    maple-mono.Normal-NF
  ];

  # ==========================================================
  #                        Graphics / GPU
  # ==========================================================

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  services.xserver.videoDrivers = if isNvidia then [ "nvidia" ] else [ "modesetting" ];

  hardware.nvidia = lib.mkIf isNvidia {
    modesetting.enable = true;
    # powerManagement.enable задаётся в performance.nix
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };

  # Фикс зависания кадров в играх под Niri на NVIDIA
  environment.etc."nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json" = lib.mkIf isNvidia {
    text = ''
      {
        "rules": [
          {
            "pattern": { "feature": "procname", "matches": "niri" },
            "profile": "Limit Free Buffer Pool On Wayland Compositors"
          }
        ],
        "profiles": [
          {
            "name": "Limit Free Buffer Pool On Wayland Compositors",
            "settings": [
              { "key": "GLVidHeapReuseRatio", "value": 0 }
            ]
          }
        ]
      }
    '';
  };

  # ==========================================================
  #                        Audio
  # ==========================================================

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # Настройки для гарнитуры Temple Pro Black (чип XiiSound):
    # - программный микшер (чип искажает аппаратную громкость)
    # - выравнивание квантов и буфера под 1024 сэмпла для устранения помех/дропов на адаптивном USB
    wireplumber.extraConfig = {
      "10-disable-hw-volume" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                "device.name" = "~alsa_card.usb-XiiSound.*";
              }
            ];
            actions = {
              update-props = {
                "api.alsa.soft-mixer" = true;
                "api.alsa.ignore-dB" = true;
              };
            };
          }
          {
            matches = [
              {
                "node.name" = "~alsa_output.usb-XiiSound.*";
              }
            ];
            actions = {
              update-props = {
                "api.alsa.soft-mixer" = true;
                "api.alsa.ignore-dB" = true;
                "api.alsa.headroom" = 1024;
                "api.alsa.period-size" = 1024;
                "node.latency" = "1024/48000";
                "session.suspend-timeout-seconds" = 0;
              };
            };
          }
        ];
      };
    };
  };

  # ==========================================================
  #                 Disabled Unused Services
  # ==========================================================

  # Печать отключена (CUPS, драйверы и GUI-апплет принтера)
  services.printing.enable = false;
  services.avahi.enable = false;
  programs.system-config-printer.enable = false;

  # Отключение лишних системных служб:
  # ModemManager — опрос 3G/4G/LTE модемов с SIM-картами (не нужен на стационарном ПК)
  systemd.services.ModemManager.enable = false;

  # Синтез речи / экранный диктор
  systemd.user.services.speech-dispatcher.enable = false;

  # ==========================================================
  #                        Users
  # ==========================================================

  users.users.${userConfig.username} = {
    isNormalUser = true;
    description = userConfig.userDescription;
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" "dialout" "uucp" ];
  };

  # Разрешаем доступ к платам ESP8266/ESP32 и микроконтроллерам без sudo
  services.udev.extraRules = ''
    KERNEL=="ttyUSB[0-9]*", MODE="0666"
    KERNEL=="ttyACM[0-9]*", MODE="0666"
  '';

  # ==========================================================
  #                 Maintenance & Optimization
  # ==========================================================

  # Периодический TRIM для поддержания скорости и ресурса SSD/NVMe
  services.fstrim.enable = true;

  # Автоматическая ежемесячная проверка целостности Btrfs (только если включено в user-config.nix)
  services.btrfs.autoScrub = lib.mkIf userConfig.btrfsScrub {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # ==========================================================
  #                        Programs
  # ==========================================================

  # Утилита nh (Nix CLI Helper) для удобного управления конфигурацией и ротации поколений
  programs.nh = {
    enable = true;
    flake = "/etc/nixos";
    clean = {
      enable = true;
      extraArgs = "--keep 5 --keep-since 3d";
    };
  };

  programs.nix-ld.enable = true;

  programs.gpu-screen-recorder.enable = true;

  programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;

      extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];

      extraPackages = with pkgs; [
      catppuccin-cursors.mochaDark
    ];
  };


  programs.throne = {
    enable = true;
    tunMode.enable = true;
  };

  # ==========================================================
  #                 Virtualisation / Containers
  # ==========================================================

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  hardware.nvidia-container-toolkit.enable = isNvidia;

  # Fish остаётся системным login shell; пользовательские настройки живут в home.nix.
  programs.fish.enable = true;

  # ==========================================================
  #                        Services
  # ==========================================================

  services.flatpak.enable = true;

  # Демоны для работы с дисками, разделами и флешками (критично для Dolphin и мест в сайдбаре)
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  # ==========================================================
  #                        Filesystems
  # ==========================================================
  # Пример монтирования дополнительных дисков (замените UUID на свои):
  # fileSystems."/mnt/storage" = {
  #   device = "/dev/disk/by-uuid/<YOUR-STORAGE-UUID>";
  #   fsType = "ext4";
  #   options = [ "defaults" "nofail" ];
  # };
  #
  # fileSystems."/mnt/ssd" = {
  #   device = "/dev/disk/by-uuid/<YOUR-SSD-UUID>";
  #   fsType = "ext4";
  #   options = [ "defaults" "nofail" ];
  # };

  # ==========================================================
  #                        Packages
  # ==========================================================

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    # Тема SDDM Astronaut (пресет Black Hole + шрифты)
    (pkgs.stdenv.mkDerivation {
      name = "sddm-astronaut-theme";
      src = pkgs.fetchFromGitHub {
        owner = "keyitdev";
        repo = "sddm-astronaut-theme";
        rev = "master";
        sha256 = "sha256-O/EMJc1j2TRF3W+vuurzA9j5eG1OXSjGFrYxQbp99KU=";
      };
      installPhase = ''
        mkdir -p $out/share/sddm/themes/sddm-astronaut-theme
        cp -r * $out/share/sddm/themes/sddm-astronaut-theme/
        cd $out/share/sddm/themes/sddm-astronaut-theme

        # 1. Указываем пресет Black Hole в манифесте
        sed -i 's|ConfigFile=.*|ConfigFile=Themes/black_hole.conf|' metadata.desktop

        # 2. Перезаписываем theme.conf
        cp -f Themes/black_hole.conf theme.conf

        # 3. Устанавливаем шрифты темы
        mkdir -p $out/share/fonts
        cp -r Fonts/* $out/share/fonts/ 2>/dev/null || true
      '';
    })
    alsa-utils
    kdePackages.breeze-icons
    kdePackages.qqc2-desktop-style
    kdePackages.ffmpegthumbs
    kdePackages.kdegraphics-thumbnailers
    kdePackages.kimageformats
    ffmpegthumbnailer
  ];

  # ==========================================================
  #                        SUID wrappers / misc
  # ==========================================================

  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # services.openssh.enable = true;

  # ==========================================================
  #                        Nix settings
  # ==========================================================

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.warn-dirty = true;
  nix.settings.trusted-users = [ "root" "@wheel" userConfig.username ];

  # Еженедельная автоматическая дедупликация store жесткими ссылками
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  # ==========================================================
  #                        State version
  # ==========================================================

  # НЕ менять после первой установки без прочтения release notes
  system.stateVersion = "26.05";
}
