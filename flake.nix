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
    in
    {
      nixosConfigurations = {
        mandragora-desktop = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/mandragora-desktop/default.nix
            ./hosts/mandragora-desktop/hardware-configuration.nix

            # Inputs
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            impermanence.nixosModules.impermanence
          ];
        };

        mandragora-usb = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
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
    };
}
