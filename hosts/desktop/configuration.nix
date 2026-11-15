# Desktop configuration
{ config, pkgs, lib, inputs, hostName, ... }:

{
  imports = [
    (if builtins.pathExists ./hardware-configuration.nix
     then ./hardware-configuration.nix
     else ./hardware-configuration.nix.example)
    ../../modules/niri.nix
    ../../modules/graphics.nix
    ../../modules/audio.nix
    ../../modules/desktop.nix
  ];

  # ==========================================================
  #                        Boot / Bootloader & Kernel
  # ==========================================================
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  boot.loader.timeout = 1;
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.settings.Manager.DefaultTimeoutStopSec = "10s";

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

  # Высокопроизводительное ядро CachyOS с планировщиком BORE и оптимизациями x86-64-v3
  boot.kernelPackages = pkgs.linuxPackages_cachyos-bore;

  boot.kernelParams = [
    "quiet"
    "splash"
    "loglevel=3"
    "rd.systemd.show_status=false"
    "amd_pstate=active"
  ];

  # TCP BBR + FQ сетевой стек для минимального пинга в онлайн-играх
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
    "vm.swappiness" = 100;
  };

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
  #                 Hardware & Environment
  # ==========================================================

  # Мгновенная разблокировка звука гарнитуры Ardor Temple Pro при подключении по USB
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="sound", ATTRS{idVendor}=="040b", ATTRS{idProduct}=="0897", RUN+="${pkgs.alsa-utils}/bin/amixer -c %n sset 'PCM',0 100% unmute", RUN+="${pkgs.alsa-utils}/bin/amixer -c %n sset 'PCM',1 100% unmute"
  '';

  environment.sessionVariables = {
    # 10 GiB кэш шейдеров NVIDIA (устраняет микро-статтеры в играх)
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
    __GL_SHADER_DISK_CACHE_SIZE = "10737418240";
    # Аппаратное декодирование видео через NVDEC
    LIBVA_DRIVER_NAME = "nvidia";
    NVD_BACKEND = "direct";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  # ==========================================================
  #                        Nix settings
  # ==========================================================

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    warn-dirty = true;
    trusted-users = [ "root" "@wheel" "spike" ];
    auto-optimise-store = true;
    min-free = 10 * 1024 * 1024 * 1024; # 10 GiB
    max-free = 30 * 1024 * 1024 * 1024; # 30 GiB
  };

  # Еженедельная сборка мусора и автоматическая дедупликация store жесткими ссылками
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # State version
  system.stateVersion = "26.05";
}