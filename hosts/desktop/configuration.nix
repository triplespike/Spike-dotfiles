# Desktop configuration
{ config, pkgs, lib, inputs, hostName, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/niri.nix
    ../../modules/graphics.nix
    ../../modules/audio.nix
    ../../modules/desktop.nix
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

  networking.hostName = hostName;
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
  #                        Users
  # ==========================================================

  users.users."spike" = {
    isNormalUser = true;
    description = "Spike";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # ==========================================================
  #                        System Packages
  # ==========================================================

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    # SDDM Astronaut theme (Black Hole preset)
    (stdenv.mkDerivation {
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