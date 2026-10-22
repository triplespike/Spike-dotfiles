# Editors
{ config, pkgs, lib, ... }:

{
  home = {
    packages = with pkgs; [
      kdePackages.kate
      kdePackages.kio-extras
      kdePackages.partitionmanager
      gnome-text-editor
      file-roller
      gpu-screen-recorder-gtk
    ];
  };
}