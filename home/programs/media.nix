# Media & communication apps
{ config, pkgs, lib, inputs, ... }:

{
  home = {
    packages = with pkgs; [
      # Media
      mpvpaper
      swaybg
      linux-wallpaperengine
      loupe

      # File managers (pick one)
      kdePackages.dolphin
    ];
  };

  programs = {
    spicetify = let
      spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
    in {
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
        green              = "7DCFFF";
        yellow             = "C8CBE6";
      };
      enabledExtensions = with spicePkgs.extensions; [
        adblock
        shuffle
      ];
    };
  };
}