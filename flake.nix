{
  description = "Spike-dotfiles — Niri + Noctalia + Dynamic Theme Manager NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Временный фикс мерцания меню в Niri (версия 0.8.1)
    nixpkgs-satellite.url = "github:nixos/nixpkgs/edfd59b795cd752c36d2dae60870cffcd23d3fb1";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Подключаем Noctalia вместо DMS
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lumine-capture = {
      url = "github:Netflate/LumineCapture";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      userConfig = import ./user-config.nix;
      vmUserConfig = userConfig // {
        gpu = "vm";
        luksCryptroot = false;
        btrfsScrub = false;
      };

      mkSystem = cfg: extraModules: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; userConfig = cfg; };
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${cfg.username} = import ./home.nix;
            home-manager.extraSpecialArgs = { inherit inputs; userConfig = cfg; };
          }
        ] ++ extraModules;
      };

      # Переиспользуемый Home Manager модуль: подключается в любой сторонний NixOS-флейк
      hmRiceModule = { pkgs, lib, ... }: {
        _module.args.inputs = lib.mkDefault inputs;
        imports = [ ./home.nix ];
      };
    in {
      # Основная конфигурация (управляется через user-config.nix)
      nixosConfigurations.nixos = mkSystem userConfig [];

      # Готовая тестовая QEMU VM (без NVIDIA/LUKS, с автологином и VirtIO-GL):
      # nix build github:triplespike/Spike-dotfiles#nixosConfigurations.vm.config.system.build.vm && ./result/bin/run-nixos-vm
      nixosConfigurations.vm = mkSystem vmUserConfig [
        ({ lib, pkgs, ... }: {
          boot.loader.grub.enable = lib.mkForce false;
          users.users.${vmUserConfig.username}.initialPassword = vmUserConfig.username;
          services.displayManager.autoLogin = {
            enable = true;
            user = vmUserConfig.username;
          };
          services.openssh = {
            enable = true;
            settings.PasswordAuthentication = true;
          };
          # Обход EGL BadMatch у Ghostty на QEMU virgl
          home-manager.users.${vmUserConfig.username}.programs.ghostty.package = pkgs.symlinkJoin {
            name = "ghostty-vm-wrapped";
            paths = [ pkgs.ghostty ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram "$out/bin/ghostty" --set LIBGL_ALWAYS_SOFTWARE 1
            '';
            meta.mainProgram = "ghostty";
          };
          virtualisation.vmVariant.virtualisation = {
            memorySize = 4096;
            cores = 4;
            diskSize = 8192;
            graphics = true;
            forwardPorts = [
              { from = "host"; host.port = 2223; guest.port = 22; }
            ];
            qemu.options = [
              "-device" "virtio-vga-gl"
              "-display" "sdl,gl=on"
            ];
          };
        })
      ];

      # Экспорт Home Manager модуля для подключения в чужие NixOS-конфиги
      homeManagerModules = {
        default = hmRiceModule;
        spike-rice = hmRiceModule;
      };
    };
}
