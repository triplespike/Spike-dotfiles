{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "sd_mod" "dm_mod" "dm_crypt" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/3ddb327c-e42d-4972-83d5-50f547624457";
    fsType = "btrfs";
    options = [ "rw" "relatime" "ssd" "space_cache=v2" "subvol=/" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/12CE-A600";
    fsType = "vfat";
    options = [ "rw" "relatime" "fmask=0077" "dmask=0077" "codepage=437" "iocharset=ascii" "shortname=mixed" "errors=remount-ro" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/3ddb327c-e42d-4972-83d5-50f547624457";
    fsType = "btrfs";
    options = [ "rw" "relatime" "ssd" "space_cache=v2" "subvol=/home" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/3ddb327c-e42d-4972-83d5-50f547624457";
    fsType = "btrfs";
    options = [ "rw" "relatime" "ssd" "space_cache=v2" "subvol=/nix" ];
  };

  fileSystems."/nix/store" = {
    device = "/dev/disk/by-uuid/3ddb327c-e42d-4972-83d5-50f547624457";
    fsType = "btrfs";
    options = [ "rw" "relatime" "ssd" "space_cache=v2" "subvol=/nix/store" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-uuid/3ddb327c-e42d-4972-83d5-50f547624457";
    fsType = "btrfs";
    options = [ "rw" "relatime" "ssd" "space_cache=v2" "subvol=/var/log" ];
  };

  fileSystems."/var/tmp" = {
    device = "/dev/disk/by-uuid/3ddb327c-e42d-4972-83d5-50f547624457";
    fsType = "btrfs";
    options = [ "rw" "relatime" "ssd" "space_cache=v2" "subvol=/var/tmp" ];
  };

  fileSystems."/tmp" = {
    device = "/dev/disk/by-uuid/3ddb327c-e42d-4972-83d5-50f547624457";
    fsType = "btrfs";
    options = [ "rw" "relatime" "ssd" "space_cache=v2" "subvol=/tmp" ];
  };

  fileSystems."/srv" = {
    device = "/dev/disk/by-uuid/3ddb327c-e42d-4972-83d5-50f547624457";
    fsType = "btrfs";
    options = [ "rw" "relatime" "ssd" "space_cache=v2" "subvol=/srv" ];
  };

  fileSystems."/var/lib/machines" = {
    device = "/dev/disk/by-uuid/3ddb327c-e42d-4972-83d5-50f547624457";
    fsType = "btrfs";
    options = [ "rw" "relatime" "ssd" "space_cache=v2" "subvol=/var/lib/machines" ];
  };

  fileSystems."/var/lib/portables" = {
    device = "/dev/disk/by-uuid/3ddb327c-e42d-4972-83d5-50f547624457";
    fsType = "btrfs";
    options = [ "rw" "relatime" "ssd" "space_cache=v2" "subvol=/var/lib/portables" ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/670bd593-bf6f-4769-a604-e7ce57039ee2"; }
  ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # LUKS encryption for root
  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-uuid/14b6f52f-2482-4844-9b81-ba355abfaa07";
    preLVM = true;
    allowDiscards = true;
  };
}
