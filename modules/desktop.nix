# Desktop environment module (Plasma fallback, SDDM, X11)
{ config, pkgs, lib, ... }:

{
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

  # Printing
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

  # Steam & gaming
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
  programs.nix-ld.enable = true;
  programs.gamemode.enable = true;
  programs.gpu-screen-recorder.enable = true;

  services.flatpak.enable = true;
}