_: {
  services.scx = {
    enable = true;
    scheduler = "scx_bpfland";
  };

  systemd.tmpfiles.rules = [ "w /sys/block/nvme*n*/queue/scheduler - - - - kyber" ];

  systemd.services."user@".serviceConfig.Delegate = "cpu io memory pids";
}
