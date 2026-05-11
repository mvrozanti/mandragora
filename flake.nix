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

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    bruno-tama = {
      url = "github:mvrozanti/bruno-tama";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, impermanence, nixos-generators, nixos-wsl, bruno-tama, ... }@inputs:
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
          && name != "mandragora-wsl"
        ) (builtins.readDir hostsDir)
      );

      sharedModules = [
        ./modules/shared/profile.nix
        ./modules/shared/zsh.nix
        ./modules/shared/nvim.nix
        (let rev = self.rev or self.dirtyRev or "dirty"; in {
          system.configurationRevision = rev;
          system.systemBuilderCommands = ''
            echo -n "${rev}" > $out/git-revision
          '';
        })
      ];

      mkSystem = name: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = sharedModules ++ [
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
        mandragora-wsl = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = sharedModules ++ [
            ./hosts/mandragora-wsl/default.nix
            home-manager.nixosModules.home-manager
            nixos-wsl.nixosModules.default
          ];
        };

        mandragora-usb = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = sharedModules ++ [
            ./hosts/mandragora-usb/default.nix
            "${nixpkgs}/nixos/modules/profiles/installation-device.nix"
            sops-nix.nixosModules.sops
            {
              fileSystems."/" = lib.mkDefault {
                device = "/dev/disk/by-label/nixos";
                fsType = "ext4";
              };
              boot.loader.grub.enable = lib.mkDefault false;
              boot.loader.systemd-boot.enable = lib.mkDefault true;
              boot.loader.efi.canTouchEfiVariables = lib.mkDefault false;
            }
          ];
        };
      };

      packages.${system}.usbImage = nixos-generators.nixosGenerate {
        inherit system;
        format = "raw-efi";
        modules = sharedModules ++ [
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

      checks.${system} =
        let
          guards = import ./modules/shared/build-checks.nix {
            inherit self nixpkgs system;
          };
        in {
          usb-closure-size = guards.closureSizeGuard;
          profile-eval = guards.profileEvalGuard;
          usb-sops-key = guards.sopsKeyGuard;
        };

      homeConfigurations."m@mandragora-vps" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages."aarch64-linux";
        modules = [ ./hosts/mandragora-vps/home.nix ];
      };
    };
}
