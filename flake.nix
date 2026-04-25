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

    bmad-method = {
      url = "github:bmad-code-org/BMAD-METHOD/v6.4.0";
      flake = false;
    };
    bmad-cis = {
      url = "github:bmad-code-org/bmad-module-creative-intelligence-suite/v0.2.0";
      flake = false;
    };
    bmad-tea = {
      url = "github:bmad-code-org/bmad-method-test-architecture-enterprise/v1.15.1";
      flake = false;
    };
    bmad-builder = {
      url = "github:bmad-code-org/bmad-builder/v1.6.0";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, impermanence, ... }@inputs:
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
      };
    };
}
