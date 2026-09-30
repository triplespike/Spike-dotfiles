# Spike-dotfiles: NixOS System Configuration
# Daily-driver setup with Niri scroll-compositor, Noctalia desktop shell, and NVIDIA Wayland stack.

{ config, pkgs, lib, ... }:

{
  imports = [
    # Include hardware configuration (falls back to example if not yet generated)
    (if builtins.pathExists ./hardware-configuration.nix
     then ./hardware-configuration.nix
     else ./hardware-configuration.nix.example)
  ];

  # ==========================================================
  #                        Boot / Bootloader
  # ==========================================================
  zramSwap.enable = true;

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

  # Linux Zen Kernel for low-latency desktop & gaming
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # ==========================================================
  #                        Networking
  # ==========================================================

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # Resolved for DNS handling
  services.resolved.enable = true;

  # ==========================================================
  #                        Locale / Time
  # ==========================================================

  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # ==========================================================
  #                        Desktop / Display
  # ==========================================================

  # X11 compatibility layer
  services.xserver.enable = true;

  # Plasma 6 optional fallback
  services.desktopManager.plasma6.enable = true;

  # SDDM Display Manager with Astronaut Theme
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

  # Niri scroll-compositor
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
  ];

  # ==========================================================
  #                        Graphics / NVIDIA
  # ==========================================================

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };

  # Fix: Frame hitching / buffer limits in Wayland compositors on NVIDIA
  environment.etc."nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json".text = ''
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

    wireplumber.extraConfig = {
      "10-disable-hw-volume" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                "node.name" = "~alsa_output.*";
              }
            ];
            actions = {
              update-props = {
                "api.alsa.soft-mixer" = true;
                "api.alsa.ignore-dB" = true;
              };
            };
          }
        ];
      };
    };
  };

  # ==========================================================
  #                        Printing
  # ==========================================================

  services.printing = {
    enable = true;
    drivers = with pkgs; [ gutenprint cups-filters ];
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  programs.system-config-printer.enable = true;

  # ==========================================================
  #                        Users
  # ==========================================================

  users.users."spike" = {
    isNormalUser = true;
    description = "Spike";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # ==========================================================
  #                        Programs
  # ==========================================================

  programs.nix-ld.enable = true;
  programs.gamemode.enable = true;
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

  programs.fish.enable = true;

  # ==========================================================
  #                        Services & Filesystems
  # ==========================================================

  services.flatpak.enable = true;

  # Example additional disk mounts:
  # fileSystems."/mnt/storage" = {
  #   device = "/dev/disk/by-uuid/YOUR-DISK-UUID";
  #   fsType = "ext4";
  #   options = [ "defaults" "nofail" ];
  # };

  # ==========================================================
  #                        Packages
  # ==========================================================

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    # SDDM Astronaut theme (Black Hole preset)
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

        sed -i 's|ConfigFile=.*|ConfigFile=Themes/black_hole.conf|' metadata.desktop
        cp -f Themes/black_hole.conf theme.conf

        mkdir -p $out/share/fonts
        cp -r Fonts/* $out/share/fonts/ 2>/dev/null || true
      '';
    })
  ];

  # ==========================================================
  #                        Nix settings
  # ==========================================================

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.warn-dirty = false;

  # State version
  system.stateVersion = "26.05";
}
