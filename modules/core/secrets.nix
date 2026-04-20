{ config, pkgs, lib, ... }:

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
    };
  };

  users.users.m.hashedPasswordFile = config.sops.secrets."user/password".path;
}
