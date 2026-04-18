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

        shadow-desktop = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/shadow-desktop/default.nix
            ./hosts/shadow-desktop/hardware-configuration.nix

            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            impermanence.nixosModules.impermanence
          ];
        };
      };
    };
}
