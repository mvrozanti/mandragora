_: {
  services.scx = {
    enable = true;
    scheduler = "scx_bpfland";
  };

  services.udev.extraRules = builtins.readFile ../../snippets/nvme-bfq.rules;

  systemd.services."user@".serviceConfig.Delegate = "cpu io memory pids";

  systemd.services.bitcoind-main.serviceConfig.IOWeight = 10;
}
