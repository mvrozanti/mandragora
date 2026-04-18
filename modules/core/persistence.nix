{ config, lib, ... }: 

let
  cfg = config.mandragora;
in
{
  environment.persistence."${cfg.vault}" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/etc/NetworkManager/system-connections"
    ];
    files = [
      "/etc/machine-id"
    ];

    users."${cfg.user}" = {
      directories = [
        "Documents"
        "Pictures"
        "Projects"
        ".ssh"
        ".gnupg"
        ".local/share/TelegramDesktop"
        ".local/share/nvim"
        ".mozilla"
      ];
      files = [
        ".bash_history"
        ".zsh_history"
      ];
    };
  };
}
