# Wayland programs: niri, noctalia, satty, grim, slurp, wl-clipboard
{ config, pkgs, lib, inputs, ... }:

let
  satellitePkgs = import inputs.nixpkgs-satellite {
    inherit (pkgs.stdenv.hostPlatform) system;
  };

  niriAutostart = pkgs.writeShellScript "niri-autostart" ''
    # 1. Disable 25-second D-Bus accessibility timeout
    export NO_AT_BRIDGE=1

    # Cursor variables (size 20 for Catppuccin)
    export XCURSOR_THEME="catppuccin-mocha-dark-cursors"
    export XCURSOR_SIZE=20

    # 2. Pass Wayland and cursor vars to D-Bus and systemd
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=niri DISPLAY XCURSOR_THEME XCURSOR_SIZE
    systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP DISPLAY XCURSOR_THEME XCURSOR_SIZE

    # 3. Background daemons, DMS and wallpaper
    pgrep -x wl-clip-persist >/dev/null || wl-clip-persist --clipboard regular &
    pgrep -x xwayland-satellite >/dev/null || xwayland-satellite &
    pgrep -x noctalia >/dev/null || noctalia &
  '';
in {
  home = {
    packages = with pkgs; [
      # Wayland tools
      grim
      matugen
      slurp
      wl-clip-persist
      wl-clipboard
      wtype
      satellitePkgs.xwayland-satellite
    ];
  };

  wayland.windowManager.niri = {
    enable = true;
    package = null;
    systemd.enable = false;
    xwaylandSatellitePackage = null;
    portalPackage = null;
    checkConfig = false;
    extraConfig = builtins.readFile ../../niri.kdl;
  };

  programs = {

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
  };

  xdg.configFile."niri/autostart.sh" = {
    source = niriAutostart;
    force = lib.mkForce true;
  };
}