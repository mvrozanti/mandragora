{ pkgs, ... }:

let
  eppctl = pkgs.writeShellApplication {
    name = "eppctl";
    runtimeInputs = [ pkgs.procps ];
    text = builtins.readFile ../../snippets/eppctl.sh;
  };
in
{
  environment.systemPackages = [ eppctl ];

  security.sudo.extraRules = [
    {
      users = [ "m" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/eppctl";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
