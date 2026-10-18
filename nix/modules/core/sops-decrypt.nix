{ config, pkgs, ... }:

let
  sopsDecrypt = pkgs.writeShellApplication {
    name = "mandragora-sops-decrypt";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      sops
    ];
    runtimeEnv.AGE_KEY_FILE = config.sops.age.keyFile;
    text = builtins.readFile ../../../.local/bin/mandragora-sops-decrypt.sh;
  };
in
{
  environment.systemPackages = [ sopsDecrypt ];
}
