{
  description = "Spike-dotfiles: NixOS + Niri + Noctalia Rice";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # xwayland-satellite package from unstable (follows nixpkgs)
    nixpkgs-satellite = {
      url = "github:nixos/nixpkgs/nixos-unstable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Noctalia desktop shell
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, noctalia, spicetify-nix, agenix, nixpkgs-satellite, ... }@inputs: let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
    mkHost = name: {
      configuration = import ./hosts/${name}/configuration.nix;
      hardware = import ./hosts/${name}/hardware-configuration.nix;
      home = import ./hosts/${name}/home.nix;
    };
    hosts = {
      desktop = mkHost "desktop";
    };
  in {
    nixosConfigurations = lib.mapAttrs (name: host: nixpkgs.lib.nixosSystem {
      system = system;
      specialArgs = { inherit inputs; hostName = name; };
      modules = [
        host.hardware
        host.configuration
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.spike = host.home;
          home-manager.extraSpecialArgs = { inherit inputs; hostName = name; };
        }
        agenix.nixosModules.default
      ];
    }) hosts;

    homeConfigurations = lib.mapAttrs (name: host: home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.${system};
      modules = [ host.home ];
      extraSpecialArgs = { inherit inputs; hostName = name; };
    }) hosts;

    # Checks for CI
    checks = lib.mapAttrs (name: host: {
      nixosConfig = self.nixosConfigurations.${name};
      homeConfig = self.homeConfigurations.${name};
      # Build VM test
      vm = nixpkgs.lib.nixosSystem {
        system = system;
        modules = [
          host.hardware
          host.configuration
          {
            users.users.spike = {
              isNormalUser = true;
              password = "test";
              extraGroups = [ "wheel" ];
            };
            system.build.vm = {
              enable = true;
              memorySize = 1024;
            };
          }
        ];
      }.config.system.build.vm;
    }) hosts;

    # Formatter
    formatter = with nixpkgs; {
      nix = [
        self
        nixpkgs
        home-manager
        noctalia
        spicetify-nix
        agenix
      ];
    };
  };
}