{
  description = "Mandragora NixOS - The Second Skin";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, impermanence, nixos-generators, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      hostsDir = ./hosts;

      autoHostNames = builtins.attrNames (
        lib.filterAttrs (name: type:
          type == "directory"
          && builtins.pathExists (hostsDir + "/${name}/default.nix")
          && name != "mandragora-usb"
          && name != "mandragora-vps"
        ) (builtins.readDir hostsDir)
      );

      mkSystem = name: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./modules/shared/profile.nix
          (hostsDir + "/${name}/default.nix")
          home-manager.nixosModules.home-manager
          sops-nix.nixosModules.sops
          impermanence.nixosModules.impermanence
        ] ++ lib.optional
          (builtins.pathExists (hostsDir + "/${name}/hardware-configuration.nix"))
          (hostsDir + "/${name}/hardware-configuration.nix");
      };

      autoConfigs = lib.genAttrs autoHostNames mkSystem;
    in
    {
      nixosConfigurations = autoConfigs // {
        mandragora-usb = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/shared/profile.nix
            ./hosts/mandragora-usb/default.nix
            "${nixpkgs}/nixos/modules/profiles/installation-device.nix"
            sops-nix.nixosModules.sops
          ];
        };
      };

      packages.${system}.usbImage = nixos-generators.nixosGenerate {
        inherit system;
        format = "raw-efi";
        modules = [
          ./modules/shared/profile.nix
          ./hosts/mandragora-usb/default.nix
          sops-nix.nixosModules.sops
        ];
      };

      apps.${system}.refiner = {
        type = "app";
        program = "${(import ./refiner/default.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          usbImage = self.packages.${system}.usbImage;
        })}/bin/refiner";
      };

      homeConfigurations."m@mandragora-vps" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages."aarch64-linux";
        modules = [ ./hosts/mandragora-vps/home.nix ];
      };
    };
}
