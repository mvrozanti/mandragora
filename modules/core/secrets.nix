{ config, pkgs, lib, ... }:

let
  oracleHostsInject = pkgs.writeShellScript "oracle-hosts-inject"
    (builtins.readFile ../../.local/bin/oracle-hosts-inject.sh);
in
{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";

    age = {
      keyFile = "/persistent/secrets/keys.txt";
      generateKey = false;
    };

    secrets = {
      "user/password" = {
        neededForUsers = true;
      };
      "weather/api_key" = {
        mode = "0444";
      };
      "oracle/ip" = {
        owner = "m";
        mode = "0400";
      };
      "huggingface/read_token" = {
        owner = "m";
        mode = "0400";
      };
      "image_generator/telegram_bot_key" = {
        owner = "m";
        mode = "0400";
      };
      "llm_via_telegram/env" = {
        owner = "m";
        mode = "0400";
      };
    };

    templates."hosts-oracle" = {
      content = ''
        ${config.sops.placeholder."oracle/ip"} oracle
      '';
      mode = "0444";
    };
  };

  users.users.m.hashedPasswordFile = config.sops.secrets."user/password".path;

  system.activationScripts.oracle-in-hosts = {
    text = "${oracleHostsInject}";
    deps = [ "setupSecrets" ];
  };
}
