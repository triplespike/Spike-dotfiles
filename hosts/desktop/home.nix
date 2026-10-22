{ config, pkgs, lib, inputs, hostName, ... }:

let
  esc = builtins.fromJSON ''"\u001b"'';

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
  imports = [
    ../../modules/noctalia.nix
    inputs.spicetify-nix.homeManagerModules.default
    ../../home/programs/shell.nix
    ../../home/programs/terminal.nix
    ../../home/programs/wayland.nix
    ../../home/programs/media.nix
    ../../home/programs/editors.nix
    # ./programs/development.nix
    # ./ui/gtk.nix
    # ./ui/cursors.nix
    # ./ui/fonts.nix
    # ./services/pipewire.nix
    # ./services/swayidle.nix
    # ./services/flatpak.nix
    # ./xdg.nix
  ];

  home = {
    username = "spike";
    homeDirectory = "/home/spike";
    stateVersion = "26.05";

    sessionVariables = {
      XCURSOR_THEME = "catppuccin-mocha-dark-cursors";
      XCURSOR_SIZE = "20";
      MOZ_ENABLE_WAYLAND = "1";
      NH_FLAKE = "/etc/nixos";
    };

    pointerCursor = {
      enable = true;
      gtk.enable = true;
      x11.enable = true;
      package = pkgs.catppuccin-cursors.mochaDark;
      name = "catppuccin-mocha-dark-cursors";
      size = 20;
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
}