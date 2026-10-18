{ pkgs, ... }:

let
  genPrune = pkgs.writeShellApplication {
    name = "mandragora-gen-prune";
    runtimeInputs = [ pkgs.nix ];
    text = builtins.readFile ../../../.local/bin/mandragora-gen-prune.sh;
  };
in
{
  environment.systemPackages = [ genPrune ];

  security.sudo.extraRules = [
    {
      users = [ "m" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/mandragora-gen-prune";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
