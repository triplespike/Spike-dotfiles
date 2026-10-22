# Audio module (PipeWire)
{ config, pkgs, lib, ... }:

{
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
                "device.name" = "~alsa_card.usb-XiiSound.*";
              }
              {
                "node.name" = "~alsa_output.usb-XiiSound.*";
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
}