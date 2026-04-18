{ config, pkgs, ... }:

{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";

    age = {
      # This is the path to the age key that will decrypt the secrets
      keyFile = "/persistent/secrets/keys.txt";
      generateKey = false;
    };

    secrets = {
      "user/password" = {
        neededForUsers = true;
      };
      # Example SSH key definition
      # "ssh/id_ed25519" = {
      #   path = "/home/m/.ssh/id_ed25519";
      #   owner = "m";
      # };

      # Seafile auth token — uncomment once arch-slave Seafile server is running
      # and the token has been added to secrets/secrets.yaml via sops
      # "seafile/auth-token" = {
      #   owner = "m";
      # };
    };
  };

  # Use the decrypted password for the user
  users.users.m.hashedPasswordFile = config.sops.secrets."user/password".path;
}
