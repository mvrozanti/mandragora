_: {
  services.scx = {
    enable = true;
    scheduler = "scx_bpfland";
  };

  systemd.tmpfiles.rules = [ "w /sys/block/nvme*n*/queue/scheduler - - - - bfq" ];

  systemd.services."user@".serviceConfig.Delegate = "cpu io memory pids";

  systemd.services.bitcoind-main.serviceConfig.IOWeight = 10;
}
