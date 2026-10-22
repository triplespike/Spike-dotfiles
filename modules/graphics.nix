# Graphics / NVIDIA module
{ config, pkgs, lib, ... }:

{
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
}